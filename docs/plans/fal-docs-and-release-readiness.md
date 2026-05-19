# Docs and Release Readiness

This document tracks user-facing documentation, samples, package metadata, and CI work needed to make the package feel maintained.

Use [Reference Sources](../reference-sources.md) as the canonical source list for docs updates. Feature docs should link to Fal's current docs and avoid copying large sections that can drift.

## README

Completed fixes:

- README now frames the package around Fal model APIs.
- Examples use current-style model IDs and `Payload`/`Codable` results.
- Auth guidance warns against shipping long-lived Fal keys in Apple apps.
- Realtime README guidance no longer uses unsafe blocking image loading snippets.

Current follow-up:

- Keep examples checked as public API evolves.

## Package Metadata

Completed fixes:

- `Package.swift` now declares Swift tools 5.9, matching source syntax and CI.
- Quick/Nimble were removed after converting the remaining specs to XCTest.
- User agent no longer advertises stale package version `0.1.0`.

Current issues:

- Platform matrix is broader than what CI/docs prove.

Deferred:

- Either test advertised platforms or document supported versus best-effort platforms.

## CI

Completed fixes:

- `.github/workflows/build.yml` runs `swift test` and release build for the library.

Deferred:

- Sample builds are commented out.

- Keep sample builds targeted and opt-in if simulator availability is brittle.
- Add CI jobs only after samples are updated enough to be good references.

## Samples

Completed fixes:

- Added `Sources/Samples/README.md` plus per-sample README files with proxy setup and status.
- Basic sample uses a more realistic queue timeout and avoids force-unwrapping image URLs.
- Realtime sample uses `@Observable`/`@State` and current `onChange` syntax.
- Removed commented direct key-pair snippets from sample `fal.swift` files.
- Camera sample has no hardcoded development team and is clearly labeled legacy.

Deferred:

- Camera sample still uses older camera/rendering/concurrency patterns. Rewrite only if the sample becomes an active reference again.

## New Living Docs

Recommended docs:

- `docs/reference-sources.md`: canonical Fal docs and peer packages referenced by this fork. Created.
- `docs/authentication-and-proxy.md`: API key safety, proxy, bearer/token usage. Created.
- `docs/queue.md`: submit, status, result, cancel, subscribe, status streaming. Created.
- `docs/streaming.md`: direct SSE stream endpoints. Created.
- `docs/realtime.md`: realtime connections, token-provider decision, sample status. Created.
- `docs/storage.md`: uploads, content types, lifecycle settings. Created with the current v3-first default chain and fallback behavior.
- `docs/errors.md`: public error metadata and retry guidance. Created.
- `CONTRIBUTING.md`: setup, targeted test commands, sample build commands, release checklist. Created.
- `CHANGELOG.md`: start with unreleased section and note this fork's local fixes. Created.

DocC can come later. Markdown is easier to maintain while the API is still moving.

## Release Checklist

- [x] `swift test` passes locally and is enabled in CI.
- [x] `swift build --target FalClient --configuration release` passes locally and remains enabled in CI.
- [x] README examples compile or are covered by snippet tests/manual checks.
- [x] Public API changes have migration notes.
- [x] New queue/request behavior has tests with no live credentials.
- [x] Samples are either updated or clearly labeled legacy.
- [x] Changelog has user-facing entries.
- [x] Version in docs, package references, and user agent is consistent.

## References

- [Canonical Fal and peer package sources](../reference-sources.md)
- [Swift Package Index entry](https://swiftpackageindex.com/fal-ai/fal-swift)
