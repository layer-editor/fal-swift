# Reliability and Testing Plan

This document tracks correctness risks and the targeted tests needed before broad API work. The goal is confidence, not a large test suite for its own sake.

## Current Test Baseline

Existing tests now cover helper behavior plus the first request, queue, storage, and error hardening slices:

- `Tests/FalClientTests/TimeoutSpec.swift`
- `Tests/FalClientTests/UtilitySpec.swift`
- `Tests/FalClientTests/CodableSubscribeTests.swift`
- `Tests/FalClientTests/ClientRequestTests.swift`
- `Tests/FalClientTests/QueueStatusTests.swift`
- `Tests/FalClientTests/StorageTests.swift`
- `Tests/FalClientTests/HTTPTransportTests.swift`
- `Tests/FalClientTests/PublicErrorTests.swift`
- `Tests/FalClientTests/QueueStreamStatusTests.swift`

Recently added request-option coverage:

- Direct `run` platform headers and named-option precedence over raw headers.
- Payload and typed queue submit options for `startTimeout`, `hint`, and queue `priority`.
- Rich queue submit metadata through `Queue.submitDetailed(...)`.
- Typed `subscribe(onEnqueue:)` callback metadata and custom queue fallback behavior.
- Queue status SSE request construction, path escaping, `logs=1`, default query omission, decoding, heartbeat-tolerant parsing, and HTTP error payload preservation.
- Direct model stream request construction, default and custom stream paths, client HTTP timeout, Payload and typed event decoding, HTTP error payload preservation, and typed binary input rejection before request construction.
- Reserved namespace endpoint parsing for `workflows/...` and `comfy/...`, including submit path preservation and namespace/owner/alias queue-base construction for status, stream-status, response, and cancel.
- Storage upload options for generated/default file names, sanitized custom file names, uploaded-file lifecycle headers on initiate, and clean presigned PUT headers/body.
- Object lifecycle durations are rejected before request construction when they are non-finite or not greater than zero.

Remaining gaps:

- Public transport injection for downstream package tests; the current seam is intentionally internal.
- 422 validation payload message behavior for structured `detail` arrays.
- Fake WebSocket/session boundary tests around realtime open/receive/close behavior.
- Storage upload host trust policy beyond client-side URL rejection, especially DNS names that resolve to private IPs.
- Realtime WebSocket lifecycle tests with a fake socket/session boundary.

## Test Infrastructure First

Add one of these before feature work:

1. Internal `HTTPTransport` protocol plus fake transport.
2. `URLProtocol` backed test session injection.

Implemented: internal `HTTPTransport` plus fake transport for request/response unit tests. One public-surface error test still uses `URLProtocol` because the transport seam is not public.

## P0 Tests

### Typed Subscribe Timeout

Files:

- Modify: `Sources/FalClient/Client+Codable.swift`
- Test: new queue subscribe test file under `Tests/FalClientTests/`

Expected failing behavior:

- A typed subscription with a 3 second timeout and 1 second poll interval should poll about three times.
- Current code accumulates elapsed time incorrectly and can timeout early as polling continues.

Acceptance:

- Typed and untyped `subscribe` share the same deadline logic.
- Both use monotonic deadline math and capped sleeps.
- Cancellation is checked between polls.
- A status call that does not observe cancellation cannot hold the subscribe call past the local timeout.

### Queue Query Parameters

Files:

- Modify: `Sources/FalClient/Queue.swift`
- Test: request builder or queue client test.

Expected failing behavior:

- GET queue requests build merged `queryParams` but send only `params`.

Acceptance:

- GET input-derived query parameters and explicit query parameters are both sent.
- Explicit params win on key collision, matching current merge intent.

### Queue Status Decoding

Files:

- Modify: `Sources/FalClient/QueueStatus.swift`
- Test: queue status decoding tests.

Fixtures:

