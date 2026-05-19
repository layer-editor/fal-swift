import FalClient
import Observation
import SwiftUI

struct TurboInput: Encodable {
    let prompt: String
    let image: Data
    let seed: Int
    let syncMode: Bool
    let strength: Float

    enum CodingKeys: String, CodingKey {
        case prompt
        case image = "image_bytes"
        case seed
        case syncMode = "sync_mode"
        case strength
    }
}

struct TurboResponse: Decodable {
    let images: [FalImage]
}

@MainActor
@Observable
final class LiveImage {
    var currentImage: Data?

    private var connection: TypedRealtimeConnection<TurboInput>?
    private var imageLoadTask: Task<Void, Never>?

    init() {
        ensureConnection()
    }

    func ensureConnection() {
        guard connection == nil else {
            return
        }
        connection = try? fal.realtime.connect(
            to: "fal-ai/fast-turbo-diffusion/image-to-image",
            connectionKey: "PencilKitDemo",
            throttleInterval: .never
        ) { (result: Result<TurboResponse, Error>) in
            Task { @MainActor [weak self] in
                self?.handle(result)
            }
        }
    }

    func close() {
        imageLoadTask?.cancel()
        imageLoadTask = nil
        connection?.close()
        connection = nil
    }

    private func handle(_ result: Result<TurboResponse, Error>) {
        if case let .success(data) = result,
           let image = data.images.first
        {
            load(image)
        }
        if case let .failure(error) = result {
            print("-------------- Error")
            print(error)
        }
    }

    private func load(_ image: FalImage) {
        imageLoadTask?.cancel()
        imageLoadTask = Task { @MainActor [weak self] in
            do {
                let imageData = try await image.loadData()
                try Task.checkCancellation()
                self?.currentImage = imageData
            } catch is CancellationError {
            } catch {
                print("-------------- Error")
                print(error)
            }
        }
    }

    func generate(prompt: String, drawing: Data) throws {
        ensureConnection()
        if let connection {
            try connection.send(TurboInput(
                prompt: prompt,
                image: drawing,
                seed: 6_252_023,
                syncMode: true,
                strength: 0.6
            ))
        }
    }
}
