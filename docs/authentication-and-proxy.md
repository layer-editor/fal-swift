# Authentication And Proxy

`FalClient` supports three practical authentication modes:

- `FalClient.withCredentials(.fromEnv)` for command-line tools and local development with `FAL_KEY`, `FAL_KEY_ID`, or `FAL_KEY_SECRET`.
- `FalClient.withCredentials(.keyPair("id:secret"))` for server-side code that can safely hold long-lived credentials.
- `FalClient.withProxy(...)` or `FalClient.withBearerToken(...)` for client apps.

Do not ship permanent Fal API keys inside iOS or macOS apps. Use a server proxy or a short-lived bearer-token flow controlled by your backend.

## Proxy Requests

When `requestProxy` is configured, Fal API requests are sent to the proxy URL and the intended Fal URL is passed in `x-fal-target-url`.

```swift
let fal = FalClient.withProxy("https://your-server.example.com/api/fal/proxy")
```

For key-pair credentials and proxies, the client suppresses the raw Fal `Authorization` header unless the proxy is local or an HTTPS bearer-token proxy. This keeps app clients from sending long-lived Fal keys through arbitrary network hops.

## Storage With Proxy

Storage has one important wrinkle: presigned blob uploads must go directly to the returned storage URL. The client keeps Fal authorization and lifecycle headers off presigned PUT requests.

Default storage uploads use direct CDN v3 first. If `requestProxy` is configured, the direct `fal.media` fallback is skipped because that endpoint requires a raw bearer secret. The client then falls through to REST presigned upload instead.

## Recommended App Shape

For Apple apps:

1. App talks to your backend.
2. Backend authenticates the user and protects Fal credentials.
3. Backend either proxies Fal requests or returns short-lived bearer credentials.
4. App never bundles a long-lived Fal key.

For local development, a loopback proxy such as `http://localhost:3333/api/fal/proxy` is fine as long as the proxy is the component holding `FAL_KEY`.
