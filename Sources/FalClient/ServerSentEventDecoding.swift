import Foundation

func decodeServerSentEventStream<Event: Decodable>(
    _ events: AsyncThrowingStream<Data, Error>,
    as _: Event.Type = Event.self,
    decoder: JSONDecoder = JSONDecoder(),
    until shouldFinish: (@Sendable (Event) -> Bool)? = nil
) -> AsyncThrowingStream<Event, Error> {
    let eventDecoder = ServerSentEventJSONDecoder(
        events: events,
        decoder: decoder,
        shouldFinish: shouldFinish
    )
    return AsyncThrowingStream(unfolding: {
        try await eventDecoder.nextEvent()
    })
}

private actor ServerSentEventJSONDecoder<Event: Decodable> {
    private var iterator: AsyncThrowingStream<Data, Error>.AsyncIterator
    private let decoder: JSONDecoder
    private let shouldFinish: (@Sendable (Event) -> Bool)?
    private var isFinished = false
    private var isProducing = false

    init(
        events: AsyncThrowingStream<Data, Error>,
        decoder: JSONDecoder,
        shouldFinish: (@Sendable (Event) -> Bool)?
    ) {
        self.iterator = events.makeAsyncIterator()
        self.decoder = decoder
        self.shouldFinish = shouldFinish
    }

    func nextEvent() async throws -> Event? {
        guard !isProducing else {
            throw FalError.unsupportedOperation(message: "SSE streams are single-consumer sequences.")
        }
        isProducing = true
        defer { isProducing = false }

        guard !isFinished else {
            return nil
        }
        guard let data = try await nextData() else {
            return nil
        }

        let event = try decoder.decode(Event.self, from: data)
        if shouldFinish?(event) == true {
            isFinished = true
        }
        return event
    }

    private func nextData() async throws -> Data? {
        var iterator = self.iterator
        let data = try await iterator.next()
        self.iterator = iterator
        return data
    }
}
