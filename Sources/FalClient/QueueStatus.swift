/// Enum that represents the status of a request in the queue.
/// This is the base class for the different statuses: [inProgress], [inQueue] and [completed].
public enum QueueStatus: Codable, Sendable {
    case inProgress(logs: [RequestLog])
    case inQueue(position: Int, responseUrl: String)
    case completed(logs: [RequestLog], responseUrl: String)

    enum CodingKeys: String, CodingKey {
        case status
        case logs
        case queue_position
        case response_url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)

        switch status {
        case "IN_PROGRESS":
            let logs = try container.decodeIfPresent([RequestLog].self, forKey: .logs)
            self = .inProgress(logs: logs ?? [])

        case "IN_QUEUE":
            let position = try container.decode(Int.self, forKey: .queue_position)
            let responseUrl = try container.decode(String.self, forKey: .response_url)
            self = .inQueue(position: position, responseUrl: responseUrl)

        case "COMPLETED":
            let logs = try container.decodeIfPresent([RequestLog].self, forKey: .logs)
            let responseUrl = try container.decode(String.self, forKey: .response_url)
            self = .completed(logs: logs ?? [], responseUrl: responseUrl)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Invalid status value: \(status)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inProgress(logs):
            try container.encode("IN_PROGRESS", forKey: .status)
            try container.encode(logs, forKey: .logs)

        case let .inQueue(position, responseUrl):
            try container.encode("IN_QUEUE", forKey: .status)
            try container.encode(position, forKey: .queue_position)
            try container.encode(responseUrl, forKey: .response_url)

        case let .completed(logs, responseUrl):
            try container.encode("COMPLETED", forKey: .status)
            try container.encode(logs, forKey: .logs)
            try container.encode(responseUrl, forKey: .response_url)
        }
    }

    /// Whether the request is completed or not.
    public var isCompleted: Bool {
        switch self {
        case .completed:
            return true
        default:
            return false
        }
    }

    /// Logs related to the request, if any.
    public var logs: [RequestLog] {
        switch self {
        case let .inProgress(logs), let .completed(logs, _):
            return logs
        default:
            return []
        }
    }
}

public struct QueueStatusDetail: Codable, Sendable {
    public let status: QueueStatus

    public let requestId: String?
    public let statusUrl: String?
    public let cancelUrl: String?
    public let metrics: Payload?
    public let error: Payload?
    public let errorType: String?
    private let metadataResponseUrl: String?

    enum CodingKeys: String, CodingKey {
        case status
        case requestId = "request_id"
        case responseUrl = "response_url"
        case statusUrl = "status_url"
        case cancelUrl = "cancel_url"
        case metrics
        case error
        case errorType = "error_type"
    }

    public init(
        status: QueueStatus,
        requestId: String? = nil,
        responseUrl: String? = nil,
        statusUrl: String? = nil,
        cancelUrl: String? = nil,
        metrics: Payload? = nil,
        error: Payload? = nil,
        errorType: String? = nil
    ) {
        self.status = status
        self.requestId = requestId
        self.metadataResponseUrl = responseUrl
        self.statusUrl = statusUrl
        self.cancelUrl = cancelUrl
        self.metrics = metrics
        self.error = error
        self.errorType = errorType
    }

    public init(from decoder: Decoder) throws {
        status = try QueueStatus(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        metadataResponseUrl = try container.decodeIfPresent(String.self, forKey: .responseUrl)
        statusUrl = try container.decodeIfPresent(String.self, forKey: .statusUrl)
        cancelUrl = try container.decodeIfPresent(String.self, forKey: .cancelUrl)
        metrics = try container.decodeIfPresent(Payload.self, forKey: .metrics)
        error = try container.decodeIfPresent(Payload.self, forKey: .error)
        errorType = try container.decodeIfPresent(String.self, forKey: .errorType)
    }

    public func encode(to encoder: Encoder) throws {
        try status.encode(to: encoder)

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(requestId, forKey: .requestId)
        try container.encodeIfPresent(responseUrl, forKey: .responseUrl)
        try container.encodeIfPresent(statusUrl, forKey: .statusUrl)
        try container.encodeIfPresent(cancelUrl, forKey: .cancelUrl)
        try container.encodeIfPresent(metrics, forKey: .metrics)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(errorType, forKey: .errorType)
    }

    /// Whether the request is completed or not.
    public var isCompleted: Bool { status.isCompleted }

    /// Logs related to the request, if any.
    public var logs: [RequestLog] { status.logs }

    /// The response URL, if available for this queue status.
    public var responseUrl: String? {
        switch status {
        case let .inQueue(_, responseUrl), let .completed(_, responseUrl):
            return responseUrl
        case .inProgress:
            return metadataResponseUrl
        }
    }
}

public struct RequestLog: Codable, Sendable {
    public let message: String
    public let timestamp: String
    public let labels: Labels
    public var level: LogLevel { labels.level }

    enum CodingKeys: String, CodingKey {
        case message
        case timestamp
        case labels
        case level
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        timestamp = try container.decode(String.self, forKey: .timestamp)

        if let labels = try container.decodeIfPresent(Labels.self, forKey: .labels) {
            self.labels = labels
        } else if let level = LogLevel.decodeIfPresent(from: container, forKey: .level) {
            self.labels = Labels(level: level)
        } else {
            labels = Labels(level: .info)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(labels, forKey: .labels)
    }

    public struct Labels: Codable, Sendable {
        public let level: LogLevel

        enum CodingKeys: String, CodingKey {
            case level
        }

        public init(level: LogLevel = .info) {
            self.level = level
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            level = LogLevel.decodeIfPresent(from: container, forKey: .level) ?? .info
        }
    }

    public enum LogLevel: String, Codable, Sendable {
        case stderr = "STDERR"
        case stdout = "STDOUT"
        case error = "ERROR"
        case info = "INFO"
        case warn = "WARN"
        case debug = "DEBUG"
    }
}

extension RequestLog.LogLevel {
    static func decodeIfPresent<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> RequestLog.LogLevel? {
        guard let value = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return RequestLog.LogLevel(rawValue: value) ?? .info
    }
}
