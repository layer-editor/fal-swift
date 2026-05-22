@testable import FalClient
import XCTest

final class ClientRequestTests: XCTestCase {
    private var transport: RecordingHTTPTransport!
    private var requestHandler: ((URLRequest) throws -> HTTPTransportResponse)?

    override func setUp() {
        super.setUp()
        requestHandler = nil
        transport = RecordingHTTPTransport { [unowned self] request in
            guard let requestHandler else {
                throw FalError.invalidResultFormat
            }
            return try requestHandler(request)
        }
    }

    override func tearDown() {
        requestHandler = nil
        transport = nil
        super.tearDown()
    }

    func testUserAgentDoesNotAdvertiseStalePackageVersion() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"ok":true}"#.data(using: .utf8)!, response: response)
        }
        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)

        _ = try await client.sendRequest(
            to: "https://fal.run/fal-ai/test",
            input: nil as Data?,
            options: RunOptions.withMethod(.get)
        )

        let request = try XCTUnwrap(transport.requests.first)
        let userAgent = try XCTUnwrap(request.value(forHTTPHeaderField: "user-agent"))
        XCTAssertTrue(userAgent.hasPrefix("fal.ai/swift-client - "))
        XCTAssertFalse(userAgent.contains("0.1.0"))
    }

    func testProxyRequestsDoNotForwardFalKeyAuthorizationHeader() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"ok":true}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(
            credentials: .keyPair("fal-key-id:fal-key-secret"),
            requestProxy: "http://localhost:3333/api/fal/proxy"
        ), httpTransport: transport)

        _ = try await client.sendRequest(
            to: "https://fal.run/fal-ai/test",
            input: nil,
            options: .withMethod(.get)
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:3333/api/fal/proxy")
        XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-fal-target-url"), "https://fal.run/fal-ai/test")
    }

    func testProxyRequestsDoNotForwardProtectedCallerHeaders() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"ok":true}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(
            credentials: .keyPair("fal-key-id:fal-key-secret"),
            requestProxy: "http://proxy.example.com/api/fal/proxy"
        ), httpTransport: transport)

        _ = try await client.sendRequest(
            to: "https://fal.run/fal-ai/test",
            input: nil,
            options: RunOptions(
                httpMethod: .get,
                headers: [
                    "Authorization": "Bearer leaked",
                    "Proxy-Authorization": "Bearer leaked-proxy",
                    "Cookie": "session=leaked",
                    "Host": "attacker.example",
                    "x-fal-target-url": "https://attacker.example",
                ]
            )
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "proxy-authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "host"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-fal-target-url"), "https://fal.run/fal-ai/test")
    }

    func testProxyKeyRequestsDoNotResolveRawCredentialsWhenAuthorizationIsSuppressed() async throws {
        var didResolveCredentials = false
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"ok":true}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(
            credentials: .custom {
                didResolveCredentials = true
                return "fal-key-id:fal-key-secret"
            },
            requestProxy: "http://localhost:3333/api/fal/proxy"
        ), httpTransport: transport)

        _ = try await client.sendRequest(
            to: "https://fal.run/fal-ai/test",
            input: nil,
            options: .withMethod(.get)
        )

        XCTAssertFalse(didResolveCredentials)
    }

    func testAuthorizationHeaderPolicy() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"ok":true}"#.data(using: .utf8)!, response: response)
        }

        let cases: [(String, ClientConfig, String?)] = [
            (
                "direct key",
                ClientConfig(credentials: .keyPair("fal-key-id:fal-key-secret")),
                "Key fal-key-id:fal-key-secret"
            ),
            (
                "direct bearer",
                ClientConfig(credentials: .bearerToken("session-token"), authScheme: .bearer),
                "Bearer session-token"
            ),
            (
                "proxied key",
                ClientConfig(credentials: .keyPair("fal-key-id:fal-key-secret"), requestProxy: "http://localhost:3333/api/fal/proxy"),
                nil
            ),
            (
                "proxied bearer localhost",
                ClientConfig(credentials: .bearerToken("session-token"), authScheme: .bearer, requestProxy: "http://localhost:3333/api/fal/proxy"),
                "Bearer session-token"
            ),
            (
                "proxied bearer https",
                ClientConfig(credentials: .bearerToken("session-token"), authScheme: .bearer, requestProxy: "https://proxy.example.com/api/fal/proxy"),
                "Bearer session-token"
            ),
            (
                "proxied bearer insecure remote",
                ClientConfig(credentials: .bearerToken("session-token"), authScheme: .bearer, requestProxy: "http://proxy.example.com/api/fal/proxy"),
                nil
            ),
        ]

        for (name, config, expectedAuthorization) in cases {
            transport.reset()
            let client = TestRequestClient(config: config, httpTransport: transport)

            _ = try await client.sendRequest(
                to: "https://fal.run/fal-ai/test",
                input: nil,
                options: .withMethod(.get)
            )

            let request = try XCTUnwrap(transport.requests.first, name)
            XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), expectedAuthorization, name)
        }
    }

    func testCredentialDescriptionIsRedacted() {
        let credentials: [ClientCredentials] = [
            .keyPair("fal-key-id:fal-key-secret"),
            .key(id: "fal-key-id", secret: "fal-key-secret"),
            .bearerToken("session-token"),
            .custom { "custom-secret" },
        ]

        for credential in credentials {
            XCTAssertEqual(String(describing: credential), "<redacted>")
            XCTAssertTrue(Mirror(reflecting: credential).children.isEmpty)
        }
    }

    func testRunOptionsSendPlatformHeadersAndNamedOptionsOverrideRawHeaders() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"value":"ok"}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)

        let _: RequestOutput = try await client.run(
            "fal-ai/test",
            input: RequestInput(value: "cat"),
            options: RunOptions(
                httpMethod: .post,
                headers: [
                    "X-Custom-Header": "custom",
                    "X-Fal-Request-Timeout": "1",
                    "X-Fal-Runner-Hint": "raw-hint",
                    "X-Fal-Store-IO": "1",
                ],
                startTimeout: 30,
                hint: "sticky-runner",
                queuePriority: .low,
                disableRetries: true,
                storeInputOutput: false,
                objectLifecyclePreference: .init(expirationDuration: 3_600),
                disableFallback: true
            )
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Custom-Header"), "custom")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Request-Timeout"), "30")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Runner-Hint"), "sticky-runner")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-No-Retry"), "1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Store-IO"), "0")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference"),
            #"{"expiration_duration_seconds":3600}"#
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-app-fal-disable-fallback"), "true")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Fal-Queue-Priority"))
    }

    func testQueueGetRequestsMergeInputAndExplicitQueryParameters() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"value":"ok"}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        let _: RequestOutput = try await queue.runOnQueue(
            "fal-ai/test",
            input: [
                "prompt": "cat",
            ],
            queryParams: [
                "logs": 1,
            ],
            options: .route("/requests/request-id/status?existing=true", withMethod: .get)
        )

        let request = try XCTUnwrap(transport.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(queryItems["existing"], "true")
        XCTAssertEqual(queryItems["prompt"], "cat")
        XCTAssertEqual(queryItems["logs"], "1")
    }

    func testQueueStatusPreservesEndpointPathSegments() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"status":"IN_QUEUE","queue_position":1,"response_url":"https://queue.fal.run/fal-ai/flux/schnell/requests/request-id"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        _ = try await queue.status("fal-ai/flux/schnell", of: "request-id")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fal-ai/flux/schnell/requests/request-id/status")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(queryItems["logs"], "0")
    }

    func testNamespacedQueueStatusUsesNamespaceOwnerAndAliasAsQueueBase() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"status":"IN_QUEUE","queue_position":1,"response_url":"https://queue.fal.run/workflows/chris/image-pipeline/requests/request-id"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        _ = try await queue.status("workflows/chris/image-pipeline/preview", of: "request-id")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/workflows/chris/image-pipeline/requests/request-id/status")
    }

    func testNamespacedQueueResponseAndCancelUseNamespaceOwnerAndAliasAsQueueBase() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"value":"ok"}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        _ = try await queue.response("comfy/chris/portrait-workflow/preview", of: "request-id")
        try await queue.cancel("comfy/chris/portrait-workflow/preview", of: "request-id")

        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/comfy/chris/portrait-workflow/requests/request-id",
            "/comfy/chris/portrait-workflow/requests/request-id/cancel",
        ])
    }

    func testTypedNamespacedQueueResponseUsesNamespaceOwnerAndAliasAsQueueBase() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"value":"ok"}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        let _: RequestOutput = try await queue.response("workflows/chris/image-pipeline/preview", of: "request-id")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/workflows/chris/image-pipeline/requests/request-id")
    }

    func testNamespacedQueueSubmitPreservesEndpointSubpath() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"request_id":"request-id"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        _ = try await queue.submit("workflows/chris/image-pipeline/preview", input: ["prompt": "cat"])

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/workflows/chris/image-pipeline/preview")
    }

    func testQueueStatusEncodesRequestIdAsSinglePathSegment() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"status":"IN_QUEUE","queue_position":1,"response_url":"https://queue.fal.run/fal-ai/flux/schnell/requests/request-id"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        _ = try await queue.statusDetail(
            "fal-ai/flux/schnell",
            of: "folder/request?x=1#frag.",
            includeLogs: true
        )

        let request = try XCTUnwrap(transport.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(
            components.percentEncodedPath,
            "/fal-ai/flux/schnell/requests/folder%2Frequest%3Fx%3D1%23frag%2E/status"
        )
        XCTAssertEqual(queryItems["logs"], "1")
        XCTAssertFalse(queryItems.keys.contains("x"))
    }

    func testQueueStatusDetailPreservesMetadataAndIncludesLogsQuery() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {
              "status": "COMPLETED",
              "request_id": "request-id",
              "response_url": "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id",
              "status_url": "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id/status",
              "cancel_url": "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id/cancel",
              "metrics": {
                "inference_time": 1.25
              },
              "logs": []
            }
            """.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        let detail = try await queue.statusDetail("fal-ai/flux/schnell", of: "request-id", includeLogs: true)

        let request = try XCTUnwrap(transport.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(request.url?.path, "/fal-ai/flux/schnell/requests/request-id/status")
        XCTAssertEqual(queryItems["logs"], "1")
        XCTAssertEqual(detail.requestId, "request-id")
        XCTAssertEqual(detail.responseUrl, "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id")
        XCTAssertEqual(detail.statusUrl, "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id/status")
        XCTAssertEqual(detail.cancelUrl, "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id/cancel")
        XCTAssertEqual(detail.metrics?["inference_time"], .double(1.25))
    }

    func testQueueStatusRetriesTransientHTTPResponses() async throws {
        var attempts = 0
        requestHandler = { request in
            attempts += 1
            if attempts == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"detail":"temporarily unavailable"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {
              "status": "COMPLETED",
              "request_id": "request-id",
              "response_url": "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id"
            }
            """.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        let detail = try await queue.statusDetail("fal-ai/flux/schnell", of: "request-id", includeLogs: false)

        XCTAssertTrue(detail.status.isCompleted)
        XCTAssertEqual(detail.responseUrl, "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id")
        XCTAssertEqual(attempts, 2)
    }

    func testQueueStatusDoesNotRetryUserTimeoutResponses() async throws {
        var attempts = 0
        requestHandler = { request in
            attempts += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 504,
                httpVersion: nil,
                headerFields: [
                    "X-Fal-Request-Timeout-Type": "user",
                ]
            )!
            let data = #"{"detail":"request timed out"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        do {
            _ = try await queue.statusDetail("fal-ai/flux/schnell", of: "request-id", includeLogs: false)
            XCTFail("Expected user timeout HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 504)
            XCTAssertTrue(error.isUserTimeout)
        }

        XCTAssertEqual(attempts, 1)
    }

    func testQueueStatusStopsAfterRetryLimit() async throws {
        var attempts = 0
        requestHandler = { request in
            attempts += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"detail":"temporarily unavailable"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        do {
            _ = try await queue.statusDetail("fal-ai/flux/schnell", of: "request-id", includeLogs: false)
            XCTFail("Expected transient HTTP error after retry limit")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 503)
        }

        XCTAssertEqual(attempts, 3)
    }

    func testTypedQueueResponsePreservesEndpointPathSegments() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"value":"ok"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        let _: RequestOutput = try await queue.response("fal-ai/flux/schnell", of: "request-id")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/fal-ai/flux/schnell/requests/request-id")
    }

    func testQueueResponseRetriesTransientTransportErrors() async throws {
        var attempts = 0
        requestHandler = { request in
            attempts += 1
            if attempts == 1 {
                throw URLError(.networkConnectionLost)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"value":"ok"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        let output: RequestOutput = try await queue.response("fal-ai/flux/schnell", of: "request-id")

        XCTAssertEqual(output.value, "ok")
        XCTAssertEqual(attempts, 2)
    }

    func testTypedQueueResponseEncodesRequestIdAsSinglePathSegment() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"value":"ok"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        let _: RequestOutput = try await queue.response("fal-ai/flux/schnell", of: "../request#id")

        let request = try XCTUnwrap(transport.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.percentEncodedPath, "/fal-ai/flux/schnell/requests/%2E%2E%2Frequest%23id")
        XCTAssertNil(components.query)
    }

    func testQueueCancelUsesCancelEndpoint() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"status":"CANCELLATION_REQUESTED"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        try await queue.cancel("fal-ai/flux/schnell", of: "request-id")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/fal-ai/flux/schnell/requests/request-id/cancel")
    }

    func testQueueCancelThrowsWhenImplementationDoesNotSupportCancellation() async throws {
        let queue = NonCancellingQueue()

        do {
            try await queue.cancel("fal-ai/test", of: "request-id")
            XCTFail("Expected unsupported cancellation to throw")
        } catch FalError.unsupportedOperation(let message) {
            XCTAssertEqual(message, "This Queue implementation does not support cancelling queued requests.")
        }
    }

    func testQueueCancelEncodesRequestIdAsSinglePathSegment() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"status":"CANCELLATION_REQUESTED"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        try await queue.cancel("fal-ai/flux/schnell", of: "folder/request?x=1#frag.")

        let request = try XCTUnwrap(transport.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(
            components.percentEncodedPath,
            "/fal-ai/flux/schnell/requests/folder%2Frequest%3Fx%3D1%23frag%2E/cancel"
        )
        XCTAssertNil(components.query)
    }

    func testQueueSubmitOptionsSendPriorityAndPlatformHeaders() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"request_id":"request-id"}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        _ = try await queue.submit(
            "fal-ai/test",
            input: [
                "prompt": "cat",
            ],
            webhookUrl: "https://example.com/webhook",
            options: RunOptions(
                headers: [
                    "X-Fal-Queue-Priority": "normal",
                ],
                startTimeout: 45,
                hint: "queue-runner",
                queuePriority: .low
            )
        )

        let request = try XCTUnwrap(transport.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(queryItems["fal_webhook"], "https://example.com/webhook")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Queue-Priority"), "low")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Request-Timeout"), "45")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Runner-Hint"), "queue-runner")
    }

    func testQueueSubmitDetailedPreservesSubmitMetadata() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {
              "request_id": "request-id",
              "response_url": "https://queue.fal.run/fal-ai/test/requests/request-id",
              "status_url": "https://queue.fal.run/fal-ai/test/requests/request-id/status",
              "cancel_url": "https://queue.fal.run/fal-ai/test/requests/request-id/cancel",
              "queue_position": 3
            }
            """.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        let result = try await queue.submitDetailed("fal-ai/test", input: [
            "prompt": "cat",
        ])

        XCTAssertEqual(result.requestId, "request-id")
        XCTAssertEqual(result.responseUrl, "https://queue.fal.run/fal-ai/test/requests/request-id")
        XCTAssertEqual(result.statusUrl, "https://queue.fal.run/fal-ai/test/requests/request-id/status")
        XCTAssertEqual(result.cancelUrl, "https://queue.fal.run/fal-ai/test/requests/request-id/cancel")
        XCTAssertEqual(result.queuePosition, 3)
    }

    func testQueuePayloadSubmitUsesProtocolStorageForAutoUpload() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"request_id":"request-id"}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        _ = try await queue.submit("fal-ai/test", input: [
            "image": .data(Data("image".utf8)),
        ])

        let request = try XCTUnwrap(transport.requests.first)
        let body = try Payload.create(fromJSON: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["image"].stringValue, "uploaded://image")
    }

    func testQueueGetPayloadDataThrowsBeforeQuerySerialization() async throws {
        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        do {
            let _: RequestOutput = try await queue.runOnQueue(
                "fal-ai/test",
                input: [
                    "image": .data(Data("image".utf8)),
                ],
                options: .withMethod(.get)
            )
            XCTFail("Expected GET payload binary input to throw")
        } catch FalError.unsupportedInput(let message) {
            XCTAssertTrue(message.localizedStandardContains("GET"))
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testTypedQueueSubmitRejectsDataBeforeSendingBase64JSON() async throws {
        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        do {
            _ = try await queue.submit("fal-ai/test", input: TypedDataInput(image: Data("image".utf8)))
            XCTFail("Expected typed binary input to throw")
        } catch FalError.unsupportedInput(let message) {
            XCTAssertTrue(message.localizedStandardContains("Data"))
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testTypedQueueSubmitRejectsCustomEncodedDataBeforeSendingBase64JSON() async throws {
        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        do {
            _ = try await queue.submit("fal-ai/test", input: CustomEncodedDataInput())
            XCTFail("Expected custom typed binary input to throw")
        } catch FalError.unsupportedInput(let message) {
            XCTAssertTrue(message.localizedStandardContains("Data"))
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testTypedQueueSubmitOptionsSendPriorityAndPlatformHeaders() async throws {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"request_id":"request-id"}"#.data(using: .utf8)!, response: response)
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        let queue = QueueClient(client: client)

        _ = try await queue.submit(
            "fal-ai/test",
            input: RequestInput(value: "cat"),
            options: RunOptions(startTimeout: 10, queuePriority: .normal)
        )

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Request-Timeout"), "10")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Queue-Priority"), "normal")
    }

    func testTypedSubscribeOptionsSendHeadersOnInitialQueueSubmitOnly() async throws {
        var requestIndex = 0
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            defer { requestIndex += 1 }
            switch requestIndex {
            case 0:
                return HTTPTransportResponse(data: #"{"request_id":"request-id"}"#.data(using: .utf8)!, response: response)
            case 1:
                return HTTPTransportResponse(data: #"{"status":"COMPLETED","response_url":"https://example.com/result"}"#.data(using: .utf8)!, response: response)
            default:
                return HTTPTransportResponse(data: #"{"value":"ok"}"#.data(using: .utf8)!, response: response)
            }
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)

        let output: RequestOutput = try await client.subscribe(
            to: "fal-ai/test",
            input: RequestInput(value: "cat"),
            options: RunOptions(startTimeout: 15, hint: "subscribe-runner", queuePriority: .low),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250)
        )

        XCTAssertEqual(output.value, "ok")
        XCTAssertEqual(transport.requests.count, 3)

        let submitRequest = transport.requests[0]
        XCTAssertEqual(submitRequest.value(forHTTPHeaderField: "X-Fal-Request-Timeout"), "15")
        XCTAssertEqual(submitRequest.value(forHTTPHeaderField: "X-Fal-Runner-Hint"), "subscribe-runner")
        XCTAssertEqual(submitRequest.value(forHTTPHeaderField: "X-Fal-Queue-Priority"), "low")

        let statusRequest = transport.requests[1]
        XCTAssertNil(statusRequest.value(forHTTPHeaderField: "X-Fal-Request-Timeout"))
        XCTAssertNil(statusRequest.value(forHTTPHeaderField: "X-Fal-Runner-Hint"))
        XCTAssertNil(statusRequest.value(forHTTPHeaderField: "X-Fal-Queue-Priority"))
    }

    func testTypedSubscribeOnEnqueueReceivesSubmitMetadata() async throws {
        var requestIndex = 0
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            defer { requestIndex += 1 }
            switch requestIndex {
            case 0:
                let data = """
                {
                  "request_id": "request-id",
                  "response_url": "https://queue.fal.run/fal-ai/test/requests/request-id",
                  "status_url": "https://queue.fal.run/fal-ai/test/requests/request-id/status",
                  "cancel_url": "https://queue.fal.run/fal-ai/test/requests/request-id/cancel",
                  "queue_position": 5
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case 1:
                return HTTPTransportResponse(data: #"{"status":"COMPLETED","response_url":"https://example.com/result"}"#.data(using: .utf8)!, response: response)
            default:
                return HTTPTransportResponse(data: #"{"value":"ok"}"#.data(using: .utf8)!, response: response)
            }
        }

        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)
        var enqueuedResult: QueueSubmitResult?

        let output: RequestOutput = try await client.subscribe(
            to: "fal-ai/test",
            input: RequestInput(value: "cat"),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250),
            onEnqueue: { enqueuedResult = $0 }
        )

        XCTAssertEqual(output.value, "ok")
        XCTAssertEqual(enqueuedResult?.requestId, "request-id")
        XCTAssertEqual(enqueuedResult?.statusUrl, "https://queue.fal.run/fal-ai/test/requests/request-id/status")
        XCTAssertEqual(enqueuedResult?.queuePosition, 5)
    }

    func testTypedRunRejectsDataBeforeSendingBase64JSON() async throws {
        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)

        do {
            let _: RequestOutput = try await client.run(
                "fal-ai/test",
                input: TypedDataInput(image: Data("image".utf8)),
                options: .withMethod(.post)
            )
            XCTFail("Expected typed binary input to throw")
        } catch FalError.unsupportedInput(let message) {
            XCTAssertTrue(message.localizedStandardContains("Data"))
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testTypedRunRejectsCustomEncodedDataBeforeSendingBase64JSON() async throws {
        let client = TestRequestClient(config: ClientConfig(), httpTransport: transport)

        do {
            let _: RequestOutput = try await client.run(
                "fal-ai/test",
                input: CustomEncodedDataInput(),
                options: .withMethod(.post)
            )
            XCTFail("Expected custom typed binary input to throw")
        } catch FalError.unsupportedInput(let message) {
            XCTAssertTrue(message.localizedStandardContains("Data"))
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }
}

private struct RequestOutput: Decodable {
    let value: String
}

private struct RequestInput: Encodable {
    let value: String
}

private struct TypedDataInput: Encodable {
    let image: Data
}

private struct CustomEncodedDataInput: Encodable {
    enum CodingKeys: CodingKey {
        case image
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Data("image".utf8), forKey: .image)
    }
}

