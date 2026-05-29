import Dispatch
import Foundation
import SwiftMsgpack

func throttle<T>(_ function: @escaping (T) -> Void, throttleInterval: DispatchTimeInterval) -> ((T) -> Void) {
    let state = ThrottleState()

    let throttledFunction: ((T) -> Void) = { input in
        if state.shouldExecute(throttleInterval: throttleInterval) {
            function(input)
        }
    }

    return throttledFunction
}

private final class ThrottleState: @unchecked Sendable {
    private let lock = NSLock()
    private var lastExecution = DispatchTime.now()

    func shouldExecute(throttleInterval: DispatchTimeInterval) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard DispatchTime.now() > lastExecution + throttleInterval else {
            return false
        }
        lastExecution = DispatchTime.now()
        return true
    }
}

public enum FalRealtimeError: Error {
    case connectionError(code: Int? = nil, reason: String? = nil)
    case unauthorized
    case invalidInput
    case invalidResult(requestId: String? = nil, causedBy: Error? = nil)
    case serviceError(type: String, reason: String)
}

extension FalRealtimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .connectionError(code, reason):
            let reasonSuffix = reason.map { ", reason: \($0)" } ?? ""
            return NSLocalizedString("Connection error (code: \(String(describing: code))\(reasonSuffix))", comment: "FalRealtimeError.connectionError")
        case .unauthorized:
            return NSLocalizedString("Unauthorized", comment: "FalRealtimeError.unauthorized")
        case .invalidInput:
            return NSLocalizedString("Invalid input format", comment: "FalRealtimeError.invalidInput")
        case .invalidResult:
            return NSLocalizedString("Invalid result", comment: "FalRealtimeError.invalidResult")
        case let .serviceError(type, reason):
            return NSLocalizedString("\(type): \(reason)", comment: "FalRealtimeError.serviceError")
        }
    }
}

typealias SendFunction = (URLSessionWebSocketTask.Message) throws -> Void
typealias CloseFunction = () -> Void

func hasBinaryField(_ type: Encodable) -> Bool {
    if let object = type as? Payload,
       case let .dict(dict) = object
    {
        return dict.values.contains {
            if case .data = $0 {
                return true
            }
            return false
        }
    }
    let mirror = Mirror(reflecting: type)
    for child in mirror.children {
        if child.value is Data {
            return true
        }
        if case FalImageContent.raw = child.value {
            return true
        }
    }
    return false
}

/// The real-time connection. This is used to send messages to the app, which will send
/// responses back to the `connect` result completion callback.
public class BaseRealtimeConnection<Input: Encodable>: @unchecked Sendable {
    let sendReference: SendFunction
    let closeReference: CloseFunction

    init(_ send: @escaping SendFunction, _ close: @escaping CloseFunction) {
        sendReference = send
        closeReference = close
    }

    /// Closes the connection. You can use this to manuallt close the connection.
    /// In most cases you don't need to call this method, as connections are closed
    /// automatically by the server when they are idle. The idle period is determined
    /// by the app and it may vary.
    public func close() {
        closeReference()
    }

    /// Sends a message to the app.
    public func send(_ input: Input) throws {
        if hasBinaryField(input) {
            try sendBinary(input)
        } else {
            try sendJSON(input)
        }
    }

    func sendJSON(_ data: Input) throws {
        let jsonData = try JSONEncoder().encode(data)
        guard let json = String(data: jsonData, encoding: .utf8) else {
            throw FalRealtimeError.invalidInput
        }
        try sendReference(.string(json))
    }

    func sendBinary(_ data: Input) throws {
        let payload = try MsgPackEncoder().encode(data)
        try sendReference(.data(payload))
    }
}

/// Connection implementation that can be used to send messages using the `Payload` type.
public class RealtimeConnection: BaseRealtimeConnection<Payload>, @unchecked Sendable {}

/// Connection implementation that can be used to send messages using a custom `Encodable` type.
public class TypedRealtimeConnection<Input: Encodable>: BaseRealtimeConnection<Input>, @unchecked Sendable {}

/// This is a list of apps deployed before formal realtime support. Their URLs follow
/// a different pattern and will be kept here until we fully sunset them.
let LegacyApps = [
    "lcm-sd15-i2i",
    "lcm",
    "sdxl-turbo-realtime",
    "sd-turbo-real-time-high-fps-msgpack-a10g",
    "lcm-plexed-sd15-i2i",
    "sd-turbo-real-time-high-fps-msgpack",
]

