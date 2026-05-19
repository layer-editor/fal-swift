# Model Discovery

Use `fal.models` when an app needs to browse Fal models, build a dynamic playground, or keep supported endpoint metadata outside app releases.

Model discovery uses Fal's platform model search API at `https://api.fal.ai/v1/models`. Authentication is optional for basic discovery, but authenticated requests may have higher rate limits. In shipped client apps, use the same proxy or short-lived credential strategy described in [Authentication and Proxy](authentication-and-proxy.md).

## Search

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
    print(model.metadata.displayName ?? model.endpointId)
    print(model.inferredCapabilities.task as Any)
}
```

Use `page.nextCursor` and `page.hasMore` for pagination.

## Endpoint Lookup

```swift
let model = try await fal.models.find(
    "fal-ai/flux/dev",
    expand: [.openAPI]
)
```

Multiple endpoint IDs can be fetched with repeated `endpoint_id` query parameters:

```swift
let models = try await fal.models.find([
    "fal-ai/flux/dev",
    "fal-ai/flux/schnell",
], expand: [.openAPI])
```

## Playground Schemas

When `.openAPI` is requested, `FalModel.queueSchema` extracts the queue input and output object schemas from the model's OpenAPI document.

```swift
if let input = model?.queueSchema?.input {
    for field in input.fields {
        print(field.name)
        print(field.kind)
        print(field.isRequired)
        print(field.allowedValues)
    }
}
```

The schema layer is intentionally playground-oriented. It keeps field names, titles, descriptions, required flags, default values, examples, enum values, and numeric bounds. It does not generate static Swift types at runtime.

## Capability Inference

`FalModel.inferredCapabilities` combines model metadata with expanded queue schemas to infer broad app-routing shapes:

- `inputKinds`: text, image, video, audio, file, JSON, or 3D.
- `outputKinds`: text, image, video, audio, file, JSON, or 3D.
- `task`: common shapes such as `.textToImage`, `.textToImages`, `.imageToImage`, `.imageToImages`, `.textToVideo`, or `.imageToVideo`.
- `supportsQueue`: whether the expanded schema appears to describe a queue-backed endpoint.

Treat inference as a convenience for UI routing and filtering, not as a hard backend contract. For high-value models, keep a small app-side override registry for model-specific behavior and typed `Codable` wrappers.

## Dynamic Calls

Dynamic playgrounds should submit user-entered values as `Payload`:

```swift
let output = try await fal.subscribe(
    to: model.endpointId,
    input: [
        "prompt": .string("a glass greenhouse at sunrise"),
        "num_images": .int(2),
    ]
)
```

Typed `Codable` wrappers remain the best choice for curated production flows. Model discovery is meant to make browsing, filtering, schema inspection, and hotswapping simpler without forcing every model into a generated Swift type.
