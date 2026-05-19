import Foundation

/// This establishes the contract of the client with the queue API.
public protocol Queue {
    var client: Client { get }

    /// Submits a request to the given [id]. This method uses the [queue] API to initiate
    /// the request. Next you need to rely on [status] and [result] to poll for the result.
    func submit(_ id: String, input: Payload?, webhookUrl: String?) async throws -> String

    /// Submits a request with platform request options.
    func submit(_ id: String, input: Payload?, webhookUrl: String?, options: RunOptions) async throws -> String

    /// Submits a request and returns queue metadata supplied by fal.
    func submitDetailed(_ id: String, input: Payload?, webhookUrl: String?) async throws -> QueueSubmitResult

    /// Submits a request with platform request options and returns queue metadata supplied by fal.
    func submitDetailed(_ id: String, input: Payload?, webhookUrl: String?, options: RunOptions) async throws -> QueueSubmitResult

    /// Checks the queue for the status of the request with the given [requestId].
    /// See [QueueStatus] for the different statuses.
    func status(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatus

    /// Retrieves the result of the request with the given [requestId] once
    /// the queue status is [QueueStatus.completed].
    func response(_ id: String, of requestId: String) async throws -> Payload

    /// Retrieves the result of the request with the given [requestId] once
    /// the queue status is [QueueStatus.completed]. This method is type-safe
    /// based on the [Decodable] protocol.
    func response<T: Decodable>(_ id: String, of requestId: String) async throws -> T
}

public protocol QueueStatusDetailProviding: Queue {
    /// Checks the queue for a detailed status payload including Fal request metadata.
    func statusDetail(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatusDetail
}

public protocol QueueCancellationProviding: Queue {
    /// Requests cancellation for a queued or running request.
    func cancel(_ id: String, of requestId: String) async throws
}

public protocol QueueStatusStreamingProviding: Queue {
    /// Streams detailed status updates for a queued request using Fal's status SSE endpoint.
    func streamStatus(_ id: String, of requestId: String, includeLogs: Bool) async throws -> AsyncThrowingStream<QueueStatusDetail, Error>
}

public extension Queue {
    func submit(_ id: String, input: Payload? = nil, webhookUrl: String? = nil) async throws -> String {
        try await submit(id, input: input, webhookUrl: webhookUrl)
    }

    func submit(_ id: String, input: Payload? = nil, webhookUrl: String? = nil, options: RunOptions) async throws -> String {
        let queryParams: [String: Any] = webhookUrl != nil ? ["fal_webhook": webhookUrl ?? ""] : [:]
        let result: QueueSubmitResult = try await runOnQueue(id, input: input, queryParams: queryParams, options: options)
        return result.requestId
    }

    func submitDetailed(_ id: String, input: Payload? = nil, webhookUrl: String? = nil) async throws -> QueueSubmitResult {
        let requestId = try await submit(id, input: input, webhookUrl: webhookUrl)
        return QueueSubmitResult(requestId: requestId)
    }

    func submitDetailed(_ id: String, input: Payload? = nil, webhookUrl: String? = nil, options: RunOptions) async throws -> QueueSubmitResult {
        let queryParams: [String: Any] = webhookUrl != nil ? ["fal_webhook": webhookUrl ?? ""] : [:]
        return try await runOnQueue(id, input: input, queryParams: queryParams, options: options)
    }

    func status(_ id: String, of requestId: String, includeLogs: Bool = false) async throws -> QueueStatus {
        try await status(id, of: requestId, includeLogs: includeLogs)
    }

    func cancel(_ id: String, of requestId: String) async throws {
        guard let provider = self as? QueueCancellationProviding else {
            throw FalError.unsupportedOperation(
                message: "This Queue implementation does not support cancelling queued requests."
            )
        }
        try await provider.cancel(id, of: requestId)
    }

    func statusDetail(_ id: String, of requestId: String, includeLogs: Bool = false) async throws -> QueueStatusDetail {
        if let provider = self as? QueueStatusDetailProviding {
            return try await provider.statusDetail(id, of: requestId, includeLogs: includeLogs)
        }

        let status = try await status(id, of: requestId, includeLogs: includeLogs)
        return QueueStatusDetail(status: status)
    }

    /// Observes an existing queued request until it completes and returns its final status detail.
    ///
    /// Unlike high-level `subscribe` calls that submit a new request, this method does not cancel the
    /// server-side request if the observer times out or its Swift task is cancelled.
    func subscribeToStatus(
        _ id: String,
        of requestId: String,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onQueueStatusDetailUpdate: @escaping OnQueueStatusDetailUpdate = { _ in }
    ) async throws -> QueueStatusDetail {
        try await pollQueueStatusUntilCompleted(
            queue: self,
            app: id,
            requestId: requestId,
            pollInterval: pollInterval,
            timeout: timeout,
            includeLogs: includeLogs,
            onQueueStatusDetailUpdate: onQueueStatusDetailUpdate
        )
    }

