@testable import FalClient
import Nimble
import Quick

class UtilitySpec: QuickSpec {
    override static func spec() {
        describe("Utility.buildUrl") {
            it("should create a url to gateway fal.ai from a legacy app alias") {
                let id = "1234-app-alias"
                let url = buildUrl(fromId: id)
                expect(url).to(equal("https://fal.run/1234/app-alias"))
            }
            it("should create a url to fal.run from an app alias") {
                let id = "user/app-alias"
                let url = buildUrl(fromId: id)
                expect(url).to(equal("https://fal.run/user/app-alias"))
            }
            it("should append paths with a single separator") {
                let url = buildUrl(fromId: "fal-ai/flux/schnell/", path: "stream")
                expect(url).to(equal("https://fal.run/fal-ai/flux/schnell/stream"))
            }
        }
        describe("Utility.AppId.parse") {
            it ("should parse an id without a path") {
                let appId = try AppId.parse(id: "fal-ai/fast-sdxl")
                expect(appId.ownerId).to(equal("fal-ai"))
                expect(appId.appAlias).to(equal("fast-sdxl"))
                expect(appId.namespace).to(beNil())
                expect(appId.path).to(beNil())
                expect(appId.endpointPath).to(equal("fal-ai/fast-sdxl"))
                expect(appId.queueBasePath).to(equal("fal-ai/fast-sdxl"))
            }
            it ("should parse an id with a path") {
                let appId = try AppId.parse(id: "fal-ai/fast-sdxl/image-to-image")
                expect(appId.ownerId).to(equal("fal-ai"))
                expect(appId.appAlias).to(equal("fast-sdxl"))
                expect(appId.namespace).to(beNil())
                expect(appId.path).to(equal("image-to-image"))
                expect(appId.endpointPath).to(equal("fal-ai/fast-sdxl/image-to-image"))
                expect(appId.queueBasePath).to(equal("fal-ai/fast-sdxl/image-to-image"))
            }
            it ("should parse reserved namespace ids") {
                let appId = try AppId.parse(id: "workflows/chris/image-pipeline/preview")
                expect(appId.namespace).to(equal("workflows"))
                expect(appId.ownerId).to(equal("chris"))
                expect(appId.appAlias).to(equal("image-pipeline"))
                expect(appId.path).to(equal("preview"))
                expect(appId.endpointPath).to(equal("workflows/chris/image-pipeline/preview"))
                expect(appId.queueBasePath).to(equal("workflows/chris/image-pipeline"))
            }
        }
    }
}