func buildRealtimeUrl(forApp app: String, path requestedPath: String? = nil, token: String? = nil) throws -> URL {
    // Some basic support for old ids, this should be removed during 1.0.0 release
    // For full-support of old ids, users can point to version 0.4.x
    let path = try realtimePath(forApp: app, requestedPath: requestedPath)
    guard var components = URLComponents(string: buildUrl(fromId: app, path: path)) else {
        preconditionFailure("Invalid URL. This is unexpected and likely a problem in the client library.")
    }
    components.scheme = "wss"

    if let token {
        components.queryItems = [URLQueryItem(name: "fal_jwt_token", value: token)]
    }
    // swiftlint:disable:next force_unwrapping
    return components.url!
}

private func realtimePath(forApp app: String, requestedPath: String?) throws -> String? {
    if let requestedPath {
        return try normalizedRealtimePath(requestedPath)
    }

    let appAlias = (try? appAlias(fromId: app)) ?? app
    if LegacyApps.contains(appAlias) || !app.contains("/") {
        return "/ws"
    }
    if (try? AppId.parse(id: app).path) != nil {
        return nil
    }
    return "/realtime"
}

private func normalizedRealtimePath(_ path: String) throws -> String {
    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedPath.isEmpty,
          !trimmedPath.contains("?"),
          !trimmedPath.contains("#"),
          !trimmedPath.contains("\\")
    else {
        throw FalRealtimeError.invalidInput
    }

    let components = URLComponents(string: trimmedPath)
    guard components?.scheme == nil, components?.host == nil else {
        throw FalRealtimeError.invalidInput
    }

    let lowercasedPath = trimmedPath.lowercased()
    guard !lowercasedPath.contains("%2f"), !lowercasedPath.contains("%5c") else {
        throw FalRealtimeError.invalidInput
    }

    let segments = trimmedPath.trimmingRealtimeSlashes.split(separator: "/", omittingEmptySubsequences: false)
    guard !segments.isEmpty,
          segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
    else {
        throw FalRealtimeError.invalidInput
    }

    return "/" + segments.joined(separator: "/")
}

private func realtimeTokenAppIdentifier(forApp app: String, path _: String?) throws -> String {
    // fal scopes realtime JWTs by app ALIAS (the middle id component) — the owner
    // prefix and any path suffix are stripped. This matches fal-js
    // `getTemporaryAuthToken`, which sends `allowed_apps: [appId.alias]`. Sending the
    // full endpoint path (or appending the realtime path like `/ws` or `/realtime`)
    // produces a token fal rejects at the WS handshake with `1008 Forbidden`.
    (try? AppId.parse(id: app).appAlias) ?? app
}

private extension String {
    var trimmingRealtimeSlashes: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

typealias RefreshTokenFunction = @Sendable (String, String?, @escaping @Sendable (Result<String, Error>) -> Void) -> Void

private let TokenDurationSeconds = 300
private let TokenRefreshLeadTimeSeconds = 30

typealias WebSocketMessage = URLSessionWebSocketTask.Message

private struct RealtimeEndpointIdentity {
    let app: String
    let path: String?

    var poolKeyPath: String {
        path ?? ""
    }
}

private func realtimeEndpointIdentity(forApp app: String, path requestedPath: String?) throws -> RealtimeEndpointIdentity {
    RealtimeEndpointIdentity(
        app: ((try? AppId.parse(id: app).endpointPath) ?? app).trimmingRealtimeSlashes,
        path: try realtimePath(forApp: app, requestedPath: requestedPath)
    )
}

func realtimeConnectionPoolKey(forApp app: String, path: String?, connectionKey: String) throws -> String {
    let endpointIdentity = try realtimeEndpointIdentity(forApp: app, path: path)
    return "\(endpointIdentity.app):\(endpointIdentity.poolKeyPath):\(connectionKey)"
}

protocol RealtimeWebSocketTask: AnyObject {
    func resume()
    func send(
        _ message: WebSocketMessage,
        completionHandler: @escaping @Sendable (Error?) -> Void
    )
    func receive(completionHandler: @escaping @Sendable (Result<WebSocketMessage, Error>) -> Void)
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

extension URLSessionWebSocketTask: RealtimeWebSocketTask {}

protocol RealtimeWebSocketTaskFactory: Sendable {
    func webSocketTask(with url: URL, delegate: URLSessionWebSocketDelegate) -> RealtimeWebSocketTask
}

final class URLSessionRealtimeWebSocketTaskFactory: RealtimeWebSocketTaskFactory, @unchecked Sendable {
    static let shared = URLSessionRealtimeWebSocketTaskFactory()

    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    func webSocketTask(with url: URL, delegate: URLSessionWebSocketDelegate) -> RealtimeWebSocketTask {
        let task = session.webSocketTask(with: url)
        task.delegate = delegate
        return task
    }
}

final class WebSocketConnection: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    let app: String
    let path: String?
    let client: Client
    let onMessage: (WebSocketMessage) -> Void
    let onError: (Error) -> Void
    var onClose: () -> Void = {}

