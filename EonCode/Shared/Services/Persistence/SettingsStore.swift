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

    private let defaults = UserDefaults.standard

    private init() {
        defaultModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "defaultModel") ?? "") ?? .sonnet45
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
    }

    private func save(_ key: String, value: Any?) {
        defaults.set(value, forKey: key)
    }
}
