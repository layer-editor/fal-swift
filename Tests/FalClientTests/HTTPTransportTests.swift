@testable import FalClient
import XCTest

final class HTTPTransportTests: XCTestCase {
    func testSendRequestUsesInjectedHTTPTransport() async throws {
        let transport = RecordingHTTPTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: #"{"value":"ok"}"#.data(using: .utf8)!, response: response)
        }
        let client = TransportTestClient(httpTransport: transport)

        let data = try await client.sendRequest(
            to: "https://fal.run/fal-ai/test",
            input: nil as Data?,
            options: RunOptions.withMethod(.get)
        )

        XCTAssertEqual(try Payload.create(fromJSON: data)["value"].stringValue, "ok")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, ["https://fal.run/fal-ai/test"])
    }

    func testStorageUploadUsesInjectedHTTPTransportForInitiateAndPut() async throws {
        let transport = RecordingHTTPTransport { request in
            if request.url?.absoluteString == "https://rest.alpha.fal.ai/storage/upload/initiate" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/file.png",
                  "upload_url": "https://storage.googleapis.com/upload"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: Data(), response: response)
        }
        let client = TransportTestClient(httpTransport: transport)
        let storage = StorageClient(client: client)

        let fileUrl = try await storage.upload(data: Data("image".utf8), ofType: FileType.imagePng)

        XCTAssertEqual(fileUrl, "https://fal.media/file.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.alpha.fal.ai/storage/upload/initiate",
            "https://storage.googleapis.com/upload",
        ])
        XCTAssertEqual(transport.requests.last?.httpMethod, "PUT")
    }
}

private struct TransportTestClient: Client, HTTPTransportProviding {
    let config = ClientConfig()
    let httpTransport: HTTPTransport

    var queue: Queue {
        fatalError("TransportTestClient.queue is unused in these tests")
    }

    var realtime: Realtime {
        fatalError("TransportTestClient.realtime is unused in these tests")
    }

    var storage: Storage {
        fatalError("TransportTestClient.storage is unused in these tests")
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        fatalError("TransportTestClient.run is unused in these tests")
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("TransportTestClient.subscribe is unused in these tests")
    }
}
