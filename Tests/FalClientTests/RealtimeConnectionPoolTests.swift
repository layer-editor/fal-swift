@testable import FalClient
import XCTest

final class RealtimeConnectionPoolTests: XCTestCase {
    func testRealtimeUrlUsesDefaultPathForAppWithoutEndpointPath() throws {
        let url = try buildRealtimeUrl(forApp: "fal-ai/test", token: "test-jwt")

        XCTAssertEqual(url.absoluteString, "wss://fal.run/fal-ai/test/realtime?fal_jwt_token=test-jwt")
    }

    func testRealtimeUrlDoesNotDuplicateDefaultPathWhenAppIncludesEndpointPath() throws {
        let url = try buildRealtimeUrl(forApp: "fal-ai/test/realtime", token: "test-jwt")

        XCTAssertEqual(url.absoluteString, "wss://fal.run/fal-ai/test/realtime?fal_jwt_token=test-jwt")
    }

    func testRealtimeUrlUsesCustomPath() throws {
        let url = try buildRealtimeUrl(forApp: "fal-ai/test", path: "/custom-ws", token: "test-jwt")

        XCTAssertEqual(url.absoluteString, "wss://fal.run/fal-ai/test/custom-ws?fal_jwt_token=test-jwt")
    }

    func testRealtimeUrlUsesCustomPathForShorthandAppId() throws {
        let url = try buildRealtimeUrl(forApp: "123-test-app", path: "/custom-ws", token: "test-jwt")

        XCTAssertEqual(url.absoluteString, "wss://fal.run/123/test-app/custom-ws?fal_jwt_token=test-jwt")
    }

    func testRealtimeUrlRejectsInvalidCustomPaths() {
        let invalidPaths = [
            "https://example.com/custom-ws",
            "/custom-ws?token=secret",
            "/custom-ws#fragment",
            "/../admin",
            "/custom-ws/%2Fadmin",
        ]

        for path in invalidPaths {
            XCTAssertThrowsError(try buildRealtimeUrl(forApp: "fal-ai/test", path: path, token: "test-jwt"))
        }
    }

    func testRealtimeConnectSupportsExplicitPathOverloads() throws {
        let realtime = RealtimeClient(client: RealtimeTestClient())

        let payloadConnection = try realtime.connect(
            to: "fal-ai/test",
            path: "/custom-ws",
            connectionKey: UUID().uuidString,
            onResult: { (_: Result<Payload, Error>) in }
        )
        let typedConnection: TypedRealtimeConnection<RealtimePrompt> = try realtime.connect(
            to: "fal-ai/test",
            path: "/custom-ws",
            connectionKey: UUID().uuidString,
            onResult: { (_: Result<Payload, Error>) in }
        )
        defer {
            payloadConnection.close()
            typedConnection.close()
        }

        XCTAssertNotNil(payloadConnection)
        XCTAssertNotNil(typedConnection)
    }

    func testRealtimeConnectRejectsInvalidExplicitPath() {
        let realtime = RealtimeClient(client: RealtimeTestClient())

        XCTAssertThrowsError(try realtime.connect(
            to: "fal-ai/test",
            path: "/custom-ws?token=secret",
            connectionKey: UUID().uuidString,
            onResult: { (_: Result<Payload, Error>) in }
        ))
        XCTAssertThrowsError(try (realtime.connect(
            to: "fal-ai/test",
            path: "/custom-ws?token=secret",
            connectionKey: UUID().uuidString,
            onResult: { (_: Result<Payload, Error>) in }
        ) as TypedRealtimeConnection<RealtimePrompt>))
    }

    func testPoolReusesConnectionForSameKey() {
        let pool = RealtimeConnectionPool()
        let client = RealtimeTestClient()

        let first = pool.connection(for: "fal-ai/test:shared") {
            WebSocketConnection(
                app: "fal-ai/test",
                client: client,
                onMessage: { _ in },
                onError: { _ in }
            )
        }
        let second = pool.connection(for: "fal-ai/test:shared") {
            WebSocketConnection(
                app: "fal-ai/test",
                client: client,
                onMessage: { _ in },
                onError: { _ in }
            )
        }

        XCTAssertTrue(first === second)
    }

