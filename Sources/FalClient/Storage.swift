import Foundation

public enum FileType {
    case custom(String)

    public static var imagePng: Self { .custom("image/png") }
    public static var imageJpeg: Self { .custom("image/jpeg") }
    public static var imageWebp: Self { .custom("image/webp") }
    public static var imageGif: Self { .custom("image/gif") }
    public static var videoMp4: Self { .custom("video/mp4") }
    public static var videoMpeg: Self { .custom("video/mpeg") }
    public static var audioMp3: Self { .custom("audio/mp3") }
    public static var audioMpeg: Self { .custom("audio/mpeg") }
    public static var audioWav: Self { .custom("audio/wav") }
    public static var audioOgg: Self { .custom("audio/ogg") }
    public static var audioWebm: Self { .custom("audio/webm") }
    public static var applicationStream: Self { .custom("application/octet-stream") }

    public var mimeType: String {
        switch self {
        case let .custom(type):
            return type
        }
    }

    public var fileExtension: String {
        guard case let .custom(type) = self else {
            return "bin"
        }
        if type == FileType.applicationStream.mimeType {
            return "bin"
        }
        return String(type.split(separator: "/").last ?? "bin")
    }
}

/// Upload backends supported by the storage client.
public struct StorageUploadRepository: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case falCDNV3PresignedURL
        case directFalCDNV3
        case directFalMedia
    }

    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    /// The existing REST initiate flow that returns a presigned upload URL for Fal CDN v3 storage.
    public static let falCDNV3PresignedURL = StorageUploadRepository(kind: .falCDNV3PresignedURL)

    /// Direct Fal CDN v3 upload using a short-lived CDN token from fal's REST API.
    public static let directFalCDNV3 = StorageUploadRepository(kind: .directFalCDNV3)

    /// Direct upload to the `fal.media` fallback endpoint.
    public static let directFalMedia = StorageUploadRepository(kind: .directFalMedia)
}

/// Controls automatic multipart storage uploads.
public struct StorageMultipartUploadOptions: Equatable, Sendable {
    public static let defaultThresholdBytes = 100 * 1024 * 1024
    public static let defaultChunkSizeBytes = 10 * 1024 * 1024

    /// Default multipart behavior: use 10 MB chunks for uploads larger than 100 MB.
    public static let automatic = StorageMultipartUploadOptions()

    /// Disables multipart uploads.
    public static let disabled = StorageMultipartUploadOptions(
        isEnabled: false,
        thresholdBytes: defaultThresholdBytes,
        chunkSizeBytes: defaultChunkSizeBytes
    )

    /// Whether multipart uploads are enabled.
    public let isEnabled: Bool

    /// Minimum data size that should use multipart upload.
    public let thresholdBytes: Int

    /// Size of each multipart chunk.
    public let chunkSizeBytes: Int

    /// Creates multipart upload options.
    /// - Parameters:
    ///   - thresholdBytes: Minimum data size that should use multipart upload.
    ///   - chunkSizeBytes: Size of each multipart chunk.
    public init(
        thresholdBytes: Int = defaultThresholdBytes,
        chunkSizeBytes: Int = defaultChunkSizeBytes
    ) {
        self.isEnabled = true
        self.thresholdBytes = thresholdBytes
        self.chunkSizeBytes = chunkSizeBytes
    }

    private init(isEnabled: Bool, thresholdBytes: Int, chunkSizeBytes: Int) {
        self.isEnabled = isEnabled
        self.thresholdBytes = thresholdBytes
        self.chunkSizeBytes = chunkSizeBytes
    }
}

/// Options that customize a storage upload.
public struct StorageUploadOptions: Equatable, Sendable {
    /// Preferred primary upload backend for this package.
    public static let defaultRepository: StorageUploadRepository = .directFalCDNV3

    /// Preferred fallback upload backends, in order.
    public static let defaultFallbackRepositories: [StorageUploadRepository] = [
        .directFalMedia,
        .falCDNV3PresignedURL,
    ]

    /// Preferred modern Fal CDN upload behavior.
    public static let preferredFalCDN = StorageUploadOptions()

    /// Legacy REST presigned URL upload behavior.
    public static let presignedFalCDNV3 = StorageUploadOptions(
        repository: .falCDNV3PresignedURL,
        fallbackRepositories: []
    )

