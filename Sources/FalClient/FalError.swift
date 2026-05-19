import Foundation

/// Errors thrown by the Fal client.
public enum FalError: Error, Equatable, LocalizedError, CustomStringConvertible {
    /// HTTP error details associated with a non-success Fal response.
    public typealias HTTPError = FalHTTPError

    /// The API returned a non-success HTTP response.
    case httpError(FalHTTPError)

    /// The response could not be decoded into the expected result shape.
    case invalidResultFormat

    /// A URL string could not be parsed or failed client-side safety checks.
    case invalidUrl(url: String)

    /// A queue-backed request did not complete before the local timeout.
    case queueTimeout(requestId: String? = nil)

    /// An endpoint identifier could not be parsed.
    case invalidAppId(id: String)

    /// The input cannot be represented safely by this client API.
    case unsupportedInput(message: String)

    /// The requested operation is not supported by the active client implementation.
    case unsupportedOperation(message: String)

    public var errorDescription: String? {
        switch self {
        case let .httpError(error):
            return error.message
        case .invalidResultFormat:
            return "The response format was invalid."
        case let .invalidUrl(url):
            return "Invalid URL: \(url.redactedURLForDescription)"
        case .queueTimeout:
            return "The queued request timed out."
        case let .invalidAppId(id):
            return "Invalid app identifier: \(id)"
        case let .unsupportedInput(message):
            return message
        case let .unsupportedOperation(message):
            return message
        }
    }

    public var description: String {
        errorDescription ?? String(describing: self)
    }

    /// The HTTP error details when this error wraps a non-success API response.
    public var httpResponseError: FalHTTPError? {
        guard case let .httpError(error) = self else {
            return nil
        }
        return error
    }

    /// The Fal request identifier associated with the error, when available.
    public var requestId: String? {
        switch self {
        case let .httpError(error):
            return error.requestId
        case let .queueTimeout(requestId):
            return requestId
        default:
            return nil
        }
    }
}

/// Details for a non-success Fal HTTP response.
public struct FalHTTPError: Error, Equatable, LocalizedError, CustomStringConvertible {
    /// The HTTP status code returned by Fal.
    public let statusCode: Int

    /// Alias for `statusCode`, matching peer client naming.
    public var status: Int { statusCode }

    /// A human-readable error message.
    public let message: String

    /// The parsed response payload, when the body was valid JSON.
    public let payload: Payload?

    /// The Fal request identifier from the response headers, when present.
    public let requestId: String?

    /// The machine-readable Fal error type, when present.
    public let errorType: String?

    /// The Fal request timeout category, when present.
    public let requestTimeoutType: String?

    /// Alias for `requestTimeoutType`, matching peer client naming.
    public var timeoutType: String? { requestTimeoutType }

    /// Response headers, normalized to lowercase names for case-insensitive lookup.
    public let headers: [String: String]

    /// Alias for `headers`, matching peer client naming.
    public var responseHeaders: [String: String] { headers }

    public init(
        statusCode: Int,
        message: String,
        payload: Payload? = nil,
        requestId: String? = nil,
        errorType: String? = nil,
        requestTimeoutType: String? = nil,
        headers: [String: String] = [:]
    ) {
        self.statusCode = statusCode
        self.message = message
        self.payload = payload
        self.requestId = requestId
        self.errorType = errorType
        self.requestTimeoutType = requestTimeoutType
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
    }

    public var errorDescription: String? {
        message
    }

    public var description: String {
        "\(statusCode): \(message)"
    }

    /// Whether Fal classified this response as a user-request timeout.
    public var isUserTimeout: Bool {
        requestTimeoutType == "user"
    }
}

private extension String {
    var redactedURLForDescription: String {
        guard var components = URLComponents(string: self) else {
            return self
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? self
    }
}
