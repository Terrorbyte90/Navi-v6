import Foundation
import AVFoundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MediaGenerationManager

@MainActor
final class MediaGenerationManager: ObservableObject {
    static let shared = MediaGenerationManager()

    @Published var generations: [MediaGeneration] = []
    @Published var balance: XAIBalance?
    @Published var isLoadingBalance = false

    private let maxConcurrent = 10
    private var saveDebounceTask: Task<Void, Never>? = nil
    private let icloud = iCloudSyncEngine.shared
    private let client = XAIClient.shared
    private let historyFilename = "media-history.json"

    private init() {
        Task { await loadHistory() }
    }

    // MARK: - Active generations

    var activeGenerations: [MediaGeneration] {
        generations.filter { $0.status.isActive }
    }

    var completedGenerations: [MediaGeneration] {
        generations.filter { $0.status == .completed }
    }

    var canGenerate: Bool {
        activeGenerations.count < maxConcurrent
    }

    // MARK: - Generate Image

    func generateImage(
        prompt: String,
        model: String = "grok-imagine-image",
        size: String = "1024x1024",
        variations: Int = 1
    ) async {
        guard canGenerate else {
            NaviLog.warning("MediaGen: max \(maxConcurrent) samtidiga genereringar nått")
            return
        }

        var gen = MediaGeneration(
            type: .image,
            prompt: prompt,
            model: model,
            parameters: MediaParameters(size: size, variations: variations)
        )
        gen.status = .generating
        generations.insert(gen, at: 0)
        await saveHistory()

        do {
            let results = try await client.generateImage(
                prompt: prompt,
                model: model,
                size: size,
                n: variations
            )

            for (i, result) in results.enumerated() {
                let imageData: Data
                if let url = result.url {
                    imageData = try await client.downloadImageData(from: url)
                } else if let b64 = result.b64 {
                    // xAI returns b64_json as "data:image/png;base64,<data>" — strip the prefix
                    let rawBase64: String
                    if let commaIdx = b64.firstIndex(of: ",") {
                        rawBase64 = String(b64[b64.index(after: commaIdx)...])
                    } else {
                        rawBase64 = b64
                    }
                    guard let decoded = Data(base64Encoded: rawBase64, options: .ignoreUnknownCharacters) else {
                        throw XAIError.invalidResponse
                    }
                    imageData = decoded
                } else {
                    throw XAIError.invalidResponse
                }
                let filename = "\(gen.id.uuidString)\(i > 0 ? "-\(i)" : "").png"

                try await saveToICloud(data: imageData, folder: Constants.iCloud.mediaImagesFolder, filename: filename)

                if i == 0 {
                    gen.resultFilename = filename
                    let captured = imageData
                    gen.thumbnailData = await Task.detached(priority: .utility) {
                        MediaGenerationManager.makeThumbnail(from: captured)
                    }.value
                }
            }

            gen.status = .completed
            gen.completedAt = Date()
            updateGeneration(gen)
        } catch {
            gen.status = .failed
            gen.error = error.localizedDescription
            updateGeneration(gen)
            NaviLog.error("MediaGen: bildgenerering misslyckades", error: error)
        }
    }

    // MARK: - Generate Video (xAI Aurora)

