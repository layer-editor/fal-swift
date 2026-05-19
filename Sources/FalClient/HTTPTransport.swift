import Foundation

struct HTTPTransportResponse {
    let data: Data
    let response: URLResponse
}

protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> HTTPTransportResponse
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
}

extension Client {
    var resolvedHTTPTransport: HTTPTransport {
        (self as? HTTPTransportProviding)?.httpTransport ?? URLSessionHTTPTransport.shared
    }
}
