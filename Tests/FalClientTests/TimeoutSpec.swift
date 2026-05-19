@testable import FalClient
import Dispatch
import Foundation
import XCTest

final class TimeoutSpec: XCTestCase {
    func testDispatchTimeIntervalConvertsSecondsToMilliseconds() {
        XCTAssertEqual(DispatchTimeInterval.seconds(1).milliseconds, 1_000)
        XCTAssertEqual(DispatchTimeInterval.seconds(5).milliseconds, 5_000)
        XCTAssertEqual(DispatchTimeInterval.seconds(60).milliseconds, 60_000)
    }

    func testDispatchTimeIntervalReturnsMillisecondsAsIs() {
        XCTAssertEqual(DispatchTimeInterval.milliseconds(500).milliseconds, 500)
        XCTAssertEqual(DispatchTimeInterval.milliseconds(1_500).milliseconds, 1_500)
    }

    func testDispatchTimeIntervalConvertsMicrosecondsToMilliseconds() {
        XCTAssertEqual(DispatchTimeInterval.microseconds(1_000).milliseconds, 1)
        XCTAssertEqual(DispatchTimeInterval.microseconds(5_000).milliseconds, 5)
    }

    func testDispatchTimeIntervalConvertsNanosecondsToMilliseconds() {
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(1_000_000).milliseconds, 1)
        XCTAssertEqual(DispatchTimeInterval.nanoseconds(5_000_000).milliseconds, 5)
    }

    func testDispatchTimeIntervalNeverMeansNoDeadline() {
        XCTAssertEqual(DispatchTimeInterval.never.milliseconds, Int.max)
    }

    func testDispatchTimeIntervalConvertsMinutesHelper() {
        XCTAssertEqual(DispatchTimeInterval.minutes(1).milliseconds, 60_000)
        XCTAssertEqual(DispatchTimeInterval.minutes(3).milliseconds, 180_000)
    }

    func testRunOptionsDefaultTimeout() {
        let options = RunOptions()

        XCTAssertEqual(options.timeoutInterval, 60)
    }

    func testRunOptionsAllowsCustomTimeout() {
        let options = RunOptions(timeoutInterval: 120)

        XCTAssertEqual(options.timeoutInterval, 120)
    }

    func testRunOptionsPreservesInitializerParameters() {
        let options = RunOptions(path: "/custom", httpMethod: .put, timeoutInterval: 30)

        XCTAssertEqual(options.path, "/custom")
        XCTAssertEqual(options.httpMethod, .put)
        XCTAssertEqual(options.timeoutInterval, 30)
    }

    func testRunOptionsWithMethodUsesDefaultTimeout() {
        let options = RunOptions.withMethod(.get)

        XCTAssertEqual(options.httpMethod, .get)
        XCTAssertEqual(options.timeoutInterval, 60)
    }

    func testRunOptionsWithTimeoutUsesPostByDefault() {
        let options = RunOptions.withTimeout(90)

        XCTAssertEqual(options.timeoutInterval, 90)
        XCTAssertEqual(options.httpMethod, .post)
    }

    func testRunOptionsWithTimeoutAllowsMethodOverride() {
        let options = RunOptions.withTimeout(45, method: .delete)

        XCTAssertEqual(options.timeoutInterval, 45)
        XCTAssertEqual(options.httpMethod, .delete)
    }

    func testRunOptionsRouteUsesDefaultTimeout() {
        let options = RunOptions.route("/status", withMethod: .get)

        XCTAssertEqual(options.path, "/status")
        XCTAssertEqual(options.httpMethod, .get)
        XCTAssertEqual(options.timeoutInterval, 60)
    }

    func testURLRequestAppliesRunOptionsTimeout() {
        let options = RunOptions(timeoutInterval: 45)
        let request = URLRequest(url: URL(string: "https://example.com")!, timeoutInterval: options.timeoutInterval)

        XCTAssertEqual(request.timeoutInterval, 45)
    }
}
