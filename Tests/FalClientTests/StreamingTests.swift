@testable import FalClient
import XCTest

final class StreamingTests: XCTestCase {
    private var transport: RecordingHTTPTransport!

    override func tearDown() {
        transport = nil
        super.tearDown()
    }

    func testPayloadStreamBuildsDirectSSERequestAndDecodesEvents() async throws {
        transport = RecordingHTTPTransport(serverSentEventData: [
            #"{"progress":0.25,"message":"Generating"}"#,
            #"{"images":[{"url":"https://fal.media/result.png"}],"seed":42}"#,
        ])
        let client = TestStreamingClient(httpTransport: transport)

        let stream = try await client.stream(
            "fal-ai/streaming-model",
            input: .dict(["prompt": "hello"]),
            options: StreamOptions(timeoutInterval: 12)
        )
        XCTAssertEqual(transport.requests.count, 0)

        var events: [Payload] = []
        for try await event in stream {
            events.append(event)
        }

        let request = try XCTUnwrap(transport.requests.first)
        let body = try Payload.create(fromJSON: try XCTUnwrap(request.httpBody))

        XCTAssertEqual(request.url?.absoluteString, "https://fal.run/fal-ai/streaming-model/stream")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 12)
        XCTAssertEqual(request.value(forHTTPHeaderField: "accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Queue-Priority"), nil)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Request-Timeout"), nil)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Fal-Runner-Hint"), nil)
        XCTAssertEqual(body["prompt"].stringValue, "hello")
        XCTAssertEqual(events.first?["message"].stringValue, "Generating")
        XCTAssertEqual(events.last?["seed"], 42)
    }

    func testTypedStreamBuildsCustomPathAndDecodesEvents() async throws {
        transport = RecordingHTTPTransport(serverSentEventData: [
            #"{"token":"hel"}"#,
            #"{"token":"lo"}"#,
        ])
        let client = TestStreamingClient(httpTransport: transport)

        let stream: AsyncThrowingStream<TestStreamEvent, Error> = try await client.stream(
            "fal-ai/text-model",
            input: TestStreamInput(prompt: "hello"),
            options: StreamOptions(path: "/chat/stream")
        )

        var events: [TestStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let request = try XCTUnwrap(transport.requests.first)
        let body = try JSONDecoder().decode(TestStreamInput.self, from: try XCTUnwrap(request.httpBody))

        XCTAssertEqual(request.url?.absoluteString, "https://fal.run/fal-ai/text-model/chat/stream")
        XCTAssertEqual(body.prompt, "hello")
        XCTAssertEqual(events.map(\.token), ["hel", "lo"])
    }

    func testPayloadStreamPreservesHTTPErrorPayload() async throws {
        let errorData = Data(#"{"detail":"stream endpoint unavailable","error_type":"not_streaming"}"#.utf8)
        transport = RecordingHTTPTransport(
            serverSentEventStatusCode: 404,
            body: errorData,
            headers: ["x-fal-request-id": "req_direct_stream"]
        )
        let client = TestStreamingClient(httpTransport: transport)

        let stream = try await client.stream("fal-ai/no-stream", input: .dict(["prompt": "hello"]))
        XCTAssertEqual(transport.requests.count, 0)

        do {
            for try await _ in stream {}
            XCTFail("Expected stream to throw an HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 404)
            XCTAssertEqual(error.message, "stream endpoint unavailable")
            XCTAssertEqual(error.requestId, "req_direct_stream")
            XCTAssertEqual(error.errorType, "not_streaming")
            XCTAssertEqual(error.payload?["detail"].stringValue, "stream endpoint unavailable")
        } catch {
            XCTFail("Expected FalError.httpError, got \(error)")
        }
    }

    func testTypedStreamRejectsBinaryDataBeforeSendingRequest() async throws {
        transport = RecordingHTTPTransport(serverSentEventData: [])
        let client = TestStreamingClient(httpTransport: transport)

        do {
            let _: AsyncThrowingStream<TestStreamEvent, Error> = try await client.stream(
                "fal-ai/text-model",
                input: TestBinaryStreamInput(file: Data("binary".utf8))
            )
            XCTFail("Expected stream to reject typed binary input")
        } catch FalError.unsupportedInput(let message) {
            XCTAssertTrue(message.contains("Payload.data"))
            XCTAssertEqual(transport.requests.count, 0)
        } catch {
            XCTFail("Expected FalError.unsupportedInput, got \(error)")
        }
    }
}

private struct TestStreamInput: Codable, Equatable {
    let prompt: String
}

private struct TestStreamEvent: Decodable, Equatable {
    let token: String
}

private struct TestBinaryStreamInput: Encodable {
    let file: Data
}

private struct TestStreamingClient: Client, HTTPTransportProviding {
    let config = ClientConfig(credentials: .keyPair("fal-key-id:fal-key-secret"))
    let httpTransport: HTTPTransport

    var queue: Queue {
        fatalError("TestStreamingClient.queue is unused in these tests")
    }

    var realtime: Realtime {
        fatalError("TestStreamingClient.realtime is unused in these tests")
    }

    var storage: Storage {
        fatalError("TestStreamingClient.storage is unused in these tests")
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        fatalError("TestStreamingClient.run is unused in these tests")
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("TestStreamingClient.subscribe is unused in these tests")
    }
}
