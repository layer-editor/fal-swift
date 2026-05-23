import Foundation

func buildUrl(fromId id: String, path: String? = nil, subdomain: String? = nil) -> String {
    let appId = ((try? AppId.parse(id: id).endpointPath) ?? id).trimmingEndpointSlashes
    let sub = subdomain != nil ? "\(subdomain!)." : ""
    return "https://\(sub)fal.run/\(appId)" + normalizedEndpointPath(path)
}

func queueRequestPath(for requestId: String, suffix: String = "") -> String {
    "/requests/\(requestId.percentEncodedQueueRequestPathSegment)\(suffix)"
}

func ensureAppIdFormat(_ id: String) throws -> String {
    let parts = id.split(separator: "/")
    if parts.count > 1 {
        return id
    }
    let regex = try NSRegularExpression(pattern: "^([0-9]+)-([a-zA-Z0-9-]+)$")
    let matches = regex.matches(in: id, options: [], range: NSRange(location: 0, length: id.utf16.count))
    if let match = matches.first, match.numberOfRanges == 3,
       let appOwnerRange = Range(match.range(at: 1), in: id),
       let appIdRange = Range(match.range(at: 2), in: id)
    {
        let appOwner = String(id[appOwnerRange])
        let appId = String(id[appIdRange])
        return "\(appOwner)/\(appId)"
    }
    return id
}

func appAlias(fromId id: String) throws -> String {
    try AppId.parse(id: id).appAlias
}

struct AppId {
    private static let reservedNamespaces: Set<String> = ["workflows", "comfy"]

    let namespace: String?
    let ownerId: String
    let appAlias: String
    let path: String?
    let endpointPath: String
    let queueBasePath: String

    static func parse(id: String) throws -> Self {
        let appId = try ensureAppIdFormat(id)
        let parts = appId.trimmingEndpointSlashes
            .split(separator: "/")
            .map(String.init)
        guard parts.count > 1 else {
            throw FalError.invalidAppId(id: id)
        }
        if reservedNamespaces.contains(parts[0]), parts.count > 2 {
            let namespace = parts[0]
            let ownerId = parts[1]
            let appAlias = parts[2]
            let path = parts.count > 3 ? parts.dropFirst(3).joined(separator: "/") : nil
            let queueBasePath = [namespace, ownerId, appAlias].joined(separator: "/")
            return Self(
                namespace: namespace,
                ownerId: ownerId,
                appAlias: appAlias,
                path: path,
                endpointPath: parts.joined(separator: "/"),
                queueBasePath: queueBasePath
            )
        }

        return Self(
            namespace: nil,
            ownerId: parts[0],
            appAlias: parts[1],
            path: parts.endIndex > 2 ? parts.dropFirst(2).joined(separator: "/") : nil,
            endpointPath: parts.joined(separator: "/"),
            queueBasePath: "\(parts[0])/\(parts[1])"
        )
    }
}

private func normalizedEndpointPath(_ path: String?) -> String {
    guard let path else {
        return ""
    }
    let trimmed = path.trimmingEndpointSlashes
    guard !trimmed.isEmpty else {
        return ""
    }
    return "/\(trimmed)"
}

private extension String {
    var trimmingEndpointSlashes: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private extension String {
    var percentEncodedQueueRequestPathSegment: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
