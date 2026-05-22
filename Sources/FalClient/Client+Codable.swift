import Dispatch
import Foundation

public struct EmptyInput: Encodable, Sendable {
    public static let empty = EmptyInput()
}

public extension Client {
    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func run<Output: Decodable>(
        _ app: String,
        input: (some Encodable) = EmptyInput.empty,
        options: RunOptions = DefaultRunOptions
    ) async throws -> Output {
        let inputData = try input is EmptyInput ? nil : encodeTypedInputRejectingBinaryData(
            input,
            message: "Typed Encodable values containing Data are not supported for automatic upload yet. Use Payload.data with the Payload-based run API so binary values can be uploaded before request encoding.",
            configure: { $0.dateEncodingStrategy = .iso8601 }
        )
        let queryParams = inputData != nil && options.httpMethod == .get
            ? try Payload.create(fromJSON: inputData!)
            : Payload.dict([:])

        let url = buildUrl(fromId: app, path: options.path)
        let data = try await sendRequest(
            to: url,
            input: inputData,
            queryParams: queryParams.asDictionary,
            options: options,
            includeQueuePriority: false
        )
        return try decoder.decode(Output.self, from: data)
    }

    func stream<Event: Decodable>(
        _ app: String,
        input: (some Encodable) = EmptyInput.empty,
        options: StreamOptions = DefaultStreamOptions
    ) async throws -> AsyncThrowingStream<Event, Error> {
        let inputData = try input is EmptyInput ? nil : encodeTypedInputRejectingBinaryData(
            input,
            message: "Typed Encodable values containing Data are not supported for automatic upload yet. Use Payload.data with the Payload-based stream API so binary values can be uploaded before request encoding.",
            configure: { $0.dateEncodingStrategy = .iso8601 }
        )

        let url = buildUrl(fromId: app, path: options.path)
        let events = try await sendServerSentEvents(
            to: url,
            input: inputData,
            options: RunOptions(httpMethod: .post, timeoutInterval: options.timeoutInterval)
        )
        return decodeServerSentEventStream(events, as: Event.self, decoder: decoder)
    }

    func subscribe<Output: Decodable>(
        to app: String,
        input: (some Encodable) = EmptyInput.empty,
        options: RunOptions,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onQueueUpdate: OnQueueUpdate? = nil
    ) async throws -> Output {
        let requestId = try await queue.submit(app, input: input, options: options)
        return try await queueResponseAfterPolling(
            queue: queue,
            app: app,
            requestId: requestId,
            pollInterval: pollInterval,
            timeout: timeout,
            includeLogs: includeLogs,
            onQueueUpdate: onQueueUpdate
        )
    }

    func subscribe<Output: Decodable>(
        to app: String,
        input: (some Encodable) = EmptyInput.empty,
        options: RunOptions,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onEnqueue: @escaping OnQueueEnqueue,
        onQueueUpdate: OnQueueUpdate? = nil
    ) async throws -> Output {
        let submitResult = try await queue.submitDetailed(app, input: input, options: options)
        onEnqueue(submitResult)
        return try await queueResponseAfterPolling(
            queue: queue,
            app: app,
            requestId: submitResult.requestId,
            pollInterval: pollInterval,
            timeout: timeout,
            includeLogs: includeLogs,
            onQueueUpdate: onQueueUpdate
        )
    }

    func subscribe<Output: Decodable>(
        to app: String,
        input: (some Encodable) = EmptyInput.empty,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onQueueUpdate: OnQueueUpdate? = nil
    ) async throws -> Output {
        let requestId = try await queue.submit(app, input: input)
        return try await queueResponseAfterPolling(
            queue: queue,
            app: app,
            requestId: requestId,
            pollInterval: pollInterval,
            timeout: timeout,
            includeLogs: includeLogs,
            onQueueUpdate: onQueueUpdate
        )
    }

    func subscribe<Output: Decodable>(
        to app: String,
        input: (some Encodable) = EmptyInput.empty,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onEnqueue: @escaping OnQueueEnqueue,
        onQueueUpdate: OnQueueUpdate? = nil
    ) async throws -> Output {
        let submitResult = try await queue.submitDetailed(app, input: input)
        onEnqueue(submitResult)
        return try await queueResponseAfterPolling(
            queue: queue,
            app: app,
            requestId: submitResult.requestId,
            pollInterval: pollInterval,
            timeout: timeout,
            includeLogs: includeLogs,
            onQueueUpdate: onQueueUpdate
        )
    }

    func subscribeWithStatusDetails<Output: Decodable>(
        to app: String,
        input: (some Encodable) = EmptyInput.empty,
        options: RunOptions,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onQueueStatusDetailUpdate: @escaping OnQueueStatusDetailUpdate
    ) async throws -> Output {
        let requestId = try await queue.submit(app, input: input, options: options)
        return try await queueResponseAfterStatusDetailPolling(
            queue: queue,
            app: app,
            requestId: requestId,
            pollInterval: pollInterval,
            timeout: timeout,
            includeLogs: includeLogs,
            onQueueStatusDetailUpdate: onQueueStatusDetailUpdate
        )
    }

    func subscribeWithStatusDetails<Output: Decodable>(
        to app: String,
        input: (some Encodable) = EmptyInput.empty,
        pollInterval: DispatchTimeInterval = .seconds(1),
        timeout: DispatchTimeInterval = .minutes(3),
        includeLogs: Bool = false,
        onQueueStatusDetailUpdate: @escaping OnQueueStatusDetailUpdate
    ) async throws -> Output {
        let requestId = try await queue.submit(app, input: input)
        return try await queueResponseAfterStatusDetailPolling(
            queue: queue,
            app: app,
            requestId: requestId,
            pollInterval: pollInterval,
            timeout: timeout,
            includeLogs: includeLogs,
            onQueueStatusDetailUpdate: onQueueStatusDetailUpdate
        )
    }
}
