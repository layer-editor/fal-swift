//
//  FalModelCatalog.swift
//  FalClient
//
//  Created by Chris on 5/19/26.
//

import Foundation

/// Fetches Fal model metadata and optional schema documents from the Fal platform API.
public protocol FalModelCatalog {
    /// Lists models matching the supplied filters.
    func list(
        category: String?,
        status: FalModelStatus?,
        limit: Int?,
        cursor: String?,
        expand: [FalModelExpansion]
    ) async throws -> FalModelPage

    /// Searches models matching the supplied text and filters.
    func search(
        _ query: String,
        category: String?,
        status: FalModelStatus?,
        limit: Int?,
        cursor: String?,
        expand: [FalModelExpansion]
    ) async throws -> FalModelPage

    /// Finds the first model matching an endpoint ID.
    func find(_ endpointId: String, expand: [FalModelExpansion]) async throws -> FalModel?

    /// Finds models matching the supplied endpoint IDs.
    func find(_ endpointIds: [String], expand: [FalModelExpansion]) async throws -> [FalModel]
}

public extension Client {
    /// Accesses Fal platform model discovery APIs.
    var models: FalModelCatalogClient {
        FalModelCatalogClient(client: self)
    }
}

/// A Fal platform model catalog client.
public struct FalModelCatalogClient: FalModelCatalog {
    let client: Client

    public init(client: Client) {
        self.client = client
    }

    public func list(
        category: String? = nil,
        status: FalModelStatus? = nil,
        limit: Int? = nil,
        cursor: String? = nil,
        expand: [FalModelExpansion] = []
    ) async throws -> FalModelPage {
        try await search(
            nil,
            category: category,
            status: status,
            endpointIds: [],
            limit: limit,
            cursor: cursor,
            expand: expand
        )
    }

    public func search(
        _ query: String,
        category: String? = nil,
        status: FalModelStatus? = nil,
        limit: Int? = nil,
        cursor: String? = nil,
        expand: [FalModelExpansion] = []
    ) async throws -> FalModelPage {
        try await search(
            query,
            category: category,
            status: status,
            endpointIds: [],
            limit: limit,
            cursor: cursor,
            expand: expand
        )
    }

    public func find(_ endpointId: String, expand: [FalModelExpansion] = []) async throws -> FalModel? {
        try await find([endpointId], expand: expand).first
    }

    public func find(_ endpointIds: [String], expand: [FalModelExpansion] = []) async throws -> [FalModel] {
        guard !endpointIds.isEmpty else {
            return []
        }

        return try await search(
            nil,
            category: nil,
            status: nil,
            endpointIds: endpointIds,
            limit: nil,
            cursor: nil,
            expand: expand
        ).models
    }

    private func search(
        _ query: String?,
        category: String?,
        status: FalModelStatus?,
        endpointIds: [String],
        limit: Int?,
        cursor: String?,
        expand: [FalModelExpansion]
    ) async throws -> FalModelPage {
        let url = try modelSearchURL(
            query: query,
            category: category,
            status: status,
            endpointIds: endpointIds,
            limit: limit,
            cursor: cursor,
            expand: expand
        )
        let data = try await client.sendRequest(
            to: url,
            input: nil as Data?,
            options: .withMethod(.get)
        )
        return try JSONDecoder().decode(FalModelPage.self, from: data)
    }
}

/// Optional expansions for Fal model search responses.
public struct FalModelExpansion: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    /// Includes the model's OpenAPI 3.0 queue schema document.
    public static let openAPI = FalModelExpansion(rawValue: "openapi-3.0")
    /// Includes enterprise availability metadata when returned by the API.
    public static let enterpriseStatus = FalModelExpansion(rawValue: "enterprise_status")

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A page of Fal model search results.
public struct FalModelPage: Decodable, Equatable, Sendable {
    public let models: [FalModel]
    public let nextCursor: String?
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case models
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

/// A model listed by Fal's platform model search API.
public struct FalModel: Decodable, Equatable, Sendable {
    public let endpointId: String
    public let metadata: FalModelMetadata
    public let openapi: Payload?
    public let enterpriseStatus: String?

    enum CodingKeys: String, CodingKey {
        case endpointId = "endpoint_id"
        case metadata
        case openapi
        case enterpriseStatus = "enterprise_status"
    }

    /// The queue input and output schema extracted from the model's OpenAPI document, when expanded.
    public var queueSchema: FalModelQueueSchema? {
        FalModelQueueSchema(openAPI: openapi)
    }

