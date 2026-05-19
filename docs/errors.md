# Errors

Public APIs throw `FalError`.

Canonical references: Fal's [Model Errors](https://fal.ai/docs/documentation/model-apis/errors)
and [Request Error Types](https://fal.ai/docs/documentation/model-apis/request-errors)
docs are the source of truth for platform error meaning. See
[Reference Sources](reference-sources.md) for peer client references.

```swift
do {
    let result = try await fal.subscribe(to: "fal-ai/flux/dev", input: input)
    print(result)
} catch let error as FalError {
    print(error)
}
```

## HTTP Errors

Non-success HTTP responses are exposed as `FalError.httpError`.

```swift
catch FalError.httpError(let error) {
    print(error.statusCode)
    print(error.requestId ?? "missing request id")
    print(error.errorType ?? "missing error type")
    print(error.payload ?? .dict([:]))
}
```

`FalHTTPError` includes:

- `statusCode`
- `message`
- parsed JSON `payload`, when available
- Fal request ID
- Fal error type
- Fal timeout type
- normalized response headers

Sensitive response headers are not exposed through this public error surface.

## Queue Timeout

`FalError.queueTimeout(requestId:)` is thrown when a local queue wait times out. If the client knows the queue request ID, it is included so the caller can inspect or cancel separately.

## Invalid URLs

`FalError.invalidUrl(url:)` redacts credentials, query strings, and fragments before exposing the value. Storage and image-loading helpers reject unsafe remote URLs and unsafe redirects before following them.

## Retry Behavior

The package uses a fixed internal retry policy for transient queue status/result calls and storage transfer paths where retrying is useful. Public retry knobs are intentionally not part of the API yet.
