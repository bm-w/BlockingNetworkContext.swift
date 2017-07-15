# Blocking networking

```swift
DispatchQueue.global().async() {
	let request: URLRequest = ...
	let (cancel, _, sending, receive) = context.perform(request)
	var totalBytesSent: UInt = 0
	for bytesSent in sending() { totalBytesSent += bytesSent }
	if isNoLongerRequired { cancel() }
	let (response, receiving, complete) = try! receive()
	var accumulatedData = Data()
	for data in receiving() { accumulatedData.append(data) }
	try! complete()
}
```

