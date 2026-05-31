@testable import FalClient
import XCTest

final class StorageTests: XCTestCase {
    func testDefaultUploadUsesDirectFalCDNV3WithFallbackRepositories() async throws {
        let image = Data("image".utf8)
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://v3.fal.media/files/rabbit/default.png"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage: Storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(data: image, ofType: .imagePng)

        XCTAssertEqual(fileUrl, "https://v3.fal.media/files/rabbit/default.png")
        XCTAssertEqual(StorageUploadOptions().repository, .directFalCDNV3)
        XCTAssertEqual(StorageUploadOptions().fallbackRepositories, [.directFalMedia, .falCDNV3PresignedURL])
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://v3.fal.media/files/upload",
        ])
    }

    func testExplicitPresignedRepositoryDoesNotUseDefaultFallbacks() async throws {
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3"
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        XCTAssertEqual(StorageUploadOptions(repository: .falCDNV3PresignedURL).fallbackRepositories, [])
        do {
            _ = try await storage.upload(
                data: Data("image".utf8),
                ofType: .imagePng,
                options: .init(repository: .falCDNV3PresignedURL)
            )
            XCTFail("Expected presigned upload to fail without trying default fallbacks")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 503)
        }
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
        ])
    }

    func testPresignedUploadInitiateSendsGeneratedFileNameAndNoLifecycleByDefault() async throws {
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

        _ = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(repository: .falCDNV3PresignedURL, fallbackRepositories: [])
        )

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
                objectLifecyclePreference: .init(expirationDuration: 3_600),
                repository: .falCDNV3PresignedURL,
                fallbackRepositories: []
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

        let fileUrl = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(repository: .falCDNV3PresignedURL, fallbackRepositories: [])
        )

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
            _ = try await storage.upload(
                data: Data("image".utf8),
                ofType: .imagePng,
                options: .init(repository: .falCDNV3PresignedURL, fallbackRepositories: [])
            )
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
            options: .init(
                fileName: "C:\\Users\\chris\\private\rname.png",
                repository: .falCDNV3PresignedURL,
                fallbackRepositories: []
            )
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

        do {
            _ = try await storage.upload(
                data: Data("custom-repository".utf8),
                ofType: .imagePng,
                options: .presignedFalCDNV3
            )
            XCTFail("Expected custom storage implementation to reject non-default repository")
        } catch FalError.unsupportedOperation {
        }

        do {
            _ = try await storage.upload(
                data: Data("custom-fal-media".utf8),
                ofType: .imagePng,
                options: .init(repository: .directFalMedia)
            )
            XCTFail("Expected custom storage implementation to reject direct fal.media repository")
        } catch FalError.unsupportedOperation {
        }

        do {
            _ = try await storage.upload(
                data: Data("custom-fallback".utf8),
                ofType: .imagePng,
                options: .init(fallbackRepositories: [.directFalCDNV3])
            )
            XCTFail("Expected custom storage implementation to reject fallback repositories")
        } catch FalError.unsupportedOperation {
        }

        do {
            _ = try await storage.upload(
                data: Data("custom-multipart".utf8),
                ofType: .imagePng,
                options: .init(multipartUpload: .init(thresholdBytes: 1, chunkSizeBytes: 1))
            )
            XCTFail("Expected custom storage implementation to reject multipart options")
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

    func testUploadRejectsNonAllowlistedUploadHostBeforePut() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media/file.png",
            uploadUrl: "https://attacker.example/upload",
            expectedInvalidUrl: "https://attacker.example/upload"
        )
    }

    func testUploadRejectsNonAllowlistedFileHostBeforePut() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://cdn.example.com/file.png",
            uploadUrl: "https://storage.googleapis.com/upload",
            expectedInvalidUrl: "https://cdn.example.com/file.png"
        )
    }

    func testUploadRejectsAllowlistSuffixSpoofingBeforePut() async throws {
        try await assertUploadThrowsInvalidUrl(
            fileUrl: "https://fal.media.evil.test/file.png",
            uploadUrl: "https://storage.googleapis.com.evil.test/upload",
            expectedInvalidUrl: "https://storage.googleapis.com.evil.test/upload"
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
            _ = try await storage.upload(
                data: Data("image".utf8),
                ofType: .imagePng,
                options: .init(repository: .falCDNV3PresignedURL, fallbackRepositories: [])
            )
            XCTFail("Expected upload to reject unsafe final response URL")
        } catch FalError.invalidUrl(let url) {
            XCTAssertEqual(url, "http://127.0.0.1/upload")
        }

        XCTAssertEqual(transport.requests.count, 2)
    }

    func testDirectFalCDNV3UploadFetchesTokenAndUploadsToTokenBaseURL() async throws {
        let image = Data("image".utf8)
        let transport = RecordingHTTPTransport { request in
            if request.url?.absoluteString == "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            }

            XCTAssertEqual(request.url?.absoluteString, "https://v3.fal.media/files/upload")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"access_url":"https://v3.fal.media/files/rabbit/result.png"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(
            data: image,
            ofType: .imagePng,
            options: .init(
                fileName: "custom.png",
                objectLifecyclePreference: .init(expirationDuration: 3_600),
                repository: .directFalCDNV3
            )
        )

        XCTAssertEqual(fileUrl, "https://v3.fal.media/files/rabbit/result.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://v3.fal.media/files/upload",
        ])

        let tokenRequest = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(tokenRequest.httpMethod, "POST")
        XCTAssertEqual(tokenRequest.value(forHTTPHeaderField: "Authorization"), "Key test-key:test-secret")

        let uploadRequest = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(uploadRequest.httpMethod, "POST")
        XCTAssertEqual(uploadRequest.httpBody, image)
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Authorization"), "Bearer cdn-token")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Content-Length"), String(image.count))
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "X-Fal-File-Name"), "custom.png")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle"), #"{"expiration_duration_seconds":3600}"#)
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference"), #"{"expiration_duration_seconds":3600}"#)
    }

    func testDirectFalCDNV3UploadAcceptsShardedTokenBaseURL() async throws {
        // Regression: fal's storage-auth-token endpoint returns sharded CDN hosts
        // (e.g. `v3b.fal.media`, not just `v3.fal.media`). The upload must proceed
        // to whatever host the token names rather than throwing
        // `FalError.invalidUrl` from the upload-host allow-list.
        let image = Data("image".utf8)
        let transport = RecordingHTTPTransport { request in
            if request.url?.absoluteString == "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3b.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            }

            XCTAssertEqual(request.url?.absoluteString, "https://v3b.fal.media/files/upload")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"access_url":"https://v3b.fal.media/files/rabbit/result.png"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(
            data: image,
            ofType: .imagePng,
            options: .init(repository: .directFalCDNV3)
        )

        XCTAssertEqual(fileUrl, "https://v3b.fal.media/files/rabbit/result.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://v3b.fal.media/files/upload",
        ])
    }

    func testDirectFalCDNV3UploadRoutesThroughProxyAndPreservesCallerAuth() async throws {
        let image = Data("image".utf8)
        let proxyURL = "https://proxy.example.com/api/fal/proxy"
        let transport = RecordingHTTPTransport { request in
            switch request.value(forHTTPHeaderField: "x-fal-target-url") ?? request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://v3.fal.media/files/rabbit/proxied.png"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(
            config: ClientConfig(
                credentials: .bearerToken("openstudio-jwt"),
                authScheme: .bearer,
                requestProxy: proxyURL
            ),
            httpTransport: transport
        ))

        let fileUrl = try await storage.upload(
            data: image,
            ofType: .imagePng,
            options: .init(repository: .directFalCDNV3)
        )

        XCTAssertEqual(fileUrl, "https://v3.fal.media/files/rabbit/proxied.png")
        let uploadRequest = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(uploadRequest.url?.absoluteString, proxyURL)
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "x-fal-target-url"), "https://v3.fal.media/files/upload")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Authorization"), "Bearer openstudio-jwt")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "x-fal-cdn-authorization"), "Bearer cdn-token")
    }

    func testDirectFalCDNV3MultipartUploadRoutesAllStepsThroughProxy() async throws {
        let data = Data("abcdefgh".utf8)
        let proxyURL = "https://proxy.example.com/api/fal/proxy"
        let transport = RecordingHTTPTransport { request in
            switch request.value(forHTTPHeaderField: "x-fal-target-url") ?? request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload/multipart":
                XCTAssertEqual(request.url?.absoluteString, proxyURL)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openstudio-jwt")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-fal-cdn-authorization"), "Bearer cdn-token")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://v3.fal.media/files/rabbit/proxied-multipart.png","uploadId":"upload-xyz"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/rabbit/proxied-multipart.png/multipart/upload-xyz/1",
                 "https://v3.fal.media/files/rabbit/proxied-multipart.png/multipart/upload-xyz/2",
                 "https://v3.fal.media/files/rabbit/proxied-multipart.png/multipart/upload-xyz/3":
                XCTAssertEqual(request.url?.absoluteString, proxyURL)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openstudio-jwt")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-fal-cdn-authorization"), "Bearer cdn-token")
                let partNumber = request.value(forHTTPHeaderField: "x-fal-target-url")?
                    .components(separatedBy: "/").last ?? ""
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["ETag": "etag-\(partNumber)"]
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            case "https://v3.fal.media/files/rabbit/proxied-multipart.png/multipart/upload-xyz/complete":
                XCTAssertEqual(request.url?.absoluteString, proxyURL)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer openstudio-jwt")
                XCTAssertEqual(request.value(forHTTPHeaderField: "x-fal-cdn-authorization"), "Bearer cdn-token")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(
            config: ClientConfig(
                credentials: .bearerToken("openstudio-jwt"),
                authScheme: .bearer,
                requestProxy: proxyURL
            ),
            httpTransport: transport
        ))

        let fileURL = try await storage.upload(
            data: data,
            ofType: .imagePng,
            options: .init(
                fileName: "proxied-multipart.png",
                repository: .directFalCDNV3,
                multipartUpload: .init(thresholdBytes: 4, chunkSizeBytes: 3)
            )
        )

        XCTAssertEqual(fileURL, "https://v3.fal.media/files/rabbit/proxied-multipart.png")
        XCTAssertEqual(
            transport.requests.map { $0.value(forHTTPHeaderField: "x-fal-target-url") ?? $0.url?.absoluteString },
            [
                "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
                "https://v3.fal.media/files/upload/multipart",
                "https://v3.fal.media/files/rabbit/proxied-multipart.png/multipart/upload-xyz/1",
                "https://v3.fal.media/files/rabbit/proxied-multipart.png/multipart/upload-xyz/2",
                "https://v3.fal.media/files/rabbit/proxied-multipart.png/multipart/upload-xyz/3",
                "https://v3.fal.media/files/rabbit/proxied-multipart.png/multipart/upload-xyz/complete",
            ]
        )
        XCTAssertTrue(
            transport.requests.dropFirst().allSatisfy { $0.url?.absoluteString == proxyURL },
            "All direct-CDN upload requests should be sent to the proxy URL"
        )
    }

    func testDirectFalCDNV3UploadRoutesThroughLoopbackProxy() async throws {
        let image = Data("image".utf8)
        let proxyURL = "http://localhost:3333/api/fal/proxy"
        let transport = RecordingHTTPTransport { request in
            switch request.value(forHTTPHeaderField: "x-fal-target-url") ?? request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://v3.fal.media/files/rabbit/proxied.png"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(
            config: ClientConfig(
                credentials: .bearerToken("openstudio-jwt"),
                authScheme: .bearer,
                requestProxy: proxyURL
            ),
            httpTransport: transport
        ))

        let fileUrl = try await storage.upload(
            data: image,
            ofType: .imagePng,
            options: .init(repository: .directFalCDNV3)
        )

        XCTAssertEqual(fileUrl, "https://v3.fal.media/files/rabbit/proxied.png")
        let uploadRequest = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(uploadRequest.url?.absoluteString, proxyURL)
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "x-fal-target-url"), "https://v3.fal.media/files/upload")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "Authorization"), "Bearer openstudio-jwt")
        XCTAssertEqual(uploadRequest.value(forHTTPHeaderField: "x-fal-cdn-authorization"), "Bearer cdn-token")
    }

    func testDirectFalCDNV3UploadRejectsNonFalTokenBaseURL() async throws {
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = """
            {
              "token": "cdn-token",
              "token_type": "Bearer",
              "base_url": "https://storage.googleapis.com/fal-upload",
              "expires_at": "2026-05-19T12:00:00+00:00"
            }
            """.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        do {
            _ = try await storage.upload(
                data: Data("image".utf8),
                ofType: .imagePng,
                options: .init(repository: .directFalCDNV3)
            )
            XCTFail("Expected direct CDN upload to reject non-Fal token base URL")
        } catch FalError.invalidUrl(let url) {
            XCTAssertEqual(url, "https://storage.googleapis.com/fal-upload/files/upload")
        }

        XCTAssertEqual(transport.requests.count, 1)
    }

    func testDirectFalCDNV3UploadFallsBackAfterTransientBodyUploadFailure() async throws {
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            case "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/files/rabbit/fallback-from-v3.png",
                  "upload_url": "https://storage.googleapis.com/upload"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://storage.googleapis.com/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileURL = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(repository: .directFalCDNV3, fallbackRepositories: [.falCDNV3PresignedURL])
        )

        XCTAssertEqual(fileURL, "https://fal.media/files/rabbit/fallback-from-v3.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://v3.fal.media/files/upload",
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://storage.googleapis.com/upload",
        ])
    }

    func testDirectFalCDNV3UploadRetriesTokenFetchBeforeUploadingBody() async throws {
        var tokenAttempts = 0
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                tokenAttempts += 1
                if tokenAttempts == 1 {
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(
                    data: Data(#"{"access_url":"https://v3.fal.media/files/rabbit/retried-token.png"}"#.utf8),
                    response: response
                )
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileURL = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(repository: .directFalCDNV3)
        )

        XCTAssertEqual(fileURL, "https://v3.fal.media/files/rabbit/retried-token.png")
        XCTAssertEqual(tokenAttempts, 2)
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://v3.fal.media/files/upload",
        ])
    }

    func testDirectFalCDNV3MultipartUploadChunksAndCompletesLargeData() async throws {
        let data = Data("abcdefgh".utf8)
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload/multipart":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertNil(request.httpBody)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cdn-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-File-Name"), "large.png")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://v3.fal.media/files/rabbit/large.png","uploadId":"upload-123"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/rabbit/large.png/multipart/upload-123/1",
                 "https://v3.fal.media/files/rabbit/large.png/multipart/upload-123/2",
                 "https://v3.fal.media/files/rabbit/large.png/multipart/upload-123/3":
                let partNumber = request.url!.lastPathComponent
                let expectedBodies = [
                    "1": Data("abc".utf8),
                    "2": Data("def".utf8),
                    "3": Data("gh".utf8),
                ]
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.httpBody, expectedBodies[partNumber])
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer cdn-token")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "identity")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "ETag": "etag-\(partNumber)",
                    ]
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            case "https://v3.fal.media/files/rabbit/large.png/multipart/upload-123/complete":
                XCTAssertEqual(request.httpMethod, "POST")
                let body = try Payload.create(fromJSON: try XCTUnwrap(request.httpBody))
                XCTAssertEqual(body["parts"][0]["partNumber"], .int(1))
                XCTAssertEqual(body["parts"][0]["etag"].stringValue, "etag-1")
                XCTAssertEqual(body["parts"][1]["partNumber"], .int(2))
                XCTAssertEqual(body["parts"][1]["etag"].stringValue, "etag-2")
                XCTAssertEqual(body["parts"][2]["partNumber"], .int(3))
                XCTAssertEqual(body["parts"][2]["etag"].stringValue, "etag-3")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileURL = try await storage.upload(
            data: data,
            ofType: .imagePng,
            options: .init(
                fileName: "large.png",
                repository: .directFalCDNV3,
                multipartUpload: .init(thresholdBytes: 4, chunkSizeBytes: 3)
            )
        )

        XCTAssertEqual(fileURL, "https://v3.fal.media/files/rabbit/large.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://v3.fal.media/files/upload/multipart",
            "https://v3.fal.media/files/rabbit/large.png/multipart/upload-123/1",
            "https://v3.fal.media/files/rabbit/large.png/multipart/upload-123/2",
            "https://v3.fal.media/files/rabbit/large.png/multipart/upload-123/3",
            "https://v3.fal.media/files/rabbit/large.png/multipart/upload-123/complete",
        ])
    }

    func testDirectFalCDNV3MultipartUploadRejectsInvalidOptionsBeforeNetwork() async throws {
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
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        do {
            _ = try await storage.upload(
                data: Data("image".utf8),
                ofType: .imagePng,
                options: .init(repository: .directFalCDNV3, multipartUpload: .init(thresholdBytes: 0, chunkSizeBytes: 1))
            )
            XCTFail("Expected invalid multipart threshold to throw")
        } catch FalError.unsupportedInput(let message) {
            XCTAssertEqual(message, "Multipart upload threshold and chunk size must be greater than 0 bytes.")
        }

        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testPresignedUploadIgnoresInvalidMultipartOptions() async throws {
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

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return HTTPTransportResponse(data: Data(), response: response)
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileURL = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(
                repository: .falCDNV3PresignedURL,
                fallbackRepositories: [],
                multipartUpload: .init(thresholdBytes: 0, chunkSizeBytes: 0)
            )
        )

        XCTAssertEqual(fileURL, "https://fal.media/file.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://storage.googleapis.com/upload",
        ])
    }

    func testDirectFalCDNV3MultipartUploadRetriesTransientPartPutAndComplete() async throws {
        var firstPartAttempts = 0
        var completeAttempts = 0
        let data = Data("abcd".utf8)
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload/multipart":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://v3.fal.media/files/rabbit/retry.png","uploadId":"upload-123"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/rabbit/retry.png/multipart/upload-123/1":
                firstPartAttempts += 1
                if firstPartAttempts == 1 {
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "ETag": "etag-1",
                    ]
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            case "https://v3.fal.media/files/rabbit/retry.png/multipart/upload-123/2":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "ETag": "etag-2",
                    ]
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            case "https://v3.fal.media/files/rabbit/retry.png/multipart/upload-123/complete":
                completeAttempts += 1
                if completeAttempts == 1 {
                    let response = HTTPURLResponse(
                        url: request.url!,
                        statusCode: 503,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                    return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileURL = try await storage.upload(
            data: data,
            ofType: .imagePng,
            options: .init(repository: .directFalCDNV3, multipartUpload: .init(thresholdBytes: 2, chunkSizeBytes: 2))
        )

        XCTAssertEqual(fileURL, "https://v3.fal.media/files/rabbit/retry.png")
        XCTAssertEqual(firstPartAttempts, 2)
        XCTAssertEqual(completeAttempts, 2)
    }

    func testDirectFalCDNV3MultipartUploadDoesNotFallbackAfterPartUploadStarts() async throws {
        var partAttempts = 0
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload/multipart":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://v3.fal.media/files/rabbit/terminal.png","uploadId":"upload-123"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/rabbit/terminal.png/multipart/upload-123/1":
                partAttempts += 1
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        do {
            _ = try await storage.upload(
                data: Data("abcd".utf8),
                ofType: .imagePng,
                options: .init(
                    repository: .directFalCDNV3,
                    fallbackRepositories: [.falCDNV3PresignedURL],
                    multipartUpload: .init(thresholdBytes: 2, chunkSizeBytes: 2)
                )
            )
            XCTFail("Expected multipart part failure to be terminal")
        } catch let error as TransientStorageUploadError {
            guard case FalError.httpError(let httpError) = error.underlying else {
                XCTFail("Expected HTTP error, got \(error)")
                return
            }
            XCTAssertEqual(httpError.statusCode, 503)
        } catch {
            XCTFail("Expected terminal transient storage upload error, got \(error)")
        }

        XCTAssertEqual(partAttempts, 3)
        XCTAssertFalse(transport.requests.contains {
            $0.url?.absoluteString == "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3"
        })
    }

    func testUploadCanFallbackFromPresignedRepositoryToDirectFalCDNV3() async throws {
        var initiateAttempts = 0
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3":
                initiateAttempts += 1
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "token": "cdn-token",
                  "token_type": "Bearer",
                  "base_url": "https://v3.fal.media",
                  "expires_at": "2026-05-19T12:00:00+00:00"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://v3.fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://v3.fal.media/files/rabbit/fallback.png"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(repository: .falCDNV3PresignedURL, fallbackRepositories: [.directFalCDNV3])
        )

        XCTAssertEqual(fileUrl, "https://v3.fal.media/files/rabbit/fallback.png")
        XCTAssertEqual(initiateAttempts, 1)
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://v3.fal.media/files/upload",
        ])
    }

    func testDirectFalMediaUploadUsesBearerSecretAndLifecycleHeaders() async throws {
        let image = Data("image".utf8)
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://fal.media/files/upload")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.httpBody, image)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), String(image.count))
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-File-Name"), "fallback.png")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle"), #"{"expiration_duration_seconds":3600}"#)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference"), #"{"expiration_duration_seconds":3600}"#)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"access_url":"https://fal.media/files/rabbit/fallback.png"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(
            data: image,
            ofType: .imagePng,
            options: .init(
                fileName: "fallback.png",
                objectLifecyclePreference: .init(expirationDuration: 3_600),
                repository: .directFalMedia
            )
        )

        XCTAssertEqual(fileUrl, "https://fal.media/files/rabbit/fallback.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://fal.media/files/upload",
        ])
    }

    func testDirectFalMediaUploadUsesBearerTokenCredentials() async throws {
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"access_url":"https://fal.media/files/rabbit/bearer.png"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }
        let client = StorageTestClient(
            config: ClientConfig(credentials: .bearerToken("access-token"), authScheme: .bearer),
            httpTransport: transport
        )
        let storage = StorageClient(client: client)

        let fileUrl = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(repository: .directFalMedia)
        )

        XCTAssertEqual(fileUrl, "https://fal.media/files/rabbit/bearer.png")
    }

    func testDirectFalMediaUploadRejectsUnsafeAccessURL() async throws {
        let transport = RecordingHTTPTransport { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = #"{"access_url":"https://fal.media.evil.test/files/rabbit/file.png?signature=secret"}"#.data(using: .utf8)!
            return HTTPTransportResponse(data: data, response: response)
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        do {
            _ = try await storage.upload(
                data: Data("image".utf8),
                ofType: .imagePng,
                options: .init(repository: .directFalMedia)
            )
            XCTFail("Expected direct fal.media upload to reject unsafe access URL")
        } catch FalError.invalidUrl(let url) {
            XCTAssertEqual(url, "https://fal.media.evil.test/files/rabbit/file.png")
        }
    }

    func testDirectFalMediaUploadFallsBackAfterTransientBodyUploadFailure() async throws {
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            case "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/files/rabbit/fallback-from-media.png",
                  "upload_url": "https://storage.googleapis.com/upload"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://storage.googleapis.com/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileURL = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(
                repository: .directFalMedia,
                fallbackRepositories: [.falCDNV3PresignedURL]
            )
        )

        XCTAssertEqual(fileURL, "https://fal.media/files/rabbit/fallback-from-media.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://fal.media/files/upload",
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://storage.googleapis.com/upload",
        ])
    }

    func testUploadCanFallbackFromDirectFalCDNV3TokenFetchToDirectFalMedia() async throws {
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            case "https://fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = #"{"access_url":"https://fal.media/files/rabbit/fallback.png"}"#.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(
            data: Data("image".utf8),
            ofType: .imagePng,
            options: .init(
                repository: .directFalCDNV3,
                fallbackRepositories: [.directFalMedia, .falCDNV3PresignedURL]
            )
        )

        XCTAssertEqual(fileUrl, "https://fal.media/files/rabbit/fallback.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://fal.media/files/upload",
        ])
    }

    func testDefaultUploadFallsBackThroughFalMediaToPresignedREST() async throws {
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            case "https://fal.media/files/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            case "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/files/rabbit/default-rest-fallback.png",
                  "upload_url": "https://storage.googleapis.com/upload"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://storage.googleapis.com/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let storage = StorageClient(client: StorageTestClient(httpTransport: transport))

        let fileUrl = try await storage.upload(data: Data("image".utf8), ofType: .imagePng)

        XCTAssertEqual(fileUrl, "https://fal.media/files/rabbit/default-rest-fallback.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://fal.media/files/upload",
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://storage.googleapis.com/upload",
        ])
    }

    func testDefaultUploadWithProxySkipsDirectFalMediaFallback() async throws {
        let proxyURL = "https://proxy.example.com/api/fal/proxy"
        let transport = RecordingHTTPTransport { request in
            switch request.value(forHTTPHeaderField: "x-fal-target-url") ?? request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            case "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/files/rabbit/proxy-rest-fallback.png",
                  "upload_url": "https://storage.googleapis.com/upload"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://storage.googleapis.com/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let client = StorageTestClient(
            config: ClientConfig(
                credentials: .keyPair("test-key:test-secret"),
                requestProxy: proxyURL
            ),
            httpTransport: transport
        )
        let storage = StorageClient(client: client)

        let fileUrl = try await storage.upload(data: Data("image".utf8), ofType: .imagePng)

        XCTAssertEqual(fileUrl, "https://fal.media/files/rabbit/proxy-rest-fallback.png")
        XCTAssertFalse(transport.requests.contains { $0.url?.host == "fal.media" })
        XCTAssertEqual(
            transport.requests.map { $0.value(forHTTPHeaderField: "x-fal-target-url") ?? $0.url?.absoluteString },
            [
                "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
                "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
                "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
                "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
                "https://storage.googleapis.com/upload",
            ]
        )
    }

    func testDefaultUploadSkipsDirectFalMediaFallbackWhenCredentialsCannotAuthorizeIt() async throws {
        let transport = RecordingHTTPTransport { request in
            switch request.url?.absoluteString {
            case "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(#"{"detail":"temporarily unavailable"}"#.utf8), response: response)
            case "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let data = """
                {
                  "file_url": "https://fal.media/files/rabbit/malformed-key-rest-fallback.png",
                  "upload_url": "https://storage.googleapis.com/upload"
                }
                """.data(using: .utf8)!
                return HTTPTransportResponse(data: data, response: response)
            case "https://storage.googleapis.com/upload":
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            default:
                XCTFail("Unexpected request to \(request.url?.absoluteString ?? "nil")")
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return HTTPTransportResponse(data: Data(), response: response)
            }
        }
        let client = StorageTestClient(
            config: ClientConfig(credentials: .keyPair("malformed-key")),
            httpTransport: transport
        )
        let storage = StorageClient(client: client)

        let fileUrl = try await storage.upload(data: Data("image".utf8), ofType: .imagePng)

        XCTAssertEqual(fileUrl, "https://fal.media/files/rabbit/malformed-key-rest-fallback.png")
        XCTAssertEqual(transport.requests.map { $0.url?.absoluteString }, [
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            "https://storage.googleapis.com/upload",
        ])
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
            _ = try await storage.upload(
                data: Data("image".utf8),
                ofType: .imagePng,
                options: .init(repository: .falCDNV3PresignedURL, fallbackRepositories: [])
            )
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
    var config = ClientConfig(credentials: .keyPair("test-key:test-secret"))
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
