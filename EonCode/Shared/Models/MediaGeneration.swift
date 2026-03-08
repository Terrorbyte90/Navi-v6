import Foundation

// MARK: - MediaGeneration

struct MediaGeneration: Codable, Identifiable {
    let id: UUID
    var type: MediaType
    var prompt: String
    var status: GenerationStatus
    var resultFilename: String?      // filename in iCloud Media/Images or Media/Videos
    var thumbnailData: Data?
    var costUSD: Double
    var costSEK: Double
    var model: String                // "grok-2-image"
    var parameters: MediaParameters
    var createdAt: Date
    var completedAt: Date?
    var error: String?

    init(
        type: MediaType,
        prompt: String,
        model: String = "grok-2-image",
        parameters: MediaParameters = MediaParameters()
    ) {
        self.id = UUID()
        self.type = type
        self.prompt = prompt
        self.status = .pending
        self.costUSD = 0
        self.costSEK = 0
        self.model = model
        self.parameters = parameters
        self.createdAt = Date()
    }

    var displayTitle: String {
        String(prompt.prefix(50))
    }

    var durationText: String? {
        guard type == .video, let dur = parameters.duration else { return nil }
        return "\(dur)s"
    }

    var iCloudSubfolder: String {
        switch type {
        case .image: return Constants.iCloud.mediaImagesFolder
        case .video: return Constants.iCloud.mediaVideosFolder
        }
    }
}

// MARK: - Supporting types

enum MediaType: String, Codable, CaseIterable {
    case image
    case video

    var displayName: String {
        switch self {
        case .image: return "Bild"
        case .video: return "Video"
        }
    }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        }
    }
}

enum GenerationStatus: String, Codable {
    case pending
    case generating
    case completed
    case failed

    var displayName: String {
        switch self {
        case .pending:    return "Väntar…"
        case .generating: return "Genererar…"
        case .completed:  return "Klar"
        case .failed:     return "Misslyckades"
        }
    }

    var isActive: Bool { self == .pending || self == .generating }
}

struct MediaParameters: Codable {
    var size: String?           // "1024x1024", "512x512"
    var aspectRatio: String?    // "16:9", "9:16", "1:1"
    var duration: Int?          // seconds for video (1-15)
    var resolution: String?     // "720p", "480p"
    var variations: Int?        // number of images (1-4)

    init(
        size: String? = "1024x1024",
        aspectRatio: String? = nil,
        duration: Int? = nil,
        resolution: String? = nil,
        variations: Int? = 1
    ) {
        self.size = size
        self.aspectRatio = aspectRatio
        self.duration = duration
        self.resolution = resolution
        self.variations = variations
    }
}

// MARK: - Media History (iCloud persistence)

struct MediaHistory: Codable {
    var generations: [MediaGeneration]
}
