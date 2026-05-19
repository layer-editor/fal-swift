# Changelog

## Unreleased

- Modernized queue APIs with detailed submit/status metadata, cancellation, queue status streaming, and detail-aware subscribe helpers.
- Added Fal model discovery APIs with catalog search, endpoint lookup, optional OpenAPI expansion, queue schema extraction, and broad capability inference for dynamic Apple-client playgrounds.
- Added direct model SSE streaming with `Payload` and typed `Codable` event decoding.
- Hardened endpoint parsing for namespaced IDs such as `workflows/...` and `comfy/...`.
- Added public inspectable `FalError` and `FalHTTPError` metadata.
- Added testable HTTP transport seams and internal transient retry handling for queue/status and selected storage paths.
- Modernized storage uploads for Fal CDN v3, direct `fal.media`, multipart uploads, lifecycle headers, custom file names, fallback sequencing, and proxy-aware credential protection.
- Added safe async Fal image loading helpers and deprecated synchronous remote byte loading.
- Updated package release metadata, CI test execution, user-facing docs, and sample status notes.