    /// File name sent to fal as upload metadata.
    ///
    /// This value may be visible in storage metadata or generated URLs. Only
    /// the final path component is used.
    public let fileName: String?

    /// CDN lifecycle preference for the uploaded file.
    public let objectLifecyclePreference: FalObjectLifecyclePreference?

    /// Primary upload backend.
    public let repository: StorageUploadRepository

    /// Upload backends to try if the primary backend fails with a transient error.
    public let fallbackRepositories: [StorageUploadRepository]

    /// Multipart behavior for repositories that support multipart uploads.
    public let multipartUpload: StorageMultipartUploadOptions

    /// Creates storage upload options.
    /// - Parameters:
    ///   - fileName: File name sent to fal as upload metadata.
    ///   - objectLifecyclePreference: CDN lifecycle preference for the uploaded file.
    ///   - repository: Primary upload backend.
    ///   - fallbackRepositories: Upload backends to try if the primary backend fails with a transient error.
    ///   - multipartUpload: Multipart behavior for repositories that support multipart uploads.
    public init(
        fileName: String? = nil,
        objectLifecyclePreference: FalObjectLifecyclePreference? = nil,
        repository: StorageUploadRepository = StorageUploadOptions.defaultRepository,
        fallbackRepositories: [StorageUploadRepository]? = nil,
        multipartUpload: StorageMultipartUploadOptions = .automatic
    ) {
        self.fileName = fileName
        self.objectLifecyclePreference = objectLifecyclePreference
        self.repository = repository
        self.fallbackRepositories = fallbackRepositories ?? Self.defaultFallbackRepositories(for: repository)
        self.multipartUpload = multipartUpload
    }

    private static func defaultFallbackRepositories(for repository: StorageUploadRepository) -> [StorageUploadRepository] {
        repository == defaultRepository ? defaultFallbackRepositories : []
    }
}

/// This establishes the contract of the client with the storage API. The storage API is used
/// to upload files to the fal.ai storage so model APIs can access the files when needed.
///
/// This allows for a decoupled architecture where the model API does not need to worry about
/// file handling and can always rely on a valid URL to read files from.
public protocol Storage {
    var client: Client { get }

    /// Uploads the given `data` to the fal.ai storage and returns the URL of the uploaded file.
    func upload(data: Data, ofType type: FileType) async throws -> String

    /// Uploads the given `data` with additional metadata and returns the URL of the uploaded file.
    func upload(data: Data, ofType type: FileType, options: StorageUploadOptions) async throws -> String
}

public extension Storage {
    func upload(data: Data, ofType type: FileType = .applicationStream) async throws -> String {
        return try await upload(data: data, ofType: type)
    }

    /// Uploads data with additional upload metadata.
    ///
    /// Custom `Storage` conformers that only implement `upload(data:ofType:)`
    /// remain source-compatible. Those conformers accept empty options and
    /// reject non-empty options unless they implement this overload.
    func upload(
        data: Data,
        ofType type: FileType = .applicationStream,
        options: StorageUploadOptions
    ) async throws -> String {
        guard options == .init() else {
            throw FalError.unsupportedOperation(
                message: "The active Storage implementation does not support upload options."
            )
        }
        return try await upload(data: data, ofType: type)
    }

    func autoUpload(input: Payload) async throws -> Payload {
        switch input {
        case let .data(data):
            return try await .string(upload(data: data))
        case let .array(array):
            var transformedValues: [Payload] = []
            transformedValues.reserveCapacity(array.count)
            for value in array {
                transformedValues.append(try await autoUpload(input: value))
            }
            return .array(transformedValues)
        case let .dict(dict):
            var transformedValues: [String: Payload] = [:]
            transformedValues.reserveCapacity(dict.count)
            for (key, value) in dict {
                transformedValues[key] = try await autoUpload(input: value)
            }
            return .dict(transformedValues)
        default:
            return input
        }
    }
}

struct UploadUrl: Codable {
    let fileUrl: String
    let uploadUrl: String

    enum CodingKeys: String, CodingKey {
        case fileUrl = "file_url"
        case uploadUrl = "upload_url"
    }
}

