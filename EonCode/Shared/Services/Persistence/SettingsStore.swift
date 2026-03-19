import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var defaultModel: ClaudeModel {
        didSet { save("defaultModel", value: defaultModel.rawValue) }
    }
    @Published var ttsEnabled: Bool {
        didSet { save("ttsEnabled", value: ttsEnabled) }
    }
    @Published var darkMode: Bool {
        didSet { save("darkMode", value: darkMode) }
    }
    @Published var autoSnapshot: Bool {
        didSet { save("autoSnapshot", value: autoSnapshot) }
    }
    @Published var agentConfirmDestructive: Bool {
        didSet { save("agentConfirmDestructive", value: agentConfirmDestructive) }
    }
    @Published var iCloudDefaultFolder: String? {
        didSet { save("iCloudDefaultFolder", value: iCloudDefaultFolder) }
    }
    @Published var macServerURL: String {
        didSet { save("macServerURL", value: macServerURL) }
    }
    @Published var iosAgentMode: AgentMode {
        didSet { save("iosAgentMode", value: iosAgentMode.rawValue) }
    }
    @Published var maxParallelWorkers: Int {
        didSet { save("maxParallelWorkers", value: maxParallelWorkers) }
    }
    @Published var parallelAgentsEnabled: Bool {
        didSet { save("parallelAgentsEnabled", value: parallelAgentsEnabled) }
    }
    @Published var autoGitHubSync: Bool {
        didSet { save("autoGitHubSync", value: autoGitHubSync) }
    }
    @Published var autoExtractMemories: Bool {
        didSet { save("autoExtractMemories", value: autoExtractMemories) }
    }
    @Published var selectedVoiceID: String {
        didSet { save("selectedVoiceID", value: selectedVoiceID) }
    }
    @Published var selectedVoiceName: String {
        didSet { save("selectedVoiceName", value: selectedVoiceName) }
    }
    @Published var macHandoffEnabled: Bool {
        didSet { save("macHandoffEnabled", value: macHandoffEnabled) }
    }
    @Published var macRemoteEnabled: Bool {
        didSet { save("macRemoteEnabled", value: macRemoteEnabled) }
    }
    @Published var chatModel: String {
        didSet { save("chatModel", value: chatModel) }
    }
    @Published var codeModel: String {
        didSet { save("codeModel", value: codeModel) }
    }

    // MARK: - ElevenLabs Voice Preferences
    // Defaults tuned for natural, slightly expressive speech at a comfortable pace.

    @Published var voiceStability: Double {
        didSet { save("voiceStability", value: voiceStability) }
    }
    @Published var voiceSimilarityBoost: Double {
        didSet { save("voiceSimilarityBoost", value: voiceSimilarityBoost) }
    }
    @Published var voiceStyle: Double {
        didSet { save("voiceStyle", value: voiceStyle) }
    }
    @Published var voiceSpeed: Double {
        didSet { save("voiceSpeed", value: voiceSpeed) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaultModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "defaultModel") ?? "") ?? .qwen3CoderFree
        ttsEnabled = UserDefaults.standard.bool(forKey: "ttsEnabled")
        darkMode = UserDefaults.standard.value(forKey: "darkMode") as? Bool ?? true
        autoSnapshot = UserDefaults.standard.value(forKey: "autoSnapshot") as? Bool ?? true
        agentConfirmDestructive = UserDefaults.standard.value(forKey: "agentConfirmDestructive") as? Bool ?? true
        iCloudDefaultFolder = UserDefaults.standard.string(forKey: "iCloudDefaultFolder")
        macServerURL = UserDefaults.standard.string(forKey: "macServerURL") ?? ""
        iosAgentMode = AgentMode(rawValue: UserDefaults.standard.string(forKey: "iosAgentMode") ?? "") ?? .autonomous
        maxParallelWorkers = UserDefaults.standard.integer(forKey: "maxParallelWorkers").nonZero ?? 4
        parallelAgentsEnabled = UserDefaults.standard.value(forKey: "parallelAgentsEnabled") as? Bool ?? true
        autoGitHubSync = UserDefaults.standard.value(forKey: "autoGitHubSync") as? Bool ?? false
        autoExtractMemories = UserDefaults.standard.value(forKey: "autoExtractMemories") as? Bool ?? true
        selectedVoiceID = UserDefaults.standard.string(forKey: "selectedVoiceID") ?? "21m00Tcm4TlvDq8ikWAM"
        selectedVoiceName = UserDefaults.standard.string(forKey: "selectedVoiceName") ?? "Rachel"
        macHandoffEnabled = UserDefaults.standard.value(forKey: "macHandoffEnabled") as? Bool ?? false
        macRemoteEnabled = UserDefaults.standard.value(forKey: "macRemoteEnabled") as? Bool ?? false
        chatModel = UserDefaults.standard.string(forKey: "chatModel") ?? "claude-sonnet-4-6"
        codeModel = UserDefaults.standard.string(forKey: "codeModel") ?? "minimax"
        // Voice preferences — sensible defaults for natural-sounding speech
        voiceStability      = UserDefaults.standard.object(forKey: "voiceStability") as? Double ?? 0.45
        voiceSimilarityBoost = UserDefaults.standard.object(forKey: "voiceSimilarityBoost") as? Double ?? 0.75
        voiceStyle          = UserDefaults.standard.object(forKey: "voiceStyle") as? Double ?? 0.25
        voiceSpeed          = UserDefaults.standard.object(forKey: "voiceSpeed") as? Double ?? 0.80
    }

    private func save(_ key: String, value: Any?) {
        defaults.set(value, forKey: key)
    }
}
