import Foundation

/// The kind of event emitted while a workflow request is streaming.
///
/// A workflow runs as a graph of steps. As execution progresses, the server
/// emits one event per state transition. See ``WorkflowEventData`` for the
/// payload carried by each kind.
public enum WorkflowEventType: String, Codable, Sendable {
    /// A new step has been submitted for execution.
    case submit
    /// An individual step has finished and produced its results.
    case completion
    /// The workflow finished and the final result is ready.
    case output
    /// A step failed.
    case error
}

/// Fields shared by every workflow streaming event.
public protocol WorkflowEvent: Decodable, Sendable {
    /// Identifier of the workflow node the event refers to.
    var nodeId: String { get }
}

/// Emitted every time a new step is submitted to execution.
public struct WorkflowSubmitEvent: WorkflowEvent {
    public let nodeId: String
    /// Identifier of the app backing the submitted step.
    public let appId: String
    /// Identifier of the queued request for the submitted step.
    public let requestId: String

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case appId = "app_id"
        case requestId = "request_id"
    }
}

/// Emitted upon the completion of an individual step within the workflow.
public struct WorkflowCompletionEvent: WorkflowEvent {
    public let nodeId: String
    /// Identifier of the app that produced the step result.
    public let appId: String
    /// The step's results.
    public let output: Payload

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case appId = "app_id"
        case output
    }
}

/// Emitted when the workflow finishes and the final result is ready.
public struct WorkflowOutputEvent: WorkflowEvent {
    public let nodeId: String
    /// The final workflow result.
    public let output: Payload

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case output
    }
}

/// Emitted when a step fails.
public struct WorkflowErrorEvent: WorkflowEvent {
    public let nodeId: String
    /// A human-readable description of the error.
    public let message: String
    /// The underlying error details, carrying `status` and `body`.
    // TODO: decode the underlying error to a more specific type once the
    // server contract for `body` is stable.
    public let error: Payload

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case message
        case error
    }
}

/// A typed workflow streaming event.
///
/// Decode a workflow stream by requesting this type from ``Client/stream(_:input:options:)``:
///
/// ```swift
/// let stream: AsyncThrowingStream<WorkflowEventData, Error> = try await client.stream(
///     "workflows/owner/my-workflow",
///     input: input
/// )
/// for try await event in stream {
///     switch event {
///     case let .submit(submit): print("submitted", submit.nodeId)
///     case let .completion(step): print("step done", step.nodeId)
///     case let .output(done): print("workflow done", done.output)
///     case let .error(failure): print("failed", failure.message)
///     }
/// }
/// ```
///
/// The concrete event is selected by the `type` discriminator on the wire.
public enum WorkflowEventData: Decodable, Sendable {
    case submit(WorkflowSubmitEvent)
    case completion(WorkflowCompletionEvent)
    case output(WorkflowOutputEvent)
    case error(WorkflowErrorEvent)

    private enum DiscriminatorKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let type = try container.decode(WorkflowEventType.self, forKey: .type)
        let single = try decoder.singleValueContainer()
        switch type {
        case .submit:
            self = .submit(try single.decode(WorkflowSubmitEvent.self))
        case .completion:
            self = .completion(try single.decode(WorkflowCompletionEvent.self))
        case .output:
            self = .output(try single.decode(WorkflowOutputEvent.self))
        case .error:
            self = .error(try single.decode(WorkflowErrorEvent.self))
        }
    }
}

public extension WorkflowEventData {
    /// The kind of this event.
    var type: WorkflowEventType {
        switch self {
        case .submit: return .submit
        case .completion: return .completion
        case .output: return .output
        case .error: return .error
        }
    }

    /// The workflow node this event refers to.
    var nodeId: String {
        switch self {
        case let .submit(event): return event.nodeId
        case let .completion(event): return event.nodeId
        case let .output(event): return event.nodeId
        case let .error(event): return event.nodeId
        }
    }

    /// Whether this event marks the end of the workflow stream.
    ///
    /// Both a terminal ``WorkflowOutputEvent`` and a ``WorkflowErrorEvent``
    /// end the stream.
    var isTerminal: Bool {
        switch self {
        case .output, .error: return true
        case .submit, .completion: return false
        }
    }
}
