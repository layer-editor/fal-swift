@testable import FalClient
import XCTest

final class UtilitySpec: XCTestCase {
    func testBuildUrlCreatesUrlToGatewayFalAIFromLegacyAppAlias() {
        let id = "1234-app-alias"
        let url = buildUrl(fromId: id)

        XCTAssertEqual(url, "https://fal.run/1234/app-alias")
    }

    func testBuildUrlCreatesUrlToFalRunFromAppAlias() {
        let id = "user/app-alias"
        let url = buildUrl(fromId: id)

        XCTAssertEqual(url, "https://fal.run/user/app-alias")
    }

    func testBuildUrlAppendsPathsWithSingleSeparator() {
        let url = buildUrl(fromId: "fal-ai/flux/schnell/", path: "stream")

        XCTAssertEqual(url, "https://fal.run/fal-ai/flux/schnell/stream")
    }

    func testAppIdParsesIdWithoutPath() throws {
        let appId = try AppId.parse(id: "fal-ai/fast-sdxl")

        XCTAssertEqual(appId.ownerId, "fal-ai")
        XCTAssertEqual(appId.appAlias, "fast-sdxl")
        XCTAssertNil(appId.namespace)
        XCTAssertNil(appId.path)
        XCTAssertEqual(appId.endpointPath, "fal-ai/fast-sdxl")
        XCTAssertEqual(appId.queueBasePath, "fal-ai/fast-sdxl")
    }

    func testAppIdParsesIdWithPath() throws {
        let appId = try AppId.parse(id: "fal-ai/fast-sdxl/image-to-image")

        XCTAssertEqual(appId.ownerId, "fal-ai")
        XCTAssertEqual(appId.appAlias, "fast-sdxl")
        XCTAssertNil(appId.namespace)
        XCTAssertEqual(appId.path, "image-to-image")
        XCTAssertEqual(appId.endpointPath, "fal-ai/fast-sdxl/image-to-image")
        XCTAssertEqual(appId.queueBasePath, "fal-ai/fast-sdxl/image-to-image")
    }

    func testAppIdParsesReservedNamespaceIds() throws {
        let appId = try AppId.parse(id: "workflows/chris/image-pipeline/preview")

        XCTAssertEqual(appId.namespace, "workflows")
        XCTAssertEqual(appId.ownerId, "chris")
        XCTAssertEqual(appId.appAlias, "image-pipeline")
        XCTAssertEqual(appId.path, "preview")
        XCTAssertEqual(appId.endpointPath, "workflows/chris/image-pipeline/preview")
        XCTAssertEqual(appId.queueBasePath, "workflows/chris/image-pipeline")
    }
}
