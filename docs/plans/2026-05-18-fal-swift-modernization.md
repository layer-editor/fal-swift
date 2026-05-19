# Fal Swift Modernization Implementation Plan

> **For Claude/Codex:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` when executing any approved task from this plan. Keep changes small, write targeted tests first, and do not broaden scope without updating this document.

**Goal:** Bring `FalClient` into practical parity with current fal model API clients while improving safety, testability, and Apple-platform ergonomics without refactoring for its own sake.

**Architecture:** Keep the public facade small: `FalClient` plus `queue`, `storage`, `realtime`, and a new streaming surface. Add internal seams only where they pay for themselves: request construction, HTTP transport, queue polling/status streaming, generic SSE event decoding, and error metadata. Preserve current call sites first; introduce additive options and deprecations before removals.

**Streaming Architecture Rule:** SSE consumers should be pull-driven by the caller's `AsyncSequence` iteration, not eager producer tasks with unbounded buffering. Treat SSE as a protocol boundary: support comments/heartbeats, extra blank separators, multiline `data:` payloads, EOF after a final event, bounded non-2xx error bodies, and Fal HTTP error payload preservation.

**Tech Stack:** Swift Package Manager, async/await, URLSession, Codable, XCTest or Swift Testing, mocked URLProtocol or internal HTTP transport for network tests.

---

## Status

- [x] Audited current Swift package against official fal docs and peer clients.
- [x] Created living planning docs under `docs/plans/`.
- [x] Added initial characterization tests for current behavior and known bugs.
- [x] Implemented queue/request parity gaps.
- [x] Implemented shared SSE transport and queue status streaming.
- [x] Implemented direct model `/stream` support.
- [x] Hardened storage uploads and typed binary handling.
- [ ] Updated README, sample docs, CI, and release metadata.

## Source Baseline

Local repo:

- Fork: `layer-editor/fal-swift`
- Current branch: `main`
- Current local head during audit: `e4f8c3a Return concrete FalClient from factory methods`
- Upstream `fal-ai/fal-swift` shallow head during audit: `4a589b9 chore: update realtime example to use turbo`

External references checked:

- fal docs: [Client Setup](https://fal.ai/docs/documentation/model-apis/inference/client-setup), [Asynchronous Inference](https://fal.ai/docs/documentation/model-apis/inference/queue), [Streaming Inference](https://fal.ai/docs/documentation/model-apis/inference/streaming), [Real-Time Inference](https://fal.ai/docs/documentation/model-apis/inference/real-time), [Platform Headers](https://fal.ai/docs/documentation/model-apis/common-parameters), [Request Error Types](https://fal.ai/docs/documentation/model-apis/request-errors)
- Peer clients: `fal-ai/fal-js` at `442a757`, `fal-ai/fal` Python client at `e70e60a`, `fal-ai/fal-java` at `c998c35`, `fal-ai/fal-dart` at `6871206`

## Priority Model

`P0` means correctness or API behavior that can fail real users today.

`P1` means high-leverage parity or safety work needed before this should be treated as maintained.

`P2` means ergonomic, documentation, or release-quality work that should follow once the core API surface is stable.

## P0: Correctness and Safety

- [x] Fix typed `subscribe` timeout math in `Sources/FalClient/Client+Codable.swift`.
  - Current risk: elapsed time is accumulated as triangular time, so typed subscriptions can time out much earlier than requested.
  - Test first: a fake queue that remains `IN_QUEUE` should poll until the configured deadline, not a triangular elapsed threshold.
  - Follow-up review fix: cap poll sleeps to the remaining deadline and race status polling against the deadline.

- [x] Fix queue query parameter propagation in `Sources/FalClient/Queue.swift`.
  - Current risk: `runOnQueue` builds merged `queryParams` but passes `params` to `sendRequest`, so GET input params can be dropped.
  - Test first: queue GET requests with input plus explicit params should include both query sources.

- [x] Make queue log decoding tolerate current fal responses in `Sources/FalClient/QueueStatus.swift`.
  - Current risk: `RequestLog` requires `labels.level`, while current docs show log entries with only `message` and `timestamp`.
  - Follow-up review fix: tolerate absent `logs`, empty `labels`, and unknown future log levels.

- [x] Harden storage upload URL validation in `Sources/FalClient/Storage.swift`.
  - Current risk: storage upload directly `PUT`s returned URLs outside the configured client/proxy path.
  - Validate `upload_url` and `file_url` before upload: HTTPS, non-empty host, no userinfo, and no loopback/private/link-local/multicast hosts.
  - Non-canonical IPv4 forms such as integer, hex, octal, and shortened addresses are parsed before host safety checks.

- [x] Preserve current queue status metadata in `Sources/FalClient/QueueStatus.swift`.
  - Added additive `QueueStatusDetail` / `Queue.statusDetail(...)` API with `requestId`, `statusUrl`, `responseUrl`, `cancelUrl`, optional `metrics`, optional `error`, optional `errorType`.
  - Kept existing `QueueStatus` enum cases source-compatible for downstream pattern matching.

- [x] Add a public, inspectable error surface.
  - Current risk: public APIs throw an internal `FalError`, so consumers cannot switch over `queueTimeout` or HTTP errors.
  - Include: HTTP status, message, parsed payload, request ID, response headers needed for `X-Fal-Error-Type` and `X-Fal-Request-Timeout-Type`.
  - Added public `FalError`, `FalHTTPError`, normalized response headers, typed Fal header accessors, and queue timeout request IDs.

- [x] Add testable HTTP seams before expanding network behavior.
  - Original risk: `URLSession.shared` was hard-coded, leaving request headers, retry, error, and upload behavior mostly untested.
  - Added internal `HTTPTransport` / `URLSessionHTTPTransport` and migrated request/storage tests off process-global `URLProtocol` where public API visibility does not require it.

## P1: fal API Parity

- [x] Add shared request options for current platform controls.
  - Include `headers`, `startTimeout`, `hint`, and queue `priority`.
  - Preserve `RunOptions` compatibility while adding additive initializers or option structs.
  - Map documented headers: `X-Fal-Request-Timeout`, `X-Fal-Runner-Hint`, `X-Fal-Queue-Priority`, `X-Fal-No-Retry`, `X-Fal-Store-IO`, `X-Fal-Object-Lifecycle-Preference`, and `x-app-fal-disable-fallback`.
  - Added `RunOptions` fields for raw headers, start timeout, runner hint, queue priority, retry disable, input/output storage, object lifecycle, and fallback disable. Named fields override matching raw platform headers.

- [ ] Expand queue API beyond `submit -> String`.
  - Add rich submit result or handle: `requestId`, `responseUrl`, `statusUrl`, `cancelUrl`, queue position when available. `Queue.submitDetailed(...)` now returns `QueueSubmitResult` while preserving existing `submit -> String`.
  - Add `cancel`.
  - Add `subscribeToStatus`. `Queue.subscribeToStatus(...)` now observes an existing request until completion and returns the final `QueueStatusDetail` without taking ownership of server-side cancellation.
  - Add `streamStatus` using the queue status SSE endpoint. `Queue.streamStatus(...)` now exposes Fal's `/requests/{request_id}/status/stream` SSE endpoint as an `AsyncThrowingStream<QueueStatusDetail, Error>`.
  - Add `onEnqueue` to high-level `subscribe`. Payload and typed subscribe overloads can now receive `QueueSubmitResult` after enqueue.
  - Add detail-aware subscribe callbacks so high-level subscribers can observe status metadata without manual `statusDetail` polling. `Payload` and typed `Decodable` `subscribeWithStatusDetails(...)` APIs are now available without changing existing `subscribe` trailing-closure behavior.
  - On client timeout or Swift task cancellation, attempt server-side cancel where a request ID is known. `Queue.cancel(...)` now uses the documented `PUT /requests/{request_id}/cancel` endpoint, and subscribe preserves the original timeout/cancellation error if server-side cancel fails.

- [x] Add `stream` support for model `/stream` endpoints.
  - Direct `fal.run` SSE, not queue-backed.
  - Expose typed and `Payload` event decoding.
  - Add a small internal generic SSE JSON decoder before the public API so queue status streaming and direct model streaming share stream semantics.
  - Limit the public option surface to direct-stream controls: path and client HTTP timeout. Do not apply queue-only controls such as priority, start timeout, runner hint, or queue retry flags.
  - Document that queue retry semantics do not apply to direct streaming.

- [ ] Fix endpoint parsing for namespaced endpoints.
  - Support IDs such as `workflows/...` and `comfy/...` without dropping namespace or path pieces during status/result URL construction.

- [ ] Modernize storage uploads after request options land.
  - Move away from `rest.alpha.fal.ai` where appropriate.
  - Add lifecycle settings, file names, recursive `Payload` transform, and explicit behavior for typed `Data`.
  - Recursive `Payload.data` upload transforms are now implemented for dictionaries and arrays.
  - Payload auto-upload now works through the `Storage` protocol, so custom storage conformers can participate.
  - Typed `Encodable` inputs containing `Data` now fail at JSON encoding time instead of silently sending base64 JSON, including custom `encode(to:)` implementations.
  - `Payload.data` on GET requests now fails before query serialization to avoid leaking binary data into URLs.
  - Evaluate fal CDN v3 and multipart support as a separate implementation step, because that can grow quickly.

## P1: Robustness and Test Coverage

- [ ] Replace duplicated subscribe polling with a shared queue poller.
  - Both typed and untyped APIs should share deadline, cancellation, logging, callback, and response-fetch behavior.

- [ ] Add client-side retry policy for transient transport/status/result failures.
  - Start with queue status/result and storage upload.
  - Avoid retrying Swift task cancellation and fal user timeout responses.
  - Match peer-client behavior only where it improves client-side network reliability; fal server-side queue retries are separate.
  - Do not add retries to direct `/stream`; Fal documents streaming as a direct SSE request outside queue retry semantics.

- [x] Make realtime state concurrency-safe.
  - Replaced the global mutable connection dictionary with a synchronized `RealtimeConnectionPool`.
  - Serialized mutable WebSocket connection state through a single state queue.
  - `swift build --target FalClient -Xswiftc -strict-concurrency=complete` now completes cleanly for the package target.

- [ ] Deprecate or replace unsafe synchronous media helpers.
  - `FalImageContent.data` force unwraps URLs and performs blocking network I/O.
  - Add async throwing load helpers before deprecating the property.

## P2: Ergonomics, Docs, and Release Quality

- [ ] Refresh `README.md`.
  - Use current model API language.
  - Show `Payload` and `Codable` results accurately.
  - Warn clearly against shipping API keys in client apps.
  - Replace unsafe realtime examples.

- [ ] Add DocC or markdown guides.
  - Setup and auth/proxy.
  - Queue submit/subscribe/cancel.
  - Streaming.
  - Realtime.
  - Storage uploads.
  - Error handling.

- [ ] Update sample apps or mark them as legacy.
  - Add per-sample README files with proxy setup and expected behavior.
  - Remove unsafe force unwraps and blocking image loads.
  - Move SwiftUI samples toward current observation/concurrency patterns.

- [ ] Fix release metadata.
  - Align `swift-tools-version` with syntax and CI.
  - Enable targeted CI tests.
  - Stop hardcoding user agent version `0.1.0`.
  - Add `CHANGELOG.md` and `CONTRIBUTING.md`.

## Drill-Down Docs

- [API parity audit](fal-api-parity-audit.md)
- [Reliability and testing plan](fal-reliability-and-testing.md)
- [Docs and release readiness](fal-docs-and-release-readiness.md)

## Done Log

- 2026-05-18: Audited current Swift code, official fal docs, and peer clients.
- 2026-05-18: Created this canonical plan and supporting drill-down documents.
- 2026-05-18: Fixed typed `subscribe` timeout math, queue GET query propagation, proxy auth key forwarding, credential redaction, queue endpoint path preservation, tolerant queue log decoding, typed queue response path preservation, existing query merging, and malformed upload URL handling.
- 2026-05-18: Added public inspectable error types with Fal request IDs, error types, timeout types, normalized headers, and queue timeout request IDs.
- 2026-05-18: Added recursive `Payload.data` storage upload transforms, typed binary input rejection, GET binary payload rejection, protocol-based storage auto-upload, and non-canonical IPv4 upload URL rejection.
- 2026-05-18: Added shared `RunOptions` platform controls and queue submit overloads for start timeout, runner hint, priority, retry disable, I/O storage, generated-file lifecycle, fallback disable, and raw headers.
- 2026-05-18: Added `QueueSubmitResult`, `Queue.submitDetailed(...)`, and high-level `subscribe(onEnqueue:)` overloads so callers can observe request/status/response/cancel URLs and queue position when Fal returns them.
- 2026-05-18: Added polling-based `Queue.subscribeToStatus(...)` for observing an existing request through completion with `QueueStatusDetail` callbacks and no implicit cancellation of the observed request on observer timeout.
- 2026-05-18: Ran branch simplification review and collapsed duplicated subscribe response polling, typed queue input conversion, queue polling loops, and overgrown `RunOptions` factory surfaces while preserving the canonical initializer for advanced request controls.
- 2026-05-18: Added `Queue.streamStatus(...)` for queue status SSE updates, including request-id path encoding, `logs=1` support, and shared SSE parsing through the internal HTTP transport seam.
- 2026-05-18: Updated streaming architecture guidance after queue status streaming review: pull-driven streams, bounded SSE error bodies, heartbeat/comment tolerance, shared generic event decoding before direct `/stream`, and explicit ownership semantics for queue observation versus request-owning subscribe flows.
- 2026-05-18: Added direct `FalClient.stream(...)` support for model `/stream` SSE endpoints with narrow `StreamOptions`, Payload and typed event decoding, custom stream paths, client HTTP timeout, and fake-transport coverage for error payloads and typed binary input rejection.

## Non-Goals

- Do not rewrite the package into a large layered architecture.
- Do not break existing `FalClient.withCredentials`, `withProxy`, `run`, `subscribe`, `Payload`, or realtime call sites without a deprecation path.
- Do not add platform APIs for billing, account, compute, or serverless management unless a concrete product use case appears.
- Do not implement full generated model schemas in this package; typed `Codable` support is the right level for now.
