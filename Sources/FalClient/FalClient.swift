import Dispatch
import Foundation

/// The main client class that provides access to simple API model usage,
/// as well as access to the `queue` and `storage` APIs.
///
/// Example:
///
/// ```swift
/// import FalClient
///
/// let fal = FalClient.withCredentials("fal_key_id:fal_key_secret");
///
/// void main() async {
///   // check https://fal.ai/models for the available models
///   final result = await fal.subscribe(to: 'text-to-image', input: {
///     'prompt': 'a cute shih-tzu puppy',
///     'model_name': 'stabilityai/stable-diffusion-xl-base-1.0',
///   });
///   print(result);
/// }
/// ```
public struct FalClient: Client {
    public var config: ClientConfig

    public var queue: Queue { QueueClient(client: self) }

    public var realtime: Realtime { RealtimeClient(client: self) }

    public var storage: Storage { StorageClient(client: self) }

    /// Updates the access token used for authentication in place.
    /// - Parameter token: The new Bearer token
    public mutating func setAccessToken(_ token: String) {
        config = ClientConfig(
            credentials: .bearerToken(token),
            authScheme: .bearer,
            requestProxy: config.requestProxy
        )
    }

    /// Updates the proxy URL in place.
    /// - Parameter url: The new proxy URL, or nil to remove proxy
    public mutating func setProxy(_ url: String?) {
        config = ClientConfig(
            credentials: config.credentials,
            authScheme: config.authScheme,
            requestProxy: url
        )
    }

    /// Updates both the proxy URL and access token in place.
    /// - Parameters:
    ///   - url: The new proxy URL, or nil to remove proxy
    ///   - token: The new Bearer token
    public mutating func setProxy(_ url: String?, accessToken token: String) {
        config = ClientConfig(
            credentials: .bearerToken(token),
            authScheme: .bearer,
            requestProxy: url
        )
    }

    public func run(_ app: String, input: Payload?, options: RunOptions) async throws -> Payload {
        var requestInput = input
        if let input, input.hasBinaryData {
            guard options.httpMethod != .get else {
                throw FalError.unsupportedInput(
                    message: "Payload.data cannot be sent with GET requests because binary values would be serialized into the URL. Use a POST request so binary values can be uploaded before request encoding."
                )
            }
            requestInput = try await storage.autoUpload(input: input)
        }
        let queryParams = options.httpMethod == .get ? input : nil
        let url = buildUrl(fromId: app, path: options.path)
        let data = try await sendRequest(
            to: url,
            input: requestInput?.json(),
            queryParams: queryParams?.asDictionary,
            options: options,
            includeQueuePriority: false
        )
        return try .create(fromJSON: data)
    }

    public func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        let requestId = try await queue.submit(app, input: input)
        try await pollQueueUntilCompleted(
            queue: queue,
            app: app,
            requestId: requestId,
            pollInterval: pollInterval,
            timeout: timeout,
            includeLogs: includeLogs,
            onQueueUpdate: onQueueUpdate
        )
        return try await queue.response(app, of: requestId)
    }
}

public extension FalClient {
    /// Creates a client with a proxy URL (primarily for testing).
    static func withProxy(_ url: String) -> FalClient {
        FalClient(config: ClientConfig(requestProxy: url))
    }

    /// Creates a client with a proxy URL and access token (primarily for testing).
    static func withProxy(_ url: String, accessToken: String) -> FalClient {
        FalClient(config: ClientConfig(
            credentials: .bearerToken(accessToken),
            authScheme: .bearer,
            requestProxy: url
        ))
    }

    static func withCredentials(_ credentials: ClientCredentials) -> FalClient {
        FalClient(config: ClientConfig(credentials: credentials))
    }

    /// Creates a client with a Bearer token (primarily for testing).
    static func withBearerToken(_ token: String) -> FalClient {
        FalClient(config: ClientConfig(
            credentials: .bearerToken(token),
            authScheme: .bearer
        ))
    }
}

// Typealiases to expose core service contracts under the FalClient namespace.
public typealias FalClientStorage = Storage
public typealias FalClientRealtime = Realtime
public typealias FalClientQueue = Queue

public extension FalClient {
    typealias Storage = FalClientStorage
    typealias Realtime = FalClientRealtime
    typealias Queue = FalClientQueue
}
