//
//  FalModelCatalogTests.swift
//  FalClient
//
//  Created by Chris on 5/19/26.
//

@testable import FalClient
import XCTest

final class FalModelCatalogTests: XCTestCase {
    private var transport: RecordingHTTPTransport!
    private var requestHandler: ((URLRequest) throws -> HTTPTransportResponse)?

    override func setUp() {
        super.setUp()
        requestHandler = nil
        transport = RecordingHTTPTransport { [unowned self] request in
            guard let requestHandler else {
                throw FalError.invalidResultFormat
            }
            return try requestHandler(request)
        }
    }

    override func tearDown() {
        requestHandler = nil
        transport = nil
        super.tearDown()
    }

    func testSearchModelsBuildsPlatformRequestAndDecodesCapabilities() async throws {
        requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "api.fal.ai")
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "accept"), "application/json")

            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            XCTAssertEqual(queryItems.value(for: "q"), "banana")
            XCTAssertEqual(queryItems.value(for: "category"), "image-to-image")
            XCTAssertEqual(queryItems.value(for: "status"), "active")
            XCTAssertEqual(queryItems.value(for: "limit"), "25")
            XCTAssertEqual(queryItems.value(for: "cursor"), "next")
            XCTAssertEqual(queryItems.values(for: "expand"), ["openapi-3.0", "enterprise_status"])

            return HTTPTransportResponse(
                data: Self.modelSearchResponseData,
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let client = ModelCatalogTestClient(config: ClientConfig(credentials: .keyPair("key-id:key-secret")), httpTransport: transport)
        let page = try await client.models.search(
            "banana",
            category: "image-to-image",
            status: .active,
            limit: 25,
            cursor: "next",
            expand: [.openAPI, .enterpriseStatus]
        )

        XCTAssertEqual(page.models.count, 1)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextCursor, "Mg==")

        let model = try XCTUnwrap(page.models.first)
        XCTAssertEqual(model.endpointId, "fal-ai/nano-banana-2/edit")
        XCTAssertEqual(model.metadata.displayName, "Nano Banana 2")
        XCTAssertEqual(model.metadata.category, "image-to-image")
        XCTAssertEqual(model.metadata.status, .active)
        XCTAssertEqual(model.metadata.tags, ["editing"])
        XCTAssertEqual(model.metadata.group?.label, "Image Editing")
        XCTAssertEqual(model.enterpriseStatus, "ready")
        XCTAssertNotNil(model.openapi)
        XCTAssertEqual(model.inferredCapabilities.task, .imageToImages)
        XCTAssertEqual(model.inferredCapabilities.inputKinds, [.text, .image])
        XCTAssertEqual(model.inferredCapabilities.outputKinds, [.image])
        XCTAssertTrue(model.inferredCapabilities.supportsQueue)

        let schema = try XCTUnwrap(model.queueSchema)
        XCTAssertEqual(schema.input?.fields.map(\.name), ["prompt", "image_urls", "num_images", "output_format", "aspect_ratio"])
        XCTAssertEqual(schema.input?.fields.first?.kind, .text)
        XCTAssertTrue(schema.input?.fields.first?.isRequired == true)
        XCTAssertEqual(schema.input?.fields.first?.title, "Prompt")
        XCTAssertEqual(schema.input?.fields[1].kind, .images)
        XCTAssertEqual(schema.input?.fields[2].kind, .integer)
        XCTAssertEqual(schema.input?.fields[2].defaultValue, .int(1))
        XCTAssertEqual(schema.input?.fields[3].allowedValues, ["png", "jpeg"])
        XCTAssertEqual(schema.input?.fields[4].kind, .string)
        XCTAssertEqual(schema.input?.fields[4].title, "Aspect Ratio")
        XCTAssertEqual(schema.input?.fields[4].defaultValue, .string("auto"))
        XCTAssertEqual(schema.input?.fields[4].allowedValues, ["auto", "1:1"])
        XCTAssertEqual(schema.output?.fields.map(\.name), ["images", "description"])
        XCTAssertEqual(schema.output?.fields.first?.kind, .images)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "Key key-id:key-secret")
    }

    func testFindModelUsesEndpointIdQueryAndReturnsFirstModel() async throws {
        requestHandler = { request in
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            let queryItems = components.queryItems ?? []
            XCTAssertEqual(queryItems.values(for: "endpoint_id"), ["fal-ai/flux/dev"])
            XCTAssertEqual(queryItems.values(for: "expand"), ["openapi-3.0"])

            return HTTPTransportResponse(
                data: Self.modelSearchResponseData,
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let client = ModelCatalogTestClient(config: ClientConfig(), httpTransport: transport)
        let model = try await client.models.find("fal-ai/flux/dev", expand: [.openAPI])

        XCTAssertEqual(model?.endpointId, "fal-ai/nano-banana-2/edit")
    }

    func testFindModelsPreservesMultipleEndpointIdQueryItems() async throws {
        requestHandler = { request in
            let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            XCTAssertEqual(
                components.queryItems?.values(for: "endpoint_id"),
                ["fal-ai/flux/dev", "fal-ai/flux/schnell"]
            )

            return HTTPTransportResponse(
                data: Self.emptyModelSearchResponseData,
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let client = ModelCatalogTestClient(config: ClientConfig(), httpTransport: transport)
        let models = try await client.models.find(["fal-ai/flux/dev", "fal-ai/flux/schnell"])

        XCTAssertTrue(models.isEmpty)
    }

    func testFindModelsWithNoEndpointIdsDoesNotSendRequest() async throws {
        requestHandler = { _ in
            XCTFail("Empty endpoint lookup should not send a request")
            throw FalError.invalidResultFormat
        }

        let client = ModelCatalogTestClient(config: ClientConfig(), httpTransport: transport)
        let models = try await client.models.find([])

        XCTAssertTrue(models.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

private struct ModelCatalogTestClient: Client, HTTPTransportProviding {
    let config: ClientConfig
    let httpTransport: HTTPTransport

    var queue: Queue {
        fatalError("ModelCatalogTestClient.queue is unused in these tests")
    }

    var realtime: Realtime {
        fatalError("ModelCatalogTestClient.realtime is unused in these tests")
    }

    var storage: Storage {
        fatalError("ModelCatalogTestClient.storage is unused in these tests")
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        fatalError("ModelCatalogTestClient.run is unused in these tests")
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("ModelCatalogTestClient.subscribe is unused in these tests")
    }
}

private extension FalModelCatalogTests {
    static let emptyModelSearchResponseData = Data(#"{"models":[],"next_cursor":null,"has_more":false}"#.utf8)

    static let modelSearchResponseData = Data(
        #"""
        {
          "models": [
            {
              "endpoint_id": "fal-ai/nano-banana-2/edit",
              "metadata": {
                "display_name": "Nano Banana 2",
                "category": "image-to-image",
                "description": "Image editing model",
                "status": "active",
                "tags": ["editing"],
                "updated_at": "2026-04-28T16:29:09.509Z",
                "is_favorited": false,
                "thumbnail_url": "https://v3b.fal.media/files/example.jpg",
                "model_url": "https://fal.run/fal-ai/nano-banana-2/edit",
                "license_type": "commercial",
                "date": "2026-02-26T16:20:09.685Z",
                "group": {
                  "key": "nano-banana-2",
                  "label": "Image Editing"
                },
                "highlighted": false,
                "kind": "inference",
                "pinned": false
              },
              "enterprise_status": "ready",
              "openapi": {
                "openapi": "3.0.4",
                "info": {
                  "title": "Queue OpenAPI for fal-ai/nano-banana-2/edit",
                  "version": "1.0.0",
                  "x-fal-metadata": {
                    "endpointId": "fal-ai/nano-banana-2/edit",
                    "category": "image-to-image",
                    "playgroundUrl": "https://fal.ai/models/fal-ai/nano-banana-2/edit",
                    "documentationUrl": "https://fal.ai/models/fal-ai/nano-banana-2/edit/api"
                  }
                },
                "components": {
                  "schemas": {
                    "NanoBanana2EditInput": {
                      "type": "object",
                      "required": ["prompt", "image_urls"],
                      "x-fal-order-properties": ["prompt", "image_urls", "num_images", "output_format", "aspect_ratio"],
                      "properties": {
                        "output_format": {
                          "enum": ["png", "jpeg"],
                          "type": "string",
                          "description": "The format of the generated image.",
                          "default": "png",
                          "title": "Output Format"
                        },
                        "prompt": {
                          "description": "The prompt for image editing.",
                          "type": "string",
                          "minLength": 3,
                          "maxLength": 50000,
                          "title": "Prompt"
                        },
                        "image_urls": {
                          "type": "array",
                          "items": { "type": "string" },
                          "description": "The URLs of the images to use for image-to-image generation or image editing.",
                          "title": "Image URLs"
                        },
                        "num_images": {
                          "default": 1,
                          "maximum": 4,
                          "type": "integer",
                          "description": "The number of images to generate.",
                          "minimum": 1,
                          "title": "Number of Images"
                        },
                        "aspect_ratio": {
                          "anyOf": [
                            {
                              "enum": ["auto", "1:1"],
                              "type": "string"
                            },
                            {
                              "type": "null"
                            }
                          ],
                          "default": "auto",
                          "description": "The aspect ratio of the generated image.",
                          "title": "Aspect Ratio"
                        }
                      }
                    },
                    "NanoBanana2EditOutput": {
                      "type": "object",
                      "required": ["images", "description"],
                      "x-fal-order-properties": ["images", "description"],
                      "properties": {
                        "images": {
                          "type": "array",
                          "items": { "$ref": "#/components/schemas/ImageFile" },
                          "description": "The edited images.",
                          "title": "Images"
                        },
                        "description": {
                          "type": "string",
                          "description": "The description of the generated images.",
                          "title": "Description"
                        }
                      }
                    },
                    "ImageFile": {
                      "type": "object",
                      "required": ["url"],
                      "properties": {
                        "url": {
                          "type": "string",
                          "description": "The URL where the file can be downloaded from.",
                          "title": "Url"
                        }
                      },
                      "title": "ImageFile"
                    }
                  }
                },
                "paths": {
                  "/fal-ai/nano-banana-2/edit": {
                    "post": {
                      "requestBody": {
                        "required": true,
                        "content": {
                          "application/json": {
                            "schema": { "$ref": "#/components/schemas/NanoBanana2EditInput" }
                          }
                        }
                      },
                      "responses": {
                        "200": {
                          "description": "The request status."
                        }
                      }
                    }
                  },
                  "/fal-ai/nano-banana-2/edit/requests/{request_id}": {
                    "get": {
                      "responses": {
                        "200": {
                          "description": "Result of the request.",
                          "content": {
                            "application/json": {
                              "schema": { "$ref": "#/components/schemas/NanoBanana2EditOutput" }
                            }
                          }
                        }
                      }
                    }
                  }
                },
                "servers": [
                  { "url": "https://queue.fal.run" }
                ]
              }
            }
          ],
          "next_cursor": "Mg==",
          "has_more": true
        }
        """#.utf8
    )
}

private extension Array where Element == URLQueryItem {
    func value(for name: String) -> String? {
        first { $0.name == name }?.value
    }

    func values(for name: String) -> [String] {
        filter { $0.name == name }.compactMap(\.value)
    }
}
