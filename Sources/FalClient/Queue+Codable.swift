import Foundation

public struct QueueSubmitResult: Decodable, Equatable, Sendable {
    public let requestId: String
    public let responseUrl: String?
    public let statusUrl: String?
    public let cancelUrl: String?
    public let queuePosition: Int?

    public init(
        requestId: String,
        responseUrl: String? = nil,
        statusUrl: String? = nil,
        cancelUrl: String? = nil,
        queuePosition: Int? = nil
    ) {
        self.requestId = requestId
        self.responseUrl = responseUrl
        self.statusUrl = statusUrl
        self.cancelUrl = cancelUrl
        self.queuePosition = queuePosition
    }

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case responseUrl = "response_url"
        case statusUrl = "status_url"
        case cancelUrl = "cancel_url"
        case queuePosition = "queue_position"
    }
}

public extension Queue {
    func submit(_ id: String, input: (some Encodable) = EmptyInput.empty, webhookUrl: String? = nil) async throws -> String {
        let inputPayload = try typedQueueInputPayload(from: input)
        return try await submit(id, input: inputPayload, webhookUrl: webhookUrl)
    }

    func submitDetailed(
        _ id: String,
        input: (some Encodable) = EmptyInput.empty,
        webhookUrl: String? = nil
    ) async throws -> QueueSubmitResult {
        let inputPayload = try typedQueueInputPayload(from: input)
        return try await submitDetailed(id, input: inputPayload, webhookUrl: webhookUrl)
    }

    func submit(
        _ id: String,
        input: (some Encodable) = EmptyInput.empty,
        webhookUrl: String? = nil,
        options: RunOptions
    ) async throws -> String {
        let inputPayload = try typedQueueInputPayload(from: input)
        return try await submit(id, input: inputPayload, webhookUrl: webhookUrl, options: options)
    }

    func submitDetailed(
        _ id: String,
        input: (some Encodable) = EmptyInput.empty,
        webhookUrl: String? = nil,
        options: RunOptions
    ) async throws -> QueueSubmitResult {
        let inputPayload = try typedQueueInputPayload(from: input)
        return try await submitDetailed(id, input: inputPayload, webhookUrl: webhookUrl, options: options)
    }

    func response<Output: Decodable>(_ id: String, of requestId: String) async throws -> Output {
        return try await runOnQueue(
            AppId.parse(id: id).queueBasePath,
            input: nil as Payload?,
            options: .route(queueRequestPath(for: requestId), withMethod: .get),
            retryPolicy: .transientRequest
        )
    }
}

private func typedQueueInputPayload(from input: some Encodable) throws -> Payload? {
    guard !(input is EmptyInput) else {
        return nil
    }
    let data = try encodeTypedInputRejectingBinaryData(
        input,
        message: "Typed Encodable values containing Data are not supported for automatic upload yet. Use Payload.data so binary values can be uploaded before request encoding."
    )
    return try Payload.create(fromJSON: data)
}
