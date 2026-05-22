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

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> HTTPTransportResponse
    func data(
        for request: URLRequest,
        validatingRedirectsWith validator: @Sendable @escaping (URL) -> Bool
    ) async throws -> HTTPTransportResponse
    func serverSentEvents(for request: URLRequest) async throws -> HTTPTransportEventStream
}

extension HTTPTransport {
    // Compatibility fallback for simple fake transports. Real network transports
    // used for storage uploads should override this method and reject unsafe
    // redirects before following them.
    func data(
        for request: URLRequest,
        validatingRedirectsWith validator: @Sendable @escaping (URL) -> Bool
    ) async throws -> HTTPTransportResponse {
        let transportResponse = try await data(for: request)
        if let responseURL = transportResponse.response.url,
           !validator(responseURL)
        {
            throw FalError.invalidUrl(url: responseURL.absoluteString.redactedURLForDescription)
        }
        return transportResponse
    }
}

protocol HTTPTransportProviding {
    var httpTransport: HTTPTransport { get }
}

struct URLSessionHTTPTransport: HTTPTransport {
    static let shared = URLSessionHTTPTransport()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let (data, response) = try await session.data(for: request)
        return HTTPTransportResponse(data: data, response: response)
    }

    func data(
        for request: URLRequest,
        validatingRedirectsWith validator: @Sendable @escaping (URL) -> Bool
    ) async throws -> HTTPTransportResponse {
        let delegate = RedirectValidatingURLSessionDelegate(validator: validator)
        let (data, response) = try await session.data(for: request, delegate: delegate)
        if let rejectedURL = delegate.rejectedRedirectURL {
            throw FalError.invalidUrl(url: rejectedURL.absoluteString.redactedURLForDescription)
        }
        if let responseURL = response.url,
           !validator(responseURL)
        {
            throw FalError.invalidUrl(url: responseURL.absoluteString.redactedURLForDescription)
        }
        return HTTPTransportResponse(data: data, response: response)
    }

    func serverSentEvents(for request: URLRequest) async throws -> HTTPTransportEventStream {
        let (bytes, response) = try await session.bytes(for: request)
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

final class RedirectValidatingURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let validator: @Sendable (URL) -> Bool
    private let lock = NSLock()
    private var _rejectedRedirectURL: URL?

    init(validator: @escaping @Sendable (URL) -> Bool) {
        self.validator = validator
    }

    var rejectedRedirectURL: URL? {
        lock.withLock {
            _rejectedRedirectURL
        }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, validator(url) else {
            lock.withLock {
                _rejectedRedirectURL = request.url
            }
            completionHandler(nil)
            return
        }
        completionHandler(request)
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

private actor ServerSentEventParser<Lines: AsyncSequence> where Lines.Element == String {
    private var iterator: Lines.AsyncIterator
    private var dataLines: [String] = []
    private var isProducing = false

    init(lines: Lines) {
        self.iterator = lines.makeAsyncIterator()
    }

    func nextEvent() async throws -> Data? {
        guard !isProducing else {
            throw FalError.unsupportedOperation(message: "SSE streams are single-consumer sequences.")
        }
        isProducing = true
        defer { isProducing = false }

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
