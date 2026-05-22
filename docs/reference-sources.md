# Reference Sources

This fork is intentionally documented against Fal's public docs and peer
packages so future changes can be checked against a canonical source instead of
only against this repository's current behavior.

## Canonical Fal Documentation

- Documentation index for humans and agents: https://fal.ai/docs/llms.txt
- Model APIs overview: https://fal.ai/docs/documentation/model-apis/overview
- Client setup and credential guidance: https://fal.ai/docs/documentation/model-apis/inference/client-setup
- Proxy setup for client apps: https://fal.ai/docs/documentation/model-apis/inference/proxy-setup
- Async queue inference: https://fal.ai/docs/documentation/model-apis/inference/queue
- Synchronous inference: https://fal.ai/docs/documentation/model-apis/inference/synchronous
- Streaming inference: https://fal.ai/docs/documentation/model-apis/inference/streaming
- Real-time inference: https://fal.ai/docs/documentation/model-apis/inference/real-time
- Platform headers: https://fal.ai/docs/documentation/model-apis/common-parameters
- Common model arguments: https://fal.ai/docs/documentation/model-apis/model-arguments
- Fal CDN uploads: https://fal.ai/docs/documentation/model-apis/fal-cdn
- Data retention and media expiration: https://fal.ai/docs/documentation/model-apis/media-expiration
- Model errors: https://fal.ai/docs/documentation/model-apis/errors
- Request error types: https://fal.ai/docs/documentation/model-apis/request-errors
- Platform APIs for models: https://fal.ai/docs/api-reference/platform-apis/for-models
- Platform OpenAPI schema: https://fal.ai/docs/api-reference/platform-apis/openapi-schema

## Peer Packages Referenced

- Python/serverless repository: https://github.com/fal-ai/fal
- Python client docs: https://fal.ai/docs/api-reference/client-libraries/python
- Python `fal_client` API reference: https://fal.ai/docs/api-reference/client-libraries/python/fal_client
- JavaScript/TypeScript client docs: https://fal.ai/docs/api-reference/client-libraries/javascript
- JavaScript queue API reference: https://fal.ai/docs/api-reference/client-libraries/javascript/queue
- JavaScript streaming API reference: https://fal.ai/docs/api-reference/client-libraries/javascript/streaming
- JavaScript realtime API reference: https://fal.ai/docs/api-reference/client-libraries/javascript/realtime
- JavaScript storage API reference: https://fal.ai/docs/api-reference/client-libraries/javascript/storage
- Kotlin / Java client docs: https://fal.ai/docs/api-reference/client-libraries/kotlin
- Dart client docs: https://fal.ai/docs/api-reference/client-libraries/dart
- Fal Swift client docs: https://fal.ai/docs/api-reference/client-libraries/swift

## Drift-Prevention Notes

- Treat Fal's documentation index as the first place to check when updating
  request lifecycle, queue state, streaming, realtime, storage, or model catalog
  behavior.
- Treat Python and JavaScript clients as the primary peer packages for API
  shape and option parity. Kotlin, Java, Dart, and Swift references are useful
  for platform naming and mobile-client expectations.
- Prefer linking to canonical Fal docs from feature docs rather than copying
  large sections of Fal prose into this repository.
- If Fal docs and peer client behavior disagree, document the mismatch in the
  relevant feature doc or plan before changing Swift behavior.
