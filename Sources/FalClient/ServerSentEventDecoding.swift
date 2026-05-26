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
    private var pendingEvents: [Event] = []
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

        if let event = drainPending() {
            return event
        }
        guard !isFinished else {
            return nil
        }
        guard let data = try await nextData() else {
            return nil
        }

        let events = try decodeEvents(from: data)
        pendingEvents = events
        return drainPending()
    }

    /// Decodes one or more `Event` values from a single SSE event data chunk.
    ///
    /// Spec-compliant streams emit exactly one event per `data:` group, but
    /// fal's queue status stream — and any other server that batches
    /// successive `data:` lines into a single event without a blank-line
    /// separator between them — produces a chunk that contains multiple
    /// newline-joined JSON objects. `JSONDecoder.decode(Event.self, from:)`
    /// rejects that because it sees stray characters after the first
    /// top-level value. Try the single-event shape first so well-formed
    /// streams pay no extra cost; only fall back to per-line decoding when
    /// the single-event decode fails. Any successfully decoded line is
    /// queued and returned in arrival order; only when nothing decodes at
    /// all do we surface the original error to the caller.
    private func decodeEvents(from data: Data) throws -> [Event] {
        if let event = try? decoder.decode(Event.self, from: data) {
            return [event]
        }

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        guard lines.count > 1 else {
            // Single-line payload that couldn't decode — let the original
            // single-event decode error surface unchanged.
            return try [decoder.decode(Event.self, from: data)]
        }

        var events: [Event] = []
        var lastError: Error?
        for line in lines {
            let lineData = Data(line)
            do {
                events.append(try decoder.decode(Event.self, from: lineData))
            } catch {
                lastError = error
            }
        }

        if events.isEmpty, let lastError {
            throw lastError
        }
        return events
    }

    private func drainPending() -> Event? {
        guard !pendingEvents.isEmpty else {
            return nil
        }
        let event = pendingEvents.removeFirst()
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
