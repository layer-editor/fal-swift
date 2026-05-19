@testable import FalClient
import Foundation

final class RecordingHTTPTransport: HTTPTransport {
    private let handler: (URLRequest) throws -> HTTPTransportResponse
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) throws -> HTTPTransportResponse) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        requests.append(request)
        return try handler(request)
    }

    func reset() {
        requests = []
    }
}
