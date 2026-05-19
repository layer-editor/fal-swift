# FalRealtimeSampleApp

Status: maintained as a realtime API reference.

This sample shows a SwiftUI drawing surface connected to a Fal realtime endpoint. It demonstrates:

- `fal.realtime.connect`
- typed realtime input/output
- `connection.send(...)`
- async image loading from `FalImage`
- closing the connection when the view disappears, with reconnect on the next appearance or send

## Setup

The sample defaults to:

```swift
let fal = FalClient.withProxy("http://localhost:3333/api/fal/proxy")
```

Run a local proxy that owns `FAL_KEY`, or replace this with a short-lived bearer-token flow for app development. Do not embed permanent Fal API keys in a client app.

## Notes

This sample is intentionally small. It is useful for package API shape, not as a complete SwiftUI app architecture.
