import Foundation

/// Loads remote image content from a URL.
public protocol FalImageContentDataLoading: Sendable {
    /// Returns the data at the specified URL.
    /// - Parameter url: The remote image URL to load.
    func data(from url: URL) async throws -> Data
}

/// A URLSession-backed loader for remote Fal image content.
public final class URLSessionFalImageContentDataLoader: FalImageContentDataLoading, @unchecked Sendable {
    /// Shared loader using `URLSession.shared`.
    public static let shared = URLSessionFalImageContentDataLoader()

    private let session: URLSession

    /// Creates a loader backed by the specified URL session.
    /// - Parameter session: The session used to load remote image bytes.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Returns the data at the specified URL.
    /// - Parameter url: The remote image URL to load.
    public func data(from url: URL) async throws -> Data {
        try validateFalImageContentURL(url)

        let request = URLRequest(url: url)
        let validator: @Sendable (URL) -> Bool = { URL.safeExternalHTTPSURL($0) }
        let delegate = RedirectValidatingURLSessionDelegate(validator: validator)
        let (data, response) = try await session.data(for: request, delegate: delegate)
        if let rejectedURL = delegate.rejectedRedirectURL {
            throw FalError.invalidUrl(url: rejectedURL.absoluteString.redactedURLForDescription)
        }
        if let responseURL = response.url {
            try validateFalImageContentURL(responseURL)
        }
        if let httpResponse = response as? HTTPURLResponse,
           !httpResponse.isSuccessful
        {
            throw FalError.httpError(FalHTTPError(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            ))
        }
        return data
    }
}

public enum FalImageContent: Codable, Sendable {
    case url(String)
    case raw(Data)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let url = try? container.decode(String.self) {
            self = .url(url)
        } else if let data = try? container.decode(Data.self) {
            self = .raw(data)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "FalImageContent must be either URL, Base64 or Binary")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .url(url):
            try container.encode(url)
        case let .raw(data):
            try container.encode(data)
        }
    }

    @available(*, deprecated, message: "Use loadData() async throws instead.")
    public var data: Data {
        switch self {
        case .url:
            preconditionFailure("FalImageContent.data cannot synchronously load URL-backed content. Use loadData() async throws instead.")
        case let .raw(data):
            return data
        }
    }

    /// Loads the image bytes represented by this content.
    /// - Parameter loader: The loader used for URL-backed content.
    /// - Returns: Raw image bytes.
    public func loadData(
        using loader: FalImageContentDataLoading = URLSessionFalImageContentDataLoader.shared
    ) async throws -> Data {
        switch self {
        case let .url(urlString):
            guard let url = URL.safeExternalHTTPSURL(from: urlString) else {
                throw FalError.invalidUrl(url: urlString)
            }
            return try await loader.data(from: url)
        case let .raw(data):
            return data
        }
    }
}

private func validateFalImageContentURL(_ url: URL) throws {
    guard URL.safeExternalHTTPSURL(url) else {
        throw FalError.invalidUrl(url: url.absoluteString.redactedURLForDescription)
    }
}

extension FalImageContent: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .url(value)
    }
}

extension FalImageContent: ExpressibleByStringInterpolation {
    public init(stringInterpolation: StringInterpolation) {
        self = .url(stringInterpolation.string)
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var string: String = ""

        public init(literalCapacity _: Int, interpolationCount _: Int) {}

        public mutating func appendLiteral(_ literal: String) {
            string.append(literal)
        }

        public mutating func appendInterpolation(_ value: String) {
            string.append(value)
        }
    }
}

public struct FalImage: Codable, Sendable {
    public let content: FalImageContent
    public let contentType: String
    public let width: Int
    public let height: Int

    /// Creates an image model.
    /// - Parameters:
    ///   - content: The image content, either remote URL or raw data.
    ///   - contentType: The image MIME type.
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    public init(
        content: FalImageContent,
        contentType: String,
        width: Int,
        height: Int
    ) {
        self.content = content
        self.contentType = contentType
        self.width = width
        self.height = height
    }

    /// Loads the image bytes represented by `content`.
    /// - Parameter loader: The loader used for URL-backed content.
    /// - Returns: Raw image bytes.
    public func loadData(
        using loader: FalImageContentDataLoading = URLSessionFalImageContentDataLoader.shared
    ) async throws -> Data {
        try await content.loadData(using: loader)
    }

    // The following exist so we support payloads with both `url` and `content` keys
    // This should no longer be necessary once the Server API is consolidated
    enum UrlCodingKeys: String, CodingKey {
        case content = "url"
        case contentType = "content_type"
        case width
        case height
    }

    enum RawDataCodingKeys: String, CodingKey {
        case content
        case contentType = "content_type"
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: UrlCodingKeys.self)
        if let url = try? container.decode(String.self, forKey: .content) {
            content = .url(url)
            contentType = try container.decode(String.self, forKey: .contentType)
            width = try container.decode(Int.self, forKey: .width)
            height = try container.decode(Int.self, forKey: .height)
        } else {
            let container = try decoder.container(keyedBy: RawDataCodingKeys.self)
            content = try .raw(container.decode(Data.self, forKey: .content))
            contentType = try container.decode(String.self, forKey: .contentType)
            width = try container.decode(Int.self, forKey: .width)
            height = try container.decode(Int.self, forKey: .height)
        }
    }
}
