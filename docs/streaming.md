# Streaming

Direct streaming uses a model's `fal.run` server-sent events endpoint. It is not queue-backed, so queue priority, queue retry behavior, and queue status polling do not apply.

## Payload Events

```swift
let events = try await fal.stream(
    "fal-ai/flux/dev",
    input: ["prompt": .string("a glass greenhouse in pencil")]
)

for try await event in events {
    print(event)
}
```

## Typed Events

```swift
struct StreamEvent: Decodable {
    let type: String
}

let events: AsyncThrowingStream<StreamEvent, Error> = try await fal.stream(
    "fal-ai/flux/dev",
    input: ["prompt": "a small print studio"]
)
```

Typed `Encodable` inputs containing `Data` are rejected before request encoding. Use the `Payload` API with `.data` when binary input should be uploaded before the stream request.

## Custom Paths And Timeout

```swift
let options = StreamOptions(path: "/stream", timeoutInterval: 120)
let events = try await fal.stream("fal-ai/flux/dev", input: input, options: options)
```

The stream is pull-driven by `AsyncSequence` iteration. The SSE parser tolerates comments, heartbeats, blank separators, multiline `data:` events, and final events before EOF.