    private let stateQueue = DispatchQueue(label: "ai.fal.WebSocketConnection.\(UUID().uuidString)")
    private let webSocketTaskFactory: RealtimeWebSocketTaskFactory
    private let refreshTokenFunction: RefreshTokenFunction?
    private var enqueuedMessages: [WebSocketMessage] = []
    private var task: RealtimeWebSocketTask?
    private var token: String?

    private var isConnecting = false
    private var isRefreshingToken = false
    private var isClosed = false

    init(
        app: String,
        path: String? = nil,
        client: Client,
        webSocketTaskFactory: RealtimeWebSocketTaskFactory = URLSessionRealtimeWebSocketTaskFactory.shared,
        refreshToken: RefreshTokenFunction? = nil,
        onMessage: @escaping (WebSocketMessage) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.app = app
        self.path = path
        self.client = client
        self.webSocketTaskFactory = webSocketTaskFactory
        self.refreshTokenFunction = refreshToken
        self.onMessage = onMessage
        self.onError = onError
    }

    func connect() {
        stateQueue.async {
            self.isClosed = false
            self.connectOnStateQueue()
        }
    }

    private func connectOnStateQueue() {
        if task == nil, !isConnecting, !isRefreshingToken, !isClosed {
            isConnecting = true
            if token == nil, !isRefreshingToken {
                isRefreshingToken = true
                refreshToken(app, path: path) { result in
                    self.stateQueue.async {
                        guard !self.isClosed else {
                            self.isConnecting = false
                            self.isRefreshingToken = false
                            return
                        }
                        switch result {
                        case let .success(token):
                            self.token = token
                            self.isRefreshingToken = false
                            self.isConnecting = false

                            // Very simple token expiration handling for now.
                            // Create the deadline 90% of the way through the token's lifetime.
                            let tokenExpirationDeadline: DispatchTime = .now()
                                + .seconds(TokenDurationSeconds - TokenRefreshLeadTimeSeconds)
                            self.stateQueue.asyncAfter(deadline: tokenExpirationDeadline) {
                                guard !self.isClosed else {
                                    return
                                }
                                self.token = nil
                            }

                            self.connectOnStateQueue()
                        case let .failure(error):
                            self.isConnecting = false
                            self.isRefreshingToken = false
                            self.onError(error)
                        }
                    }
                }
                return
            }

            let url: URL
            do {
                url = try buildRealtimeUrl(
                    forApp: app,
                    path: path,
                    token: token
                )
            } catch {
                isConnecting = false
                onError(error)
                return
            }
            task = webSocketTaskFactory.webSocketTask(with: url, delegate: self)
            // connect and keep the task reference
            task?.resume()
            isConnecting = false
            receiveMessage()
        }
    }

