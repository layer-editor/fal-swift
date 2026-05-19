import Dispatch
import Foundation

func cancelQueueRequestIgnoringFailure(queue: Queue, app: String, requestId: String) async {
    let job = QueueCancellationJob(queue: queue, app: app, requestId: requestId)
    await withCheckedContinuation { continuation in
        Task {
            await job.cancelIgnoringFailure()
            continuation.resume()
        }
    }
}

private final class QueueCancellationJob: @unchecked Sendable {
    private let queue: Queue
    private let app: String
    private let requestId: String

    init(queue: Queue, app: String, requestId: String) {
        self.queue = queue
        self.app = app
        self.requestId = requestId
    }

    func cancelIgnoringFailure() async {
        do {
            try await queue.cancel(app, of: requestId)
        } catch {}
    }
}

func shouldCancelQueueRequest(after error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if case FalError.queueTimeout = error {
        return true
    }
    return false
}

func pollQueueUntilCompleted(
    queue: Queue,
    app: String,
    requestId: String,
    pollInterval: DispatchTimeInterval,
    timeout: DispatchTimeInterval,
    includeLogs: Bool,
    onQueueUpdate: OnQueueUpdate?
) async throws {
    _ = try await pollQueueUntilCompleted(
        queue: queue,
        app: app,
        requestId: requestId,
        pollInterval: pollInterval,
        timeout: timeout,
        cancelOnFailure: true,
        fetchUpdate: {
            try await queue.status(app, of: requestId, includeLogs: includeLogs)
        },
        isCompleted: \.isCompleted,
        onUpdate: { onQueueUpdate?($0) }
    )
}

func pollQueueUntilCompletedWithStatusDetails(
    queue: Queue,
    app: String,
    requestId: String,
    pollInterval: DispatchTimeInterval,
    timeout: DispatchTimeInterval,
    includeLogs: Bool,
    onQueueStatusDetailUpdate: @escaping OnQueueStatusDetailUpdate
) async throws {
    _ = try await pollQueueUntilCompleted(
        queue: queue,
        app: app,
        requestId: requestId,
        pollInterval: pollInterval,
        timeout: timeout,
        cancelOnFailure: true,
        fetchUpdate: {
            try await queue.statusDetail(app, of: requestId, includeLogs: includeLogs)
        },
        isCompleted: \.status.isCompleted,
        onUpdate: onQueueStatusDetailUpdate
    )
}

func queueResponseAfterPolling<Output: Decodable>(
    queue: Queue,
    app: String,
    requestId: String,
    pollInterval: DispatchTimeInterval,
    timeout: DispatchTimeInterval,
    includeLogs: Bool,
    onQueueUpdate: OnQueueUpdate?
) async throws -> Output {
    try await pollQueueUntilCompleted(
        queue: queue,
        app: app,
        requestId: requestId,
        pollInterval: pollInterval,
        timeout: timeout,
        includeLogs: includeLogs,
        onQueueUpdate: onQueueUpdate
    )
    return try await queue.response(app, of: requestId)
}

func queueResponseAfterStatusDetailPolling<Output: Decodable>(
    queue: Queue,
    app: String,
    requestId: String,
    pollInterval: DispatchTimeInterval,
    timeout: DispatchTimeInterval,
    includeLogs: Bool,
    onQueueStatusDetailUpdate: @escaping OnQueueStatusDetailUpdate
) async throws -> Output {
    try await pollQueueUntilCompletedWithStatusDetails(
        queue: queue,
        app: app,
        requestId: requestId,
        pollInterval: pollInterval,
        timeout: timeout,
        includeLogs: includeLogs,
        onQueueStatusDetailUpdate: onQueueStatusDetailUpdate
    )
    return try await queue.response(app, of: requestId)
}

func decodeQueueStatusDetailStream(
    _ events: AsyncThrowingStream<Data, Error>
) -> AsyncThrowingStream<QueueStatusDetail, Error> {
    let decoder = QueueStatusDetailStreamDecoder(events: events)
    return AsyncThrowingStream(unfolding: {
        try await decoder.nextUpdate()
    })
}

private final class QueueStatusDetailStreamDecoder: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator
    private let decoder = JSONDecoder()
    private var isFinished = false

    init(events: AsyncThrowingStream<Data, Error>) {
        self.iterator = events.makeAsyncIterator()
    }

    func nextUpdate() async throws -> QueueStatusDetail? {
        guard !isFinished else {
            return nil
        }
        guard let event = try await nextEvent() else {
            return nil
        }

        let update = try decoder.decode(QueueStatusDetail.self, from: event)
        if update.isCompleted {
            isFinished = true
        }
        return update
    }

    private func nextEvent() async throws -> Data? {
        var iterator = self.iterator
        let event = try await iterator.next()
        self.iterator = iterator
        return event
    }
}

func pollQueueStatusUntilCompleted(
    queue: Queue,
    app: String,
    requestId: String,
    pollInterval: DispatchTimeInterval,
    timeout: DispatchTimeInterval,
    includeLogs: Bool,
    onQueueStatusDetailUpdate: @escaping OnQueueStatusDetailUpdate
) async throws -> QueueStatusDetail {
    try await pollQueueUntilCompleted(
        queue: queue,
        app: app,
        requestId: requestId,
        pollInterval: pollInterval,
        timeout: timeout,
        cancelOnFailure: false,
        fetchUpdate: {
            try await queue.statusDetail(app, of: requestId, includeLogs: includeLogs)
        },
        isCompleted: \.status.isCompleted,
        onUpdate: onQueueStatusDetailUpdate
    )
}

private func pollQueueUntilCompleted<Update: Sendable>(
    queue: Queue,
    app: String,
    requestId: String,
    pollInterval: DispatchTimeInterval,
    timeout: DispatchTimeInterval,
    cancelOnFailure: Bool,
    fetchUpdate: @escaping () async throws -> Update,
    isCompleted: (Update) -> Bool,
    onUpdate: (Update) -> Void
) async throws -> Update {
    let deadline = QueuePollingDeadline(timeout: timeout)

    do {
        while deadline.hasRemainingTime {
            try Task.checkCancellation()

            let update: Update
            do {
                update = try await withQueuePollTimeout(milliseconds: deadline.remainingMilliseconds) {
                    try await fetchUpdate()
                }
            } catch FalError.queueTimeout {
                throw FalError.queueTimeout(requestId: requestId)
            }

            onUpdate(update)
            if isCompleted(update) {
                return update
            }

            try await pollInterval.sleep(upTo: deadline.remainingMilliseconds)
        }

        throw FalError.queueTimeout(requestId: requestId)
    } catch {
        if cancelOnFailure, shouldCancelQueueRequest(after: error) {
            await cancelQueueRequestIgnoringFailure(queue: queue, app: app, requestId: requestId)
        }
        throw error
    }
}