- `IN_QUEUE` with `request_id`, `queue_position`, `response_url`, `status_url`, `cancel_url`.
- `IN_PROGRESS` with logs containing `message` and `timestamp` only.
- `COMPLETED` with logs, `metrics.inference_time`, `error`, and `error_type`.

Acceptance:

- Decoding is tolerant of missing log level labels.
- Known metadata is preserved.
- Unknown future fields do not fail decoding.
- High-level subscribers can opt into `subscribeWithStatusDetails(...)` for status metadata without breaking existing `subscribe` trailing-closure call sites.
- Existing queued requests can be observed with `Queue.subscribeToStatus(...)`, including status detail callbacks and final metadata, without cancelling the server-side request if the observer times out.

## P1 Tests

### Cancellation

Files:

- Modify: `Sources/FalClient/Queue.swift`
- Modify: `Sources/FalClient/FalClient.swift`
- Modify: `Sources/FalClient/Client+Codable.swift`

Cases:

- `subscribe` timeout after `submit` should call queue cancel if request ID is known. Covered for typed subscribe.
- Swift task cancellation during polling should attempt queue cancel and still surface cancellation to the caller. Covered for typed subscribe.
- Cancel failure should not hide the original timeout/cancellation unless cancellation was the user-requested operation. Covered for typed subscribe timeout.
- Successful completion should not cancel. Covered for typed subscribe.
- Remaining: add explicit coverage for payload `FalClient.subscribe` and `subscribeWithStatusDetails` timeout/cancellation paths.

### Queue Enqueue Metadata

Files:

- Modify: `Sources/FalClient/Queue.swift`
- Modify: `Sources/FalClient/Queue+Codable.swift`
- Modify: `Sources/FalClient/Client.swift`
- Modify: `Sources/FalClient/Client+Codable.swift`

Acceptance:

- Existing `submit -> String` remains source-compatible.
- `submitDetailed` preserves `requestId`, `responseUrl`, `statusUrl`, `cancelUrl`, and `queuePosition` when present.
- `QueueSubmitResult` is constructible by downstream queue conformers and tests.
- `subscribe(onEnqueue:)` fires after submit and before polling.
- Custom queues that only implement the original submit contract still get a synthesized enqueue result instead of falling through to the network-backed default path.

### Retry Policy

Files:

- Modify: `Sources/FalClient/Client+Request.swift` or new request executor file.

Cases:

- Retry transient transport errors.
- Retry selected ingress/status codes for idempotent status/result calls.
- Do not retry `CancellationError`.
- Do not retry fal user timeout responses with `X-Fal-Request-Timeout-Type: user`.
- Preserve final response metadata in thrown errors.
- Do not retry direct `/stream` requests; direct streaming is outside queue retry semantics.

### SSE and Direct Streaming

Files:

- Modify: `Sources/FalClient/HTTPTransport.swift`
- Modify: `Sources/FalClient/QueuePolling.swift` or a new generic streaming decoder file.
- Modify: `Sources/FalClient/FalClient.swift`
- Test: direct stream tests under `Tests/FalClientTests/`

Acceptance:

- [x] SSE parsing remains pull-driven by caller iteration, without eager producer tasks that can buffer unbounded events.
- [x] Parser skips comments, heartbeat frames, and empty event delimiters without ending the stream early.
- [x] Parser supports multiline `data:` fields and EOF after a final event without a trailing blank line.
- [x] Non-2xx SSE responses preserve Fal HTTP error payloads using a bounded error body.
- [x] `FalClient.stream(...)` sends a direct request to `fal.run`, defaults to `"/stream"`, and does not send queue-only platform headers.
- [x] Payload and typed `Decodable` stream overloads decode each JSON event independently.
- Tests use fake transports only and never make live Fal API calls.

### Platform Request Options

Files:

- Modify: `Sources/FalClient/Client.swift`
- Modify: `Sources/FalClient/Client+Request.swift`
- Modify: `Sources/FalClient/Queue.swift`
- Modify: `Sources/FalClient/Queue+Codable.swift`

