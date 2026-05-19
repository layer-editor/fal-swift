@testable import FalClient
import XCTest

final class RealtimeConnectionPoolTests: XCTestCase {
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
}

private struct RealtimeTestClient: Client {
    let config = ClientConfig()

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