    /// Practical input/output capabilities inferred from metadata and the expanded schema.
    public var inferredCapabilities: FalModelCapabilities {
        FalModelCapabilities(model: self)
    }
}

/// Metadata attached to a Fal model listing.
public struct FalModelMetadata: Decodable, Equatable, Sendable {
    public let displayName: String?
    public let category: String?
    public let description: String?
    public let status: FalModelStatus?
    public let tags: [String]
    public let updatedAt: String?
    public let isFavorited: Bool?
    public let thumbnailUrl: String?
    public let modelUrl: String?
    public let licenseType: String?
    public let date: String?
    public let group: FalModelGroup?
    public let highlighted: Bool?
    public let kind: String?
    public let pinned: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case category
        case description
        case status
        case tags
        case updatedAt = "updated_at"
        case isFavorited = "is_favorited"
        case thumbnailUrl = "thumbnail_url"
        case modelUrl = "model_url"
        case licenseType = "license_type"
        case date
        case group
        case highlighted
        case kind
        case pinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decodeIfPresent(FalModelStatus.self, forKey: .status)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        isFavorited = try container.decodeIfPresent(Bool.self, forKey: .isFavorited)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        modelUrl = try container.decodeIfPresent(String.self, forKey: .modelUrl)
        licenseType = try container.decodeIfPresent(String.self, forKey: .licenseType)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        group = try container.decodeIfPresent(FalModelGroup.self, forKey: .group)
        highlighted = try container.decodeIfPresent(Bool.self, forKey: .highlighted)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned)
    }
}

/// A model group supplied by Fal metadata.
public struct FalModelGroup: Decodable, Equatable, Sendable {
    public let key: String?
    public let label: String?
}

/// A model status supplied by Fal metadata.
public enum FalModelStatus: Equatable, Sendable {
    case active
    case deprecated
    case comingSoon
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .active:
            return "active"
        case .deprecated:
            return "deprecated"
        case .comingSoon:
            return "coming-soon"
        case let .unknown(value):
            return value
        }
    }
}

extension FalModelStatus: Decodable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "active":
            self = .active
        case "deprecated":
            self = .deprecated
        case "coming-soon":
            self = .comingSoon
        default:
            self = .unknown(value)
        }
    }
}

/// Practical model capabilities inferred for dynamic Apple-client routing and playgrounds.
public struct FalModelCapabilities: Equatable, Sendable {
    public let task: FalModelTask?
    public let inputKinds: Set<FalModelIOKind>
    public let outputKinds: Set<FalModelIOKind>
    public let supportsQueue: Bool

    init(model: FalModel) {
        let schema = model.queueSchema
        let schemaInputKinds = schema?.input?.ioKinds ?? []
        let schemaOutputKinds = schema?.output?.ioKinds ?? []
        let categoryKinds = FalModelCapabilities.kinds(fromCategory: model.metadata.category)
        let inputKinds = schemaInputKinds.isEmpty ? categoryKinds.input : schemaInputKinds
        let outputKinds = schemaOutputKinds.isEmpty ? categoryKinds.output : schemaOutputKinds

        self.inputKinds = inputKinds
        self.outputKinds = outputKinds
        self.supportsQueue = schema?.supportsQueue ?? false
        self.task = FalModelTask(inputKinds: inputKinds, outputKinds: outputKinds, outputSchema: schema?.output)
            ?? FalModelTask(category: model.metadata.category)
    }

    private static func kinds(fromCategory category: String?) -> (input: Set<FalModelIOKind>, output: Set<FalModelIOKind>) {
        guard let category,
              let separatorRange = category.range(of: "-to-")
        else {
            return ([], [])
        }
        let input = String(category[..<separatorRange.lowerBound])
        let output = String(category[separatorRange.upperBound...])
        return (kinds(fromCategoryComponent: input), kinds(fromCategoryComponent: output))
    }

    private static func kinds(fromCategoryComponent component: String) -> Set<FalModelIOKind> {
        switch component {
        case "text":
            return [.text]
        case "image":
            return [.image]
        case "video":
            return [.video]
        case "audio":
            return [.audio]
        case "file":
            return [.file]
        default:
            return []
        }
    }
}

/// A broad input or output media kind for a model.
public enum FalModelIOKind: String, Equatable, Hashable, Sendable {
    case text
    case image
    case video
    case audio
    case file
    case threeD
    case json
}

