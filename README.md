# Fal Swift

A pragmatic Swift client for Fal model APIs. This fork focuses on production Apple-platform app needs: direct requests, queue-backed inference, model discovery, streaming, realtime connections, storage uploads, typed `Codable` calls, and testable networking.

## Installation

Add the package with Swift Package Manager:

```swift
.package(url: "https://github.com/layer-editor/fal-swift.git", branch: "main")
```

Then add `FalClient` to your target dependencies.

## Authentication

For server tools, scripts, and local development, use `FAL_KEY` or explicit credentials:

```swift
import FalClient

let fal = FalClient.withCredentials(.fromEnv)
```

Do not ship long-lived Fal API keys inside iOS or macOS apps. Client apps should call through a server proxy or use short-lived bearer credentials:

```swift
let fal = FalClient.withProxy("https://your-server.example.com/api/fal/proxy")
```

See [Authentication and Proxy](docs/authentication-and-proxy.md) for the app-side guidance.

## Queue Requests

Queue-backed requests are the default shape for model APIs that may take more than a few seconds:

```swift
let result = try await fal.subscribe(
    to: "fal-ai/flux/dev",
    input: [
        "prompt": .string("a quiet studio desk with warm morning light"),
    ],
    pollInterval: .milliseconds(500),
    timeout: .minutes(3),
    includeLogs: true
) { status in
    print(status)
}

if case let .string(url) = result["images"][0]["url"] {
    print(url)
}
```

For richer queue metadata, use `queue.submitDetailed`, `queue.statusDetail`, `queue.response`, `queue.cancel`, or `queue.streamStatus`. See [Queue](docs/queue.md).

## Model Discovery

Use `fal.models` to search Fal's model catalog, fetch optional OpenAPI schemas, infer broad input/output capabilities, and build dynamic playgrounds with `Payload`:

```swift
let page = try await fal.models.search(
    "flux",
    category: "text-to-image",
    status: .active,
    limit: 25,
    expand: [.openAPI]
)

for model in page.models {
    print(model.endpointId)
    print(model.inferredCapabilities.task as Any)
}
```

See [Model Discovery](docs/models.md).

## Typed Calls

The client also supports `Codable` request and response types:

```swift
struct ImageInput: Encodable {
    let prompt: String
}

struct ImageOutput: Decodable {
    let images: [FalImage]
}

let output: ImageOutput = try await fal.subscribe(
    to: "fal-ai/flux/dev",
    input: ImageInput(prompt: "a small print studio")
)
```

Typed `Encodable` inputs that contain `Data` are rejected before request encoding. Use the `Payload` API with `.data` when you want the client to upload binary inputs before sending the model request.

## Streaming

Direct streaming uses the model `/stream` SSE endpoint and is separate from queue polling:

```swift
let events = try await fal.stream(
    "fal-ai/flux/dev",
    input: ["prompt": .string("a graphite sketch of a glass house")]
)

for try await event in events {
    print(event)
}
```

See [Streaming](docs/streaming.md).

## Storage

Binary `Payload.data` values are uploaded automatically before request encoding. Direct storage uploads default to the modern Fal CDN path: `v3.fal.media`, then `fal.media`, then REST presigned fallback. Proxy-backed clients skip direct `fal.media` fallback so raw credentials are not sent from app clients.

See [Storage Uploads](docs/storage.md).

## Realtime

Realtime WebSocket APIs are available through `fal.realtime.connect(...)`. The realtime sample is useful as a reference for API shape, but it is still labeled as a sample rather than production app architecture.

See [Realtime](docs/realtime.md).

## Errors

Public APIs throw `FalError`, including inspectable HTTP status, Fal request ID, error type, timeout type, and parsed JSON payload when available.

See [Errors](docs/errors.md).

## Samples

Sample apps live in `Sources/Samples`. Each sample has a README with its status and setup notes. Treat them as lightweight references, not production app architecture.

## Development

```bash
swift test
swift build --target FalClient --configuration release
```

See [CONTRIBUTING](CONTRIBUTING.md) for the local workflow.

## License

Distributed under the MIT License. See [LICENSE](LICENSE).
