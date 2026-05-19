# Storage Uploads

`FalClient` uploads local binary inputs to Fal CDN and passes the returned URL to model APIs. CDN URLs are public-by-URL and follow Fal media retention settings, so callers should set lifecycle preferences for temporary or sensitive assets.

## Default Behavior

The default upload path is the modern Fal CDN chain:

1. Direct CDN v3: `v3.fal.media`
2. Direct CDN fallback: `fal.media`
3. REST presigned upload: `rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3`

When `requestProxy` is configured, the direct `fal.media` fallback is skipped because it would require sending the raw Fal secret directly from the client. It is also skipped as an intermediate fallback when the configured credentials cannot authorize `fal.media` uploads. In both cases the client falls through to REST presigned upload.

This is available through the default initializer and the named convenience value:

```swift
let options = StorageUploadOptions.preferredFalCDN
let url = try await fal.storage.upload(data: imageData, ofType: .imagePng, options: options)
```

Calling `upload(data:ofType:)` uses the same preferred chain.

Explicit non-default repositories do not inherit fallback repositories. For example, `StorageUploadOptions(repository: .falCDNV3PresignedURL)` keeps presigned-only behavior unless `fallbackRepositories` is set.

## Large Files

Direct CDN v3 automatically uses multipart uploads for data larger than `100 MB`, with `10 MB` chunks by default.

```swift
let options = StorageUploadOptions(
    multipartUpload: .init(
        thresholdBytes: 100 * 1024 * 1024,
        chunkSizeBytes: 10 * 1024 * 1024
    )
)
```

Multipart can be disabled for callers that need single-request upload behavior:

```swift
let options = StorageUploadOptions(multipartUpload: .disabled)
```

## Legacy Presigned Uploads

Use REST presigned uploads explicitly when you need the older conservative behavior:

```swift
let options = StorageUploadOptions.presignedFalCDNV3
let url = try await fal.storage.upload(data: imageData, ofType: .imagePng, options: options)
```

Presigned PUT requests do not send Fal authorization or lifecycle headers to the blob upload URL.

## File Names And Lifecycle

Upload options support custom file names and object lifecycle preferences:

```swift
let options = StorageUploadOptions(
    fileName: "canvas.png",
    objectLifecyclePreference: .init(expirationDuration: 60 * 60)
)
```

Custom file names are reduced to the final path component and sanitized before they are sent.

## Fallback Tradeoff

For small direct uploads, transient failures can fall through to the next configured repository. This improves reliability and follows Fal's current client behavior, but a failed direct upload may still have created an orphaned object if the server accepted bytes before failing. Multipart uploads remain terminal after part upload starts.
