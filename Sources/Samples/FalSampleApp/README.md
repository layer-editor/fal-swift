# FalSampleApp

Status: maintained as a small queue API reference.

This sample shows a simple SwiftUI app that submits a model request through `fal.subscribe`, observes queue logs, and renders the returned image URL.

## Setup

The sample defaults to:

```swift
let fal = FalClient.withProxy("http://localhost:3333/api/fal/proxy")
```

Run a local proxy that owns `FAL_KEY`, or change `fal.swift` for local experimentation. Do not ship a production app with long-lived Fal credentials embedded in the app bundle.

## Notes

- The sample is intentionally minimal and is not production app architecture.
- If model IDs or schemas change, update the prompt/request shape before treating the sample as current.