private struct TestRequestClient: Client, HTTPTransportProviding {
    let config: ClientConfig
    let httpTransport: HTTPTransport

    var queue: Queue {
        QueueClient(client: self)
    }

    var realtime: Realtime {
        fatalError("TestRequestClient.realtime is unused in these tests")
    }

    var storage: Storage {
        TestStorage()
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        fatalError("TestRequestClient.run is unused in these tests")
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("TestRequestClient.subscribe is unused in these tests")
    }
}

private struct TestStorage: Storage {
    var client: Client {
        fatalError("TestStorage.client is unused in these tests")
    }

    func upload(data: Data, ofType type: FileType) async throws -> String {
        "uploaded://\(String(decoding: data, as: UTF8.self))"
    }
}

private struct NonCancellingQueue: Queue {
    var client: Client {
        fatalError("NonCancellingQueue.client is unused in these tests")
    }

    func submit(_ id: String, input: Payload?, webhookUrl: String?) async throws -> String {
        "request-id"
    }

    func submit(_ id: String, input: Payload?, webhookUrl: String?, options: RunOptions) async throws -> String {
        "request-id"
    }

    func submitDetailed(_ id: String, input: Payload?, webhookUrl: String?) async throws -> QueueSubmitResult {
        QueueSubmitResult(requestId: "request-id")
    }

    func submitDetailed(_ id: String, input: Payload?, webhookUrl: String?, options: RunOptions) async throws -> QueueSubmitResult {
        QueueSubmitResult(requestId: "request-id")
    }

    func status(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatus {
        .completed(logs: [], responseUrl: "https://example.com/result")
    }

    func response(_ id: String, of requestId: String) async throws -> Payload {
        [:]
    }

    func response<T: Decodable>(_ id: String, of requestId: String) async throws -> T {
        throw FalError.invalidResultFormat
    }
}