struct StorageCDNToken: Codable {
    let token: String
    let tokenType: String
    let baseURL: String

    enum CodingKeys: String, CodingKey {
        case token
        case tokenType = "token_type"
        case baseURL = "base_url"
    }
}

struct DirectStorageUploadResponse: Codable {
    let accessURL: String

    enum CodingKeys: String, CodingKey {
        case accessURL = "access_url"
    }
}

struct MultipartStorageUploadResponse: Codable {
    let accessURL: String
    let uploadID: String

    enum CodingKeys: String, CodingKey {
        case accessURL = "access_url"
        case uploadID = "uploadId"
    }
}

struct MultipartStorageUploadPart: Encodable {
    let partNumber: Int
    let etag: String
}

struct CompleteMultipartStorageUploadRequest: Encodable {
    let parts: [MultipartStorageUploadPart]
}

struct StorageClient: Storage {
    let client: Client

    func initiateUpload(
        data _: Data,
        ofType type: FileType,
        options: StorageUploadOptions
    ) async throws -> UploadUrl {
        let input: Payload = [
            "content_type": .string(type.mimeType),
            "file_name": .string(options.normalizedFileName(for: type)),
        ]
        var requestOptions = RunOptions.withMethod(.post)
        if let objectLifecyclePreference = options.objectLifecyclePreference {
            let lifecycleHeader = try objectLifecyclePreference.headerValue()
            requestOptions = RunOptions(
                httpMethod: .post,
                headers: [
                    "X-Fal-Object-Lifecycle": lifecycleHeader,
                ]
            )
        }
        let response = try await client.sendRequest(
            to: "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3",
            input: input.json(),
            options: requestOptions
        )
        return try JSONDecoder().decode(UploadUrl.self, from: response)
    }

    func upload(data: Data, ofType type: FileType) async throws -> String {
        try await upload(data: data, ofType: type, options: .init())
    }

    func upload(data: Data, ofType type: FileType, options: StorageUploadOptions) async throws -> String {
        if let objectLifecyclePreference = options.objectLifecyclePreference {
            _ = try objectLifecyclePreference.headerValue()
        }
        let repositories = try effectiveRepositoryChain(for: options)
        var lastError: Error?
        for repository in repositories {
            do {
                return try await upload(data: data, ofType: type, options: options, repository: repository)
            } catch let terminalError as TerminalStorageUploadError {
                throw terminalError.underlying
            } catch {
                guard shouldFallbackAfterStorageUploadError(error),
                      repository != repositories.last
                else {
                    throw error
                }
                lastError = error
            }
        }
        throw lastError ?? FalError.invalidResultFormat
    }

    private func effectiveRepositoryChain(for options: StorageUploadOptions) throws -> [StorageUploadRepository] {
        var repositories: [StorageUploadRepository] = []
        for (index, repository) in options.repositoryChain.enumerated() {
            guard repository.kind == .directFalMedia else {
                repositories.append(repository)
                continue
            }
            if client.config.requestProxy != nil {
                if index == 0 {
                    throw FalError.unsupportedInput(
                        message: "Direct fal.media uploads are unavailable when requestProxy is configured."
                    )
                }
                continue
            }
            if !client.canAuthorizeDirectFalMediaUpload {
                if index == 0 {
                    repositories.append(repository)
                }
                continue
            }
            repositories.append(repository)
        }
        guard !repositories.isEmpty else {
            throw FalError.unsupportedInput(
                message: "No supported storage upload repositories are available for the current client configuration."
            )
        }
        return repositories
    }

    private func upload(
        data: Data,
        ofType type: FileType,
        options: StorageUploadOptions,
        repository: StorageUploadRepository
    ) async throws -> String {
        switch repository.kind {
        case .falCDNV3PresignedURL:
            return try await uploadUsingPresignedURL(data: data, ofType: type, options: options)
        case .directFalCDNV3:
            return try await uploadDirectlyToFalCDNV3(data: data, ofType: type, options: options)
        case .directFalMedia:
            return try await uploadDirectlyToFalMedia(data: data, ofType: type, options: options)
        }
    }

