import Foundation

enum Constants {
    enum API {
        static let anthropicBaseURL = "https://api.anthropic.com/v1/messages"
        static let anthropicVersion = "2023-06-01"
        static let elevenLabsBaseURL = "https://api.elevenlabs.io/v1"
        static let exchangeRateURL = "https://open.er-api.com/v6/latest/USD"
        static let xaiBaseURL = "https://api.x.ai/v1"
        static let xaiChatEndpoint = "https://api.x.ai/v1/chat/completions"
        static let openRouterBaseURL = "https://openrouter.ai/api/v1/chat/completions"
        static let xaiImageEndpoint = "https://api.x.ai/v1/images/generations"
        static let xaiVideoEndpoint = "https://api.x.ai/v1/videos/generations"
        static let xaiVideoPollBase  = "https://api.x.ai/v1/videos"
    }

    enum iCloud {
        static let containerID = "iCloud.com.tedsvard.navi"
        static let rootFolder = "Navi"
        static let projectsFolder = "Projects"
        static let instructionsFolder = "Instructions"
        static let versionsFolder = "Versions"
        static let conversationsFolder = "Conversations"
        static let deviceStatusFolder = "DeviceStatus"
        static let checkpointsFolder = "Checkpoints"
        static let plansFolder = "Plans"
        static let agentsFolder = "Agents"
        static let mediaFolder = "Media"
        static let mediaImagesFolder = "Media/Images"
        static let mediaVideosFolder = "Media/Videos"
        static let mediaAudioFolder  = "Media/Ljud"
        static let defaultProjectsFolder = "Navi/Projects"
        static let githubReposFolder = "GitHub/Repos"
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
        static let grok4 = "grok-4"
        static let grok41Fast = "grok-4-1-fast"
        static let grok3Mini = "grok-3-mini"
        static let minimaxM25 = "minimax/minimax-m2.5"
        static let kimiK25 = "moonshotai/kimi-k2.5"
        static let qwen3CoderFree = "qwen/qwen3-coder:free"

        // Price per million tokens (USD)
        static let prices: [String: (input: Double, output: Double)] = [
            haiku:          (1.0,   5.0),
            sonnet45:       (3.0,  15.0),
            sonnet46:       (3.0,  15.0),
            opus46:         (5.0,  25.0),
            grok4:          (3.0,  15.0),
            grok41Fast:     (0.20,  0.50),
            grok3Mini:      (0.30,  0.50),
            minimaxM25:     (0.295, 1.20),
            kimiK25:        (0.45,  2.20),
            qwen3CoderFree: (0.0,   0.0),
        ]
    }

    enum Keychain {
        static let service = "com.tedsvard.navi.apikeys"
        static let anthropicKey = "anthropic"
        static let elevenLabsKey = "elevenlabs"
        static let muxKey = "mux"
        static let githubKey = "github"
        static let xaiKey = "xai"
        static let openRouterKey = "openrouter"
        static let accessGroup = "com.tedsvard.navi"
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

// MARK: - AI Provider

enum AIProvider: String, Codable {
    case anthropic
    case xai
    case openRouter
}

// MARK: - Model enum

enum ClaudeModel: String, CaseIterable, Codable, Identifiable {
    // Anthropic
    case haiku = "claude-haiku-4-5-20251001"
    case sonnet45 = "claude-sonnet-4-5"
    case sonnet46 = "claude-sonnet-4-6"
    case opus46 = "claude-opus-4-6"
    // xAI / Grok
    case grok4 = "grok-4"
    case grok41Fast = "grok-4-1-fast"
    case grok3Mini = "grok-3-mini"
    // OpenRouter
    case minimaxM25 = "minimax/minimax-m2.5"
    case kimiK25 = "moonshotai/kimi-k2.5"
    case qwen3CoderFree = "qwen/qwen3-coder:free"

    var id: String { rawValue }

    var provider: AIProvider {
        switch self {
        case .haiku, .sonnet45, .sonnet46, .opus46: return .anthropic
        case .grok4, .grok41Fast, .grok3Mini: return .xai
        case .minimaxM25, .kimiK25, .qwen3CoderFree: return .openRouter
        }
    }

    var displayName: String {
        switch self {
        case .haiku:      return "Haiku 4.5"
        case .sonnet45:   return "Sonnet 4.5"
        case .sonnet46:   return "Sonnet 4.6"
        case .opus46:     return "Opus 4.6"
        case .grok4:          return "Grok 4"
        case .grok41Fast:     return "Grok 4.1 Fast"
        case .grok3Mini:      return "Grok 3 Mini"
        case .minimaxM25:     return "MiniMax M2.5"
        case .kimiK25:        return "Kimi K2.5"
        case .qwen3CoderFree: return "Qwen3 Coder (gratis)"
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
        case .haiku:      return "Snabbast & billigast · $1/$5/MTok"
        case .sonnet45:   return "Balanserad · $3/$15/MTok"
        case .sonnet46:   return "Senaste Sonnet · $3/$15/MTok"
        case .opus46:     return "Kraftfullast · $5/$25/MTok"
        case .grok4:          return "Mest kapabel · $3/$15/MTok"
        case .grok41Fast:     return "Snabb & billig · $0.20/$0.50/MTok"
        case .grok3Mini:      return "Liten & effektiv · $0.30/$0.50/MTok"
        case .minimaxM25:     return "80% SWE-Bench · $0.295/$1.20/MTok"
        case .kimiK25:        return "Agentisk kodning · $0.45/$2.20/MTok"
        case .qwen3CoderFree: return "480B MoE · GRATIS · 262K context"
        }
    }

    /// Group label for UI sections
    var providerDisplayName: String {
        switch provider {
        case .anthropic: return "Anthropic"
        case .xai: return "xAI / Grok"
        case .openRouter: return "OpenRouter"
        }
    }

    /// Models grouped by provider for the model picker
    static var anthropicModels: [ClaudeModel] { [.haiku, .sonnet45, .sonnet46, .opus46] }
    static var xaiModels: [ClaudeModel] { [.grok4, .grok41Fast, .grok3Mini] }
    static var openRouterModels: [ClaudeModel] { [.minimaxM25, .kimiK25, .qwen3CoderFree] }

    // Safe Codable: fall back to .haiku for unknown raw values
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ClaudeModel(rawValue: raw) ?? .haiku
    }
}
