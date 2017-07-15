# Blocking networking

```swift
DispatchQueue.global().async() {
	let (response, data) = try! context.perform(request)
}
```
