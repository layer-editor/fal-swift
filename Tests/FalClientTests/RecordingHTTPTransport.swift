@testable import FalClient
import Foundation

final class RecordingHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let handler: (URLRequest) throws -> HTTPTransportResponse
    private let eventStreamHandler: (URLRequest) throws -> HTTPTransportEventStream
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) throws -> HTTPTransportResponse) {
        self.handler = handler
        self.eventStreamHandler = { _ in
            throw FalError.invalidResultFormat
        }
    }

    init(serverSentEventData events: [String]) {
        self.handler = { _ in
            throw FalError.invalidResultFormat
        }
        self.eventStreamHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "content-type": "text/event-stream",
                ]
            )!
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
            return HTTPTransportEventStream(events: stream, response: response, errorData: Data())
        }
    }

    init(serverSentEventStatusCode statusCode: Int, body: Data, headers: [String: String] = [:]) {
        self.handler = { _ in
            throw FalError.invalidResultFormat
        }
        self.eventStreamHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                continuation.finish()
            }
            return HTTPTransportEventStream(events: stream, response: response, errorData: body)
        }
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        requests.append(request)
        return try handler(request)
    }

    func serverSentEvents(for request: URLRequest) async throws -> HTTPTransportEventStream {
        requests.append(request)
        return try eventStreamHandler(request)
    }

    func reset() {
        requests = []
    }
}