Acceptance:

- Raw `headers` are applied to outbound requests.
- Named options set the documented fal platform headers and override raw values for the same platform header.
- Direct `run` supports `startTimeout`, `hint`, retry disable, I/O storage, object lifecycle, fallback disable, and raw headers.
- Queue `submit` supports those shared controls plus `queuePriority`.

### Error Metadata

Files:

- Modify: `Sources/FalClient/FalError.swift`
- Modify: `Sources/FalClient/Client+Request.swift`

Cases:

- 422 model validation response preserves payload.
- 503 with `X-Fal-Error-Type` exposes machine-readable error type.
- 504 with `X-Fal-Request-Timeout-Type: user` exposes timeout type.
- `x-fal-request-id` is exposed when present.
- Non-Fal diagnostic headers are not exposed on public HTTP errors.
- Invalid URL descriptions redact credentials, query strings, and fragments.

### Storage Uploads

Files:

- Modify: `Sources/FalClient/Storage.swift`
- Modify: `Sources/FalClient/Queue+Codable.swift`
- Modify: `Sources/FalClient/Client+Codable.swift`

Cases:

- Top-level `Payload.data` uploads.
- Nested dictionary and array data uploads recursively. Covered by `StorageTests`.
- Invalid upload URL throws instead of crashing and rejects malformed, hostless, loopback, private, trailing-dot loopback, IPv4-mapped IPv6 loopback, numeric/hex/octal loopback, and invalid returned file URLs.
- Upload initiation uses `rest.fal.ai` with `storage_type=fal-cdn-v3`, generated file names by default, custom sanitized file names when requested, and upload lifecycle headers only on the initiate request.
- Presigned PUT requests keep the original body, content type, content length, and do not receive Fal authorization or lifecycle headers.
- Invalid object lifecycle durations throw before any request is sent.
- Invalid storage URL associated values redact signed query strings and fragments before being thrown.
- Built-in URLSession storage PUTs reject unsafe redirects before following them; fake/custom transports still get final response URL validation as a compatibility fallback.
- Safe 307 storage redirects are allowed by the URLSession transport while preserving PUT method and content type.
- IPv4-compatible and hex IPv4-mapped IPv6 loopback aliases are rejected.
- Typed `Encodable` containing `Data` throws a documented unsupported-input error before sending base64 JSON accidentally. Covered for typed `run` and typed `queue.submit`, including custom `encode(to:)` implementations.
- `Payload.data` is rejected for GET queue requests before query serialization.
- POST payload auto-upload is exercised through the `Storage` protocol extension so custom storage conformers are covered.

## Realtime Reliability

Current risks:

- The global connection pool is now protected by `RealtimeConnectionPool`.
- `WebSocketConnection` mutable state is now serialized through one state queue.
- Remaining risk: there is no fake WebSocket/session boundary, so open/receive/close flows are still mostly covered by compile-time checks and pool unit tests rather than full lifecycle tests.
- Token refresh uses fixed assumptions and older endpoint shape.

Plan:

- Add fake WebSocket/session boundary tests around connection open, queued send flush, receive errors, and close behavior.
- Consider an actor-based connection implementation if the session boundary is refactored more deeply.
- Keep public realtime API stable while making token refresh and lifecycle behavior stricter.

## Build and Test Commands

Use targeted commands by default:

```bash
swift test --filter UtilitySpec
swift test --filter TimeoutSpec
swift test --filter QueueStatus
swift test --filter QueueRequest
swift test --filter Storage
```

Run the whole package only when touching shared transport, package configuration, or public API:

```bash
swift test
swift build --target FalClient --configuration release
```

## References

- [fal async queue docs](https://fal.ai/docs/documentation/model-apis/inference/queue)
- [fal request error types](https://fal.ai/docs/documentation/model-apis/request-errors)
- [fal platform headers](https://fal.ai/docs/documentation/model-apis/common-parameters)