    func generateVideo(
        prompt: String,
        referenceImageData: Data? = nil,
        duration: Int = 5,
        ratio: String = "720:1280"
    ) async {
        guard canGenerate else {
            NaviLog.warning("MediaGen: max \(maxConcurrent) samtidiga genereringar nått")
            return
        }

        // Convert "width:height" ratio to "w:h" aspect ratio string for xAI
        let aspectRatio = ratio == "1280:720" ? "16:9" : "9:16"

        var gen = MediaGeneration(
            type: .video,
            prompt: prompt,
            model: "aurora",
            parameters: MediaParameters(aspectRatio: aspectRatio, duration: duration)
        )
        gen.status = .generating
        generations.insert(gen, at: 0)
        await saveHistory()

        do {
            // Set thumbnail from reference image if provided
            if let provided = referenceImageData {
                gen.thumbnailData = await Task.detached(priority: .utility) {
                    MediaGenerationManager.makeThumbnail(from: provided)
                }.value
                updateGeneration(gen)
            }

            // Generate video with xAI (image-to-video if reference provided, else text-to-video)
            let videoData = try await client.generateVideo(
                prompt: prompt,
                imageData: referenceImageData,
                duration: duration,
                aspectRatio: aspectRatio
            )

            let filename = "\(gen.id.uuidString).mp4"
            try await saveToICloud(data: videoData, folder: Constants.iCloud.mediaVideosFolder, filename: filename)

            gen.resultFilename = filename
            if gen.thumbnailData == nil {
                let captured = videoData
                gen.thumbnailData = await Task.detached(priority: .utility) {
                    MediaGenerationManager.makeVideoThumbnail(from: captured)
                }.value
            }

            gen.status = .completed
            gen.completedAt = Date()
            updateGeneration(gen)

        } catch {
            gen.status = .failed
            gen.error = error.localizedDescription
            updateGeneration(gen)
            NaviLog.error("MediaGen: videogenerering misslyckades", error: error)
        }
    }

    // MARK: - Balance

    func refreshBalance() async {
        isLoadingBalance = true
        defer { isLoadingBalance = false }

        do {
            balance = try await client.fetchBalance()
        } catch {
            NaviLog.warning("MediaGen: kunde inte hämta saldo: \(error.localizedDescription)")
        }
    }

    // MARK: - Delete

    func delete(_ generation: MediaGeneration) async {
        generations.removeAll { $0.id == generation.id }

        // Delete file from iCloud
        if let filename = generation.resultFilename,
           let root = icloud.naviRoot {
            let filePath = root
                .appendingPathComponent(generation.iCloudSubfolder)
                .appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: filePath)
        }

        await saveHistory()
    }

    // MARK: - Persistence

    func loadHistory() async {
        guard let root = icloud.mediaRoot else { return }
        let historyURL = root.appendingPathComponent(historyFilename)

        do {
            let history: MediaHistory = try await icloud.read(MediaHistory.self, from: historyURL)
            generations = history.generations.sorted { $0.createdAt > $1.createdAt }
        } catch {
            // First launch or no history
            generations = []
        }
    }

    func saveHistory() async {
        guard let root = icloud.mediaRoot else { return }
        let historyURL = root.appendingPathComponent(historyFilename)
        let history = MediaHistory(generations: generations)
        try? await icloud.write(history, to: historyURL)
    }

    // MARK: - File helpers

    private func saveToICloud(data: Data, folder: String, filename: String) async throws {
        guard let root = icloud.naviRoot else {
            throw XAIError.invalidResponse
        }
        let folderURL = root.appendingPathComponent(folder)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let fileURL = folderURL.appendingPathComponent(filename)
        try await icloud.writeData(data, to: fileURL)
    }

    func imageURL(for generation: MediaGeneration) -> URL? {
        guard let filename = generation.resultFilename,
              let root = icloud.naviRoot else { return nil }
        return root
            .appendingPathComponent(generation.iCloudSubfolder)
            .appendingPathComponent(filename)
    }

    // nonisolated + static: safe to call from a Task.detached (no MainActor requirement)
    nonisolated static func makeThumbnail(from imageData: Data) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: imageData) else { return nil }
        let size = NSSize(width: 200, height: 200)
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()
        guard let tiff = thumbnail.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        #else
        guard let image = UIImage(data: imageData) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: CGSize(width: 200, height: 200)))
        }
        return thumbnail.jpegData(compressionQuality: 0.6)
        #endif
    }

    private func updateGeneration(_ gen: MediaGeneration) {
        if let idx = generations.firstIndex(where: { $0.id == gen.id }) {
            generations[idx] = gen
        }
        // Debounce saves — batch rapid status updates into a single iCloud write
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard !Task.isCancelled else { return }
            await saveHistory()
        }
    }

    nonisolated static func makeVideoThumbnail(from videoData: Data) -> Data? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        guard (try? videoData.write(to: tmpURL)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let asset = AVURLAsset(url: tmpURL)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        guard let cgImage = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }

        #if os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        #else
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.6)
        #endif
    }
}

