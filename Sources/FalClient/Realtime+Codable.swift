import Dispatch
import Foundation

public extension Realtime {
    func connect<Input: Encodable, Output: Decodable>(
        to app: String,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(64),
        onResult completion: @escaping (Result<Output, Error>) -> Void
    ) throws -> TypedRealtimeConnection<Input> {
        handleConnection(
            to: app,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            connectionFactory: { send, close in
                TypedRealtimeConnection(send, close)
            },
            onResult: completion
        ) as! TypedRealtimeConnection<Input>
    }

    /// Connects to a custom realtime endpoint path using typed input and output models.
    func connect<Input: Encodable, Output: Decodable>(
        to app: String,
        path: String,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(64),
        onResult completion: @escaping (Result<Output, Error>) -> Void
    ) throws -> TypedRealtimeConnection<Input> {
        _ = try realtimeConnectionPoolKey(forApp: app, path: path, connectionKey: connectionKey)
        return handleConnection(
            to: app,
            path: path,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            connectionFactory: { send, close in
                TypedRealtimeConnection(send, close)
            },
            onResult: completion
        ) as! TypedRealtimeConnection<Input>
    }
}
