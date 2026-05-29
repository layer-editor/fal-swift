@testable import FalClient
import XCTest

final class WorkflowEventTests: XCTestCase {
    private let decoder = JSONDecoder()

    private func decode(_ json: String) throws -> WorkflowEventData {
        try decoder.decode(WorkflowEventData.self, from: Data(json.utf8))
    }

    func testDecodesSubmitEvent() throws {
        let event = try decode(#"""
        {"type":"submit","node_id":"node-1","app_id":"fal-ai/flux","request_id":"req-123"}
        """#)

        guard case let .submit(submit) = event else {
            return XCTFail("expected submit event, got \(event)")
        }
        XCTAssertEqual(event.type, .submit)
        XCTAssertEqual(event.nodeId, "node-1")
        XCTAssertFalse(event.isTerminal)
        XCTAssertEqual(submit.appId, "fal-ai/flux")
        XCTAssertEqual(submit.requestId, "req-123")
    }

    func testDecodesCompletionEvent() throws {
        let event = try decode(#"""
        {"type":"completion","node_id":"node-1","app_id":"fal-ai/flux","output":{"seed":42}}
        """#)

        guard case let .completion(completion) = event else {
            return XCTFail("expected completion event, got \(event)")
        }
        XCTAssertEqual(event.type, .completion)
        XCTAssertEqual(event.nodeId, "node-1")
        XCTAssertFalse(event.isTerminal)
        XCTAssertEqual(completion.appId, "fal-ai/flux")
        XCTAssertEqual(completion.output["seed"], 42)
    }

    func testDecodesOutputEventWithFinalResult() throws {
        let event = try decode(#"""
        {"type":"output","node_id":"node-final","output":{"images":[{"url":"https://fal.media/r.png"}]}}
        """#)

        guard case let .output(output) = event else {
            return XCTFail("expected output event, got \(event)")
        }
        XCTAssertEqual(event.type, .output)
        XCTAssertEqual(event.nodeId, "node-final")
        XCTAssertTrue(event.isTerminal)
        XCTAssertEqual(output.output["images"][0]["url"].stringValue, "https://fal.media/r.png")
    }

    func testDecodesErrorEvent() throws {
        let event = try decode(#"""
        {"type":"error","node_id":"node-2","message":"step failed","error":{"status":500,"body":"boom"}}
        """#)

        guard case let .error(failure) = event else {
            return XCTFail("expected error event, got \(event)")
        }
        XCTAssertEqual(event.type, .error)
        XCTAssertEqual(event.nodeId, "node-2")
        XCTAssertTrue(event.isTerminal)
        XCTAssertEqual(failure.message, "step failed")
        XCTAssertEqual(failure.error["status"], 500)
        XCTAssertEqual(failure.error["body"].stringValue, "boom")
    }

    func testUnknownEventTypeThrows() {
        XCTAssertThrowsError(try decode(#"{"type":"heartbeat","node_id":"n"}"#))
    }

    func testStreamDecodesWorkflowEvents() async throws {
        let transport = RecordingHTTPTransport(serverSentEventData: [
            #"{"type":"submit","node_id":"n1","app_id":"fal-ai/flux","request_id":"req-1"}"#,
            #"{"type":"completion","node_id":"n1","app_id":"fal-ai/flux","output":{"seed":7}}"#,
            #"{"type":"output","node_id":"n1","output":{"done":true}}"#,
        ])
        let client = WorkflowTestClient(httpTransport: transport)

        let stream: AsyncThrowingStream<WorkflowEventData, Error> = try await client.stream(
            "workflows/owner/my-workflow",
            input: WorkflowTestInput(prompt: "hello")
        )

        var events: [WorkflowEventData] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.map(\.type), [.submit, .completion, .output])
        XCTAssertTrue(events.last?.isTerminal == true)
    }
}

private struct WorkflowTestInput: Encodable {
    let prompt: String
}

private struct WorkflowTestClient: Client, HTTPTransportProviding {
    let config = ClientConfig(credentials: .keyPair("fal-key-id:fal-key-secret"))
    let httpTransport: HTTPTransport

    var queue: Queue { fatalError("unused") }
    var realtime: Realtime { fatalError("unused") }
    var storage: Storage { fatalError("unused") }

    func run(_: String, input _: Payload?, options _: RunOptions) async throws -> Payload {
        fatalError("unused")
    }

    func subscribe(
        to _: String,
        input _: Payload?,
        pollInterval _: DispatchTimeInterval,
        timeout _: DispatchTimeInterval,
        includeLogs _: Bool,
        onQueueUpdate _: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("unused")
    }
}