    private func uploadUsingPresignedURL(data: Data, ofType type: FileType, options: StorageUploadOptions) async throws -> String {
        let uploadUrl = try await initiateUpload(data: data, ofType: type, options: options)
        guard let url = URL.safeFalStorageUploadURL(from: uploadUrl.uploadUrl) else {
            throw FalError.invalidUrl(url: uploadUrl.uploadUrl.redactedURLForDescription)
        }
        guard URL.safeFalStorageFileURL(from: uploadUrl.fileUrl) != nil else {
            throw FalError.invalidUrl(url: uploadUrl.fileUrl.redactedURLForDescription)
        }

        // Upload the file to the upload URL.
        // Here we use URLSession directly instead of the client to avoid going
        // through the proxy, we need to hit the blob url directly.
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(type.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")

        try await retrying(policy: .transientRequest) {
            let transportResponse = try await client.resolvedHTTPTransport.data(
                for: request,
                validatingRedirectsWith: { URL.safeFalStorageUploadURL($0) }
            )
            try client.checkResponseStatus(for: transportResponse.response, withData: transportResponse.data)
        }

        return uploadUrl.fileUrl
    }

    private func uploadDirectlyToFalMedia(data: Data, ofType type: FileType, options: StorageUploadOptions) async throws -> String {
        let fileName = options.normalizedFileName(for: type)
        let uploadUrlString = "https://fal.media/files/upload"
        guard let url = URL.safeFalDirectMediaUploadURL(from: uploadUrlString) else {
            throw FalError.invalidUrl(url: uploadUrlString.redactedURLForDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(try client.falMediaAuthorizationHeader(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(type.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue(fileName, forHTTPHeaderField: "X-Fal-File-Name")
        if let objectLifecyclePreference = options.objectLifecyclePreference {
            let lifecycleHeader = try objectLifecyclePreference.headerValue()
            request.setValue(lifecycleHeader, forHTTPHeaderField: "X-Fal-Object-Lifecycle")
            request.setValue(lifecycleHeader, forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference")
        }

        let response = try await client.resolvedHTTPTransport.data(
            for: request,
            validatingRedirectsWith: { URL.safeFalDirectMediaUploadURL($0) }
        )
        try client.checkResponseStatus(for: response.response, withData: response.data)
        let uploadResponse = try JSONDecoder().decode(DirectStorageUploadResponse.self, from: response.data)
        guard URL.safeFalStorageFileURL(from: uploadResponse.accessURL) != nil else {
            throw FalError.invalidUrl(url: uploadResponse.accessURL.redactedURLForDescription)
        }
        return uploadResponse.accessURL
    }

    private func uploadDirectlyToFalCDNV3(data: Data, ofType type: FileType, options: StorageUploadOptions) async throws -> String {
        try options.multipartUpload.validate()
        if options.multipartUpload.shouldUploadUsingMultipart(dataByteCount: data.count) {
            return try await uploadMultipartDirectlyToFalCDNV3(data: data, ofType: type, options: options)
        }
        let token = try await fetchCDNToken()
        let fileName = options.normalizedFileName(for: type)
        let uploadUrlString = "\(token.baseURL.trimmingSuffix("/"))/files/upload"
        guard let url = URL.safeFalDirectCDNV3UploadURL(from: uploadUrlString) else {
            throw FalError.invalidUrl(url: uploadUrlString.redactedURLForDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(type.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        setCDNAuthorizationHeader(on: &request, token: token)
        request.setValue(fileName, forHTTPHeaderField: "X-Fal-File-Name")
        if let objectLifecyclePreference = options.objectLifecyclePreference {
            let lifecycleHeader = try objectLifecyclePreference.headerValue()
            request.setValue(lifecycleHeader, forHTTPHeaderField: "X-Fal-Object-Lifecycle")
            request.setValue(lifecycleHeader, forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference")
        }

        let response = try await client.resolvedHTTPTransport.data(
            for: request,
            validatingRedirectsWith: { URL.safeFalDirectCDNV3UploadURL($0) }
        )
        try client.checkResponseStatus(for: response.response, withData: response.data)
        let uploadResponse = try JSONDecoder().decode(DirectStorageUploadResponse.self, from: response.data)
        guard URL.safeFalStorageFileURL(from: uploadResponse.accessURL) != nil else {
            throw FalError.invalidUrl(url: uploadResponse.accessURL.redactedURLForDescription)
        }
        return uploadResponse.accessURL
    }

    private func uploadMultipartDirectlyToFalCDNV3(data: Data, ofType type: FileType, options: StorageUploadOptions) async throws -> String {
        let token = try await fetchCDNToken()
        let fileName = options.normalizedFileName(for: type)
        let upload = try await createMultipartUpload(token: token, fileName: fileName, type: type, options: options)

        do {
            var parts: [MultipartStorageUploadPart] = []
            var partNumber = 1
            var chunkStart = data.startIndex
            while chunkStart < data.endIndex {
                let chunkEnd = Swift.min(chunkStart + options.multipartUpload.chunkSizeBytes, data.endIndex)
                let chunk = data[chunkStart ..< chunkEnd]
                let etag = try await uploadMultipartPart(
                    chunk,
                    partNumber: partNumber,
                    upload: upload,
                    token: token,
                    type: type
                )
                parts.append(MultipartStorageUploadPart(partNumber: partNumber, etag: etag))
                partNumber += 1
                chunkStart = chunkEnd
            }
            try await completeMultipartUpload(upload: upload, token: token, parts: parts)
            return upload.accessURL
        } catch {
            throw TerminalStorageUploadError(underlying: error)
        }
    }

    private func createMultipartUpload(
        token: StorageCDNToken,
        fileName: String,
        type: FileType,
        options: StorageUploadOptions
    ) async throws -> MultipartStorageUploadResponse {
        let uploadUrlString = "\(token.baseURL.trimmingSuffix("/"))/files/upload/multipart"
        guard let url = URL.safeFalDirectCDNV3UploadURL(from: uploadUrlString) else {
            throw FalError.invalidUrl(url: uploadUrlString.redactedURLForDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        setCDNAuthorizationHeader(on: &request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(type.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(fileName, forHTTPHeaderField: "X-Fal-File-Name")
        if let objectLifecyclePreference = options.objectLifecyclePreference {
            let lifecycleHeader = try objectLifecyclePreference.headerValue()
            request.setValue(lifecycleHeader, forHTTPHeaderField: "X-Fal-Object-Lifecycle")
            request.setValue(lifecycleHeader, forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference")
        }

        let response = try await client.resolvedHTTPTransport.data(
            for: request,
            validatingRedirectsWith: { URL.safeFalDirectCDNV3UploadURL($0) }
        )
        try client.checkResponseStatus(for: response.response, withData: response.data)
        let upload = try JSONDecoder().decode(MultipartStorageUploadResponse.self, from: response.data)
        guard URL.safeFalStorageFileURL(from: upload.accessURL) != nil else {
            throw FalError.invalidUrl(url: upload.accessURL.redactedURLForDescription)
        }
        return upload
    }

    private func uploadMultipartPart(
        _ data: Data,
        partNumber: Int,
        upload: MultipartStorageUploadResponse,
        token: StorageCDNToken,
        type: FileType
    ) async throws -> String {
        let uploadUrlString = "\(upload.accessURL.trimmingSuffix("/"))/multipart/\(upload.uploadID)/\(partNumber)"
        guard let url = URL.safeFalDirectCDNV3UploadURL(from: uploadUrlString) else {
            throw FalError.invalidUrl(url: uploadUrlString.redactedURLForDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        setCDNAuthorizationHeader(on: &request, token: token)
        request.setValue(type.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        let response = try await retrying(policy: .transientRequest) {
            let response = try await client.resolvedHTTPTransport.data(
                for: request,
                validatingRedirectsWith: { URL.safeFalDirectCDNV3UploadURL($0) }
            )
            do {
                try client.checkResponseStatus(for: response.response, withData: response.data)
            } catch let falError as FalError {
                throw TransientStorageUploadError.nonTerminal(falError)
            }
            return response
        }
        guard let httpResponse = response.response as? HTTPURLResponse,
              let etag = httpResponse.headerValue(named: "etag")
        else {
            throw FalError.invalidResultFormat
        }
        return etag
    }

    private func completeMultipartUpload(
        upload: MultipartStorageUploadResponse,
        token: StorageCDNToken,
        parts: [MultipartStorageUploadPart]
    ) async throws {
        let uploadUrlString = "\(upload.accessURL.trimmingSuffix("/"))/multipart/\(upload.uploadID)/complete"
        guard let url = URL.safeFalDirectCDNV3UploadURL(from: uploadUrlString) else {
            throw FalError.invalidUrl(url: uploadUrlString.redactedURLForDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(CompleteMultipartStorageUploadRequest(parts: parts))
        setCDNAuthorizationHeader(on: &request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        try await retrying(policy: .transientRequest) {
            let response = try await client.resolvedHTTPTransport.data(
                for: request,
                validatingRedirectsWith: { URL.safeFalDirectCDNV3UploadURL($0) }
            )
            do {
                try client.checkResponseStatus(for: response.response, withData: response.data)
            } catch let falError as FalError {
                throw TransientStorageUploadError.nonTerminal(falError)
            }
        }
    }

    private func setCDNAuthorizationHeader(on request: inout URLRequest, token: StorageCDNToken) {
        let bearer = "\(token.tokenType) \(token.token)"
        // When the caller routes through their own proxy, the proxy's gateway typically validates
        // a caller-supplied JWT on `Authorization`. Sending the CDN bearer on a separate header
        // lets the gateway forward it (relocating it back to `Authorization` on the outbound hop)
        // without colliding with the caller's auth.
        let headerName = client.config.requestProxy != nil ? "x-fal-cdn-authorization" : "Authorization"
        request.setValue(bearer, forHTTPHeaderField: headerName)
    }

    private func fetchCDNToken() async throws -> StorageCDNToken {
        let response = try await client.sendRequest(
            to: "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3",
            input: Data("{}".utf8),
            options: .withMethod(.post),
            retryPolicy: .transientRequest
        )
        return try JSONDecoder().decode(StorageCDNToken.self, from: response)
    }
}

private extension StorageUploadOptions {
    var repositoryChain: [StorageUploadRepository] {
        var repositories: [StorageUploadRepository] = []
        for repository in [repository] + fallbackRepositories where !repositories.contains(repository) {
            repositories.append(repository)
        }
        return repositories
    }

    func normalizedFileName(for type: FileType) -> String {
        guard let fileName else {
            return "\(UUID().uuidString).\(type.fileExtension)"
        }
        let component = fileName
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last
            .map(String.init) ?? fileName
        let sanitized = String(
            component
                .prefix(255)
                .map { character in
                    character.isAllowedUploadFileNameCharacter ? character : "_"
                }
        )
        return sanitized.isEmpty ? "\(UUID().uuidString).\(type.fileExtension)" : sanitized
    }
}

private extension StorageMultipartUploadOptions {
    func validate() throws {
        guard thresholdBytes > 0, chunkSizeBytes > 0 else {
            throw FalError.unsupportedInput(
                message: "Multipart upload threshold and chunk size must be greater than 0 bytes."
            )
        }
    }

    func shouldUploadUsingMultipart(dataByteCount: Int) -> Bool {
        isEnabled && dataByteCount > thresholdBytes
    }
}

private extension Character {
    var isAllowedUploadFileNameCharacter: Bool {
        guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else {
            return false
        }
        if CharacterSet.controlCharacters.contains(scalar) || self == "/" || self == "\\" {
            return false
        }
        return true
    }
}

private extension HTTPURLResponse {
    func headerValue(named name: String) -> String? {
        for (key, value) in allHeaderFields where String(describing: key).lowercased() == name.lowercased() {
            return String(describing: value)
        }
        return nil
    }
}

private extension Client {
    var canAuthorizeDirectFalMediaUpload: Bool {
        let credentials = config.credentials.rawValue
        guard !credentials.isEmpty else {
            return false
        }
        switch config.authScheme {
        case .bearer:
            return true
        case .key:
            let parts = credentials.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count == 2 && !parts[1].isEmpty
        }
    }

    func falMediaAuthorizationHeader() throws -> String {
        let credentials = config.credentials.rawValue
        guard !credentials.isEmpty else {
            throw FalError.unsupportedInput(message: "Fal credentials are required for direct fal.media uploads.")
        }

        switch config.authScheme {
        case .bearer:
            return "Bearer \(credentials)"
        case .key:
            let parts = credentials.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[1].isEmpty else {
                throw FalError.unsupportedInput(
                    message: "Direct fal.media uploads require key credentials in '<id>:<secret>' format."
                )
            }
            return "Bearer \(parts[1])"
        }
    }
}

extension URL {
    static func safeExternalHTTPSURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              safeExternalHTTPSURL(url)
        else {
            return nil
        }
        return url
    }

    static func safeExternalHTTPSURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host,
              !host.isEmpty,
              !host.isLocalOrPrivateHost
        else {
            return false
        }
        return true
    }

    static func safeFalStorageUploadURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              safeFalStorageUploadURL(url)
        else {
            return nil
        }
        return url
    }

    static func safeFalStorageUploadURL(_ url: URL) -> Bool {
        guard safeExternalHTTPSURL(url),
              let host = url.host?.normalizedHostForPolicy
        else {
            return false
        }
        return host.isAllowedFalStorageUploadHost
    }

    static func safeFalDirectCDNV3UploadURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              safeFalDirectCDNV3UploadURL(url)
        else {
            return nil
        }
        return url
    }

    static func safeFalDirectCDNV3UploadURL(_ url: URL) -> Bool {
        guard safeExternalHTTPSURL(url),
              let host = url.host?.normalizedHostForPolicy
        else {
            return false
        }
        return host.isAllowedDirectFalCDNV3UploadHost
    }

    static func safeFalDirectMediaUploadURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              safeFalDirectMediaUploadURL(url)
        else {
            return nil
        }
        return url
    }

    static func safeFalDirectMediaUploadURL(_ url: URL) -> Bool {
        guard safeExternalHTTPSURL(url),
              let host = url.host?.normalizedHostForPolicy
        else {
            return false
        }
        return host.isAllowedDirectFalMediaUploadHost
    }

    static func safeFalStorageFileURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              safeFalStorageFileURL(url)
        else {
            return nil
        }
        return url
    }

    static func safeFalStorageFileURL(_ url: URL) -> Bool {
        guard safeExternalHTTPSURL(url),
              let host = url.host?.normalizedHostForPolicy
        else {
            return false
        }
        return host.isAllowedFalStorageFileHost
    }
}

func encodeTypedInputRejectingBinaryData<Input: Encodable>(
    _ input: Input,
    message: String,
    configure: (JSONEncoder) -> Void = { _ in }
) throws -> Data {
    let encoder = JSONEncoder()
    configure(encoder)
    encoder.dataEncodingStrategy = .custom { _, _ in
        throw FalError.unsupportedInput(message: message)
    }
    return try encoder.encode(input)
}

private extension String {
    var normalizedHostForPolicy: String {
        lowercased().trimmingSuffix(".")
    }

    var isAllowedFalStorageUploadHost: Bool {
        isEqualToOrSubdomain(of: "storage.googleapis.com")
            || isEqualToOrSubdomain(of: "v3.fal.media")
            || isEqualToOrSubdomain(of: "fal.media")
    }

    var isAllowedDirectFalCDNV3UploadHost: Bool {
        isEqualToOrSubdomain(of: "v3.fal.media")
    }

    var isAllowedDirectFalMediaUploadHost: Bool {
        isEqualToOrSubdomain(of: "fal.media")
    }

    var isAllowedFalStorageFileHost: Bool {
        isEqualToOrSubdomain(of: "v3.fal.media")
            || isEqualToOrSubdomain(of: "fal.media")
    }

    func isEqualToOrSubdomain(of domain: String) -> Bool {
        self == domain || hasSuffix(".\(domain)")
    }

    var isLocalOrPrivateHost: Bool {
        let host = lowercased().trimmingSuffix(".")
        if host == "localhost" || host.hasSuffix(".localhost") {
            return true
        }
        if let ipv6Bytes = host.ipv6AddressBytes {
            return ipv6Bytes.isLocalOrPrivateIPv6Address
        }
        if let octets = host.ipv4AddressOctets {
            return octets.isLocalOrPrivateIPv4Address
        }
        return false
    }

    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }

    var ipv6AddressBytes: [UInt8]? {
        var address = in6_addr()
        guard withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
            return nil
        }
        return withUnsafeBytes(of: address) { pointer in
            Array(pointer)
        }
    }

    var ipv4AddressOctets: [Int]? {
        let parts = split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 4).contains(parts.count) else {
            return nil
        }
        let components = parts.compactMap { Self.parseIPv4Component($0) }
        guard components.count == parts.count else {
            return nil
        }

        let address: UInt32
        switch components.count {
        case 1:
            guard components[0] <= UInt32.max else {
                return nil
            }
            address = UInt32(components[0])
        case 2:
            guard components[0] <= 0xff, components[1] <= 0x00ff_ffff else {
                return nil
            }
            address = UInt32((components[0] << 24) | components[1])
        case 3:
            guard components[0] <= 0xff, components[1] <= 0xff, components[2] <= 0xffff else {
                return nil
            }
            address = UInt32((components[0] << 24) | (components[1] << 16) | components[2])
        case 4:
            guard components.allSatisfy({ $0 <= 0xff }) else {
                return nil
            }
            address = UInt32((components[0] << 24) | (components[1] << 16) | (components[2] << 8) | components[3])
        default:
            return nil
        }

        return [
            Int((address >> 24) & 0xff),
            Int((address >> 16) & 0xff),
            Int((address >> 8) & 0xff),
            Int(address & 0xff),
        ]
    }

    static func parseIPv4Component(_ component: Substring) -> UInt64? {
        guard !component.isEmpty else {
            return nil
        }
        if component.hasPrefix("0x") || component.hasPrefix("0X") {
            let start = component.index(component.startIndex, offsetBy: 2)
            let digits = component[start...]
            guard !digits.isEmpty else {
                return nil
            }
            return UInt64(digits, radix: 16)
        }
        if component.count > 1, component.first == "0" {
            return UInt64(component, radix: 8)
        }
        return UInt64(component, radix: 10)
    }
}

private struct TerminalStorageUploadError: Error {
    let underlying: Error
}

struct TransientStorageUploadError: Error {
    let underlying: Error

    static func nonTerminal(_ error: Error) -> TransientStorageUploadError {
        TransientStorageUploadError(underlying: error)
    }
}

private func shouldFallbackAfterStorageUploadError(_ error: Error) -> Bool {
    if let transientError = error as? TransientStorageUploadError {
        return shouldFallbackAfterStorageUploadError(transientError.underlying)
    }
    if error is CancellationError {
        return false
    }
    if let urlError = error as? URLError, urlError.code == .cancelled {
        return false
    }
    if let falError = error as? FalError {
        switch falError {
        case .invalidUrl,
             .unsupportedInput,
             .unsupportedOperation,
             .invalidAppId,
             .queueTimeout,
             .invalidResultFormat:
            return false
        case let .httpError(error):
            return error.statusCode == 408
                || error.statusCode == 409
                || error.statusCode == 425
                || error.statusCode == 429
                || error.statusCode >= 500
        }
    }
    if let urlError = error as? URLError {
        return urlError.code != .badURL
    }
    return false
}

private extension Array where Element == Int {
    var isLocalOrPrivateIPv4Address: Bool {
        guard count == 4 else {
            return false
        }
        return self[0] == 0
            || self[0] == 10
            || self[0] == 127
            || (self[0] == 100 && (64 ... 127).contains(self[1]))
            || (self[0] == 169 && self[1] == 254)
            || (self[0] == 172 && (16 ... 31).contains(self[1]))
            || (self[0] == 192 && self[1] == 168)
            || self[0] >= 224
    }
}

private extension Array where Element == UInt8 {
    var isLocalOrPrivateIPv6Address: Bool {
        guard count == 16 else {
            return false
        }
        if allSatisfy({ $0 == 0 }) || self == Array(repeating: 0, count: 15) + [1] {
            return true
        }
        if self[0] == 0xfe && (0x80 ... 0xbf).contains(self[1]) {
            return true
        }
        if (0xfc ... 0xfd).contains(self[0]) || self[0] == 0xff {
            return true
        }
        if prefix(12).allSatisfy({ $0 == 0 }) {
            return Array(suffix(4)).map(Int.init).isLocalOrPrivateIPv4Address
        }
        if prefix(10).allSatisfy({ $0 == 0 }) && self[10] == 0xff && self[11] == 0xff {
            return Array(suffix(4)).map(Int.init).isLocalOrPrivateIPv4Address
        }
        return false
    }
}
