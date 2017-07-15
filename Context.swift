//
//  Context.swift
//  BlockingNetwork
//
//  Created by Bastiaan Marinus van de Weerd on 12/07/2017.
//  Copyright © 2017 Bastiaan Marinus van de Weerd. All rights reserved.
//


import Foundation


enum ContextError: Error {
	case invalidResponse(URLResponse)
}


struct Context {
	typealias Error = ContextError

	private let _urlSession: URLSession
	private let _urlSessionDelegate = _URLSessionDelegate()

	init(target: DispatchQueue? = nil) {
		let urlSessionConfiguration = URLSessionConfiguration.default
		urlSessionConfiguration.httpAdditionalHeaders = ["User-Agent": "eu.bm-w.BlockingNetwork/0"]

		let delegateOperationQueue = OperationQueue()
		delegateOperationQueue.underlyingQueue = DispatchQueue(label: "eu.bm-w.BlockingNetworkContext-\(Unmanaged.passUnretained(self._urlSessionDelegate).toOpaque())", target: target)

		self._urlSession = URLSession(configuration: urlSessionConfiguration, delegate: self._urlSessionDelegate, delegateQueue: delegateOperationQueue)
	}

///	Returns four closures:
///	 -  `cancel`: cancels the request (not guaranteed: cancelation may not be acknowledged until the request is already fully sent, or the response already fully received);
///	 -  `resume`: resumes the request (the request will also resume upon calling `sending` or `receive`);
///	 -  `sending`: returns a newly-made blocking itererator over the byte sizes of chunks sent; accumulate these sizes to calculate the total size, and compare to the expected size to derive relative progress;
///	 -  `receive`: blocks, then throws or returns the HTTP response, and two closures:
///	     -  `receiving`: returns a newly-made blocking itererator over the chunks of data received (may be run multiple times; each iterator will receive any previous chunks accumulated into one; internally accumulated data is released with this closure);
///	     -  `complete`: blocks, then throws or returns to indicate that the response is complete (the request may be canceled if this closure is released before completion).
///
///	Usage:
///
///	    let request: URLRequest = ...
///	    let (cancel, _, sending, receive) = context.perform(request)
///	    var totalBytesSent: UInt = 0
///	    for bytesSent in sending() { totalBytesSent += bytesSent }
///	    if isNoLongerRequired { cancel() }
///	    let (response, receiving, complete) = try! receive()
///	    var accumulatedData = Data()
///	    for data in receiving() { accumulatedData.append(data) }
///	    try! complete()
///
	func perform(_ request: URLRequest) -> (cancel: () -> (), resume: () -> (), sending: () -> AnyIterator<UInt>, receive: () throws -> (HTTPURLResponse, receiving: () -> AnyIterator<Data>, complete: () throws -> ())) {
		return self._urlSessionDelegate.perform(self._urlSession.dataTask(with: request), on: self._urlSession.delegateQueue.underlyingQueue.unsafelyUnwrapped)
	}
}


private final class _PerformBox {
	enum State {
		case sending(bytesSent: UInt?, push: [(UInt?) -> ()])
		case receiving(HTTPURLResponse, Data?, push: [(Data?) -> ()])
		case completed(Error?, received: (HTTPURLResponse, Data?)?)
	}

	let groups = (receiving: DispatchGroup(), complete: DispatchGroup())
	var state: State = .sending(bytesSent: nil, push: [])
	weak var task: URLSessionTask?

	init(task: URLSessionTask) {
		self.task = task
	}
}


private final class _URLSessionDelegate: NSObject, URLSessionDataDelegate {
	private var _taskBoxes: [URLSessionTask: _PerformBox] = [:]

