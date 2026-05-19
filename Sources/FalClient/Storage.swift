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

/// This establishes the contract of the client with the storage API. The storage API is used
/// to upload files to the fal.ai storage so model APIs can access the files when needed.
///
/// This allows for a decoupled architecture where the model API does not need to worry about
/// file handling and can always rely on a valid URL to read files from.
public protocol Storage {
    var client: Client { get }

    /// Uploads the given `data` to the fal.ai storage and returns the URL of the uploaded file.
    func upload(data: Data, ofType type: FileType) async throws -> String
}

public extension Storage {
    func upload(data: Data, ofType type: FileType = .applicationStream) async throws -> String {
        try await upload(data: data, ofType: type)
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

struct StorageClient: Storage {
    let client: Client

    func initiateUpload(data _: Data, ofType type: FileType) async throws -> UploadUrl {
        let input: Payload = [
            "content_type": .string(type.mimeType),
            "file_name": .string("\(UUID().uuidString).\(type.fileExtension)"),
        ]
        let response = try await client.sendRequest(
            to: "https://rest.alpha.fal.ai/storage/upload/initiate",
            input: input.json(),
            options: .withMethod(.post)
        )
        return try JSONDecoder().decode(UploadUrl.self, from: response)
    }

    func upload(data: Data, ofType type: FileType) async throws -> String {
        let uploadUrl = try await initiateUpload(data: data, ofType: type)
        guard let url = URL.safeExternalHTTPSURL(from: uploadUrl.uploadUrl) else {
            throw FalError.invalidUrl(url: uploadUrl.uploadUrl)
        }
        guard URL.safeExternalHTTPSURL(from: uploadUrl.fileUrl) != nil else {
            throw FalError.invalidUrl(url: uploadUrl.fileUrl)
        }

        // Upload the file to the upload URL.
        // Here we use URLSession directly instead of the client to avoid going
        // through the proxy, we need to hit the blob url directly.
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(type.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")

        let transportResponse = try await client.resolvedHTTPTransport.data(for: request)
        try client.checkResponseStatus(for: transportResponse.response, withData: transportResponse.data)

        return uploadUrl.fileUrl
    }
}

private extension URL {
    static func safeExternalHTTPSURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host,
              !host.isEmpty,
              !host.isLocalOrPrivateHost
        else {
            return nil
        }
        return url
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
    var isLocalOrPrivateHost: Bool {
        let host = lowercased().trimmingSuffix(".")
        if host == "localhost" || host.hasSuffix(".localhost") {
            return true
        }
        if let mappedIPv4Host = host.ipv4MappedIPv6Host {
            return mappedIPv4Host.isLocalOrPrivateHost
        }
        if host.contains(":") {
            if host == "::1" || host == "0:0:0:0:0:0:0:1" {
                return true
            }
            if host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("ff") {
                return true
            }
        }
        if let octets = host.ipv4AddressOctets {
            return octets[0] == 0
                || octets[0] == 10
                || octets[0] == 127
                || (octets[0] == 100 && (64 ... 127).contains(octets[1]))
                || (octets[0] == 169 && octets[1] == 254)
                || (octets[0] == 172 && (16 ... 31).contains(octets[1]))
                || (octets[0] == 192 && octets[1] == 168)
                || octets[0] >= 224
        }
        return false
    }

    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }

    var ipv4MappedIPv6Host: String? {
        guard hasPrefix("::ffff:") else {
            return nil
        }
        let start = index(startIndex, offsetBy: "::ffff:".count)
        return String(self[start...])
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
