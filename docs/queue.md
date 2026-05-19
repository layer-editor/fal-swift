# Queue

Use queue-backed APIs for model requests that may take more than a few seconds.

## Subscribe

`subscribe` submits a request, polls until completion, and returns the model response.

```swift
let result = try await fal.subscribe(
    to: "fal-ai/flux/dev",
    input: ["prompt": .string("a pencil sketch of a desk lamp")],
    pollInterval: .milliseconds(500),
    timeout: .minutes(3),
    includeLogs: true
) { status in
    print(status)
}
```

On local timeout or Swift task cancellation, high-level `subscribe` attempts to cancel the server-side queue request when it knows the request ID.

## Manual Queue Flow

Use manual queue APIs when the app needs explicit lifecycle control.

```swift
let submit = try await fal.queue.submitDetailed(
    "fal-ai/flux/dev",
    input: ["prompt": .string("a compact synth workstation")]
)

let finalStatus = try await fal.queue.subscribeToStatus(
    "fal-ai/flux/dev",
    of: submit.requestId,
    includeLogs: true
)

let response = try await fal.queue.response("fal-ai/flux/dev", of: submit.requestId)
```

`subscribeToStatus` observes an existing request. It does not cancel that request if the local observer times out.

## Cancellation

```swift
try await fal.queue.cancel("fal-ai/flux/dev", of: requestId)
```

Cancellation uses Fal's queue cancellation endpoint. If cancellation fails while handling a local timeout, the original timeout error is preserved.

## Status Streaming

```swift
let statuses = try await fal.queue.streamStatus(
    "fal-ai/flux/dev",
    of: requestId,
    includeLogs: true
)

for try await status in statuses {
    print(status)
}
```

Status streaming uses the queue SSE endpoint and shares the package's SSE parsing behavior.

## Request Options

`RunOptions` supports Fal platform controls such as headers, start timeout, runner hint, queue priority, no-retry, storage preferences, object lifecycle, and fallback disable flags. Named options override matching raw headers.

Queue status and response polling use a fixed internal transient retry policy. Public retry knobs are intentionally deferred until an app has a concrete need for them.
