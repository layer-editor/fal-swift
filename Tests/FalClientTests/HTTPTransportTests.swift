@testable import FalClient
import XCTest

final class HTTPTransportTests: XCTestCase {
    override func tearDown() {
        RedirectingURLProtocol.reset()
        super.tearDown()
    }

    func testSendRequestUsesInjectedHTTPTransport() async throws {
        let transport = RecordingHTTPTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"value":"ok"}"#.data(using: .utf8)!, response: response)
        }
        let client = TransportTestClient(httpTransport: transport)

        let data = try await client.sendRequest(
            to: "https://fal.run/fal-ai/test",
            input: nil as Data?,
            options: RunOptions.withMethod(.get)
        )

        XCTAssertEqual(try Payload.create(fromJSON: data)["value"].stringValue, "ok")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, ["https://fal.run/fal-ai/test"])
    }

    func testStorageUploadUsesInjectedHTTPTransportForInitiateAndPut() async throws {
        let transport = RecordingHTTPTransport { request in
            if request.url?.absoluteString == "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/file.png",
                  "upload_url": "https://storage.googleapis.com/upload"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: Data(), response: response)
        }
        let client = TransportTestClient(httpTransport: transport)
        let storage = StorageClient(client: client)

        let fileUrl = try await storage.upload(
            data: Data("image".utf8),
            ofType: FileType.imagePng,
            options: .presignedFalCDNV3
        )

        XCTAssertEqual(fileUrl, "https://fal.media/file.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://storage.googleapis.com/upload",
        ])
        XCTAssertEqual(transport.requests.last?.httpMethod, "PUT")
    }

    func testURLSessionTransportRejectsUnsafeRedirectsWhenValidatorIsProvided() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }
        let transport = URLSessionHTTPTransport(session: session)
        let request = URLRequest(url: URL(string: "https://storage.googleapis.com/upload")!)

        do {
            _ = try await transport.data(for: request, validatingRedirectsWith: { URL.safeExternalHTTPSURL($0) })
            XCTFail("Expected unsafe redirect to be rejected")
        } catch FalError.invalidUrl(let url) {
            XCTAssertEqual(url, "http://127.0.0.1/upload")
        }

        XCTAssertEqual(RedirectingURLProtocol.requestedURLs(), [
            URL(string: "https://storage.googleapis.com/upload")!,
        ])
    }

    func testURLSessionTransportAllowsSafeRedirectsWhenValidatorIsProvided() async throws {
        RedirectingURLProtocol.setRedirectLocation("https://storage.googleapis.com/final-upload")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }
        let transport = URLSessionHTTPTransport(session: session)
        var request = URLRequest(url: URL(string: "https://storage.googleapis.com/upload")!)
        request.httpMethod = "PUT"
        request.httpBody = Data("image".utf8)
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")

        let response = try await transport.data(
            for: request,
            validatingRedirectsWith: { URL.safeExternalHTTPSURL($0) }
        )

        XCTAssertEqual(String(data: response.data, encoding: .utf8), "ok")
        XCTAssertEqual(RedirectingURLProtocol.requestedRequests(), [
            RedirectingURLProtocolRequest(
                url: URL(string: "https://storage.googleapis.com/upload")!,
                httpMethod: "PUT",
                contentType: "image/png"
            ),
            RedirectingURLProtocolRequest(
                url: URL(string: "https://storage.googleapis.com/final-upload")!,
                httpMethod: "PUT",
                contentType: "image/png"
            ),
        ])
    }

    func testServerSentEventParserYieldsDataEvents() async throws {
        let lines = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(": heartbeat")
            continuation.yield("")
            continuation.yield("data: {\"status\":\"IN_PROGRESS\"}")
            continuation.yield("")
            continuation.yield("data: {")
            continuation.yield("data: \"status\":\"COMPLETED\"")
            continuation.yield("data: }")
            continuation.finish()
        }
        let events = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                do {
                    try await parseServerSentEvents(from: lines, yieldingTo: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        var decodedEvents: [String] = []
        for try await event in events {
            decodedEvents.append(String(data: event, encoding: .utf8) ?? "")
        }

        XCTAssertEqual(decodedEvents, [
            #"{"status":"IN_PROGRESS"}"#,
            """
            {
            "status":"COMPLETED"
            }
            """,
        ])
    }
}

private final class RedirectingURLProtocol: URLProtocol {
    private static let state = RedirectingURLProtocolState()

    static func reset() {
        state.reset()
    }

    static func setRedirectLocation(_ location: String) {
        state.setRedirectLocation(location)
    }

    static func requestedURLs() -> [URL] {
        state.requestedURLs()
    }

    static func requestedRequests() -> [RedirectingURLProtocolRequest] {
        state.requestedRequests()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: FalError.invalidResultFormat)
            return
        }
        Self.state.appendRequestedRequest(
            RedirectingURLProtocolRequest(
                url: url,
                httpMethod: request.httpMethod,
                contentType: request.value(forHTTPHeaderField: "Content-Type")
            )
        )
        let redirectLocation = Self.state.redirectLocation()
        guard url.absoluteString != redirectLocation else {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("ok".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 307,
            httpVersion: nil,
            headerFields: [
                "Location": redirectLocation,
            ]
        )!
        var redirectRequest = request
        redirectRequest.url = URL(string: redirectLocation)!
        client?.urlProtocol(self, wasRedirectedTo: redirectRequest, redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct RedirectingURLProtocolRequest: Equatable, Sendable {
    let url: URL
    let httpMethod: String?
    let contentType: String?
}

private final class RedirectingURLProtocolState: @unchecked Sendable {
    private let defaultRedirectLocation = "http://127.0.0.1/upload?signature=secret"
    private let lock = NSLock()
    private var requests: [RedirectingURLProtocolRequest] = []
    private var location = "http://127.0.0.1/upload?signature=secret"

    func appendRequestedRequest(_ request: RedirectingURLProtocolRequest) {
        lock.withLock {
            requests.append(request)
        }
    }

    func requestedURLs() -> [URL] {
        lock.withLock {
            requests.map(\.url)
        }
    }

    func requestedRequests() -> [RedirectingURLProtocolRequest] {
        lock.withLock {
            requests
        }
    }

    func setRedirectLocation(_ location: String) {
        lock.withLock {
            self.location = location
        }
    }

    func redirectLocation() -> String {
        lock.withLock {
            location
        }
    }

    func reset() {
        lock.withLock {
            requests.removeAll()
            location = defaultRedirectLocation
        }
    }
}

private struct TransportTestClient: Client, HTTPTransportProviding {
    let config = ClientConfig()
    let httpTransport: HTTPTransport

    var queue: Queue {
        fatalError("TransportTestClient.queue is unused in these tests")
    }

    var realtime: Realtime {
        fatalError("TransportTestClient.realtime is unused in these tests")
    }

    var storage: Storage {
        fatalError("TransportTestClient.storage is unused in these tests")
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        fatalError("TransportTestClient.run is unused in these tests")
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("TransportTestClient.subscribe is unused in these tests")
    }
}