/// A common model task shape inferred from model metadata and schemas.
public enum FalModelTask: String, Equatable, Sendable {
    case textToImage
    case textToImages
    case imageToImage
    case imageToImages
    case textToVideo
    case imageToVideo
    case textToAudio
    case audioToText
    case textToText
    case multimodal
}

/// A queue request/response schema extracted from a model's OpenAPI document.
public struct FalModelQueueSchema: Equatable, Sendable {
    public let input: FalModelObjectSchema?
    public let output: FalModelObjectSchema?
    public let supportsQueue: Bool

    init?(openAPI: Payload?) {
        guard let openAPI else {
            return nil
        }

        let resolver = OpenAPISchemaResolver(document: openAPI)
        input = resolver.queueInputSchema()
        output = resolver.queueOutputSchema()
        supportsQueue = resolver.supportsQueue()

        guard input != nil || output != nil || supportsQueue else {
            return nil
        }
    }
}

/// An object schema suitable for building dynamic playground forms or result summaries.
public struct FalModelObjectSchema: Equatable, Sendable {
    public let title: String?
    public let fields: [FalModelField]

    var ioKinds: Set<FalModelIOKind> {
        Set(fields.compactMap(\.kind.ioKind))
    }
}

/// A model input or output field extracted from an OpenAPI schema.
public struct FalModelField: Equatable, Sendable {
    public let name: String
    public let title: String?
    public let description: String?
    public let kind: FalModelSchemaKind
    public let isRequired: Bool
    public let allowedValues: [String]
    public let defaultValue: Payload?
    public let examples: [Payload]
    public let minimum: Double?
    public let maximum: Double?
}

/// A playground-friendly schema field kind.
public enum FalModelSchemaKind: Equatable, Sendable {
    case text
    case image
    case images
    case video
    case videos
    case audio
    case audios
    case file
    case files
    case string
    case integer
    case number
    case boolean
    case object
    case array
    case null
    case json
    case unknown(String)

    var ioKind: FalModelIOKind? {
        switch self {
        case .text:
            return .text
        case .image, .images:
            return .image
        case .video, .videos:
            return .video
        case .audio, .audios:
            return .audio
        case .file, .files:
            return .file
        case .object, .array, .json:
            return .json
        default:
            return nil
        }
    }
}

private func modelSearchURL(
    query: String?,
    category: String?,
    status: FalModelStatus?,
    endpointIds: [String],
    limit: Int?,
    cursor: String?,
    expand: [FalModelExpansion]
) throws -> String {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "api.fal.ai"
    components.path = "/v1/models"

    var queryItems: [URLQueryItem] = []
    query.map { queryItems.append(URLQueryItem(name: "q", value: $0)) }
    category.map { queryItems.append(URLQueryItem(name: "category", value: $0)) }
    status.map { queryItems.append(URLQueryItem(name: "status", value: $0.rawValue)) }
    limit.map { queryItems.append(URLQueryItem(name: "limit", value: String($0))) }
    cursor.map { queryItems.append(URLQueryItem(name: "cursor", value: $0)) }
    queryItems += endpointIds.map { URLQueryItem(name: "endpoint_id", value: $0) }
    queryItems += expand.map { URLQueryItem(name: "expand", value: $0.rawValue) }
    components.queryItems = queryItems.isEmpty ? nil : queryItems

    guard let url = components.url else {
        throw FalError.invalidUrl(url: "https://api.fal.ai/v1/models")
    }
    return url.absoluteString
}

private struct OpenAPISchemaResolver {
    let document: Payload

    func queueInputSchema() -> FalModelObjectSchema? {
        guard let schema = queueInputSchemaPayload() else {
            return nil
        }
        return objectSchema(from: schema)
    }

    func queueOutputSchema() -> FalModelObjectSchema? {
        guard let schema = queueOutputSchemaPayload() else {
            return nil
        }
        return objectSchema(from: schema)
    }

    func supportsQueue() -> Bool {
        let hasQueuePaths = document["paths"].object?.keys.contains { $0.contains("/requests/{request_id}") } == true
        let hasQueueServer = document["servers"].array?.contains {
            $0["url"].stringValue?.contains("queue.fal.run") == true
        } == true
        return hasQueuePaths || hasQueueServer
    }

    private func queueInputSchemaPayload() -> Payload? {
        guard let paths = document["paths"].object else {
            return nil
        }
        for path in paths.keys.sorted() {
            guard let post = paths[path]?["post"],
                  post["requestBody"] != .nilValue
            else {
                continue
            }
            let schema = post["requestBody"]["content"]["application/json"]["schema"]
            if let resolved = resolve(schema) {
                return resolved
            }
        }
        return nil
    }

