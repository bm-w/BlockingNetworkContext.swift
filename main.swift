//
//  main.swift
//  BlockingNetwork
//
//  Created by Bastiaan Marinus van de Weerd on 11/07/2017.
//  Copyright © 2017 Bastiaan Marinus van de Weerd. All rights reserved.
//


import Foundation


print("Go...")
let serial = DispatchQueue.global()
let concurrent = DispatchQueue.global()
let group = DispatchGroup()

final class Box { var values: [Int] = [], push: [(Int?) -> ()] = [] }
let box = Box()

for i in 0..<5 {
	serial.asyncAfter(deadline: .now() + TimeInterval(i)) {
		var push: ((Int?) -> ())!
		let iterator = BlockingIterator(push: &push, values: box.values, target: serial)
		box.push.append(push)

		concurrent.async(group: group) {
			print("Go (\(i))...")
			for value in AnySequence({ iterator }) {
				print("Value (\(i)):", value)
			}
			print("Completed (\(i))!")
		}
	}
}

for i in 0..<10 {
	print("Push:", i)
	serial.sync() {
		box.values.append(i)
		for push in box.push {
			push(i)
		}
	}
	sleep(1)
}

for push in box.push {
	push(nil)
}

group.wait()
print("All completed!")

sleep(1)
print("Ding!")
