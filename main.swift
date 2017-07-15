//
//  main.swift
//  BlockingNetwork
//
//  Created by Bastiaan Marinus van de Weerd on 11/07/2017.
//  Copyright © 2017 Bastiaan Marinus van de Weerd. All rights reserved.
//


import Foundation


let context = Context(target: DispatchQueue(label: "eu.bm-w.BlockingNetwork"))

DispatchQueue.global().sync() {
	var request = URLRequest(url: URL(string: "https://httpbin.org/post")!)
	request.httpMethod = "POST"
	request.httpBody = Data(bytesNoCopy: UnsafeMutableRawPointer.allocate(bytes: 32767, alignedTo: 8), count: 32767, deallocator: .free)

	print("Sending request (body length: \(request.httpBody!.count) bytes)")
	print(request)

	let (response, data): (HTTPURLResponse, Data?)
	do { (response, data) = try context.perform(request) }
	catch { dump(error, name: "Error receiving (\(index))"); return }

	print("Received response (body length: \(data.map({ "\($0.count) bytes" }) ?? "no body")):")
	print(response)
}