    private func queueOutputSchemaPayload() -> Payload? {
        guard let paths = document["paths"].object else {
            return nil
        }
        for path in paths.keys.sorted() where path.contains("/requests/{request_id}")
            && !path.contains("/status")
            && !path.contains("/cancel")
        {
            guard let get = paths[path]?["get"] else {
                continue
            }
            let schema = get["responses"]["200"]["content"]["application/json"]["schema"]
            if let resolved = resolve(schema) {
                return resolved
            }
        }
        return nil
    }

    private func objectSchema(from schema: Payload) -> FalModelObjectSchema? {
        guard let properties = schema["properties"].object else {
            return nil
        }

        let required = Set(schema["required"].array?.compactMap(\.stringValue) ?? [])
        let orderedNames = orderedPropertyNames(in: schema, properties: properties)
        let fields = orderedNames.compactMap { name -> FalModelField? in
            guard let property = properties[name] else {
                return nil
            }
            let resolved = resolve(property) ?? property
            return FalModelField(
                name: name,
                title: resolved["title"].stringValue,
                description: resolved["description"].stringValue,
                kind: schemaKind(name: name, schema: resolved),
                isRequired: required.contains(name),
                allowedValues: resolved["enum"].array?.compactMap(\.stringValue) ?? [],
                defaultValue: resolved.value(forKey: "default"),
                examples: resolved["examples"].array ?? [],
                minimum: resolved["minimum"].doubleValue,
                maximum: resolved["maximum"].doubleValue
            )
        }

        return FalModelObjectSchema(title: schema["title"].stringValue, fields: fields)
    }

    private func orderedPropertyNames(in schema: Payload, properties: [String: Payload]) -> [String] {
        let preferred = schema["x-fal-order-properties"].array?.compactMap(\.stringValue) ?? []
        let preferredSet = Set(preferred)
        let remaining = properties.keys.filter { !preferredSet.contains($0) }.sorted()
        return preferred.filter { properties[$0] != nil } + remaining
    }

    private func resolve(_ schema: Payload) -> Payload? {
        if let ref = schema["$ref"].stringValue {
            return resolve(ref)
        }

        if let options = schema["anyOf"].array ?? schema["oneOf"].array {
            for option in options {
                if option["type"].stringValue != "null",
                   let resolved = resolve(option) ?? option.nilToOptional
                {
                    return resolved.mergingMissingMetadata(from: schema)
                }
            }
        }

        return schema.nilToOptional
    }

    private func resolve(_ ref: String) -> Payload? {
        let prefix = "#/components/schemas/"
        guard ref.hasPrefix(prefix) else {
            return nil
        }
        let name = String(ref.dropFirst(prefix.count))
        return document["components"]["schemas"][name].nilToOptional
    }

    private func schemaKind(name: String, schema: Payload) -> FalModelSchemaKind {
        let normalizedName = name.lowercased()
        let type = schema["type"].stringValue
        let title = schema["title"].stringValue?.lowercased() ?? ""
        let description = schema["description"].stringValue?.lowercased() ?? ""
        let mediaContext = [normalizedName, title, description].joined(separator: " ")

        if type == "array" {
            let item = resolve(schema["items"]) ?? schema["items"]
            if isImage(name: normalizedName, schema: item) {
                return .images
            }
            if isVideo(name: normalizedName, schema: item) {
                return .videos
            }
            if isAudio(name: normalizedName, schema: item) {
                return .audios
            }
            if isFile(name: normalizedName, schema: item, context: mediaContext) {
                return .files
            }
            return .array
        }

        if isText(name: normalizedName, schema: schema, context: mediaContext) {
            return .text
        }

        switch type {
        case "integer":
            return .integer
        case "number":
            return .number
        case "boolean":
            return .boolean
        default:
            break
        }

        if isImage(name: normalizedName, schema: schema) {
            return .image
        }
        if isVideo(name: normalizedName, schema: schema) {
            return .video
        }
        if isAudio(name: normalizedName, schema: schema) {
            return .audio
        }
        if isFile(name: normalizedName, schema: schema, context: mediaContext) {
            return .file
        }

        switch type {
        case "string":
            return .string
        case "object":
            return .object
        case "null":
            return .null
        case let type?:
            return .unknown(type)
        default:
            return .json
        }
    }

