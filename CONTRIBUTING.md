# Contributing

This fork is maintained for practical Apple-platform app use. Keep changes small, tested, and aligned with the existing package shape.

Before changing Fal request lifecycle, queue, streaming, realtime, storage,
model catalog, or error behavior, check [Reference Sources](docs/reference-sources.md)
and note any intentional divergence from Fal docs or peer clients in the
relevant feature doc.

## Setup

```bash
swift package resolve
swift test
swift build --target FalClient --configuration release
```

Do not run tests or examples with real Fal API keys unless the test is explicitly intended to hit live infrastructure.

## Common Verification

Use targeted tests while iterating:

```bash
swift test --filter StorageTests
swift test --filter ClientRequestTests
swift test --filter RealtimeConnectionPoolTests
```

Before committing shared package changes, run:

```bash
swift test
swift build --target FalClient -Xswiftc -strict-concurrency=complete
swift build --target FalClient --configuration release
git diff --check
```

## Samples

Sample apps under `Sources/Samples` are lightweight references. They are not release gates unless a change explicitly targets a sample. Prefer documenting sample status over broad sample rewrites.

## Release Checklist

- `swift test` passes locally and in CI.
- `swift build --target FalClient --configuration release` passes.
- README examples are checked manually or covered by tests.
- Public API changes have migration notes in `CHANGELOG.md`.
- Samples are updated or clearly labeled as legacy/reference-only.
- User-agent product/version policy is reviewed before public tags.
