//
//  RetryPolicy.swift
//  FalClient
//
//  Created by Chris Zelazo on 5/18/26.
//

import Foundation

struct RetryPolicy: Sendable {
    static let none = RetryPolicy(maxAttempts: 1)
    static let transientRequest = RetryPolicy(maxAttempts: 3, initialDelayMilliseconds: 50, maximumDelayMilliseconds: 500)

    let maxAttempts: Int
    let initialDelayMilliseconds: Int
    let maximumDelayMilliseconds: Int

    init(maxAttempts: Int, initialDelayMilliseconds: Int = 0, maximumDelayMilliseconds: Int = 0) {
        self.maxAttempts = max(1, maxAttempts)
        self.initialDelayMilliseconds = max(0, initialDelayMilliseconds)
        self.maximumDelayMilliseconds = max(0, maximumDelayMilliseconds)
    }

    func shouldRetry(_ error: Error, afterAttempt attempt: Int) -> Bool {
        guard attempt < maxAttempts else {
            return false
        }
        if error is CancellationError {
            return false
        }
        if let urlError = error as? URLError {
            return urlError.code.isTransientRetryable
        }
        guard case let FalError.httpError(httpError) = error else {
            return false
        }
        return httpError.isTransientRetryable
    }

    func delayMilliseconds(afterAttempt attempt: Int, error: Error) -> Int {
        if case let FalError.httpError(httpError) = error,
           let retryAfterMilliseconds = httpError.retryAfterMilliseconds
        {
            return boundedDelayMilliseconds(retryAfterMilliseconds)
        }

        guard initialDelayMilliseconds > 0 else {
            return 0
        }
        let multiplier = 1 << min(max(0, attempt - 1), 10)
        return boundedDelayMilliseconds(initialDelayMilliseconds.saturatingMultiply(by: multiplier))
    }

    private func boundedDelayMilliseconds(_ milliseconds: Int) -> Int {
        guard maximumDelayMilliseconds > 0 else {
            return max(0, milliseconds)
        }
        return min(max(0, milliseconds), maximumDelayMilliseconds)
    }
}

func retrying<Output>(
    policy: RetryPolicy,
    operation: () async throws -> Output
) async throws -> Output {
    var attempt = 1
    while true {
        try Task.checkCancellation()
        do {
            return try await operation()
        } catch {
            guard policy.shouldRetry(error, afterAttempt: attempt) else {
                throw error
            }
            let delayMilliseconds = policy.delayMilliseconds(afterAttempt: attempt, error: error)
            if delayMilliseconds > 0 {
                try await DispatchTimeInterval.milliseconds(delayMilliseconds).sleep()
            }
            attempt += 1
        }
    }
}

private extension URLError.Code {
    var isTransientRetryable: Bool {
        switch self {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .badServerResponse:
            return true
        case .cancelled:
            return false
        default:
            return false
        }
    }
}

private extension FalHTTPError {
    var isTransientRetryable: Bool {
        guard !isUserTimeout else {
            return false
        }
        switch statusCode {
        case 408, 425, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }

    var retryAfterMilliseconds: Int? {
        guard let value = headers["retry-after"],
              let seconds = TimeInterval(value),
              seconds.isFinite,
              seconds >= 0
        else {
            return nil
        }
        let milliseconds = seconds * 1000
        guard milliseconds <= TimeInterval(Int.max) else {
            return Int.max
        }
        return Int(milliseconds.rounded(.up))
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
