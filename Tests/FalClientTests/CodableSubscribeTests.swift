@testable import FalClient
import XCTest

final class CodableSubscribeTests: XCTestCase {
    func testTypedSubscribeWaitsUntilDeadlineInsteadOfAccumulatingElapsedTime() async throws {
        let queue = StubQueue(statuses: Array(repeating: .inQueue(position: 1, responseUrl: "https://example.com/result"), count: 12) + [
            .completed(logs: [], responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)

        let output: SubscribeOutput = try await client.subscribe(
            to: "fal-ai/test",
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250)
        )

        XCTAssertEqual(output.value, "ok")
        XCTAssertGreaterThanOrEqual(queue.statusCallCount, 13)
    }

    func testTypedSubscribeCanReceiveQueueStatusDetails() async throws {
        let queue = StubQueue(statusDetails: [
            QueueStatusDetail(
                status: .inQueue(position: 1, responseUrl: "https://example.com/result"),
                requestId: "request-id",
                responseUrl: "https://example.com/result",
                statusUrl: "https://example.com/status",
                cancelUrl: "https://example.com/cancel"
            ),
            QueueStatusDetail(
                status: .completed(logs: [], responseUrl: "https://example.com/result"),
                requestId: "request-id",
                responseUrl: "https://example.com/result",
                metrics: [
                    "inference_time": 1.25,
                ]
            ),
        ])
        let client = StubClient(queue: queue)
        var updates: [QueueStatusDetail] = []

        let output: SubscribeOutput = try await client.subscribeWithStatusDetails(
            to: "fal-ai/test",
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250),
            includeLogs: true,
            onQueueStatusDetailUpdate: { updates.append($0) }
        )

        XCTAssertEqual(output.value, "ok")
        XCTAssertEqual(queue.includeLogsValues, [true, true])
        XCTAssertEqual(updates.map(\.requestId), ["request-id", "request-id"])
        XCTAssertEqual(updates.first?.statusUrl, "https://example.com/status")
        XCTAssertEqual(updates.first?.cancelUrl, "https://example.com/cancel")
        XCTAssertEqual(updates.last?.metrics?["inference_time"], .double(1.25))
    }

    func testQueueSubscribeToStatusEmitsDetailsAndReturnsCompletedStatus() async throws {
        let queue = StubQueue(statusDetails: [
            QueueStatusDetail(
                status: .inQueue(position: 2, responseUrl: "https://example.com/result"),
                requestId: "request-id",
                responseUrl: "https://example.com/result",
                statusUrl: "https://example.com/status"
            ),
            QueueStatusDetail(
                status: .completed(logs: [], responseUrl: "https://example.com/result"),
                requestId: "request-id",
                responseUrl: "https://example.com/result",
                metrics: [
                    "inference_time": 2.5,
                ]
            ),
        ])
        var updates: [QueueStatusDetail] = []

        let finalStatus = try await queue.subscribeToStatus(
            "fal-ai/test",
            of: "request-id",
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250),
            includeLogs: true,
            onQueueStatusDetailUpdate: { updates.append($0) }
        )

