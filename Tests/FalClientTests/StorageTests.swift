@testable import FalClient
import XCTest

final class StorageTests: XCTestCase {
    func testUploadInitiateSendsGeneratedFileNameAndNoLifecycleByDefault() async throws {
        let transport = RecordingHTTPTransport { request in
            if request.url?.host == "rest.fal.ai" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/generated.png",
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
        let storage: Storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        _ = try await storage.upload(data: Data("image".utf8), ofType: .imagePng)

        let initiateRequest = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(initiateRequest.httpMethod, "POST")
        XCTAssertEqual(
            initiateRequest.url?.absoluteString,
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3"
        )
        let body = try Payload.create(fromJSON: try XCTUnwrap(initiateRequest.httpBody))
        XCTAssertEqual(body["content_type"].stringValue, "image/png")
        let fileName = try XCTUnwrap(body["file_name"].stringValue)
        XCTAssertTrue(fileName.hasSuffix(".png"))
        XCTAssertNil(initiateRequest.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle"))
        XCTAssertNil(initiateRequest.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference"))
    }

    func testUploadOptionsSendFileNameAndLifecycleHeadersOnInitiateOnly() async throws {
        let image = Data("image".utf8)
        let transport = RecordingHTTPTransport { request in
            if request.url?.host == "rest.fal.ai" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/custom.png",
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
        let storage: Storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(
            data: image,
            ofType: .imagePng,
            options: StorageUploadOptions(
                fileName: "custom.png",
                objectLifecyclePreference: .init(expirationDuration: 3_600)
            )
        )

        XCTAssertEqual(fileUrl, "https://fal.media/custom.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://storage.googleapis.com/upload",
        ])

        let initiateRequest = try XCTUnwrap(transport.requests.first)
        let initiateBody = try Payload.create(fromJSON: try XCTUnwrap(initiateRequest.httpBody))
        XCTAssertEqual(initiateBody["content_type"].stringValue, "image/png")
        XCTAssertEqual(initiateBody["file_name"].stringValue, "custom.png")
        XCTAssertEqual(
            initiateRequest.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle"),
            #"{"expiration_duration_seconds":3600}"#
        )
        XCTAssertNil(initiateRequest.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference"))

        let putRequest = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(putRequest.httpMethod, "PUT")
        XCTAssertEqual(putRequest.httpBody, image)
        XCTAssertEqual(putRequest.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(putRequest.value(forHTTPHeaderField: "Content-Length"), String(image.count))
        XCTAssertNil(putRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(putRequest.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle"))
        XCTAssertNil(putRequest.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference"))
    }

    func testUploadRetriesTransientPutResponses() async throws {
        var putAttempts = 0
        let transport = RecordingHTTPTransport { request in
            if request.url?.host == "rest.fal.ai" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/retried.png",
                  "upload_url": "https://storage.googleapis.com/upload"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            }

            putAttempts += 1
            if putAttempts == 1 {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"detail":"temporarily unavailable"}"#.data(using: .utf8)!
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
        let storage: Storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(data: Data("image".utf8), ofType: .imagePng)

        XCTAssertEqual(fileUrl, "https://fal.media/retried.png")
        XCTAssertEqual(putAttempts, 2)
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://storage.googleapis.com/upload",
            "https://storage.googleapis.com/upload",
        ])
    }

    func testUploadDoesNotRetryTransientInitiateResponses() async throws {
        var initiateAttempts = 0
        let transport = RecordingHTTPTransport { request in
            initiateAttempts += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"detail":"temporarily unavailable"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }
        let storage: Storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        do {
            _ = try await storage.upload(data: Data("image".utf8), ofType: .imagePng)
            XCTFail("Expected transient initiate failure")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 503)
        }

        XCTAssertEqual(initiateAttempts, 1)
    }

    func testUploadOptionsRejectInvalidLifecycleDurationBeforeSendingRequest() async throws {
        let transport = RecordingHTTPTransport { request in
            XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: Data(), response: response)
        }
        let storage: Storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        do {
            _ = try await storage.upload(
                data: Data("image".utf8),
                ofType: .imagePng,
                options: .init(objectLifecyclePreference: .init(expirationDuration: -.infinity))
            )
            XCTFail("Expected upload to reject invalid lifecycle duration")
        } catch FalError.unsupportedInput(let message) {
            XCTAssertEqual(message, "Object lifecycle expiration duration must be finite and greater than 0 seconds.")
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testUploadOptionsSanitizeCustomFileName() async throws {
        let transport = RecordingHTTPTransport { request in
            if request.url?.host == "rest.fal.ai" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/custom.png",
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
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        _ = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(fileName: "C:\\Users\\chris\\private\rname.png")
        )

        let initiateRequest = try XCTUnwrap(transport.requests.first)
        let body = try Payload.create(fromJSON: try XCTUnwrap(initiateRequest.httpBody))
        XCTAssertEqual(body["file_name"].stringValue, "private_name.png")
    }

    func testStorageUploadConvenienceCallsRemainSourceCompatible() async throws {
        let storage = RecordingStorage()

        _ = try await storage.upload(data: Data("default".utf8))
        _ = try await storage.upload(data: Data("png".utf8), ofType: .imagePng)
        _ = try await storage.upload(data: Data("empty-options".utf8), ofType: .imagePng, options: .init())

        do {
            _ = try await storage.upload(
                data: Data("custom-options".utf8),
                ofType: .imagePng,
                options: .init(fileName: "custom.png")
            )
            XCTFail("Expected custom storage implementation to reject non-empty options")
        } catch FalError.unsupportedOperation {
        }
    }

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
            expectedInvalidUrl: "not%20a%20url"
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
            expectedInvalidUrl: "https://127.0.0.1./upload"
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

    func testUploadThrowsInvalidUrlForHexIPv4MappedIPv6LoopbackUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://[::ffff:7f00:1]/upload",
            expectedInvalidUrl: "https://[::ffff:7f00:1]/upload"
        )
    }

    func testUploadThrowsInvalidUrlForIPv4CompatibleIPv6LoopbackUploadUrl() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://[::127.0.0.1]/upload",
            expectedInvalidUrl: "https://[::127.0.0.1]/upload"
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
            fileUrl: "https://localhost/file.png?signature=secret",
            uploadUrl: "https://storage.googleapis.com/upload",
            expectedInvalidUrl: "https://localhost/file.png"
        )
    }

    func testUploadThrowsInvalidUrlWhenFinalUploadResponseUrlIsUnsafe() async throws {
        let transport = RecordingHTTPTransport { request in
            if request.url?.host == "rest.fal.ai" {
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

            let redirectedURL = URL(string: "http://127.0.0.1/upload?signature=secret")!
            let response = HTTPURLResponse(
                url: redirectedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: Data(), response: response)
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        do {
            _ = try await storage.upload(data: Data("image".utf8), ofType: .imagePng)
            XCTFail("Expected upload to reject unsafe final response URL")
        } catch FalError.invalidUrl(let url) {
            XCTAssertEqual(url, "http://127.0.0.1/upload")
        }

        XCTAssertEqual(transport.requests.count, 2)
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
