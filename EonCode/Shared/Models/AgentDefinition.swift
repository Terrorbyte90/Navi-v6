import Foundation

// MARK: - Agent Definition (user-created autonomous agent)

struct AgentDefinition: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var goal: String                    // The long-form goal the agent works toward
    var projectID: UUID?                // Linked project (optional)
    var projectName: String?
    var model: ClaudeModel
    var createdAt: Date
    var lastActiveAt: Date?
    var status: AutonomousAgentStatus
    var runLog: [AgentRunEntry]         // Persistent log of all actions
    var currentTaskDescription: String  // What it's doing right now
    var totalTokensUsed: Int
    var totalCostSEK: Double
    var iterationCount: Int             // How many reasoning loops completed
    var maxIterations: Int              // Safety cap (0 = unlimited)
    var autoRestartOnFailure: Bool
    var conversationHistory: [StoredMessage] // Full conversation for context

    init(
        id: UUID = UUID(),
        name: String,
        goal: String,
        projectID: UUID? = nil,
        projectName: String? = nil,
        model: ClaudeModel = .sonnet45,
        maxIterations: Int = 0,
        autoRestartOnFailure: Bool = false
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.projectID = projectID
        self.projectName = projectName
        self.model = model
        self.createdAt = Date()
        self.status = .idle
        self.runLog = []
        self.currentTaskDescription = ""
        self.totalTokensUsed = 0
        self.totalCostSEK = 0
        self.iterationCount = 0
        self.maxIterations = maxIterations
        self.autoRestartOnFailure = autoRestartOnFailure
        self.conversationHistory = []
    }

    static func == (lhs: AgentDefinition, rhs: AgentDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

enum AutonomousAgentStatus: String, Codable, Equatable {
    case idle
    case running
    case paused
    case completed
    case failed

    var displayName: String {
        switch self {
        case .idle:      return "Inaktiv"
        case .running:   return "Arbetar"
        case .paused:    return "Pausad"
        case .completed: return "Klar"
        case .failed:    return "Misslyckad"
        }
    }

    var isActive: Bool { self == .running }

    var color: String {
        switch self {
        case .idle:      return "gray"
        case .running:   return "green"
        case .paused:    return "orange"
        case .completed: return "blue"
        case .failed:    return "red"
        }
    }
}

struct AgentRunEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var type: EntryType
    var content: String
    var isError: Bool = false

    enum EntryType: String, Codable {
        case thought, action, result, tool, error, milestone, userMessage, assistantMessage
    }
}

struct StoredMessage: Codable {
    var role: String   // "user" or "assistant"
    var content: String
    var timestamp: Date = Date()
}