    func testPoolCreatesNewConnectionAfterRemove() {
        let pool = RealtimeConnectionPool()
        let client = RealtimeTestClient()

        let first = pool.connection(for: "fal-ai/test:shared") {
            WebSocketConnection(
                app: "fal-ai/test",
                client: client,
                onMessage: { _ in },
                onError: { _ in }
            )
        }
        pool.removeConnection(for: "fal-ai/test:shared", matching: first)

        let second = pool.connection(for: "fal-ai/test:shared") {
            WebSocketConnection(
                app: "fal-ai/test",
                client: client,
                onMessage: { _ in },
                onError: { _ in }
            )
        }

        XCTAssertFalse(first === second)
    }

    func testPoolDoesNotRemoveDifferentConnectionForSameKey() {
        let pool = RealtimeConnectionPool()
        let client = RealtimeTestClient()
        let staleConnection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            onMessage: { _ in },
            onError: { _ in }
        )

        let currentConnection = pool.connection(for: "fal-ai/test:shared") {
            WebSocketConnection(
                app: "fal-ai/test",
                client: client,
                onMessage: { _ in },
                onError: { _ in }
            )
        }
        pool.removeConnection(for: "fal-ai/test:shared", matching: staleConnection)

        let reusedConnection = pool.connection(for: "fal-ai/test:shared") {
            WebSocketConnection(
                app: "fal-ai/test",
                client: client,
                onMessage: { _ in },
                onError: { _ in }
            )
        }

