//
//  BlockIterator.swift
//  BlockingNetwork
//
//  Created by Bastiaan Marinus van de Weerd on 11/07/2017.
//  Copyright © 2017 Bastiaan Marinus van de Weerd. All rights reserved.
//


import Foundation


final class BlockingIterator<T>: IteratorProtocol {
	private enum _State {
		case iterating(DispatchSemaphore), finished
	}

	enum Error: Swift.Error {
		case timedOut
	}


	private var _serial: DispatchQueue! /// `var` && implicitly-unwrapped in order to label using `self` address
	private var _state: _State
	private var _values: [T]

	init(push: inout ((T?) -> ())!, values: [T] = [], target: DispatchQueue? = nil) {
		self._state = .iterating(DispatchSemaphore(value: 0))
		self._values = values

		self._serial = DispatchQueue(label: "eu.bm-w.BlockingIterator-\(Unmanaged.passUnretained(self).toOpaque())", target: target)

		let originalPush = push
		push = { [weak self] value in
			originalPush?(value)

			guard let ownedSelf = self else { return }
			ownedSelf._serial.async() {
				guard case .iterating(let semaphore) = ownedSelf._state else { preconditionFailure("Pushing when already finished") }
				if let value = value { ownedSelf._values.append(value) }
				else { ownedSelf._state = .finished }
				semaphore.signal()
			}
		}
	}


	func next(timeout: DispatchTime) throws -> T? {
		func iterating() -> DispatchSemaphore? {
			return self._serial.sync() {
				if self._values.isEmpty, case let .iterating(semaphore) = self._state { return semaphore }
				return nil
			}
		}

		while case let semaphore? = iterating() {
			if case .timedOut = semaphore.wait(timeout: timeout) { throw Error.timedOut }
		}

		return self._serial.sync() {
			guard !self._values.isEmpty else { return nil }
			defer { self._values.removeFirst() }
			return self._values[0]
		}
	}

	func next() -> T? {
		do { return try self.next(timeout: .distantFuture) }
		catch { preconditionFailure("Invalid timeout") }
	}
}