    private func isText(name: String, schema: Payload, context: String) -> Bool {
        guard schema["type"].stringValue == "string" else {
            return false
        }
        return name == "prompt"
            || name == "negative_prompt"
            || name == "system_prompt"
            || name.hasSuffix("_prompt")
            || context.contains("prompt")
            || context.contains("text")
    }

    private func isImage(name: String, schema: Payload) -> Bool {
        isMedia(name: name, schema: schema, singular: "image", fileSchema: "ImageFile")
    }

    private func isVideo(name: String, schema: Payload) -> Bool {
        isMedia(name: name, schema: schema, singular: "video", fileSchema: "VideoFile")
    }

    private func isAudio(name: String, schema: Payload) -> Bool {
        isMedia(name: name, schema: schema, singular: "audio", fileSchema: "AudioFile")
    }

    private func isFile(name: String, schema: Payload, context: String) -> Bool {
        if let title = schema["title"].stringValue, title == "File" || title.hasSuffix("File") {
            return true
        }
        return name == "file" || name == "files" || name.hasSuffix("_file") || name.hasSuffix("_files") || context.contains(" file")
    }

    private func isMedia(name: String, schema: Payload, singular: String, fileSchema: String) -> Bool {
        if let title = schema["title"].stringValue, title == fileSchema || title.lowercased().contains(singular) {
            return true
        }
        return name == singular
            || name == "\(singular)s"
            || name == "\(singular)_url"
            || name == "\(singular)_urls"
            || name.hasSuffix("_\(singular)")
            || name.hasSuffix("_\(singular)s")
            || name.hasSuffix("_\(singular)_url")
            || name.hasSuffix("_\(singular)_urls")
    }
}

private extension FalModelTask {
    init?(inputKinds: Set<FalModelIOKind>, outputKinds: Set<FalModelIOKind>, outputSchema: FalModelObjectSchema?) {
        let outputsMultipleImages = outputSchema?.fields.contains { $0.kind == .images } == true
        switch (inputKinds.contains(.text), inputKinds.contains(.image), outputKinds.contains(.image), outputKinds.contains(.video), outputKinds.contains(.audio), outputKinds.contains(.text)) {
        case (true, false, true, false, false, false):
            self = outputsMultipleImages ? .textToImages : .textToImage
        case (true, true, true, false, false, false), (false, true, true, false, false, false):
            self = outputsMultipleImages ? .imageToImages : .imageToImage
        case (true, false, false, true, false, false):
            self = .textToVideo
        case (_, true, false, true, false, false):
            self = .imageToVideo
        case (true, false, false, false, true, false):
            self = .textToAudio
        case (false, false, false, false, false, true) where inputKinds.contains(.audio):
            self = .audioToText
        case (true, false, false, false, false, true):
            self = .textToText
        case _ where inputKinds.count > 1 || outputKinds.count > 1:
            self = .multimodal
        default:
            return nil
        }
    }

    init?(category: String?) {
        switch category {
        case "text-to-image":
            self = .textToImage
        case "image-to-image":
            self = .imageToImage
        case "text-to-video":
            self = .textToVideo
        case "image-to-video":
            self = .imageToVideo
        case "text-to-audio":
            self = .textToAudio
        case "audio-to-text":
            self = .audioToText
        case "text-to-text":
            self = .textToText
        default:
            return nil
        }
    }
}

private extension Payload {
    var object: [String: Payload]? {
        guard case let .dict(value) = self else {
            return nil
        }
        return value
    }

    var array: [Payload]? {
        guard case let .array(value) = self else {
            return nil
        }
        return value
    }

    var doubleValue: Double? {
        switch self {
        case let .double(value):
            return value
        case let .int(value):
            return Double(value)
        default:
            return nil
        }
    }

    var nilToOptional: Payload? {
        self == .nilValue ? nil : self
    }

    func value(forKey key: String) -> Payload? {
        guard case let .dict(value) = self else {
            return nil
        }
        return value[key]
    }

    func mergingMissingMetadata(from parent: Payload) -> Payload {
        guard case var .dict(childObject) = self,
              case let .dict(parentObject) = parent
        else {
            return self
        }

        for (key, value) in parentObject where childObject[key] == nil && !key.isCompositionKey {
            childObject[key] = value
        }
        return .dict(childObject)
    }
}

private extension String {
    var isCompositionKey: Bool {
        self == "anyOf" || self == "oneOf" || self == "allOf" || self == "$ref"
    }
}