    func refreshToken(
        _ app: String,
        path: String? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        if let refreshTokenFunction {
            refreshTokenFunction(app, path, completion)
            return
        }

        Task {
            do {
                // The current fal REST contract mints realtime JWTs at `/tokens/`
                // with `token_expiration` (seconds). The older `/tokens/realtime`
                // + `duration` shape now 422s with `{"loc":["body","app"],
                // "msg":"Field required"}`. Matches fal-js `getTemporaryAuthToken`.
                let url = "https://rest.fal.ai/tokens/"
                let body: Payload = [
                    "allowed_apps": [.string(try realtimeTokenAppIdentifier(forApp: app, path: path))],
                    "token_expiration": .int(TokenDurationSeconds),
                ]
                let response = try await self.client.sendRequest(
                    to: url,
                    input: body.json(),
                    options: .withMethod(.post)
                )
                if let payload = try? Payload.create(fromJSON: response) {
                    if let token = payload["token"].stringValue, !token.isEmpty {
                        completion(.success(token))
                    } else if let token = payload.stringValue?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                              !token.isEmpty
                    {
                        completion(.success(token))
                    } else {
                        completion(.failure(FalRealtimeError.unauthorized))
                    }
                } else if let token = String(data: response, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                    !token.isEmpty
                {
                    completion(.success(token))
                } else {
                    completion(.failure(FalRealtimeError.unauthorized))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func receiveMessage() {
        let task = task
        task?.receive { [weak self] incomingMessage in
            switch incomingMessage {
            case let .success(message):
                do {
                    self?.receiveMessage()

                    let object = try message.decode(to: Payload.self)
                    if isSuccessResult(object) {
                        self?.onMessage(message)
                        return
                    }
                    if let error = getError(object) {
                        self?.onError(error)
                        return
                    }
                } catch {
                    self?.onError(error)
                }
            case let .failure(error):
                if let connection = self {
                    connection.stateQueue.async {
                        connection.task = nil
                    }
                }
                if let posixError = error as? POSIXError, posixError.code == .ENOTCONN {
                    // Ignore this error as it's thrown by Foundation's WebSocket implementation
                    // when messages were requested but the connection was closed already.
                    // This is safe to ignore, as the client is not expecting any other messages
                    // and will reconnect when new messages are sent.
                    return
                }
                self?.onError(error)
            }
        }
    }

    func send(_ message: URLSessionWebSocketTask.Message) throws {
        stateQueue.async {
            self.isClosed = false
            if let task = self.task {
                task.send(message) { [weak self] error in
                    if let error {
                        self?.onError(error)
                    }
                }
            } else {
                self.enqueuedMessages.append(message)
                if !self.isConnecting {
                    self.connectOnStateQueue()
                }
            }
        }
    }

    func close() {
        stateQueue.async {
            self.isClosed = true
            self.task?.cancel(with: .normalClosure, reason: "Programmatically closed".data(using: .utf8))
            self.task = nil
            self.enqueuedMessages.removeAll()
            self.onClose()
        }
    }

    func urlSession(
        _: URLSession,
        webSocketTask _: URLSessionWebSocketTask,
        didOpenWithProtocol _: String?
    ) {
        realtimeSocketDidOpen()
    }

    func realtimeSocketDidOpen() {
        stateQueue.async {
            let queuedMessages = self.enqueuedMessages
            self.enqueuedMessages.removeAll()
            for message in queuedMessages {
                self.task?.send(message) { [weak self] error in
                    if let error {
                        self?.onError(error)
                    }
                }
            }
        }
    }

    func urlSession(
        _: URLSession,
        webSocketTask _: URLSessionWebSocketTask,
        didCloseWith code: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) }
        realtimeSocketDidClose(with: code, reason: reasonString)
    }

    func realtimeSocketDidClose(with code: URLSessionWebSocketTask.CloseCode, reason: String? = nil) {
        stateQueue.async {
            if code != .normalClosure {
                self.onError(FalRealtimeError.connectionError(code: code.rawValue, reason: reason))
            }
            self.task = nil
            self.onClose()
        }
    }
}

final class RealtimeConnectionPool: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [String: WebSocketConnection] = [:]

    func connection(for key: String, create: () -> WebSocketConnection) -> WebSocketConnection {
        lock.lock()
        defer {
            lock.unlock()
        }
        if let connection = connections[key] {
            return connection
        }
        let connection = create()
        connections[key] = connection
        return connection
    }

    func removeConnection(for key: String, matching connection: WebSocketConnection) {
        lock.lock()
        defer {
            lock.unlock()
        }
        if connections[key] === connection {
            connections[key] = nil
        }
    }
}

let connectionPool = RealtimeConnectionPool()

/// The real-time client contract.
public protocol Realtime {
    var client: Client { get }

    func connect(
        to app: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection

    func connect(
        to app: String,
        path: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection
}

func isSuccessResult(_ message: Payload) -> Bool {
    message["status"].stringValue != "error"
        && message["type"].stringValue != "x-fal-message"
        && message["type"].stringValue != "x-fal-error"
}

func getError(_ message: Payload) -> FalRealtimeError? {
    if message["type"].stringValue == "x-fal-error",
       let error = message["error"].stringValue,
       let reason = message["reason"].stringValue,
       // The timeout error is expected as the websocket endpoint returns that
       // when no input has ben sent for a while. It's safe to ignore and should
       // not trigger the onError callback of the client
       error != "TIMEOUT"
    {
        return FalRealtimeError.serviceError(type: error, reason: reason)
    }
    return nil
}

extension WebSocketMessage {
    func data() throws -> Data {
        switch self {
        case let .data(data):
            return data
        case let .string(string):
            guard let data = string.data(using: .utf8) else {
                throw FalRealtimeError.invalidResult()
            }
            return data
        @unknown default:
            preconditionFailure("Unknown URLSessionWebSocketTask.Message case")
        }
    }

    func decode<Type: Decodable>(to type: Type.Type) throws -> Type {
        switch self {
        case let .data(data):
            return try MsgPackDecoder().decode(type, from: data)
        case .string:
            return try JSONDecoder().decode(type, from: data())
        @unknown default:
            return try JSONDecoder().decode(type, from: data())
        }
    }
}

/// The real-time client implementation.
public struct RealtimeClient: Realtime {
    // TODO: in the future make this non-public
    // External APIs should not use it
    public let client: Client

    init(client: Client) {
        self.client = client
    }

    public func connect(
        to app: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection {
        handleConnection(
            to: app,
            path: nil,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            connectionFactory: { send, close in
                RealtimeConnection(send, close)
            },
            onResult: completion
        ) as! RealtimeConnection
    }

    public func connect(
        to app: String,
        path: String,
        connectionKey: String,
        throttleInterval: DispatchTimeInterval,
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection {
        _ = try realtimeConnectionPoolKey(forApp: app, path: path, connectionKey: connectionKey)
        return handleConnection(
            to: app,
            path: path,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            connectionFactory: { send, close in
                RealtimeConnection(send, close)
            },
            onResult: completion
        ) as! RealtimeConnection
    }
}

extension Realtime {
    func handleConnection<InputType: Encodable, ResultType: Decodable>(
        to app: String,
        path: String? = nil,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(128),
        connectionFactory createRealtimeConnection: @escaping (@escaping SendFunction, @escaping CloseFunction) -> BaseRealtimeConnection<InputType>,
        onResult completion: @escaping (Result<ResultType, Error>) -> Void
    ) -> BaseRealtimeConnection<InputType> {
        let key: String
        do {
            key = try realtimeConnectionPoolKey(forApp: app, path: path, connectionKey: connectionKey)
        } catch {
            let failedSend: SendFunction = { _ in throw error }
            let close: CloseFunction = {}
            return createRealtimeConnection(failedSend, close)
        }
        let ws = connectionPool.connection(for: key) {
            let connection = WebSocketConnection(
                app: app,
                path: path,
                client: client,
                onMessage: { message in
                    do {
                        let result = try message.decode(to: ResultType.self)
                        completion(.success(result))
                    } catch {
                        completion(.failure(error))
                    }
                },
                onError: { error in
                    completion(.failure(error))
                }
            )
            connection.onClose = { [weak connection] in
                guard let connection else {
                    return
                }
                connectionPool.removeConnection(for: key, matching: connection)
            }
            return connection
        }

        let sendData: (WebSocketMessage) -> Void = { data in
            do {
                try ws.send(data)
            } catch {
                completion(.failure(error))
            }
        }
        let send: SendFunction = throttleInterval.milliseconds > 0 ? throttle(sendData, throttleInterval: throttleInterval) : sendData
        let close: CloseFunction = {
            ws.close()
        }
        return createRealtimeConnection(send, close)
    }
}

public extension Realtime {
    /// Connects to the given `app` and returns a `RealtimeConnection` that can be used to send messages to the app.
    /// The `connectionKey` is used to identify the connection and it's used to reuse the same connection
    /// and it's useful in scenarios where the `connect` function is called multiple times.
    /// The `throttleInterval` is used to throttle the messages sent to the app, it defaults to 64 milliseconds.
    ///
    /// - Parameters:
    ///   - app: The id of the model app.
    ///   - connectionKey: The connection key.
    ///   - throttleInterval: The throttle interval.
    ///   - completion: The completion callback.
    ///
    /// - Returns: A `RealtimeConnection` that can be used to send messages to the app.
    func connect(
        to app: String,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(64),
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection {
        try connect(
            to: app,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            onResult: completion
        )
    }

    /// Connects to a custom realtime endpoint path for the given app.
    ///
    /// Most realtime apps use `/realtime`; use this overload for apps that
    /// publish a different WebSocket route.
    func connect(
        to app: String,
        path: String,
        connectionKey: String = UUID().uuidString,
        throttleInterval: DispatchTimeInterval = .milliseconds(64),
        onResult completion: @escaping (Result<Payload, Error>) -> Void
    ) throws -> RealtimeConnection {
        _ = try realtimeConnectionPoolKey(forApp: app, path: path, connectionKey: connectionKey)
        return handleConnection(
            to: app,
            path: path,
            connectionKey: connectionKey,
            throttleInterval: throttleInterval,
            connectionFactory: { send, close in
                RealtimeConnection(send, close)
            },
            onResult: completion
        ) as! RealtimeConnection
    }
}
