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
    let deadline = QueuePollingDeadline(timeout: timeout)
    var isCompleted = false

    do {
        while deadline.hasRemainingTime {
            try Task.checkCancellation()

            let update: QueueStatus
            do {
                update = try await withQueuePollTimeout(milliseconds: deadline.remainingMilliseconds) {
                    try await queue.status(app, of: requestId, includeLogs: includeLogs)
                }
            } catch FalError.queueTimeout {
                throw FalError.queueTimeout(requestId: requestId)
            }
            onQueueUpdate?(update)

            isCompleted = update.isCompleted
            if isCompleted {
                break
            }

            try await pollInterval.sleep(upTo: deadline.remainingMilliseconds)
        }

        if !isCompleted {
            throw FalError.queueTimeout(requestId: requestId)
        }
    } catch {
        if shouldCancelQueueRequest(after: error) {
            await cancelQueueRequestIgnoringFailure(queue: queue, app: app, requestId: requestId)
        }
        throw error
    }
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
    let deadline = QueuePollingDeadline(timeout: timeout)
    var isCompleted = false

    do {
        while deadline.hasRemainingTime {
            try Task.checkCancellation()

            let update: QueueStatusDetail
            do {
                update = try await withQueuePollTimeout(milliseconds: deadline.remainingMilliseconds) {
                    try await queue.statusDetail(app, of: requestId, includeLogs: includeLogs)
                }
            } catch FalError.queueTimeout {
                throw FalError.queueTimeout(requestId: requestId)
            }
            onQueueStatusDetailUpdate(update)

            isCompleted = update.status.isCompleted
            if isCompleted {
                break
            }

            try await pollInterval.sleep(upTo: deadline.remainingMilliseconds)
        }

        if !isCompleted {
            throw FalError.queueTimeout(requestId: requestId)
        }
    } catch {
        if shouldCancelQueueRequest(after: error) {
            await cancelQueueRequestIgnoringFailure(queue: queue, app: app, requestId: requestId)
        }
        throw error
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
    let deadline = QueuePollingDeadline(timeout: timeout)
    var latestUpdate: QueueStatusDetail?

    while deadline.hasRemainingTime {
        try Task.checkCancellation()

        let update: QueueStatusDetail
        do {
            update = try await withQueuePollTimeout(milliseconds: deadline.remainingMilliseconds) {
                try await queue.statusDetail(app, of: requestId, includeLogs: includeLogs)
            }
        } catch FalError.queueTimeout {
            throw FalError.queueTimeout(requestId: requestId)
        }

        latestUpdate = update
        onQueueStatusDetailUpdate(update)

        if update.status.isCompleted {
            return update
        }

        try await pollInterval.sleep(upTo: deadline.remainingMilliseconds)
    }

    if let latestUpdate, latestUpdate.status.isCompleted {
        return latestUpdate
    }
    throw FalError.queueTimeout(requestId: requestId)
}
