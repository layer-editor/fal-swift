@testable import FalClient
import XCTest

final class StorageTests: XCTestCase {
    func testAutoUploadRecursivelyUploadsNestedPayloadData() async throws {
        let storage = RecordingStorage()
        let input: Payload = [
            "image": .data(Data("root".utf8)),
            "nested": [
                "mask": .data(Data("mask".utf8)),
                "items": [
                    .data(Data("first".utf8)),
                    [
                        "thumbnail": .data(Data("thumbnail".utf8)),
                    ],
                ],
            ],
        ]

        let transformed = try await storage.autoUpload(input: input)

        XCTAssertEqual(transformed["image"].stringValue, "uploaded://root")
        XCTAssertEqual(transformed["nested"]["mask"].stringValue, "uploaded://mask")
        XCTAssertEqual(transformed["nested"]["items"][0].stringValue, "uploaded://first")
        XCTAssertEqual(transformed["nested"]["items"][1]["thumbnail"].stringValue, "uploaded://thumbnail")
        XCTAssertEqual(Set(storage.uploadedData), Set([
            Data("root".utf8),
            Data("mask".utf8),
            Data("first".utf8),
            Data("thumbnail".utf8),
        ]))
    }

    func testUploadThrowsInvalidUrlForMalformedUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "not a url",
            expectedInvalidUrl: "not a url"
        )
    }

    func testUploadThrowsInvalidUrlForHostlessUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https:example.com",
            expectedInvalidUrl: "https:example.com"
        )
    }

    func testUploadThrowsInvalidUrlForLoopbackUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://127.0.0.1/upload",
            expectedInvalidUrl: "https://127.0.0.1/upload"
        )
    }

    func testUploadThrowsInvalidUrlForLoopbackUploadUrlWithTrailingDot() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://127.0.0.1./upload?signature=secret",
            expectedInvalidUrl: "https://127.0.0.1./upload?signature=secret"
        )
    }

    func testUploadThrowsInvalidUrlForPrivateUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://192.168.1.10/upload",
            expectedInvalidUrl: "https://192.168.1.10/upload"
        )
    }

    func testUploadThrowsInvalidUrlForIPv4MappedIPv6LoopbackUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://[::ffff:127.0.0.1]/upload",
            expectedInvalidUrl: "https://[::ffff:127.0.0.1]/upload"
        )
    }

    func testUploadThrowsInvalidUrlForNumericLoopbackUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://2130706433/upload",
            expectedInvalidUrl: "https://2130706433/upload"
        )
    }

    func testUploadThrowsInvalidUrlForHexLoopbackUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://0x7f000001/upload",
            expectedInvalidUrl: "https://0x7f000001/upload"
        )
    }

    func testUploadThrowsInvalidUrlForOctalLoopbackUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://0177.0.0.1/upload",
            expectedInvalidUrl: "https://0177.0.0.1/upload"
        )
    }

    func testUploadThrowsInvalidUrlForInvalidFileUrlBeforePut() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://localhost/file.png",
            uploadUrl: "https://storage.googleapis.com/upload",
            expectedInvalidUrl: "https://localhost/file.png"
        )
    }

    private func assertUploadThrowsInvalidUrl(
        fileUrl: String,
        uploadUrl: String,
        expectedInvalidUrl: String
    ) async throws {
        let transport = RecordingHTTPTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {
              "file_url": "\(fileUrl)",
              "upload_url": "\(uploadUrl)"
            }
            """.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }

        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        do {
            _ = try await storage.upload(data: Data("image".utf8), ofType: .imagePng)
            XCTFail("Expected upload to throw")
        } catch FalError.invalidUrl(let url) {
            XCTAssertEqual(url, expectedInvalidUrl)
        }

        XCTAssertEqual(transport.requests.count, 1)
    }
}

private final class RecordingStorage: Storage {
    private(set) var uploadedData: [Data] = []

    var client: Client {
        fatalError("RecordingStorage.client is unused in these tests")
    }

    func upload(data: Data, ofType type: FileType) async throws -> String {
        uploadedData.append(data)
        return "uploaded://\(String(decoding: data, as: UTF8.self))"
    }
}

private struct StorageTestClient: Client, HTTPTransportProviding {
    let config = ClientConfig()
    let httpTransport: HTTPTransport

    var queue: Queue {
        fatalError("StorageTestClient.queue is unused in these tests")
    }

    var realtime: Realtime {
        fatalError("StorageTestClient.realtime is unused in these tests")
    }

    var storage: Storage {
        fatalError("StorageTestClient.storage is unused in these tests")
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        fatalError("StorageTestClient.run is unused in these tests")
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("StorageTestClient.subscribe is unused in these tests")
    }
}
