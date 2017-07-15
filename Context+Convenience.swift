//
//  Context+Convenience.swift
//  BlockingNetwork
//
//  Created by Bastiaan Marinus van de Weerd on 13/07/2017.
//  Copyright © 2017 Bastiaan Marinus van de Weerd. All rights reserved.
//


import Foundation


extension Context {
///	Returns three closures:
///	 -  `cancel`: cancels the request (not guaranteed: cancelation may not be acknowledged until the request is already fully sent, or the response already fully received);
///	 -  `resume`: resumes the request (the request will also resume upon calling `receiveComplete`);
///	 -  `receiveComplete`: blocks, then throws or returns the HTTP response and optional body data.
///
///	Usage:
///
///	    let request: URLRequest = ...
///	    let (cancel, _, receiveComplete) = context.perform(request)
///	    let (response, data) = try! receiveComplete()
///
	public func perform(_ request: URLRequest) -> (cancel: () -> (), resume: () -> (), receiveComplete: () throws -> (HTTPURLResponse, Data?)) {
		let (cancel, resume, _, receive) = self.perform(request)
		return (cancel, resume, {
			let (response, receiving, complete): (HTTPURLResponse, AnyIterator<Data>, complete: () throws -> ()) = try {
				let (response, receiving, complete) = try receive()
				return (response, receiving(), complete)
			}()

			var accumulatedData = Data()
			for data in receiving { accumulatedData.append(data) }

			try complete()

			return (response, accumulatedData.isEmpty ? nil : accumulatedData)
		})
	}

///	Blocks, then throws or returns the HTTP response and optional body data.
///
///	Usage:
///
///	    let request: URLRequest = ...
///	    let (response, data) = try! context.perform(request)()
///
	public func perform(_ request: URLRequest) throws -> (HTTPURLResponse, Data?) {
		return try self.perform(request).receiveComplete()
	}
}