        XCTAssertEqual(finalStatus.requestId, "request-id")
        XCTAssertEqual(finalStatus.metrics?["inference_time"], .double(2.5))
        XCTAssertEqual(updates.map(\.requestId), ["request-id", "request-id"])
        XCTAssertEqual(queue.includeLogsValues, [true, true])
    }

    func testQueueSubscribeToStatusTimeoutDoesNotCancelObservedRequest() async throws {
        let queue = StubQueue(statuses: [
            .inQueue(position: 1, responseUrl: "https://example.com/result"),
        ])

        do {
            _ = try await queue.subscribeToStatus(
                "fal-ai/test",
                of: "request-id",
                pollInterval: .milliseconds(250),
                timeout: .milliseconds(30),
                onQueueStatusDetailUpdate: { _ in }
            )
            XCTFail("Expected status subscription to time out")
        } catch FalError.queueTimeout(let requestId) {
            XCTAssertEqual(requestId, "request-id")
            XCTAssertTrue(queue.cancelledRequests.isEmpty)
        }
    }

    func testQueueSubscribeToStatusTaskCancellationDoesNotCancelObservedRequest() async throws {
        let queue = StubQueue(
            statuses: [.inQueue(position: 1, responseUrl: "https://example.com/result")],
            statusDelay: .milliseconds(250)
        )

        let task = Task {
            try await queue.subscribeToStatus(
                "fal-ai/test",
                of: "request-id",
                pollInterval: .milliseconds(10),
                timeout: .seconds(5)
            )
        }
        try await DispatchTimeInterval.milliseconds(30).sleep()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected status subscription to be cancelled")
        } catch is CancellationError {
            XCTAssertTrue(queue.cancelledRequests.isEmpty)
        }
    }

    func testQueueSubscribeToStatusCanOmitUpdateCallback() async throws {
        let queue = StubQueue(statusDetails: [
            QueueStatusDetail(
                status: .completed(logs: [], responseUrl: "https://example.com/result"),
                requestId: "request-id",
                responseUrl: "https://example.com/result"
            ),
        ])

        let finalStatus = try await queue.subscribeToStatus(
            "fal-ai/test",
            of: "request-id",
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250)
        )

        XCTAssertEqual(finalStatus.requestId, "request-id")
        XCTAssertEqual(queue.statusCallCount, 1)
    }

    func testTypedSubscribeOptionsUseConcreteQueueSubmitImplementation() async throws {
        let queue = StubQueue(statuses: [
            .completed(logs: [], responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)

        let output: SubscribeOutput = try await client.subscribe(
            to: "fal-ai/test",
            input: SubscribeInput(value: "cat"),
            options: RunOptions(startTimeout: 20, hint: "subscribe-runner", queuePriority: .low),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250)
        )

        XCTAssertEqual(output.value, "ok")
        XCTAssertEqual(queue.submittedOptionStartTimeouts, [20])
        XCTAssertEqual(queue.submittedOptionHints, ["subscribe-runner"])
        XCTAssertEqual(queue.submittedOptionPriorities, [.low])
    }

    func testTypedSubscribeOnEnqueueUsesOriginalSubmitForCustomQueueFallback() async throws {
        let queue = StubQueue(statuses: [
            .completed(logs: [], responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)
        var enqueueResult: QueueSubmitResult?

        let output: SubscribeOutput = try await client.subscribe(
            to: "fal-ai/test",
            input: SubscribeInput(value: "cat"),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250),
            onEnqueue: { enqueueResult = $0 }
        )

        XCTAssertEqual(output.value, "ok")
        XCTAssertEqual(enqueueResult, QueueSubmitResult(requestId: "request-id"))
        XCTAssertEqual(queue.submitCallCount, 1)
        XCTAssertEqual(queue.submittedOptionStartTimeouts, [])
    }

    func testPayloadSubscribeCanReceiveQueueStatusDetails() async throws {
        let queue = StubQueue(statusDetails: [
            QueueStatusDetail(
                status: .inQueue(position: 1, responseUrl: "https://example.com/result"),
                requestId: "request-id",
                responseUrl: "https://example.com/result"
            ),
            QueueStatusDetail(
                status: .completed(logs: [], responseUrl: "https://example.com/result"),
                requestId: "request-id",
                responseUrl: "https://example.com/result"
            ),
        ])
        let client = StubClient(queue: queue)
        var updates: [QueueStatusDetail] = []

        let output = try await client.subscribeWithStatusDetails(
            to: "fal-ai/test",
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250),
            onQueueStatusDetailUpdate: { updates.append($0) }
        )

        XCTAssertEqual(output["value"], "ok")
        XCTAssertEqual(updates.map(\.requestId), ["request-id", "request-id"])
    }

    func testPayloadSubscribeCancelsQueueRequestOnTimeout() async throws {
        let queue = StubQueue(statuses: [
            .inQueue(position: 1, responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)

        do {
            _ = try await client.subscribe(
                to: "fal-ai/test",
                input: nil as Payload?,
                options: RunOptions(startTimeout: 20, hint: "payload-runner", queuePriority: .low),
                pollInterval: .milliseconds(250),
                timeout: .milliseconds(30)
            )
            XCTFail("Expected payload subscribe to time out")
        } catch FalError.queueTimeout(let requestId) {
            XCTAssertEqual(requestId, "request-id")
            XCTAssertEqual(queue.cancelledRequests, [
                QueueCancelRequest(app: "fal-ai/test", requestId: "request-id"),
            ])
            XCTAssertEqual(queue.submittedOptionStartTimeouts, [20])
            XCTAssertEqual(queue.submittedOptionHints, ["payload-runner"])
            XCTAssertEqual(queue.submittedOptionPriorities, [.low])
        }
    }

    func testPayloadSubscribeOnEnqueueOptionsUseConcreteQueueSubmitImplementation() async throws {
        let queue = StubQueue(statuses: [
            .completed(logs: [], responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)
        var enqueueResult: QueueSubmitResult?

        let output = try await client.subscribe(
            to: "fal-ai/test",
            input: nil as Payload?,
            options: RunOptions(startTimeout: 15, hint: "payload-enqueue", queuePriority: .normal),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250),
            onEnqueue: { enqueueResult = $0 }
        )

        XCTAssertEqual(output["value"], "ok")
        XCTAssertEqual(enqueueResult, QueueSubmitResult(requestId: "request-id"))
        XCTAssertEqual(queue.submitCallCount, 1)
        XCTAssertEqual(queue.submittedOptionStartTimeouts, [15])
        XCTAssertEqual(queue.submittedOptionHints, ["payload-enqueue"])
        XCTAssertEqual(queue.submittedOptionPriorities, [.normal])
    }

    func testPayloadSubscribeWithStatusDetailsOptionsUseConcreteQueueSubmitImplementation() async throws {
        let queue = StubQueue(statusDetails: [
            QueueStatusDetail(
                status: .completed(logs: [], responseUrl: "https://example.com/result"),
                requestId: "request-id",
                responseUrl: "https://example.com/result"
            ),
        ])
        let client = StubClient(queue: queue)

        let output = try await client.subscribeWithStatusDetails(
            to: "fal-ai/test",
            input: nil as Payload?,
            options: RunOptions(startTimeout: 25, hint: "payload-detail", queuePriority: .low),
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250),
            onQueueStatusDetailUpdate: { _ in }
        )

        XCTAssertEqual(output["value"], "ok")
        XCTAssertEqual(queue.submitCallCount, 1)
        XCTAssertEqual(queue.submittedOptionStartTimeouts, [25])
        XCTAssertEqual(queue.submittedOptionHints, ["payload-detail"])
        XCTAssertEqual(queue.submittedOptionPriorities, [.low])
    }

    func testPayloadSubscribeWithStatusDetailsCancelsQueueRequestOnTaskCancellation() async throws {
        let queue = StubQueue(
            statusDetails: [
                QueueStatusDetail(
                    status: .inQueue(position: 1, responseUrl: "https://example.com/result"),
                    requestId: "request-id",
                    responseUrl: "https://example.com/result"
                ),
            ],
            statusDelay: .milliseconds(250)
        )
        let client = StubClient(queue: queue)

        let task = Task {
            _ = try await client.subscribeWithStatusDetails(
                to: "fal-ai/test",
                input: nil as Payload?,
                pollInterval: .milliseconds(10),
                timeout: .seconds(5),
                onQueueStatusDetailUpdate: { _ in }
            )
        }
        try await DispatchTimeInterval.milliseconds(30).sleep()
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected payload status-detail subscribe to be cancelled")
        } catch is CancellationError {
            XCTAssertEqual(queue.cancelledRequests, [
                QueueCancelRequest(app: "fal-ai/test", requestId: "request-id"),
            ])
        }
    }

    func testPayloadSubscribeWithStatusDetailsPreservesTimeoutWhenQueueCancelFails() async throws {
        let queue = StubQueue(
            statusDetails: [
                QueueStatusDetail(
                    status: .inQueue(position: 1, responseUrl: "https://example.com/result"),
                    requestId: "request-id",
                    responseUrl: "https://example.com/result"
                ),
            ],
            cancelError: FalError.invalidResultFormat
        )
        let client = StubClient(queue: queue)

        do {
            _ = try await client.subscribeWithStatusDetails(
                to: "fal-ai/test",
                input: nil as Payload?,
                pollInterval: .milliseconds(250),
                timeout: .milliseconds(30),
                onQueueStatusDetailUpdate: { _ in }
            )
            XCTFail("Expected payload status-detail subscribe to time out")
        } catch FalError.queueTimeout(let requestId) {
            XCTAssertEqual(requestId, "request-id")
            XCTAssertEqual(queue.cancelledRequests.count, 1)
        }
    }

    func testSubscribeTrailingClosureRemainsQueueStatusCallback() async throws {
        let queue = StubQueue(statuses: [
            .inQueue(position: 1, responseUrl: "https://example.com/result"),
            .completed(logs: [], responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)
        var updates: [QueueStatus] = []

        let output: SubscribeOutput = try await client.subscribe(
            to: "fal-ai/test",
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250)
        ) { updates.append($0) }

        XCTAssertEqual(output.value, "ok")
        XCTAssertEqual(updates.count, 2)
    }

    func testTypedSubscribeDoesNotSleepPastDeadline() async throws {
        let queue = StubQueue(statuses: [
            .inQueue(position: 1, responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)
        let start = Date()

        do {
            let _: SubscribeOutput = try await client.subscribe(
                to: "fal-ai/test",
                pollInterval: .milliseconds(250),
                timeout: .milliseconds(30)
            )
            XCTFail("Expected subscribe to time out")
        } catch FalError.queueTimeout(let requestId) {
            XCTAssertEqual(requestId, "request-id")
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
        }
    }

    func testTypedSubscribeCancelsQueueRequestOnTimeout() async throws {
        let queue = StubQueue(statuses: [
            .inQueue(position: 1, responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)

        do {
            let _: SubscribeOutput = try await client.subscribe(
                to: "fal-ai/test",
                pollInterval: .milliseconds(250),
                timeout: .milliseconds(30)
            )
            XCTFail("Expected subscribe to time out")
        } catch FalError.queueTimeout(let requestId) {
            XCTAssertEqual(requestId, "request-id")
            XCTAssertEqual(queue.cancelledRequests, [
                QueueCancelRequest(app: "fal-ai/test", requestId: "request-id"),
            ])
        }
    }

    func testTypedSubscribePreservesTimeoutWhenQueueCancelFails() async throws {
        let queue = StubQueue(
            statuses: [.inQueue(position: 1, responseUrl: "https://example.com/result")],
            cancelError: FalError.invalidResultFormat
        )
        let client = StubClient(queue: queue)

        do {
            let _: SubscribeOutput = try await client.subscribe(
                to: "fal-ai/test",
                pollInterval: .milliseconds(250),
                timeout: .milliseconds(30)
            )
            XCTFail("Expected subscribe to time out")
        } catch FalError.queueTimeout(let requestId) {
            XCTAssertEqual(requestId, "request-id")
            XCTAssertEqual(queue.cancelledRequests.count, 1)
        }
    }

    func testTypedSubscribeDoesNotCancelQueueRequestAfterCompletion() async throws {
        let queue = StubQueue(statuses: [
            .completed(logs: [], responseUrl: "https://example.com/result"),
        ])
        let client = StubClient(queue: queue)

        let output: SubscribeOutput = try await client.subscribe(
            to: "fal-ai/test",
            pollInterval: .milliseconds(10),
            timeout: .milliseconds(250)
        )

        XCTAssertEqual(output.value, "ok")
        XCTAssertTrue(queue.cancelledRequests.isEmpty)
    }

    func testTypedSubscribeCancelsQueueRequestOnTaskCancellation() async throws {
        let queue = StubQueue(
            statuses: [.inQueue(position: 1, responseUrl: "https://example.com/result")],
            statusDelay: .milliseconds(250)
        )
        let client = StubClient(queue: queue)

        let task = Task {
            let _: SubscribeOutput = try await client.subscribe(
                to: "fal-ai/test",
                pollInterval: .milliseconds(10),
                timeout: .seconds(5)
            )
        }
        try await DispatchTimeInterval.milliseconds(30).sleep()
        task.cancel()

        do {
            try await task.value
            XCTFail("Expected subscribe to be cancelled")
        } catch is CancellationError {
            XCTAssertEqual(queue.cancelledRequests, [
                QueueCancelRequest(app: "fal-ai/test", requestId: "request-id"),
            ])
            XCTAssertEqual(queue.cancelObservedTaskCancellationValues, [false])
        }
    }

    func testTypedSubscribeDoesNotWaitForSlowStatusPastDeadline() async throws {
        let queue = StubQueue(
            statuses: [.inQueue(position: 1, responseUrl: "https://example.com/result")],
            statusDelay: .milliseconds(250)
        )
        let client = StubClient(queue: queue)
        let start = Date()

        do {
            let _: SubscribeOutput = try await client.subscribe(
                to: "fal-ai/test",
                pollInterval: .milliseconds(10),
                timeout: .milliseconds(30)
            )
            XCTFail("Expected subscribe to time out")
        } catch FalError.queueTimeout(let requestId) {
            XCTAssertEqual(requestId, "request-id")
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
        }
    }

    func testTypedSubscribeDoesNotWaitForBlockingStatusPastDeadline() async throws {
        let queue = StubQueue(
            statuses: [.inQueue(position: 1, responseUrl: "https://example.com/result")],
            statusDelay: .milliseconds(250),
            blocksDuringStatusDelay: true
        )
        let client = StubClient(queue: queue)
        let start = Date()

        do {
            let _: SubscribeOutput = try await client.subscribe(
                to: "fal-ai/test",
                pollInterval: .milliseconds(10),
                timeout: .milliseconds(30)
            )
            XCTFail("Expected subscribe to time out")
        } catch FalError.queueTimeout(let requestId) {
            XCTAssertEqual(requestId, "request-id")
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
        }
    }
}

private struct SubscribeOutput: Codable, Equatable {
    let value: String
}

private struct SubscribeInput: Encodable {
    let value: String
}

private struct QueueCancelRequest: Equatable {
    let app: String
    let requestId: String
}

private final class StubClient: Client {
    let config = ClientConfig()
    let queue: Queue

    init(queue: Queue) {
        self.queue = queue
    }

    var realtime: Realtime {
        StubRealtime()
    }

    var storage: Storage {
        StubStorage()
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        .dict([:])
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        .dict([:])
    }
}

private final class StubQueue: Queue, @unchecked Sendable {
    let statuses: [QueueStatus]
    let statusDetails: [QueueStatusDetail]?
    let statusDelay: DispatchTimeInterval?
    let blocksDuringStatusDelay: Bool
    let cancelError: Error?
    private(set) var statusCallCount = 0
    private(set) var submitCallCount = 0
    private(set) var includeLogsValues: [Bool] = []
    private(set) var cancelledRequests: [QueueCancelRequest] = []
    private(set) var cancelObservedTaskCancellationValues: [Bool] = []
    private(set) var submittedOptionStartTimeouts: [TimeInterval?] = []
    private(set) var submittedOptionHints: [String?] = []
    private(set) var submittedOptionPriorities: [QueuePriority?] = []

    init(
        statuses: [QueueStatus],
        statusDelay: DispatchTimeInterval? = nil,
        blocksDuringStatusDelay: Bool = false,
        cancelError: Error? = nil
    ) {
        self.statuses = statuses
        self.statusDetails = nil
        self.statusDelay = statusDelay
        self.blocksDuringStatusDelay = blocksDuringStatusDelay
        self.cancelError = cancelError
    }

    init(
        statusDetails: [QueueStatusDetail],
        statusDelay: DispatchTimeInterval? = nil,
        blocksDuringStatusDelay: Bool = false,
        cancelError: Error? = nil
    ) {
        self.statuses = statusDetails.map(\.status)
        self.statusDetails = statusDetails
        self.statusDelay = statusDelay
        self.blocksDuringStatusDelay = blocksDuringStatusDelay
        self.cancelError = cancelError
    }

    var client: Client {
        fatalError("StubQueue.client is unused in these tests")
    }

    func submit(_ id: String, input: Payload?, webhookUrl: String?) async throws -> String {
        submitCallCount += 1
        return "request-id"
    }

    func submit(_ id: String, input: Payload?, webhookUrl: String?, options: RunOptions) async throws -> String {
        submitCallCount += 1
        submittedOptionStartTimeouts.append(options.startTimeout)
        submittedOptionHints.append(options.hint)
        submittedOptionPriorities.append(options.queuePriority)
        return "request-id"
    }

    func submitDetailed(_ id: String, input: Payload?, webhookUrl: String?) async throws -> QueueSubmitResult {
        QueueSubmitResult(requestId: try await submit(id, input: input, webhookUrl: webhookUrl))
    }

    func submitDetailed(_ id: String, input: Payload?, webhookUrl: String?, options: RunOptions) async throws -> QueueSubmitResult {
        QueueSubmitResult(requestId: try await submit(id, input: input, webhookUrl: webhookUrl, options: options))
    }

    func status(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatus {
        try await waitForStatusDelayIfNeeded()
        includeLogsValues.append(includeLogs)
        let index = min(statusCallCount, statuses.count - 1)
        statusCallCount += 1
        return statuses[index]
    }

    func response(_ id: String, of requestId: String) async throws -> Payload {
        [
            "value": "ok",
        ]
    }

    func response<T: Decodable>(_ id: String, of requestId: String) async throws -> T {
        let data = try JSONEncoder().encode(SubscribeOutput(value: "ok"))
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension StubQueue: QueueCancellationProviding {
    func cancel(_ id: String, of requestId: String) async throws {
        cancelObservedTaskCancellationValues.append(Task.isCancelled)
        cancelledRequests.append(QueueCancelRequest(app: id, requestId: requestId))
        if let cancelError {
            throw cancelError
        }
    }
}

extension StubQueue: QueueStatusDetailProviding {
    func statusDetail(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatusDetail {
        guard let statusDetails else {
            return QueueStatusDetail(status: try await status(id, of: requestId, includeLogs: includeLogs))
        }
        try await waitForStatusDelayIfNeeded()
        includeLogsValues.append(includeLogs)
        let index = min(statusCallCount, statusDetails.count - 1)
        statusCallCount += 1
        return statusDetails[index]
    }

    private func waitForStatusDelayIfNeeded() async throws {
        guard let statusDelay else {
            return
        }
        if blocksDuringStatusDelay {
            await withCheckedContinuation { continuation in
                Task.detached {
                    try? await statusDelay.sleep()
                    continuation.resume()
                }
            }
        } else {
            try await statusDelay.sleep()
        }
    }
}

private struct StubRealtime: Realtime {
    var client: Client {
        fatalError("StubRealtime.client is unused in these tests")
    }

    func connect(
        to app: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection {
        fatalError("StubRealtime.connect is unused in these tests")
    }
}

private struct StubStorage: Storage {
    var client: Client {
        fatalError("StubStorage.client is unused in these tests")
    }

    func upload(data: Data, ofType type: FileType) async throws -> String {
        fatalError("StubStorage.upload is unused in these tests")
    }
}
