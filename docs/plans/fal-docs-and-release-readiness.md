# Docs and Release Readiness

This document tracks user-facing documentation, samples, package metadata, and CI work needed to make the package feel maintained.

## README

Current issues:

- It frames fal as "serverless Python functions"; current docs position the client around fal model APIs and deployed endpoints.
- It uses old example IDs such as `text-to-image`.
- It suggests inline credentials too casually for an Apple client package.
- It says untyped results are `[String: Any]`, but public APIs return `Payload`.
- The realtime snippet uses unsafe patterns and undefined context.

Planned update:

- Use `fal-ai/flux/dev` or another current public model in examples.
- Show `Payload` and `Codable` variants.
- Add a clear auth section:
  - Server/dev contexts may use `FAL_KEY` or explicit credentials.
  - Client apps should use a server proxy or short-lived token flow.
  - Do not ship permanent fal API keys inside iOS/macOS apps.
- Link to dedicated auth/proxy and sample docs.

## Package Metadata

Current issues:

- `Package.swift` declares Swift tools 5.7, but source uses Swift 5.9 switch expression syntax.
- CI config uses Swift 5.9 while package metadata says 5.7.
- Quick/Nimble are heavy for the current small test surface.
- User agent hardcodes `0.1.0`.
- Platform matrix is broader than what CI/docs prove.

Planned work:

- Decide whether to raise package tools to Swift 5.9+ or remove 5.9-only syntax.
- Move tests to XCTest or Swift Testing when practical.
- Generate user agent version from package/release metadata or centralize it in one constant.
- Either test advertised platforms or document supported versus best-effort platforms.

## CI

Current issues:

- `.github/workflows/build.yml` comments out `swift test`.
- Sample builds are commented out.

Planned work:

- Enable `swift test` for library changes.
- Keep sample builds targeted and opt-in if simulator availability is brittle.
- Add CI jobs only after samples are updated enough to be good references.

## Samples

Current issues:

- Sample `fal.swift` files default to `http://localhost:3333/api/fal/proxy` without setup instructions.
- Basic sample uses a short timeout and force unwraps media URLs.
- Realtime and camera samples use older SwiftUI observation patterns.
- Camera sample uses deprecated image rendering APIs and manual DispatchQueue paths.
- Camera sample Xcode project hardcodes a development team.

Planned work:

- Add `Sources/Samples/*/README.md` files.
- Explain proxy setup and credentials for each sample.
- Update unsafe force unwraps and blocking loads.
- Modernize SwiftUI sample state only where the sample is actively kept.
- If a sample is not maintained, mark it clearly as legacy instead of pretending it is a reference implementation.

## New Living Docs

Recommended docs:

- `docs/authentication-and-proxy.md`: API key safety, proxy, bearer/token usage.
- `docs/queue.md`: submit, status, result, cancel, subscribe, status streaming.
- `docs/streaming.md`: direct SSE stream endpoints.
- `docs/storage.md`: uploads, content types, lifecycle settings.
- `docs/errors.md`: public error metadata and retry guidance.
- `CONTRIBUTING.md`: setup, targeted test commands, sample build commands, release checklist.
- `CHANGELOG.md`: start with unreleased section and note this fork's local fixes.

DocC can come later. Markdown is easier to maintain while the API is still moving.

## Release Checklist

- [ ] `swift test` passes locally and in CI.
- [ ] `swift build --target FalClient --configuration release` passes.
- [ ] README examples compile or are covered by snippet tests/manual checks.
- [ ] Public API changes have migration notes.
- [ ] New queue/request behavior has tests with no live credentials.
- [ ] Samples are either updated or clearly labeled legacy.
- [ ] Changelog has user-facing entries.
- [ ] Version in docs, package references, and user agent is consistent.

## References

- [fal client setup docs](https://fal.ai/docs/documentation/model-apis/inference/client-setup)
- [fal proxy setup docs](https://fal.ai/docs/documentation/model-apis/inference/proxy-setup)
- [Swift Package Index entry](https://swiftpackageindex.com/fal-ai/fal-swift)
