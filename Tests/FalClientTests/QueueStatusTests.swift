@testable import FalClient
import XCTest

final class QueueStatusTests: XCTestCase {
    func testDecodesInQueueMetadata() throws {
        let data = """
        {
          "status": "IN_QUEUE",
          "request_id": "req_123",
          "queue_position": 2,
          "response_url": "https://queue.fal.run/fal-ai/flux/requests/req_123",
          "status_url": "https://queue.fal.run/fal-ai/flux/requests/req_123/status",
          "cancel_url": "https://queue.fal.run/fal-ai/flux/requests/req_123/cancel"
        }
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(QueueStatusDetail.self, from: data)

        XCTAssertEqual(detail.requestId, "req_123")
        XCTAssertEqual(detail.responseUrl, "https://queue.fal.run/fal-ai/flux/requests/req_123")
        XCTAssertEqual(detail.statusUrl, "https://queue.fal.run/fal-ai/flux/requests/req_123/status")
        XCTAssertEqual(detail.cancelUrl, "https://queue.fal.run/fal-ai/flux/requests/req_123/cancel")

        guard case let .inQueue(position, responseUrl) = detail.status else {
            return XCTFail("Expected IN_QUEUE status")
        }

        XCTAssertEqual(position, 2)
        XCTAssertEqual(responseUrl, "https://queue.fal.run/fal-ai/flux/requests/req_123")
    }

    func testDecodesCompletedMetricsAndErrorMetadata() throws {
        let data = """
        {
          "status": "COMPLETED",
          "request_id": "req_456",
          "response_url": "https://queue.fal.run/fal-ai/flux/requests/req_456",
          "status_url": "https://queue.fal.run/fal-ai/flux/requests/req_456/status",
          "cancel_url": "https://queue.fal.run/fal-ai/flux/requests/req_456/cancel",
          "metrics": {
            "inference_time": 1.25
          },
          "error": {
            "message": "Invalid prompt"
          },
          "error_type": "UserError",
          "logs": []
        }
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(QueueStatusDetail.self, from: data)

        XCTAssertEqual(detail.requestId, "req_456")
        XCTAssertEqual(detail.responseUrl, "https://queue.fal.run/fal-ai/flux/requests/req_456")
        XCTAssertEqual(detail.statusUrl, "https://queue.fal.run/fal-ai/flux/requests/req_456/status")
        XCTAssertEqual(detail.cancelUrl, "https://queue.fal.run/fal-ai/flux/requests/req_456/cancel")
        XCTAssertEqual(detail.metrics?["inference_time"], .double(1.25))
        XCTAssertEqual(detail.error?["message"].stringValue, "Invalid prompt")
        XCTAssertEqual(detail.errorType, "UserError")

        guard case let .completed(logs, responseUrl) = detail.status else {
            return XCTFail("Expected COMPLETED status")
        }

        XCTAssertTrue(logs.isEmpty)
        XCTAssertEqual(responseUrl, "https://queue.fal.run/fal-ai/flux/requests/req_456")
    }

    func testDecodesInProgressWithoutLogs() throws {
        let data = """
        {
          "status": "IN_PROGRESS"
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(QueueStatus.self, from: data)

        XCTAssertTrue(status.logs.isEmpty)
    }

    func testDecodesCompletedDetailWithoutLogs() throws {
        let data = """
        {
          "status": "COMPLETED",
          "response_url": "https://queue.fal.run/fal-ai/flux/requests/req_456"
        }
        """.data(using: .utf8)!

        let detail = try JSONDecoder().decode(QueueStatusDetail.self, from: data)

        XCTAssertTrue(detail.logs.isEmpty)
        XCTAssertEqual(detail.responseUrl, "https://queue.fal.run/fal-ai/flux/requests/req_456")
    }

    func testStatusDetailResponseUrlUsesStatusPayloadAsCanonicalValue() {
        let detail = QueueStatusDetail(
            status: .completed(logs: [], responseUrl: "https://case.example.com/response"),
            requestId: "req_789",
            responseUrl: "https://metadata.example.com/response"
        )

        XCTAssertEqual(detail.responseUrl, "https://case.example.com/response")
    }

    func testDecodesLogsWithoutLabels() throws {
        let data = """
        {
          "status": "IN_PROGRESS",
          "logs": [
            {
              "message": "Loading model",
              "timestamp": "2026-05-18T17:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(QueueStatus.self, from: data)

        XCTAssertEqual(status.logs.map(\.message), ["Loading model"])
        XCTAssertEqual(status.logs.first?.level, .info)
    }

    func testDecodesLogsWithLabels() throws {
        let data = """
        {
          "status": "IN_PROGRESS",
          "logs": [
            {
              "message": "Running inference",
              "timestamp": "2026-05-18T17:00:00Z",
              "labels": {
                "level": "STDOUT"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(QueueStatus.self, from: data)

        XCTAssertEqual(status.logs.map(\.message), ["Running inference"])
        XCTAssertEqual(status.logs.first?.level, .stdout)
    }

    func testDecodesLogsWithEmptyLabels() throws {
        let data = """
        {
          "status": "IN_PROGRESS",
          "logs": [
            {
              "message": "Running inference",
              "timestamp": "2026-05-18T17:00:00Z",
              "labels": {}
            }
          ]
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(QueueStatus.self, from: data)

        XCTAssertEqual(status.logs.map(\.message), ["Running inference"])
        XCTAssertEqual(status.logs.first?.level, .info)
    }

    func testDecodesLogsWithUnknownLabelLevel() throws {
        let data = """
        {
          "status": "IN_PROGRESS",
          "logs": [
            {
              "message": "Running inference",
              "timestamp": "2026-05-18T17:00:00Z",
              "labels": {
                "level": "TRACE"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(QueueStatus.self, from: data)

        XCTAssertEqual(status.logs.map(\.message), ["Running inference"])
        XCTAssertEqual(status.logs.first?.level, .info)
    }

    func testDecodesLogsWithUnknownTopLevelLevel() throws {
        let data = """
        {
          "status": "IN_PROGRESS",
          "logs": [
            {
              "message": "Running inference",
              "timestamp": "2026-05-18T17:00:00Z",
              "level": "TRACE"
            }
          ]
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(QueueStatus.self, from: data)

        XCTAssertEqual(status.logs.map(\.message), ["Running inference"])
        XCTAssertEqual(status.logs.first?.level, .info)
    }
}
