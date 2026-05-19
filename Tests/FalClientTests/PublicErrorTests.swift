import FalClient
import XCTest

final class PublicErrorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(PublicErrorRecordingURLProtocol.self)
        PublicErrorRecordingURLProtocol.requestHandler = nil
    }

    override func tearDown() {
        PublicErrorRecordingURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(PublicErrorRecordingURLProtocol.self)
        super.tearDown()
    }

    func testPublicFalErrorCasesCanBeInspected() {
        let error: Error = FalError.queueTimeout(requestId: "req_timeout")

        switch error {
        case FalError.queueTimeout(let requestId):
            XCTAssertEqual(requestId, "req_timeout")
        default:
            XCTFail("Expected public queue timeout error")
        }
    }

    func testHTTPErrorExposesFalHeadersAndPayload() async throws {
        PublicErrorRecordingURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: [
                    "x-fal-request-id": "req_123",
                    "X-Fal-Error-Type": "runner_disconnected",
                    "X-Fal-Request-Timeout-Type": "user",
                ]
            )!
            let data = """
            {
              "detail": "Runner disconnected",
              "error_type": "request_timeout"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let client = FalClient.withCredentials(.keyPair("fal-key-id:fal-key-secret"))

        do {
            let _: Payload = try await client.run("fal-ai/test", input: nil, options: .withMethod(.get))
            XCTFail("Expected HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 503)
            XCTAssertEqual(error.status, 503)
            XCTAssertEqual(error.message, "Runner disconnected")
            XCTAssertEqual(error.payload?["error_type"].stringValue, "request_timeout")
            XCTAssertEqual(error.requestId, "req_123")
            XCTAssertEqual(error.errorType, "runner_disconnected")
            XCTAssertEqual(error.requestTimeoutType, "user")
            XCTAssertEqual(error.timeoutType, "user")
            XCTAssertTrue(error.isUserTimeout)
            XCTAssertEqual(error.headers["x-fal-request-id"], "req_123")
            XCTAssertEqual(error.responseHeaders["x-fal-request-id"], "req_123")
        }
    }

    func testHTTPErrorFallsBackToPayloadErrorTypeWhenHeaderIsMissing() async throws {
        PublicErrorRecordingURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 504,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {
              "detail": "Request timed out",
              "error_type": "request_timeout"
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let client = FalClient.withCredentials(.keyPair("fal-key-id:fal-key-secret"))

        do {
            let _: Payload = try await client.run("fal-ai/test", input: nil, options: .withMethod(.get))
            XCTFail("Expected HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 504)
            XCTAssertEqual(error.errorType, "request_timeout")
            XCTAssertNil(error.requestTimeoutType)
        }
    }

    func testHTTPErrorExtractsFalHeadersCaseInsensitively() async throws {
        PublicErrorRecordingURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: [
                    "X-FAL-REQUEST-ID": "req_upper",
                    "x-fal-error-type": "runner_connection_error",
                    "x-fal-request-timeout-type": "user",
                ]
            )!
            let data = #"{"detail":"Runner connection error"}"#.data(using: .utf8)!
            return (response, data)
        }

        let client = FalClient.withCredentials(.keyPair("fal-key-id:fal-key-secret"))

        do {
            let _: Payload = try await client.run("fal-ai/test", input: nil, options: .withMethod(.get))
            XCTFail("Expected HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.requestId, "req_upper")
            XCTAssertEqual(error.errorType, "runner_connection_error")
            XCTAssertEqual(error.requestTimeoutType, "user")
        }
    }

    func testHTTPErrorPreservesStatusAndHeadersWhenBodyIsNotJSON() async throws {
        PublicErrorRecordingURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: [
                    "x-fal-request-id": "req_non_json",
                    "X-Fal-Error-Type": "internal_error",
                ]
            )!
            let data = Data("not json".utf8)
            return (response, data)
        }

        let client = FalClient.withCredentials(.keyPair("fal-key-id:fal-key-secret"))

        do {
            let _: Payload = try await client.run("fal-ai/test", input: nil, options: .withMethod(.get))
            XCTFail("Expected HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 500)
            XCTAssertEqual(error.message, HTTPURLResponse.localizedString(forStatusCode: 500))
            XCTAssertNil(error.payload)
            XCTAssertEqual(error.requestId, "req_non_json")
            XCTAssertEqual(error.errorType, "internal_error")
        }
    }

    func testHTTPErrorDoesNotExposeSensitiveResponseHeaders() async throws {
        PublicErrorRecordingURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: [
                    "x-fal-request-id": "req_safe",
                    "set-cookie": "session=secret",
                    "authorization": "Bearer secret",
                ]
            )!
            let data = #"{"detail":"Internal error"}"#.data(using: .utf8)!
            return (response, data)
        }

        let client = FalClient.withCredentials(.keyPair("fal-key-id:fal-key-secret"))

        do {
            let _: Payload = try await client.run("fal-ai/test", input: nil, options: .withMethod(.get))
            XCTFail("Expected HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.headers["x-fal-request-id"], "req_safe")
            XCTAssertNil(error.headers["set-cookie"])
            XCTAssertNil(error.headers["authorization"])
        }
    }

    func testInvalidUrlDescriptionRedactsCredentialsAndQuery() {
        let error = FalError.invalidUrl(url: "https://user:password@example.com/upload?X-Goog-Signature=secret#fragment")

        XCTAssertEqual(error.errorDescription, "Invalid URL: https://example.com/upload")
        XCTAssertFalse(error.description.contains("secret"))
        XCTAssertFalse(error.description.contains("password"))
        XCTAssertFalse(error.description.contains("X-Goog-Signature"))
    }
}

private final class PublicErrorRecordingURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get { requestHandlerStorage.value }
        set { requestHandlerStorage.value = newValue }
    }

    private static let requestHandlerStorage = PublicErrorRequestHandlerStorage()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class PublicErrorRequestHandlerStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    var value: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return handler
        }
        set {
            lock.lock()
            handler = newValue
            lock.unlock()
        }
    }
}
