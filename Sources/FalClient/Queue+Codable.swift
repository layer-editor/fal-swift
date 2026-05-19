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
        // Convert some Encodable to Payload, so the underlying call can inspect the input more freely
        var inputPayload: Payload? = nil
        if !(input is EmptyInput) {
            let data = try encodeTypedInputRejectingBinaryData(
                input,
                message: "Typed Encodable values containing Data are not supported for automatic upload yet. Use Payload.data so binary values can be uploaded before request encoding."
            )
            inputPayload = try Payload.create(fromJSON: data)
        }
        return try await submit(id, input: inputPayload, webhookUrl: webhookUrl)
    }

    func submitDetailed(
        _ id: String,
        input: (some Encodable) = EmptyInput.empty,
        webhookUrl: String? = nil
    ) async throws -> QueueSubmitResult {
        var inputPayload: Payload? = nil
        if !(input is EmptyInput) {
            let data = try encodeTypedInputRejectingBinaryData(
                input,
                message: "Typed Encodable values containing Data are not supported for automatic upload yet. Use Payload.data so binary values can be uploaded before request encoding."
            )
            inputPayload = try Payload.create(fromJSON: data)
        }
        return try await submitDetailed(id, input: inputPayload, webhookUrl: webhookUrl)
    }

    func submit(
        _ id: String,
        input: (some Encodable) = EmptyInput.empty,
        webhookUrl: String? = nil,
        options: RunOptions
    ) async throws -> String {
        var inputPayload: Payload? = nil
        if !(input is EmptyInput) {
            let data = try encodeTypedInputRejectingBinaryData(
                input,
                message: "Typed Encodable values containing Data are not supported for automatic upload yet. Use Payload.data so binary values can be uploaded before request encoding."
            )
            inputPayload = try Payload.create(fromJSON: data)
        }
        return try await submit(id, input: inputPayload, webhookUrl: webhookUrl, options: options)
    }

    func submitDetailed(
        _ id: String,
        input: (some Encodable) = EmptyInput.empty,
        webhookUrl: String? = nil,
        options: RunOptions
    ) async throws -> QueueSubmitResult {
        var inputPayload: Payload? = nil
        if !(input is EmptyInput) {
            let data = try encodeTypedInputRejectingBinaryData(
                input,
                message: "Typed Encodable values containing Data are not supported for automatic upload yet. Use Payload.data so binary values can be uploaded before request encoding."
            )
            inputPayload = try Payload.create(fromJSON: data)
        }
        return try await submitDetailed(id, input: inputPayload, webhookUrl: webhookUrl, options: options)
    }

    func response<Output: Decodable>(_ id: String, of requestId: String) async throws -> Output {
        return try await runOnQueue(
            ensureAppIdFormat(id),
            input: nil as Payload?,
            options: .route(queueRequestPath(for: requestId), withMethod: .get)
        )
    }
}
