//
//  FalImageTests.swift
//
//
//  Created by Chris Zelazo on 5/19/26.
//

@testable import FalClient
import XCTest

final class FalImageTests: XCTestCase {
    override func tearDown() {
        ImageRedirectingURLProtocol.reset()
        super.tearDown()
    }

    func testLoadDataReturnsRawContentWithoutCallingLoader() async throws {
        let loader = RecordingImageContentDataLoader()
        let content = FalImageContent.raw(Data("raw-image".utf8))

        let data = try await content.loadData(using: loader)

        XCTAssertEqual(data, Data("raw-image".utf8))
        XCTAssertTrue(loader.requestedURLs.isEmpty)
    }

    func testLoadDataFetchesURLContentWithInjectedLoader() async throws {
        let expectedURL = try XCTUnwrap(URL(string: "https://cdn.example.com/image.png"))
        let loader = RecordingImageContentDataLoader(result: .success(Data("remote-image".utf8)))
        let content = FalImageContent.url(expectedURL.absoluteString)

        let data = try await content.loadData(using: loader)

        XCTAssertEqual(data, Data("remote-image".utf8))
        XCTAssertEqual(loader.requestedURLs, [expectedURL])
    }

    func testLoadDataThrowsForInvalidURLWithoutCallingLoader() async throws {
        let loader = RecordingImageContentDataLoader()
        let content = FalImageContent.url("://not-a-url")

        do {
            _ = try await content.loadData(using: loader)
            XCTFail("Expected invalid URL to throw")
        } catch FalError.invalidUrl(let url) {
            XCTAssertEqual(url, "://not-a-url")
        } catch {
            XCTFail("Expected invalid URL error, got \(error)")
        }

        XCTAssertTrue(loader.requestedURLs.isEmpty)
    }

    func testLoadDataRejectsUnsafeRemoteURLsWithoutCallingLoader() async throws {
        let loader = RecordingImageContentDataLoader()
        let unsafeURLs = [
            "http://cdn.example.com/image.png",
            "https://localhost/image.png",
            "https://127.0.0.1/image.png",
            "https://192.168.1.10/image.png",
        ]

        for unsafeURL in unsafeURLs {
            do {
                _ = try await FalImageContent.url(unsafeURL).loadData(using: loader)
                XCTFail("Expected \(unsafeURL) to throw")
            } catch FalError.invalidUrl {
            } catch {
                XCTFail("Expected invalid URL error for \(unsafeURL), got \(error)")
            }
        }

        XCTAssertTrue(loader.requestedURLs.isEmpty)
    }

    func testURLSessionLoaderRejectsUnsafeRedirects() async throws {
        ImageRedirectingURLProtocol.redirect(to: "http://127.0.0.1/image.png?signature=secret")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageRedirectingURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }
        let loader = URLSessionFalImageContentDataLoader(session: session)

        do {
            _ = try await FalImageContent.url("https://cdn.example.com/image.png").loadData(using: loader)
            XCTFail("Expected unsafe redirect to throw")
        } catch FalError.invalidUrl(let url) {
            XCTAssertEqual(url, "http://127.0.0.1/image.png")
        } catch {
            XCTFail("Expected invalid URL error, got \(error)")
        }

        XCTAssertEqual(ImageRedirectingURLProtocol.requestedURLs(), [
            URL(string: "https://cdn.example.com/image.png")!,
        ])
    }

    func testURLSessionLoaderLoadsSuccessfulResponses() async throws {
        ImageRedirectingURLProtocol.respond(statusCode: 200, data: Data("image".utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageRedirectingURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }
        let loader = URLSessionFalImageContentDataLoader(session: session)
        let url = try XCTUnwrap(URL(string: "https://cdn.example.com/image.png"))

        let data = try await loader.data(from: url)

        XCTAssertEqual(data, Data("image".utf8))
        XCTAssertEqual(ImageRedirectingURLProtocol.requestedURLs(), [url])
    }

    func testURLSessionLoaderThrowsHTTPErrorForUnsuccessfulResponses() async throws {
        ImageRedirectingURLProtocol.respond(statusCode: 404, data: Data("missing".utf8))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageRedirectingURLProtocol.self]
        configuration.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }
        let loader = URLSessionFalImageContentDataLoader(session: session)

        do {
            _ = try await loader.data(from: URL(string: "https://cdn.example.com/missing.png")!)
            XCTFail("Expected HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 404)
        } catch {
            XCTFail("Expected HTTP error, got \(error)")
        }
    }

    func testFalImageLoadDataDelegatesToContent() async throws {
        let expectedURL = try XCTUnwrap(URL(string: "https://cdn.example.com/image.png"))
        let loader = RecordingImageContentDataLoader(result: .success(Data("image".utf8)))
        let image = FalImage(
            content: .url(expectedURL.absoluteString),
            contentType: "image/png",
            width: 32,
            height: 16
        )

        let data = try await image.loadData(using: loader)

        XCTAssertEqual(data, Data("image".utf8))
        XCTAssertEqual(loader.requestedURLs, [expectedURL])
    }
}

private final class RecordingImageContentDataLoader: FalImageContentDataLoading, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<Data, Error>
    private var _requestedURLs: [URL] = []

    init(result: Result<Data, Error> = .success(Data())) {
        self.result = result
    }

    var requestedURLs: [URL] {
        lock.withLock { _requestedURLs }
    }

    func data(from url: URL) async throws -> Data {
        lock.withLock {
            _requestedURLs.append(url)
        }
        return try result.get()
    }
}

private final class ImageRedirectingURLProtocol: URLProtocol {
    private static let state = ImageRedirectingURLProtocolState()

    static func reset() {
        state.reset()
    }

    static func requestedURLs() -> [URL] {
        state.requestedURLs()
    }

    static func redirect(to location: String) {
        state.redirect(to: location)
    }

    static func respond(statusCode: Int, data: Data) {
        state.respond(statusCode: statusCode, data: data)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: FalError.invalidResultFormat)
            return
        }
        Self.state.appendRequestedURL(url)
        if let redirectLocation = Self.state.redirectLocation() {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 307,
                httpVersion: nil,
                headerFields: [
                    "Location": redirectLocation,
                ]
            )!
            var redirectRequest = request
            redirectRequest.url = URL(string: redirectLocation)!
            client?.urlProtocol(self, wasRedirectedTo: redirectRequest, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let stub = Self.state.stubbedResponse()
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class ImageRedirectingURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var redirect: String?
    private var statusCode = 200
    private var data = Data()

    func reset() {
        lock.withLock {
            urls.removeAll()
            redirect = nil
            statusCode = 200
            data = Data()
        }
    }

    func appendRequestedURL(_ url: URL) {
        lock.withLock {
            urls.append(url)
        }
    }

    func requestedURLs() -> [URL] {
        lock.withLock {
            urls
        }
    }

    func redirect(to location: String) {
        lock.withLock {
            redirect = location
        }
    }

    func redirectLocation() -> String? {
        lock.withLock {
            redirect
        }
    }

    func respond(statusCode: Int, data: Data) {
        lock.withLock {
            redirect = nil
            self.statusCode = statusCode
            self.data = data
        }
    }

    func stubbedResponse() -> (statusCode: Int, data: Data) {
        lock.withLock {
            (statusCode, data)
        }
    }
}
