import Dispatch
import Foundation

extension DispatchTimeInterval {
    public static func minutes(_ value: Int) -> DispatchTimeInterval {
        .seconds(value.saturatingMultiply(by: 60))
    }

    var milliseconds: Int {
        switch self {
        case let .milliseconds(value):
            return value
        case let .seconds(value):
            return value.saturatingMultiply(by: 1000)
        case let .microseconds(value):
            return value / 1000
        case let .nanoseconds(value):
            return value / 1_000_000
        case .never:
            return Int.max
        @unknown default:
            return 0
        }
    }

    func sleep() async throws {
        guard milliseconds > 0 else {
            return
        }

        if #available(iOS 16, macOS 13, macCatalyst 16, tvOS 16, watchOS 9, *) {
            switch self {
            case let .seconds(value):
                try await Task.sleep(for: .seconds(value))
            case let .milliseconds(value):
                try await Task.sleep(for: .milliseconds(value))
            case let .microseconds(value):
                try await Task.sleep(for: .microseconds(value))
            case let .nanoseconds(value):
                try await Task.sleep(for: .nanoseconds(value))
            case .never:
                try await Task.sleep(for: .seconds(Int.max / 1000))
            @unknown default:
                return
            }
        } else {
            if self == .never {
                try await Task.sleep(nanoseconds: UInt64.max)
                return
            }
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
        }
    }

    func sleep(upTo millisecondsLimit: Int) async throws {
        guard millisecondsLimit > 0 else {
            return
        }
        let sleepMilliseconds = min(max(milliseconds, 1), millisecondsLimit)
        try await DispatchTimeInterval.milliseconds(sleepMilliseconds).sleep()
    }
}

private extension Int {
    func saturatingMultiply(by multiplier: Int) -> Int {
        let result = multipliedReportingOverflow(by: multiplier)
        if result.overflow {
            return (self >= 0) == (multiplier >= 0) ? Int.max : Int.min
        }
        return result.partialValue
    }
}

struct QueuePollingDeadline {
    private let deadlineNanoseconds: UInt64

    init(timeout: DispatchTimeInterval) {
        let now = DispatchTime.now().uptimeNanoseconds
        let timeoutMilliseconds = max(0, timeout.milliseconds)
        if timeoutMilliseconds == Int.max {
            deadlineNanoseconds = UInt64.max
        } else {
            let timeoutNanoseconds = UInt64(timeoutMilliseconds).saturatingMultiply(by: 1_000_000)
            deadlineNanoseconds = now.saturatingAdd(timeoutNanoseconds)
        }
    }

    var hasRemainingTime: Bool {
        remainingNanoseconds > 0
    }

    var remainingMilliseconds: Int {
        let nanoseconds = remainingNanoseconds
        guard nanoseconds > 0 else {
            return 0
        }
        let milliseconds = (nanoseconds + 999_999) / 1_000_000
        return milliseconds > UInt64(Int.max) ? Int.max : Int(milliseconds)
    }

    private var remainingNanoseconds: UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        return deadlineNanoseconds > now ? deadlineNanoseconds - now : 0
    }
}

func withQueuePollTimeout<T: Sendable>(
    milliseconds: Int,
    operation: @escaping () async throws -> T
) async throws -> T {
    guard milliseconds > 0 else {
        throw FalError.queueTimeout()
    }

    let state = QueuePollTimeoutState<T>()
    let operationBox = QueuePollTimeoutOperation(operation)
    let operationTask = Task {
        do {
            let value = try await operationBox.run()
            state.resume(with: .success(value))
        } catch {
            state.resume(with: .failure(error))
        }
    }
    let timeoutTask = Task {
        do {
            try await DispatchTimeInterval.milliseconds(milliseconds).sleep()
            state.resume(with: .failure(FalError.queueTimeout()))
        } catch {
            state.resume(with: .failure(error))
        }
    }

    do {
        return try await withTaskCancellationHandler {
            let result = try await state.wait()
            operationTask.cancel()
            timeoutTask.cancel()
            return result
        } onCancel: {
            operationTask.cancel()
            timeoutTask.cancel()
            state.resume(with: .failure(CancellationError()))
        }
    } catch {
        operationTask.cancel()
        timeoutTask.cancel()
        throw error
    }
}

private final class QueuePollTimeoutOperation<T: Sendable>: @unchecked Sendable {
    private let operation: () async throws -> T

    init(_ operation: @escaping () async throws -> T) {
        self.operation = operation
    }

    func run() async throws -> T {
        try await operation()
    }
}

private final class QueuePollTimeoutState<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?

    func wait() async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuationToResume = self.continuation
        self.continuation = nil
        lock.unlock()
        continuationToResume?.resume(with: result)
    }
}

private extension UInt64 {
    func saturatingAdd(_ value: UInt64) -> UInt64 {
        let result = addingReportingOverflow(value)
        return result.overflow ? UInt64.max : result.partialValue
    }

    func saturatingMultiply(by multiplier: UInt64) -> UInt64 {
        let result = multipliedReportingOverflow(by: multiplier)
        return result.overflow ? UInt64.max : result.partialValue
    }
}
