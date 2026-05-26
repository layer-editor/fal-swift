@testable import FalClient
import XCTest

final class QueueStreamStatusTests: XCTestCase {
    private var transport: RecordingHTTPTransport!

    override func tearDown() {
        transport = nil
        super.tearDown()
    }

    func testQueueStreamStatusBuildsSSERequestAndDecodesStatusDetails() async throws {
        transport = RecordingHTTPTransport(serverSentEventData: [
            #"{"status":"IN_PROGRESS","request_id":"request-id","response_url":"https://queue.fal.run/fal-ai/flux/schnell/requests/request-id","status_url":"https://queue.fal.run/fal-ai/flux/schnell/requests/request-id/status","cancel_url":"https://queue.fal.run/fal-ai/flux/schnell/requests/request-id/cancel","logs":[]}"#,
            #"{"status":"COMPLETED","request_id":"request-id","response_url":"https://queue.fal.run/fal-ai/flux/schnell/requests/request-id","logs":[],"metrics":{"inference_time":1.5}}"#,
        ])
        let client = TestStreamClient(httpTransport: transport)
        let queue = QueueClient(client: client)

        let stream = try await queue.streamStatus(
            "fal-ai/flux/schnell",
            of: "request-id",
            includeLogs: true
        )
        var updates: [QueueStatusDetail] = []
        for try await update in stream {
            updates.append(update)
        }

        let request = try XCTUnwrap(transport.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "accept"), "text/event-stream")
        XCTAssertEqual(components.percentEncodedPath, "/fal-ai/flux/schnell/requests/request-id/status/stream")
        XCTAssertEqual(queryItems["logs"], "1")
        XCTAssertEqual(updates.map(\.requestId), ["request-id", "request-id"])
        XCTAssertEqual(updates.first?.statusUrl, "https://queue.fal.run/fal-ai/flux/schnell/requests/request-id/status")
        XCTAssertEqual(updates.last?.metrics?["inference_time"], .double(1.5))
    }

    func testQueueStreamStatusEncodesRequestIdAsSinglePathSegment() async throws {
        transport = RecordingHTTPTransport(serverSentEventData: [
            #"{"status":"COMPLETED","request_id":"request-id","response_url":"https://queue.fal.run/fal-ai/test/requests/request-id","logs":[]}"#,
        ])
        let client = TestStreamClient(httpTransport: transport)
        let queue = QueueClient(client: client)

        let stream = try await queue.streamStatus("fal-ai/test", of: "../request?x=1#frag")
        for try await _ in stream {}

        let request = try XCTUnwrap(transport.requests.first)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))

        XCTAssertEqual(
            components.percentEncodedPath,
            "/fal-ai/test/requests/%2E%2E%2Frequest%3Fx%3D1%23frag/status/stream"
        )
        XCTAssertNil(components.query)
    }

    func testQueueStreamStatusUsesNamespacedQueueBase() async throws {
        transport = RecordingHTTPTransport(serverSentEventData: [
            #"{"status":"COMPLETED","request_id":"request-id","response_url":"https://queue.fal.run/workflows/chris/image-pipeline/requests/request-id","logs":[]}"#,
        ])
        let client = TestStreamClient(httpTransport: transport)
        let queue = QueueClient(client: client)

        let stream = try await queue.streamStatus("workflows/chris/image-pipeline/preview", of: "request-id")
        for try await _ in stream {}

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/workflows/chris/image-pipeline/requests/request-id/status/stream")
    }

    func testQueueStreamStatusDecodesMultipleConcatenatedJSONObjectsInOneChunk() async throws {
        // Fal's queue status stream emits successive `data:` lines without a
        // blank-line separator between events. The line-based SSE parser joins
        // them with "\n" per the spec, producing a single chunk that contains
        // two or more concatenated JSON objects. JSONDecoder rejects that
        // shape with "Unexpected character '{' after top-level value", so the
        // decoder needs to fall back to per-line decoding for chunks with
        // multiple JSON values.
        let responseUrl = "https://queue.fal.run/fal-ai/x/requests/r1"
        let concatenated = #"{"status":"IN_QUEUE","request_id":"r1","queue_position":3,"response_url":"\#(responseUrl)","logs":[]}"# +
            "\n" +
            #"{"status":"IN_PROGRESS","request_id":"r1","logs":[]}"# +
            "\n" +
            #"{"status":"COMPLETED","request_id":"r1","response_url":"\#(responseUrl)","logs":[],"metrics":{"inference_time":2.4}}"#
        transport = RecordingHTTPTransport(serverSentEventData: [concatenated])
        let client = TestStreamClient(httpTransport: transport)
        let queue = QueueClient(client: client)

        let stream = try await queue.streamStatus(
            "fal-ai/x",
            of: "r1",
            includeLogs: true
        )
        var updates: [QueueStatusDetail] = []
        for try await update in stream {
            updates.append(update)
        }

        XCTAssertEqual(updates.count, 3)
        XCTAssertEqual(updates.map(\.requestId), ["r1", "r1", "r1"])
        XCTAssertEqual(updates.last?.metrics?["inference_time"], .double(2.4))
        guard case .inQueue(let position, _) = updates.first?.status else {
            return XCTFail("Expected first update to be .inQueue, got \(String(describing: updates.first?.status))")
        }
        XCTAssertEqual(position, 3)
    }

    func testQueueStreamStatusPreservesHTTPErrorPayload() async throws {
        let errorData = Data(#"{"detail":"stream unavailable","error_type":"service_unavailable"}"#.utf8)
        transport = RecordingHTTPTransport(
            serverSentEventStatusCode: 503,
            body: errorData,
            headers: ["x-fal-request-id": "req_stream"]
        )
        let client = TestStreamClient(httpTransport: transport)
        let queue = QueueClient(client: client)

        do {
            let stream = try await queue.streamStatus("fal-ai/test", of: "request-id")
            for try await _ in stream {}
            XCTFail("Expected streamStatus to throw an HTTP error")
        } catch FalError.httpError(let error) {
            XCTAssertEqual(error.statusCode, 503)
            XCTAssertEqual(error.message, "stream unavailable")
            XCTAssertEqual(error.requestId, "req_stream")
            XCTAssertEqual(error.errorType, "service_unavailable")
            XCTAssertEqual(error.payload?["detail"].stringValue, "stream unavailable")
        } catch {
            XCTFail("Expected FalError.httpError, got \(error)")
        }
    }
}

private struct TestStreamClient: Client, HTTPTransportProviding {
    let config = ClientConfig(credentials: .keyPair("fal-key-id:fal-key-secret"))
    let httpTransport: HTTPTransport

    var queue: Queue {
        QueueClient(client: self)
    }

    var realtime: Realtime {
        fatalError("TestStreamClient.realtime is unused in these tests")
    }

    var storage: Storage {
        fatalError("TestStreamClient.storage is unused in these tests")
    }

    func run(_ id: String, input: Payload?, options: RunOptions) async throws -> Payload {
        fatalError("TestStreamClient.run is unused in these tests")
    }

    func subscribe(
        to app: String,
        input: Payload?,
        pollInterval: DispatchTimeInterval,
        timeout: DispatchTimeInterval,
        includeLogs: Bool,
        onQueueUpdate: OnQueueUpdate?
    ) async throws -> Payload {
        fatalError("TestStreamClient.subscribe is unused in these tests")
    }
}