	func perform(_ task: URLSessionTask, on serial: DispatchQueue) -> (cancel: () -> (), resume: () -> (), sending: () -> AnyIterator<UInt>, receive: () throws -> (HTTPURLResponse, receiving: () -> AnyIterator<Data>, complete: () throws -> ())) {
		let box = _PerformBox(task: task)
		box.groups.receiving.enter()
		box.groups.complete.enter()

		serial.async() {
			self._taskBoxes[task] = box
		}

		final class OnDeinit {
			let block: () -> ()
			init(_ block: @escaping () -> ()) { self.block = block }
			deinit { self.block() }
		}

		func cancel() {
			serial.async() {
				switch box.task?.state {
				case .suspended?, .running?: box.task?.cancel()
				default: break
				}
			}
		}

		let cancelOnDeinit = OnDeinit(cancel)

		func resume() {
			switch box.task?.state {
			case .suspended?, .canceling?: box.task?.resume()
			default: break
			}
		}

		func resumeOnSerial() {
			serial.async(execute: resume)
		}

		return (
			cancel: cancel,
			resume: resumeOnSerial,
			sending: {
				return serial.sync() {
					resume()
					guard case let .sending(bytesSent, previousPush) = box.state else { return AnyIterator({ nil }) }

					var push: ((UInt?) -> ())!
					let iterator = BlockingIterator(push: &push, values: bytesSent.map({ [$0] }) ?? [], target: serial)
					box.state = .sending(bytesSent: bytesSent, push: previousPush + [push])
					return AnyIterator(iterator)
				}
			},
			receive: {
				resumeOnSerial()
				box.groups.receiving.wait()

				let (response, completedData) = try serial.sync() { () -> (HTTPURLResponse, Data??) in
					switch box.state {
					case .completed(let error?, _): throw error
					case .receiving(let response, _, _): return (response, nil)
					case .completed(nil, let (response, data)?): return (response, .some(data))
					default: preconditionFailure("Invalid box state")
					}
				}

				if let completedData = completedData { return (
					response,
					receiving: {
						guard let data = completedData else { return AnyIterator({ nil }) }
						return AnyIterator(IteratorOverOne<Data>(_elements: data))
					},
					complete: {}
				) }

///				After this deinit is run, further incoming data will no longer be accumulated on `box`, only passed directly to any existing iterators
				let dumpBoxDataOnDeinit = OnDeinit() {
					box.groups.receiving.wait()
					serial.async() {
						guard case let .receiving(response, .some, push) = box.state else { return }
						box.state = .receiving(response, nil, push: push)
					}
				}

				return (
					response,
					receiving: {
///						Tie the on-deinit to the lifetime of this ‘receiving’ closure, dumping the accumulated data on `box` once no more new iterators have to be made
						_ = dumpBoxDataOnDeinit

						return serial.sync() {
							switch box.state {
							case let .receiving(response, data, previousPush):
								var push: ((Data?) -> ())!
								let iterator = BlockingIterator(push: &push, values: data.map({ [$0] }) ?? [], target: serial)
								box.state = .receiving(response, data, push: previousPush + [push])
								return AnyIterator(iterator)
							case .completed(_, (_, let data?)?):
								return AnyIterator(IteratorOverOne<Data>(_elements: data))
							default:
								return AnyIterator({ nil })
							}
						}
					},
					complete: {
///						Tie the on-deinit to the lifetime of this ‘complete’ closure, canceling the URL session task once its completion becomes irrelevant
						_ = cancelOnDeinit

						box.groups.complete.wait()
						return try serial.sync() {
							guard case .completed(let error, _) = box.state else { preconditionFailure("Invalid box state") }
							if let error = error { throw error }
						}
					}
				)
			}
		)
	}

	private func _cleanUp(after task: URLSessionTask, assertionFailure message: String) {
		self._taskBoxes.removeValue(forKey: task)
		assertionFailure(message)
	}

	func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse, newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
		completionHandler(nil)
	}

	func urlSession(_: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend _: Int64) {
		guard let box = self._taskBoxes[task] else { assertionFailure("Unknown box"); return }

		guard case .sending(_, let push) = box.state else { self._cleanUp(after: task, assertionFailure: "Invalid box state"); return }
		for push in push { push(UInt(bytesSent))  }
		box.state = .sending(bytesSent: UInt(totalBytesSent), push: push)
	}

	public func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Swift.Void) {
		guard let box = self._taskBoxes[dataTask] else { assertionFailure("Unknown box"); completionHandler(.cancel); return }

		guard case .sending(_, let push) = box.state else { self._cleanUp(after: dataTask, assertionFailure: "Invalid box state"); completionHandler(.cancel); return }
		for push in push { push(nil) }

		guard let httpResponse = response as? HTTPURLResponse else { box.state = .completed(Context.Error.invalidResponse(response), received: nil); completionHandler(.cancel); return }
		box.state = .receiving(httpResponse, Data(), push: [])
		box.groups.receiving.leave()

		completionHandler(.allow)
	}

	func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		guard let box = self._taskBoxes[dataTask] else { assertionFailure("Unknown box"); return }

		guard case .receiving(let response, var previousData, let push) = box.state else { self._cleanUp(after: dataTask, assertionFailure: "Invalid box state"); return }
		for push in push { push(data) }
		previousData?.append(data)
		box.state = .receiving(response, previousData, push: push)
	}

	func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let box = self._taskBoxes[task] else { assertionFailure("Unknown box"); return }

		var received: (HTTPURLResponse, Data?)?
		switch box.state {
		case .sending(_, let push):
			for push in push { push(nil) }
			box.groups.receiving.leave()
		case let .receiving(response, data, push):
			for push in push { push(nil) }
			received = (response, data)
		default: self._cleanUp(after: task, assertionFailure: "Invalid box state"); return
		}

		box.state = .completed(error, received: received)
		box.groups.complete.leave()
		self._taskBoxes.removeValue(forKey: task)
	}
}
