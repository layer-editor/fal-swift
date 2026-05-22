import Kingfisher
import SwiftUI

let PROMPT = "a city landscape of a cyberpunk metropolis, raining, purple, pink and teal neon lights, highly detailed, uhd"

struct ContentView: View {
    @State private var imageUrl: String?
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView("Loading...")
            } else {
                Button("Generate Image") {
                    Task {
                        print("Generate image...")
                        isLoading = true
                        do {
                            let result = try await fal.subscribe(
                                to: "fal-ai/fast-lightning-sdxl",
                                input: [
                                    "prompt": .string(PROMPT),
                                ],
                                pollInterval: .milliseconds(500),
                                timeout: .minutes(3),
                                includeLogs: true
                            ) { update in
                                update.logs
                                    .filter { log in !log.message.isEmpty }
                                    .forEach { log in
                                        print(log.message)
                                    }
                            }
                            isLoading = false
                            if case let .string(url) = result["images"][0]["url"] {
                                imageUrl = url
                            }
                        } catch {
                            print(error)
                            isLoading = false
                        }
                    }
                }
                .padding()
                .clipShape(.rect(cornerRadius: 16))
                .foregroundStyle(.white)
                .background(Color.indigo)
            }

            if let imageUrl, let url = URL(string: imageUrl) {
                KFImage.url(url)
                    .fade(duration: 0.25)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .padding()
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
