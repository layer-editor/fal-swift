import Foundation

public enum ClientCredentials: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .keyPair(value):
            return value
        case let .key(id: id, secret: secret):
            return "\(id):\(secret)"
        case .fromEnv:
            if let keyPair = ProcessInfo.processInfo.environment["FAL_KEY"] {
                return keyPair
            }

            if let keyId = ProcessInfo.processInfo.environment["FAL_KEY_ID"],
               let keySecret = ProcessInfo.processInfo.environment["FAL_KEY_SECRET"]
            {
                return "\(keyId):\(keySecret)"
            }
            return ""
        case let .custom(resolver):
            return resolver()
        case let .bearerToken(token):
            return token
        }
    }

    case keyPair(_ pair: String)
    case key(id: String, secret: String)
    case fromEnv
    case custom(_ resolver: () -> String)
    case bearerToken(_ token: String)
}

public enum AuthScheme {
    case key
    case bearer
}

public struct ClientConfig {
    public let credentials: ClientCredentials
    public let authScheme: AuthScheme
    public let requestProxy: String?

    init(
        credentials: ClientCredentials = .fromEnv,
        authScheme: AuthScheme = .key,
        requestProxy: String? = nil
    ) {
        self.credentials = credentials
        self.authScheme = authScheme
        self.requestProxy = requestProxy
    }
}