    /// Streams detailed status updates for an existing queued request until the stream ends or completes.
    func streamStatus(
        _ id: String,
        of requestId: String,
        includeLogs: Bool = false
    ) async throws -> AsyncThrowingStream<QueueStatusDetail, Error> {
        guard let provider = self as? QueueStatusStreamingProviding else {
            throw FalError.unsupportedOperation(
                message: "This Queue implementation does not support streaming queued request status."
            )
        }
        return try await provider.streamStatus(id, of: requestId, includeLogs: includeLogs)
    }
}

extension Queue {
    func runOnQueue<Output: Decodable>(_ app: String, input: Payload?, queryParams params: [String: Any] = [:], options: RunOptions = .withMethod(.post)) async throws -> Output {
        var requestInput = input
        if let input, input.hasBinaryData {
            guard options.httpMethod != .get else {
                throw FalError.unsupportedInput(
                    message: "Payload.data cannot be sent with GET queue requests because binary values would be serialized into the URL. Use a POST request so binary values can be uploaded before request encoding."
                )
            }
            requestInput = try await client.storage.autoUpload(input: input)
        }
        var queryParams: [String: Any] = [:]
        if let inputDict = requestInput?.asDictionary, options.httpMethod == .get {
            queryParams.merge(inputDict) { _, new in new }
        }
        if !params.isEmpty {
            queryParams.merge(params) { _, new in new }
        }

        let url = buildUrl(fromId: app, path: options.path, subdomain: "queue")
        let data = try await client.sendRequest(to: url, input: requestInput?.json(), queryParams: queryParams, options: options)

        let decoder = JSONDecoder()
        return try decoder.decode(Output.self, from: data)
    }
}

public struct QueueClient: QueueStatusDetailProviding, QueueCancellationProviding, QueueStatusStreamingProviding {
    public let client: Client

    public func submit(_ id: String, input: Payload?, webhookUrl: String?) async throws -> String {
        try await submitDetailed(id, input: input, webhookUrl: webhookUrl).requestId
    }

    public func submit(_ id: String, input: Payload?, webhookUrl: String?, options: RunOptions) async throws -> String {
        try await submitDetailed(id, input: input, webhookUrl: webhookUrl, options: options).requestId
    }

    public func submitDetailed(_ id: String, input: Payload?, webhookUrl: String?) async throws -> QueueSubmitResult {
        try await submitDetailed(id, input: input, webhookUrl: webhookUrl, options: .withMethod(.post))
    }

    public func submitDetailed(_ id: String, input: Payload?, webhookUrl: String?, options: RunOptions) async throws -> QueueSubmitResult {
        let queryParams: [String: Any] = webhookUrl != nil ? ["fal_webhook": webhookUrl ?? ""] : [:]
        return try await runOnQueue(id, input: input, queryParams: queryParams, options: options)
    }

    public func status(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatus {
        try await statusDetail(id, of: requestId, includeLogs: includeLogs).status
    }

    public func statusDetail(_ id: String, of requestId: String, includeLogs: Bool) async throws -> QueueStatusDetail {
        let result: QueueStatusDetail = try await runOnQueue(
            AppId.parse(id: id).queueBasePath,
            input: nil,
            queryParams: [
                "logs": includeLogs ? 1 : 0,
            ],
            options: .route(queueRequestPath(for: requestId, suffix: "/status"), withMethod: .get)
        )
        return result
    }

    public func streamStatus(_ id: String, of requestId: String, includeLogs: Bool) async throws -> AsyncThrowingStream<QueueStatusDetail, Error> {
        let url = buildUrl(
            fromId: try AppId.parse(id: id).queueBasePath,
            path: queueRequestPath(for: requestId, suffix: "/status/stream"),
            subdomain: "queue"
        )
        let events = try await client.sendServerSentEvents(
            to: url,
            queryParams: includeLogs ? ["logs": 1] : [:],
            options: .withMethod(.get)
        )
        return decodeQueueStatusDetailStream(events)
    }

    public func cancel(_ id: String, of requestId: String) async throws {
        let _: Payload = try await runOnQueue(
            AppId.parse(id: id).queueBasePath,
            input: nil as Payload?,
            options: .route(queueRequestPath(for: requestId, suffix: "/cancel"), withMethod: .put)
        )
    }

    public func response(_ id: String, of requestId: String) async throws -> Payload {
        return try await runOnQueue(
            AppId.parse(id: id).queueBasePath,
            input: nil as Payload?,
            options: .route(queueRequestPath(for: requestId), withMethod: .get)
        )
    }
}
