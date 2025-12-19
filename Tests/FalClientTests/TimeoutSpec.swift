@testable import FalClient
import Dispatch
import Foundation
import Nimble
import Quick

class TimeoutSpec: QuickSpec {
    override static func spec() {
        // MARK: - DispatchTimeInterval.milliseconds

        describe("DispatchTimeInterval.milliseconds") {
            it("should convert seconds to milliseconds") {
                expect(DispatchTimeInterval.seconds(1).milliseconds).to(equal(1000))
                expect(DispatchTimeInterval.seconds(5).milliseconds).to(equal(5000))
                expect(DispatchTimeInterval.seconds(60).milliseconds).to(equal(60000))
            }

            it("should return milliseconds as-is") {
                expect(DispatchTimeInterval.milliseconds(500).milliseconds).to(equal(500))
                expect(DispatchTimeInterval.milliseconds(1500).milliseconds).to(equal(1500))
            }

            it("should convert microseconds to milliseconds") {
                expect(DispatchTimeInterval.microseconds(1000).milliseconds).to(equal(1))
                expect(DispatchTimeInterval.microseconds(5000).milliseconds).to(equal(5))
            }

            it("should convert nanoseconds to milliseconds") {
                expect(DispatchTimeInterval.nanoseconds(1_000_000).milliseconds).to(equal(1))
                expect(DispatchTimeInterval.nanoseconds(5_000_000).milliseconds).to(equal(5))
            }

            it("should return Int.max for .never (not 0)") {
                // This is the critical fix - .never should mean "wait forever", not "timeout immediately"
                expect(DispatchTimeInterval.never.milliseconds).to(equal(Int.max))
            }

            it("should convert minutes helper correctly") {
                expect(DispatchTimeInterval.minutes(1).milliseconds).to(equal(60_000))
                expect(DispatchTimeInterval.minutes(3).milliseconds).to(equal(180_000))
            }
        }

        // MARK: - RunOptions

        describe("RunOptions") {
            it("should have a default timeout of 60 seconds") {
                let options = RunOptions()
                expect(options.timeoutInterval).to(equal(60))
            }

            it("should allow custom timeout via init") {
                let options = RunOptions(timeoutInterval: 120)
                expect(options.timeoutInterval).to(equal(120))
            }

            it("should preserve all parameters in init") {
                let options = RunOptions(path: "/custom", httpMethod: .put, timeoutInterval: 30)
                expect(options.path).to(equal("/custom"))
                expect(options.httpMethod).to(equal(HttpMethod.put))
                expect(options.timeoutInterval).to(equal(30))
            }

            it("should use default timeout with withMethod factory") {
                let options = RunOptions.withMethod(.get)
                expect(options.httpMethod).to(equal(HttpMethod.get))
                expect(options.timeoutInterval).to(equal(60))
            }

            it("should set custom timeout with withTimeout factory") {
                let options = RunOptions.withTimeout(90)
                expect(options.timeoutInterval).to(equal(90))
                expect(options.httpMethod).to(equal(HttpMethod.post))
            }

            it("should allow method override with withTimeout factory") {
                let options = RunOptions.withTimeout(45, method: .delete)
                expect(options.timeoutInterval).to(equal(45))
                expect(options.httpMethod).to(equal(HttpMethod.delete))
            }

            it("should use default timeout with route factory") {
                let options = RunOptions.route("/status", withMethod: .get)
                expect(options.path).to(equal("/status"))
                expect(options.httpMethod).to(equal(HttpMethod.get))
                expect(options.timeoutInterval).to(equal(60))
            }
        }

        // MARK: - URLRequest timeout integration

        describe("URLRequest timeout") {
            it("should apply timeout from RunOptions") {
                let options = RunOptions(timeoutInterval: 45)
                let request = URLRequest(url: URL(string: "https://example.com")!, timeoutInterval: options.timeoutInterval)
                expect(request.timeoutInterval).to(equal(45))
            }
        }
    }
}
