//
//  main.swift
//  BlockingNetwork
//
//  Created by Bastiaan Marinus van de Weerd on 11/07/2017.
//  Copyright © 2017 Bastiaan Marinus van de Weerd. All rights reserved.
//


import Foundation


func go(index: Int) {
	var request = URLRequest(url: URL(string: "https://httpbin.org/post")!)
	request.httpMethod = "POST"
	request.httpBody = Data(bytesNoCopy: UnsafeMutableRawPointer.allocate(bytes: 32767, alignedTo: 8), count: 32767, deallocator: .free)
	print("Sending request (\(index)):")
	print(request)

	let (cancel: _, resume: _, sending, receive) = Context().perform(request)

	var totalBytesSent: UInt = 0
	for bytesSent in sending() {
		totalBytesSent += bytesSent
		print("Sent (\(index)): \(bytesSent) bytes (\(totalBytesSent) total)")
	}

//	cancel()

	print("Waiting for response (\(index))...")
	let (response, receiving, complete): (HTTPURLResponse, AnyIterator<Data>, () throws -> ())
	do { let t = try receive(); (response, receiving, complete) = (t.0, t.1(), t.2) }
	catch { dump(error, name: "Error receiving (\(index))"); fatalError() }

	print("Received response (\(index)):")
	print(response)

//	var data = Data()
	var totalBytesReceived: UInt = 0
	for dataReceived in receiving {
//		data.append(dataReceived)
		totalBytesReceived += UInt(dataReceived.count)
		print("Received (\(index)): \(dataReceived.count) bytes (\(totalBytesReceived) total)")
	}

	print("Waiting for completion (\(index))...")
	do { try complete() }
	catch { dump(error, name: "Error completing (\(index))"); fatalError() }
	print("Completed (\(index))!")
}


print("Go...")
let concurrent = DispatchQueue.global()
let group = DispatchGroup()

let start = Date()
DispatchQueue(label: "eu.bm-w.Concurrent", qos: .userInteractive, attributes: .concurrent).asyncAfter(deadline: .now() + 1) {
	print("Ding (\(-start.timeIntervalSinceNow) s.)!")
}

for i in 0..<80 {
	concurrent.async(group: group) {
		go(index: i)
	}
}

group.wait()
print("All completed!")

sleep(1)
print("Ding!")