        XCTAssertTrue(currentConnection === reusedConnection)
    }

    func testConnectionRunsCloseCleanupWhenManuallyClosed() async throws {
        let client = RealtimeTestClient()
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            onMessage: { _ in },
            onError: { _ in }
        )
        let cleanup = XCTestExpectation(description: "close cleanup")
        connection.onClose = {
            cleanup.fulfill()
        }

        connection.close()

        await fulfillment(of: [cleanup], timeout: 1)
    }

    func testConnectionRunsCloseCleanupWhenSocketCloses() async throws {
        let client = RealtimeTestClient()
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            onMessage: { _ in },
            onError: { _ in }
        )
        let cleanup = XCTestExpectation(description: "delegate close cleanup")
        connection.onClose = {
            cleanup.fulfill()
        }
        let url = try XCTUnwrap(URL(string: "wss://fal.run/fal-ai/test"))
        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: url)

        connection.urlSession(
            session,
            webSocketTask: task,
            didCloseWith: .normalClosure,
            reason: nil
        )

        await fulfillment(of: [cleanup], timeout: 1)
    }

    func testSendFetchesRealtimeTokenAndFlushesQueuedMessageWhenSocketOpens() async throws {
        let client = RealtimeTestClient()
        let fakeTask = FakeRealtimeWebSocketTask()
        let createdTask = XCTestExpectation(description: "created task")
        let sentMessage = XCTestExpectation(description: "sent message")
        fakeTask.onSend = {
            sentMessage.fulfill()
        }
        let capturedURL = LockedValue<URL?>(nil)
        let factory = FakeRealtimeWebSocketTaskFactory(task: fakeTask) { url in
            capturedURL.set(url)
            createdTask.fulfill()
        }
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            webSocketTaskFactory: factory,
            refreshToken: { app, path, completion in
                XCTAssertEqual(app, "fal-ai/test")
                XCTAssertNil(path)
                completion(.success("test-jwt"))
            },
            onMessage: { _ in },
            onError: { XCTFail("Unexpected realtime error: \($0)") }
        )

        try connection.send(.string(#"{"prompt":"hi"}"#))
        await fulfillment(of: [createdTask], timeout: 1)

        XCTAssertEqual(capturedURL.value?.absoluteString, "wss://fal.run/fal-ai/test/realtime?fal_jwt_token=test-jwt")
        XCTAssertEqual(fakeTask.resumeCallCount, 1)
        XCTAssertTrue(fakeTask.sentMessages.isEmpty)

        connection.realtimeSocketDidOpen()
        await fulfillment(of: [sentMessage], timeout: 1)

        guard case let .string(sentPayload)? = fakeTask.sentMessages.first else {
            return XCTFail("Expected queued string message to be sent after socket opens")
        }
        XCTAssertEqual(sentPayload, #"{"prompt":"hi"}"#)
    }

    func testSendFlushesQueuedMessagesInOrderWhenSocketOpens() async throws {
        let client = RealtimeTestClient()
        let fakeTask = FakeRealtimeWebSocketTask()
        let createdTask = XCTestExpectation(description: "created task")
        let firstSentMessage = XCTestExpectation(description: "first sent message")
        let secondSentMessage = XCTestExpectation(description: "second sent message")
        let sendCount = LockedValue(0)
        fakeTask.onSend = {
            let nextCount = sendCount.increment()
            if nextCount == 1 {
                firstSentMessage.fulfill()
            } else if nextCount == 2 {
                secondSentMessage.fulfill()
            }
        }
        let factory = FakeRealtimeWebSocketTaskFactory(task: fakeTask) { _ in
            createdTask.fulfill()
        }
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            webSocketTaskFactory: factory,
            refreshToken: { _, _, completion in completion(.success("test-jwt")) },
            onMessage: { _ in },
            onError: { XCTFail("Unexpected realtime error: \($0)") }
        )

        try connection.send(.string("first"))
        try connection.send(.string("second"))
        await fulfillment(of: [createdTask], timeout: 1)

        connection.realtimeSocketDidOpen()
        await fulfillment(of: [firstSentMessage, secondSentMessage], timeout: 1)

        XCTAssertEqual(
            fakeTask.sentMessages.map(\.testStringValue),
            ["first", "second"]
        )
    }

    func testCloseDuringTokenRefreshDoesNotOpenSocketAfterRefreshCompletes() async throws {
        let client = RealtimeTestClient()
        let fakeTask = FakeRealtimeWebSocketTask()
        let socketShouldNotOpen = expectation(description: "socket should not open")
        socketShouldNotOpen.isInverted = true
        let tokenRefreshStarted = XCTestExpectation(description: "token refresh started")
        let refreshCompletion = LockedValue<(@Sendable (Result<String, Error>) -> Void)?>(nil)
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            webSocketTaskFactory: FakeRealtimeWebSocketTaskFactory(task: fakeTask) { _ in
                socketShouldNotOpen.fulfill()
            },
            refreshToken: { _, _, completion in
                refreshCompletion.set(completion)
                tokenRefreshStarted.fulfill()
            },
            onMessage: { _ in },
            onError: { _ in }
        )

        try connection.send(.string("first"))
        await fulfillment(of: [tokenRefreshStarted], timeout: 1)

        connection.close()
        refreshCompletion.value?(.success("test-jwt"))

        await fulfillment(of: [socketShouldNotOpen], timeout: 0.2)
        XCTAssertEqual(fakeTask.resumeCallCount, 0)
    }

    func testCloseCancelsFakeSocketAndRunsCleanup() async throws {
        let client = RealtimeTestClient()
        let fakeTask = FakeRealtimeWebSocketTask()
        let createdTask = XCTestExpectation(description: "created task")
        let cleanup = XCTestExpectation(description: "close cleanup")
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            webSocketTaskFactory: FakeRealtimeWebSocketTaskFactory(task: fakeTask) { _ in
                createdTask.fulfill()
            },
            refreshToken: { _, _, completion in completion(.success("test-jwt")) },
            onMessage: { _ in },
            onError: { XCTFail("Unexpected realtime error: \($0)") }
        )
        connection.onClose = {
            cleanup.fulfill()
        }

        try connection.send(.string("first"))
        await fulfillment(of: [createdTask], timeout: 1)
        connection.close()

        await fulfillment(of: [cleanup], timeout: 1)
        XCTAssertEqual(fakeTask.cancelCode, .normalClosure)
    }

    func testReceiveDeliversSuccessMessagesAndReportsSocketFailures() async throws {
        let client = RealtimeTestClient()
        let fakeTask = FakeRealtimeWebSocketTask()
        let createdTask = XCTestExpectation(description: "created task")
        let receivedMessage = XCTestExpectation(description: "received message")
        let receivedError = XCTestExpectation(description: "received error")
        let factory = FakeRealtimeWebSocketTaskFactory(task: fakeTask) { _ in
            createdTask.fulfill()
        }
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            webSocketTaskFactory: factory,
            refreshToken: { _, _, completion in completion(.success("test-jwt")) },
            onMessage: { message in
                guard case let .string(value) = message else {
                    return XCTFail("Expected string realtime message")
                }
                XCTAssertEqual(value, #"{"status":"completed","value":1}"#)
                receivedMessage.fulfill()
            },
            onError: { error in
                XCTAssertEqual((error as NSError).domain, "FakeRealtimeWebSocketTask")
                receivedError.fulfill()
            }
        )

        try connection.send(.string(#"{"prompt":"hi"}"#))
        await fulfillment(of: [createdTask], timeout: 1)

        fakeTask.deliver(.string(#"{"status":"completed","value":1}"#))
        await fulfillment(of: [receivedMessage], timeout: 1)

        fakeTask.failReceive(NSError(domain: "FakeRealtimeWebSocketTask", code: 1))
        await fulfillment(of: [receivedError], timeout: 1)
    }

    func testRefreshTokenUsesRealtimeTokenEndpointAndFullEndpointPath() async throws {
        let transport = CapturingRealtimeHTTPTransport(responseBody: #"{"token":"test-jwt"}"#)
        let client = RealtimeTestClient(
            config: ClientConfig(credentials: .keyPair("key-id:key-secret")),
            httpTransport: transport
        )
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            path: "/custom-ws",
            client: client,
            webSocketTaskFactory: FakeRealtimeWebSocketTaskFactory(task: FakeRealtimeWebSocketTask()),
            onMessage: { _ in },
            onError: { _ in }
        )
        let refreshedToken = XCTestExpectation(description: "refreshed token")
        let result = LockedValue<Result<String, Error>?>(nil)

        connection.refreshToken("fal-ai/test", path: "/custom-ws") { tokenResult in
            result.set(tokenResult)
            refreshedToken.fulfill()
        }

        await fulfillment(of: [refreshedToken], timeout: 1)

        XCTAssertEqual(try result.value?.get(), "test-jwt")
        let request = try XCTUnwrap(transport.capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://rest.fal.ai/tokens/realtime")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Key key-id:key-secret")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(payload?["duration"] as? Int, 300)
        XCTAssertEqual(payload?["allowed_apps"] as? [String], ["fal-ai/test/custom-ws"])
    }

    func testRefreshTokenRejectsJsonObjectWithoutToken() async throws {
        let transport = CapturingRealtimeHTTPTransport(responseBody: #"{"error":"missing token"}"#)
        let client = RealtimeTestClient(httpTransport: transport)
        let connection = WebSocketConnection(
            app: "fal-ai/test",
            client: client,
            webSocketTaskFactory: FakeRealtimeWebSocketTaskFactory(task: FakeRealtimeWebSocketTask()),
            onMessage: { _ in },
            onError: { _ in }
        )
        let refreshedToken = XCTestExpectation(description: "refreshed token")
        let result = LockedValue<Result<String, Error>?>(nil)

        connection.refreshToken("fal-ai/test") { tokenResult in
            result.set(tokenResult)
            refreshedToken.fulfill()
        }

        await fulfillment(of: [refreshedToken], timeout: 1)

        XCTAssertThrowsError(try result.value?.get()) { error in
            XCTAssertTrue(error is FalRealtimeError)
        }
    }

    func testPoolKeyUsesCanonicalEndpointIdentity() throws {
        let defaultPathKey = try realtimeConnectionPoolKey(
            forApp: "fal-ai/test",
            path: nil,
            connectionKey: "shared"
        )
        let explicitPathKey = try realtimeConnectionPoolKey(
            forApp: "fal-ai/test",
            path: "/realtime",
            connectionKey: "shared"
        )
        let shorthandPathKey = try realtimeConnectionPoolKey(
            forApp: "123-test-app",
            path: "/custom-ws",
            connectionKey: "shared"
        )

        XCTAssertEqual(defaultPathKey, explicitPathKey)
        XCTAssertEqual(shorthandPathKey, "123/test-app:/custom-ws:shared")
    }
}

private struct RealtimeTestClient: Client, HTTPTransportProviding {
    let config: ClientConfig
    let httpTransport: HTTPTransport

    init(
        config: ClientConfig = ClientConfig(),
        httpTransport: HTTPTransport = UnusedRealtimeHTTPTransport()
    ) {
        self.config = config
        self.httpTransport = httpTransport
    }

    var queue: Queue {
        fatalError("RealtimeTestClient.queue is unused in these tests")
    }

    var realtime: Realtime {
        fatalError("RealtimeTestClient.realtime is unused in these tests")
    }

    var storage: Storage {
        fatalError("RealtimeTestClient.storage is unused in these tests")
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        fatalError("RealtimeTestClient.run is unused in these tests")
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("RealtimeTestClient.subscribe is unused in these tests")
    }
}

private struct RealtimePrompt: Encodable {
    let prompt = "test"
}

private final class FakeRealtimeWebSocketTaskFactory: RealtimeWebSocketTaskFactory, @unchecked Sendable {
    private let task: FakeRealtimeWebSocketTask
    private let onCreate: @Sendable (URL) -> Void

    init(
        task: FakeRealtimeWebSocketTask,
        onCreate: @escaping @Sendable (URL) -> Void = { _ in }
    ) {
        self.task = task
        self.onCreate = onCreate
    }

    func webSocketTask(with url: URL, delegate _: URLSessionWebSocketDelegate) -> RealtimeWebSocketTask {
        onCreate(url)
        return task
    }
}

private final class FakeRealtimeWebSocketTask: RealtimeWebSocketTask, @unchecked Sendable {
    var onSend: @Sendable () -> Void = {}

    private let lock = NSLock()
    private var pendingReceive: (@Sendable (Result<WebSocketMessage, Error>) -> Void)?
    private var _resumeCallCount = 0
    private var _sentMessages: [WebSocketMessage] = []
    private var _cancelCode: URLSessionWebSocketTask.CloseCode?

    var resumeCallCount: Int {
        lock.withLock { _resumeCallCount }
    }

    var sentMessages: [WebSocketMessage] {
        lock.withLock { _sentMessages }
    }

    var cancelCode: URLSessionWebSocketTask.CloseCode? {
        lock.withLock { _cancelCode }
    }

    func resume() {
        lock.withLock {
            _resumeCallCount += 1
        }
    }

    func send(
        _ message: WebSocketMessage,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        lock.withLock {
            _sentMessages.append(message)
        }
        onSend()
        completionHandler(nil)
    }

    func receive(completionHandler: @escaping @Sendable (Result<WebSocketMessage, Error>) -> Void) {
        lock.withLock {
            pendingReceive = completionHandler
        }
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason _: Data?) {
        lock.withLock {
            _cancelCode = closeCode
        }
    }

    func deliver(_ message: WebSocketMessage) {
        let handler = lock.withLock {
            let handler = pendingReceive
            pendingReceive = nil
            return handler
        }
        handler?(.success(message))
    }

    func failReceive(_ error: Error) {
        let handler = lock.withLock {
            let handler = pendingReceive
            pendingReceive = nil
            return handler
        }
        handler?(.failure(error))
    }
}

private final class CapturingRealtimeHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let responseBody: String
    private var _capturedRequest: URLRequest?

    init(responseBody: String) {
        self.responseBody = responseBody
    }

    var capturedRequest: URLRequest? {
        lock.withLock { _capturedRequest }
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        lock.withLock {
            _capturedRequest = request
        }
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        return HTTPTransportResponse(
            data: Data(responseBody.utf8),
            response: response
        )
    }

    func serverSentEvents(for _: URLRequest) async throws -> HTTPTransportEventStream {
        fatalError("CapturingRealtimeHTTPTransport.serverSentEvents is unused in these tests")
    }
}

private struct UnusedRealtimeHTTPTransport: HTTPTransport {
    func data(for _: URLRequest) async throws -> HTTPTransportResponse {
        fatalError("UnusedRealtimeHTTPTransport.data is unused in these tests")
    }

    func serverSentEvents(for _: URLRequest) async throws -> HTTPTransportEventStream {
        fatalError("UnusedRealtimeHTTPTransport.serverSentEvents is unused in these tests")
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock {
            storage = value
        }
    }
}

private extension LockedValue where Value == Int {
    func increment() -> Int {
        lock.withLock {
            storage += 1
            return storage
        }
    }
}

private extension WebSocketMessage {
    var testStringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }
}
