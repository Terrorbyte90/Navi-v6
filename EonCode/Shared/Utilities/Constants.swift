import Foundation

enum Constants {
    enum API {
        static let anthropicBaseURL = "https://api.anthropic.com/v1/messages"
        static let anthropicVersion = "2023-06-01"
        static let elevenLabsBaseURL = "https://api.elevenlabs.io/v1"
        static let exchangeRateURL = "https://open.er-api.com/v6/latest/USD"
    }

    enum iCloud {
        static let containerID = "iCloud.com.navi"
        static let rootFolder = "Navi"
        static let projectsFolder = "Projects"
        static let instructionsFolder = "Instructions"
        static let versionsFolder = "Versions"
        static let conversationsFolder = "Conversations"
        static let deviceStatusFolder = "DeviceStatus"
        static let checkpointsFolder = "Checkpoints"
        static let defaultProjectsFolder = "Navi/Projects"
    }

    enum Sync {
        static let bonjourServiceType = "_navi._tcp"
        static let httpServiceType = "_navi-http._tcp"
        static let localHTTPPort: UInt16 = 52731
        static let statusFileName = "device-status.json"
        static let instructionPollInterval: TimeInterval = 2.0
        static let syncDebounceInterval: TimeInterval = 1.0
        static let macServerInfoFile = "mac-server.json"
    }

    enum Models {
        static let haiku = "claude-haiku-4-5-20251001"
        static let sonnet45 = "claude-sonnet-4-5"
        static let sonnet46 = "claude-sonnet-4-6"
        static let opus46 = "claude-opus-4-6"

        // Price per million tokens (USD)
        static let prices: [String: (input: Double, output: Double)] = [
            haiku:    (1.0,   5.0),
            sonnet45: (3.0,  15.0),
            sonnet46: (3.0,  15.0),
            opus46:   (15.0, 75.0)
        ]
    }

    enum Keychain {
        static let service = "com.navi.apikeys"
        static let anthropicKey = "anthropic"
        static let elevenLabsKey = "elevenlabs"
        static let muxKey = "mux"
        static let githubKey = "github"
        static let accessGroup = "com.navi"
    }

    enum Agent {
        static let maxBuildAttempts = 20
        static let maxTokensDefault = 8192
        static let maxTokensLarge = 16384
        static let contextWindowBuffer = 2000
    }

    enum UI {
        static let sidebarWidth: CGFloat = 260
        static let minWindowWidth: CGFloat = 900
        static let minWindowHeight: CGFloat = 600
    }
}

enum ClaudeModel: String, CaseIterable, Codable, Identifiable {
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet45 = "claude-sonnet-4-5"
    case sonnet46 = "claude-sonnet-4-6"
    case opus46 = "claude-opus-4-6"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku: return "Haiku 4.5"
        case .sonnet45: return "Sonnet 4.5"
        case .sonnet46: return "Sonnet 4.6"
        case .opus46: return "Opus 4.6"
        }
    }

    var inputPricePerMTok: Double {
        Constants.Models.prices[rawValue]?.input ?? 1.0
    }

    var outputPricePerMTok: Double {
        Constants.Models.prices[rawValue]?.output ?? 5.0
    }

    var description: String {
        switch self {
        case .haiku: return "Snabbast & billigast · $1/$5/MTok"
        case .sonnet45: return "Balanserad · $3/$15/MTok"
        case .sonnet46: return "Senaste Sonnet · $3/$15/MTok"
        case .opus46: return "Kraftfullast · $15/$75/MTok"
        }
    }
}
