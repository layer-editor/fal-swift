# Realtime

Realtime APIs use Fal's WebSocket token endpoint and connection pool.

```swift
let connection = try fal.realtime.connect(
    to: "fal-ai/fast-turbo-diffusion/image-to-image",
    connectionKey: "CanvasPreview",
    throttleInterval: .milliseconds(128)
) { (result: Result<MyResponse, Error>) in
    switch result {
    case let .success(response):
        print(response)
    case let .failure(error):
        print(error)
    }
}
```

Send typed inputs through the connection:

```swift
try connection.send(MyInput(prompt: prompt, image: imageData))
```

Close connections when their owner goes away:

```swift
connection.close()
```

## Paths

Use the model ID path when the realtime endpoint is not the default route:

```swift
let connection = try fal.realtime.connect(
    to: "fal-ai/fast-turbo-diffusion/image-to-image",
    connectionKey: "CanvasPreview",
    throttleInterval: .milliseconds(128),
    onResult: handleResult
)
```

## Token Provider Decision

The package does not expose a public custom realtime token-provider hook right now. Token refresh uses the current Fal REST endpoint internally, and app credential protection should happen through proxy or short-lived bearer-token setup. A public provider would add expiration, refresh, and concurrency API surface before there is a concrete product need.

## Samples

`Sources/Samples/FalRealtimeSampleApp` demonstrates the API shape, but it is a sample app, not the source of truth for production SwiftUI architecture.
