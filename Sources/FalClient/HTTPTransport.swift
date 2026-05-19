import Foundation

private let maximumServerSentEventErrorBodySize = 65_536

struct HTTPTransportResponse {
    let data: Data
    let response: URLResponse
}

struct HTTPTransportEventStream {
    let events: AsyncThrowingStream<Data, Error>
    let response: URLResponse
    let errorData: Data
}

protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> HTTPTransportResponse
    func serverSentEvents(for request: URLRequest) async throws -> HTTPTransportEventStream
}

protocol HTTPTransportProviding {
    var httpTransport: HTTPTransport { get }
}

struct URLSessionHTTPTransport: HTTPTransport {
    static let shared = URLSessionHTTPTransport()

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        return HTTPTransportResponse(data: data, response: response)
    }

    func serverSentEvents(for request: URLRequest) async throws -> HTTPTransportEventStream {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, !httpResponse.isSuccessful {
            var errorData = Data()
            for try await byte in bytes {
                guard errorData.count < maximumServerSentEventErrorBodySize else {
                    break
                }
                errorData.append(byte)
            }
            return HTTPTransportEventStream(
                events: AsyncThrowingStream { $0.finish() },
                response: response,
                errorData: errorData
            )
        }

        let events = serverSentEventStream(from: bytes.lines)
        return HTTPTransportEventStream(events: events, response: response, errorData: Data())
    }
}

extension Client {
    var resolvedHTTPTransport: HTTPTransport {
        (self as? HTTPTransportProviding)?.httpTransport ?? URLSessionHTTPTransport.shared
    }
}

func parseServerSentEvents<Lines: AsyncSequence>(
    from lines: Lines,
    yieldingTo continuation: AsyncThrowingStream<Data, Error>.Continuation
) async throws where Lines.Element == String {
    for try await event in serverSentEventStream(from: lines) {
        continuation.yield(event)
    }
}

func serverSentEventStream<Lines: AsyncSequence>(
    from lines: Lines
) -> AsyncThrowingStream<Data, Error> where Lines.Element == String {
    let parser = ServerSentEventParser(lines: lines)
    return AsyncThrowingStream(unfolding: {
        try await parser.nextEvent()
    })
}

private final class ServerSentEventParser<Lines: AsyncSequence>: @unchecked Sendable where Lines.Element == String {
    private var iterator: Lines.AsyncIterator
    private var dataLines: [String] = []

    init(lines: Lines) {
        self.iterator = lines.makeAsyncIterator()
    }

    func nextEvent() async throws -> Data? {
        while let line = try await nextLine() {
            guard !line.isEmpty else {
                if let event = serverSentEventData(from: dataLines) {
                    dataLines.removeAll()
                    return event
                }
                continue
            }
            guard line.hasPrefix("data:") else {
                continue
            }

            var data = String(line.dropFirst(5))
            if data.first == " " {
                data.removeFirst()
            }
            dataLines.append(data)
        }

        defer { dataLines.removeAll() }
        return serverSentEventData(from: dataLines)
    }

    private func nextLine() async throws -> String? {
        var iterator = self.iterator
        let line = try await iterator.next()
        self.iterator = iterator
        return line
    }
}

private func serverSentEventData(from dataLines: [String]) -> Data? {
    guard !dataLines.isEmpty,
          let data = dataLines.joined(separator: "\n").data(using: .utf8)
    else {
        return nil
    }
    return data
}
