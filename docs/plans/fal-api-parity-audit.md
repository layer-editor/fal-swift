# fal API Parity Audit

This is the living parity matrix for `FalClient` against current fal model API docs and the Python, JavaScript, Java/Kotlin, and Dart clients checked on 2026-05-18.

## Summary

The Swift client has a useful core: direct `run`, queue-backed `subscribe`, manual queue `submit/status/response`, realtime WebSocket support, dynamic `Payload`, and `Codable` overloads. The main gap is that the current fal client contract is broader: official docs now describe `run`, `subscribe`, `submit`, `stream`, and realtime, with queue cancellation, status streaming, platform headers, richer status metadata, and safer timeout semantics.

## Feature Matrix

| Capability | Current Swift | Current docs / peer clients | Priority |
| --- | --- | --- | --- |
| `run` | Present, basic options | Supports `timeout`, `start_timeout`, `hint`, headers in Python; JS has timeout headers | P1 |
| `subscribe` | Present, polling only | Supports queue options, `on_enqueue`, client timeout semantics, server cancel on timeout | P0/P1 |
| `queue.submit` | Returns only `String` request ID | Returns request ID plus status/result/cancel URLs and queue position | P1 |
| `queue.status` | Polling, strict decoding | Includes request URLs, logs, metrics, error fields | P0 |
| `queue.result` / response | Present | Present | P1 for typed response wrapper metadata |
| `queue.cancel` | Missing | Documented and implemented in JS/Python | P1 |
| `queue.streamStatus` | Missing | Documented SSE endpoint and implemented in JS/Java | P1 |
| `stream` | Present | Official method for `/stream` SSE endpoints | P1 |
| realtime | Present | Needs custom path/token-provider parity and concurrency hardening | P1 |
| platform headers | Mostly missing | `start_timeout`, `hint`, `priority`, custom headers, storage/retry/fallback controls | P1 |
| namespaced endpoints | Present | Peer clients preserve namespace/path pieces | P1 |
| storage uploads | Improved | Initiates `fal-cdn-v3` uploads with file-name and lifecycle options; direct CDN, fallback, and multipart remain | P1/P2 |

## Queue API Gaps

Current files:

- `Sources/FalClient/Queue.swift`
- `Sources/FalClient/Queue+Codable.swift`
- `Sources/FalClient/QueueStatus.swift`
- `Sources/FalClient/FalClient.swift`

Planned shape:

- `QueueSubmitResult`: `requestId`, `responseUrl`, `statusUrl`, `cancelUrl`, `queuePosition`.
- `QueueStatus`: keep enum ergonomics, but preserve common metadata across states.
- `Queue.cancel(_ id:of:) async throws`.
- `Queue.streamStatus(...) -> AsyncThrowingStream<QueueStatusDetail, Error>` backed by the queue status SSE endpoint.
- `Queue.subscribeToStatus(...) async throws -> QueueStatusDetail` for polling an existing request to a completed status detail.
- High-level `FalClient.subscribe` gains `onEnqueue`, options, timeout cancellation, and status-streaming mode later.

Compatibility rule: keep existing `submit(...) async throws -> String` available until a major version or deprecate it in favor of `enqueue`/`submitResult`.

## Request Options

Current `RunOptions` mixes endpoint path, method, and URLRequest timeout. It does not model fal platform controls.

Additive option design:

- `RequestHeaders` or plain `[String: String]`.
- `startTimeout: TimeInterval?` mapped to `X-Fal-Request-Timeout`.
- `hint: String?` mapped to `X-Fal-Runner-Hint`.
- `priority: QueuePriority?` mapped to `X-Fal-Queue-Priority`.
- `storageSettings` for object lifecycle once storage is modernized.
- Keep `timeoutInterval` named as client HTTP timeout to avoid confusion with server start timeout.

Naming rule: docs should call out the difference between:

- client HTTP timeout: local URLSession request timeout.
- client subscribe timeout: total local wait for queue completion.
- start timeout: fal server-side time-to-start deadline.
- app request timeout: app developer-controlled per-attempt processing limit.

## Streaming API

Current Swift has shared SSE transport, queue status streaming, and direct model `/stream` support.

Implemented first surface:

- Internal generic JSON SSE decoder shared by queue status streaming and direct model streaming.
- `FalClient.stream(_ app: String, input: Payload?, options: StreamOptions = .init()) -> AsyncThrowingStream<Payload, Error>`.
- `FalClient.stream<Event: Decodable>(...) -> AsyncThrowingStream<Event, Error>`.
- Default path: `/stream`.
- Direct `fal.run` subdomain, not `queue.fal.run`.
- Public direct-stream options should be intentionally narrow: endpoint path and client HTTP timeout. Fal documents direct streaming as not supporting queue-only controls such as `hint`, `priority`, `start_timeout`, `client_timeout`, or custom queue headers.
- Document that direct streaming does not get queue retries.

Implementation note: this should reuse the new internal request builder and transport seams. Avoid building a second ad hoc HTTP stack. Keep stream decoding pull-driven and cover SSE comments/heartbeats, blank separators, multiline `data:` payloads, EOF after a final event, bounded error bodies, and HTTP error payload preservation.

## Endpoint Parsing

`AppId.parse` now distinguishes reserved namespace endpoint IDs from ordinary model IDs.

Implemented model:

- `AppId` includes `namespace: String?`, `ownerId`, `appAlias`, `path`, `endpointPath`, and `queueBasePath`.
- Reserved namespaces are `workflows` and `comfy`.
- Direct calls and queue submit preserve `endpointPath`, including optional endpoint subpaths.
- Queue follow-up calls use `queueBasePath`, which preserves namespace/owner/alias for reserved namespaces and preserves the full model ID for ordinary model IDs such as `fal-ai/flux/schnell`.
- Characterization tests cover path joining, reserved namespace parsing, submit preservation, and status/stream/result/cancel queue-base construction.

## Storage Parity

Current storage covers simple and nested `Payload.data` uploads and now exposes a small options surface for upload metadata.

Implemented:

- Recursive `Payload` upload transform.
- Explicit typed `Data` behavior.
- Better upload URL validation.
- Custom file names/content type.
- Object lifecycle preferences.
- `rest.fal.ai` initiate endpoint with `storage_type=fal-cdn-v3`.

Still separate from this small chunk:

- Direct `v3.fal.media` upload path with CDN auth token management.
- Fallback repositories.
- Multipart upload for large files.
- Redirect validation and stricter invalid presigned URL redaction.

## References

- [fal async queue docs](https://fal.ai/docs/documentation/model-apis/inference/queue)
- [fal streaming docs](https://fal.ai/docs/documentation/model-apis/inference/streaming)
- [fal realtime docs](https://fal.ai/docs/documentation/model-apis/inference/real-time)
- [fal platform headers](https://fal.ai/docs/documentation/model-apis/common-parameters)
- Peer source checked locally under `/tmp/fal-audit*` during the 2026-05-18 audit.
