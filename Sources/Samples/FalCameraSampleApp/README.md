# FalCameraSampleApp

Status: legacy camera/realtime demo.

This sample compiles and demonstrates an older realtime camera pipeline, but it is not a modern reference implementation. It still uses older camera, image rendering, and observable-object patterns that should be rewritten before production use.

## Setup

The sample defaults to:

```swift
let fal = FalClient.withProxy("http://localhost:3333/api/fal/proxy")
```

Run a local proxy that owns `FAL_KEY`, or adapt the sample to a short-lived bearer-token flow. Do not embed permanent Fal API keys in the app.

## Known Legacy Areas

- Camera pipeline still uses manual dispatch queues.
- Image rendering path should be revisited before reuse.
- SwiftUI state is older sample-style code.
- The sample is excluded from CI and should be treated as a demo only.
