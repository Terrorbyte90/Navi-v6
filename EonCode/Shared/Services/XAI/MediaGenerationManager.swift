import Foundation
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
                let imageData = try await client.downloadImageData(from: result.url)
                let filename = "\(gen.id.uuidString)\(i > 0 ? "-\(i)" : "").png"

                try await saveToICloud(data: imageData, folder: Constants.iCloud.mediaImagesFolder, filename: filename)

                if i == 0 {
                    gen.resultFilename = filename
                    gen.thumbnailData = createThumbnail(from: imageData)
                }
            }

            let pricePerImage = model.contains("pro") ? 0.07 : 0.02
            let costUSD = Double(variations) * pricePerImage
            gen.costUSD = costUSD
            gen.costSEK = costUSD * ExchangeRateService.shared.usdToSEK
            gen.status = .completed
            gen.completedAt = Date()

            updateGeneration(gen)
            CostTracker.shared.recordMediaCost(usd: costUSD, model: gen.model)
        } catch {
            gen.status = .failed
            gen.error = error.localizedDescription
            updateGeneration(gen)
            NaviLog.error("MediaGen: bildgenerering misslyckades", error: error)
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

    private func createThumbnail(from imageData: Data) -> Data? {
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
        let size = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return thumbnail?.jpegData(compressionQuality: 0.6)
        #endif
    }

    private func updateGeneration(_ gen: MediaGeneration) {
        if let idx = generations.firstIndex(where: { $0.id == gen.id }) {
            generations[idx] = gen
        }
        Task { await saveHistory() }
    }
}

