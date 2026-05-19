# Samples

Sample apps are lightweight references for package APIs. They are not production app architecture and should not be copied into production without app-specific auth, state, and error handling.

All samples default to a local proxy:

```swift
let fal = FalClient.withProxy("http://localhost:3333/api/fal/proxy")
```

Run a proxy that owns `FAL_KEY`, or adapt the sample to a short-lived bearer-token flow. Do not ship permanent Fal API keys in iOS or macOS apps.

| Sample | Status | Notes |
| --- | --- | --- |
| `FalSampleApp` | Maintained basic queue reference | Shows `subscribe`, queue logs, and returned image URLs. |
| `FalRealtimeSampleApp` | Maintained realtime reference | Shows realtime connection/send and async image loading. |
| `FalCameraSampleApp` | Legacy demo | Compiles as a camera/realtime demo, but uses older camera and rendering patterns. Not a modern reference implementation. |

Sample builds are intentionally not part of CI yet because simulator availability and signing settings are more brittle than the library target.
