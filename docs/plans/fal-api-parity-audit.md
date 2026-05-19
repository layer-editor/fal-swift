# fal API Parity Audit

This is the living parity matrix for `FalClient` against current fal model API docs and the Python, JavaScript, Java/Kotlin, and Dart clients checked on 2026-05-18.

## Summary

The Swift client now covers the core model API workflows: direct `run`, queue-backed `subscribe`, manual queue `submit/status/response/cancel`, queue status streaming, direct model `/stream`, realtime WebSocket support, dynamic `Payload`, and `Codable` overloads. The remaining gaps are narrower: realtime token/path parity, storage direct-CDN/fallback/multipart behavior, release docs, sample cleanup, and CI/release metadata.

## Feature Matrix

| Capability | Current Swift | Current docs / peer clients | Priority |
| --- | --- | --- | --- |
| `run` | Present with platform options | Supports client HTTP timeout, start timeout, runner hint, retry/storage/fallback controls, and raw headers | Done |
| `subscribe` | Present with queue options | Supports `onEnqueue`, status-detail callbacks, client timeout semantics, and server cancel on timeout/cancellation | Done |
| `queue.submit` | Present | Preserves existing `String` request-id API and adds `QueueSubmitResult` metadata | Done |
| `queue.status` | Present | Includes tolerant logs plus request URLs, metrics, and error metadata through `QueueStatusDetail` | Done |
| `queue.result` / response | Present | Payload and typed `Decodable` response retrieval are available | Done |
| `queue.cancel` | Present | Documented `PUT /requests/{request_id}/cancel` endpoint | Done |
| `queue.streamStatus` | Present | Documented SSE endpoint implemented as `AsyncThrowingStream<QueueStatusDetail, Error>` | Done |
| `stream` | Present | Official method for `/stream` SSE endpoints | Done |
| realtime | Present, concurrency-hardened | Still needs custom path/token-provider parity and deeper fake socket tests | P1 |
| platform headers | Present | Server-side platform headers are modeled; client-side transient retry is implemented for queue status/result and storage PUT | Done |
| namespaced endpoints | Present | Peer clients preserve namespace/path pieces | Done |
| storage uploads | Improved | Initiates `fal-cdn-v3` uploads with file-name and lifecycle options; direct CDN, fallback, and multipart remain | P1/P2 |

## Queue API Status

Current files:

- `Sources/FalClient/Queue.swift`
- `Sources/FalClient/Queue+Codable.swift`
- `Sources/FalClient/QueueStatus.swift`
- `Sources/FalClient/FalClient.swift`

Implemented shape:

- `QueueSubmitResult`: `requestId`, `responseUrl`, `statusUrl`, `cancelUrl`, `queuePosition`.
- `QueueStatus`: keep enum ergonomics, but preserve common metadata across states.
- `Queue.cancel(_ id:of:) async throws`.
- `Queue.streamStatus(...) -> AsyncThrowingStream<QueueStatusDetail, Error>` backed by the queue status SSE endpoint.
- `Queue.subscribeToStatus(...) async throws -> QueueStatusDetail` for polling an existing request to a completed status detail.
- High-level `FalClient.subscribe` has `onEnqueue`, request options, timeout/cancellation handling, and detail-aware polling through `subscribeWithStatusDetails(...)`.

Compatibility rule: keep existing `submit(...) async throws -> String` available until a major version or deprecate it in favor of `enqueue`/`submitResult`.

## Request Options

Current `RunOptions` still carries endpoint path, HTTP method, and local URLRequest timeout, but now also models fal platform controls.

Implemented option design:

- Plain `[String: String]` raw headers.
- `startTimeout: TimeInterval?` mapped to `X-Fal-Request-Timeout`.
- `hint: String?` mapped to `X-Fal-Runner-Hint`.
- `priority: QueuePriority?` mapped to `X-Fal-Queue-Priority`.
- `storeInputOutput`, `objectLifecyclePreference`, retry-disable, and fallback-disable controls.
- Keep `timeoutInterval` named as client HTTP timeout to avoid confusion with server start timeout.

Naming rule: docs should call out the difference between:

- client HTTP timeout: local URLSession request timeout.
- client subscribe timeout: total local wait for queue completion.
- start timeout: fal server-side time-to-start deadline.
- app request timeout: app developer-controlled per-attempt processing limit.

## Streaming API

Current Swift has shared SSE transport, queue status streaming, and direct model `/stream` support.

Implemented surface:

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
- Lifecycle duration validation before request construction.
- Clean presigned PUT requests without Fal auth or lifecycle headers.
- Invalid storage URL associated values redact signed query strings and fragments before being thrown.
- Built-in URLSession storage PUTs reject unsafe redirects before following them, and fake/custom transport responses are still final-URL validated.
- Numeric IPv4 forms and IPv6 loopback/private aliases, including IPv4-mapped and IPv4-compatible forms, are rejected.

Still separate from this small chunk:

- Direct `v3.fal.media` upload path with CDN auth token management.
- Fallback repositories.
- Multipart upload for large files.
- DNS rebinding/private-DNS mitigation for public-looking storage hostnames, likely through an allowlist or preflight resolution policy.

## References

- [fal async queue docs](https://fal.ai/docs/documentation/model-apis/inference/queue)
- [fal streaming docs](https://fal.ai/docs/documentation/model-apis/inference/streaming)
- [fal realtime docs](https://fal.ai/docs/documentation/model-apis/inference/real-time)
- [fal platform headers](https://fal.ai/docs/documentation/model-apis/common-parameters)
- Peer source checked locally under `/tmp/fal-audit*` during the 2026-05-18 audit.
