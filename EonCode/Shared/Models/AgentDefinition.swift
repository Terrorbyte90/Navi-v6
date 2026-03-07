import Foundation

// MARK: - Agent Definition (user-created autonomous agent)

struct AgentDefinition: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var goal: String                        // Long-form goal the agent works toward
    var projectID: UUID?
    var projectName: String?

    // ── Modell & kapacitet ──────────────────────────────────────────────────
    var model: ClaudeModel                  // Primär modell (orkestrator)
    var workerModel: ClaudeModel            // Modell för workers (ofta billigare)
    var assignedWorkers: Int                // Antal parallella workers (1–10)
    var maxTokensPerIteration: Int          // Alltid obegränsat (högt värde)

    // ── Beteende ────────────────────────────────────────────────────────────
    var maxIterations: Int                  // 0 = obegränsat
    var iterationDelaySeconds: Double       // Paus mellan iterationer
    var autoRestartOnFailure: Bool
    var pauseOnUserQuestion: Bool           // Pausa och vänta om agenten ställer fråga
    var verboseLogging: Bool                // Logga varje tanke/steg detaljerat
    var autoCommitToGitHub: Bool            // Auto-commit ändringar efter varje iteration
    var githubBranch: String                // Branch att commita till (om autoCommit)

    // ── Kontext & minne ─────────────────────────────────────────────────────
    var systemPromptAddition: String        // Extra instruktioner utöver standard
    var maxHistoryMessages: Int             // Hur många meddelanden att behålla i kontext
    var memoryEnabled: Bool                 // Använd Navi-minnen som kontext

    // ── Notifikationer ──────────────────────────────────────────────────────
    var notifyOnCompletion: Bool
    var notifyOnFailure: Bool
    var notifyOnUserQuestion: Bool

    // ── Körstatistik ────────────────────────────────────────────────────────
    var createdAt: Date
    var lastActiveAt: Date?
    var status: AutonomousAgentStatus
    var runLog: [AgentRunEntry]
    var currentTaskDescription: String
    var iterationCount: Int
    var conversationHistory: [StoredMessage]

    // ── Kostnad (agent + workers) ────────────────────────────────────────────
    var totalTokensUsed: Int
    var totalCostSEK: Double
    var workerTokensUsed: Int               // Tokens förbrukade av workers
    var workerCostSEK: Double               // Kostnad för workers separat
    var sessionTokensUsed: Int             // Tokens sedan senaste start
    var sessionCostSEK: Double             // Kostnad sedan senaste start

    init(
        id: UUID = UUID(),
        name: String,
        goal: String,
        projectID: UUID? = nil,
        projectName: String? = nil,
        model: ClaudeModel = .sonnet45,
        workerModel: ClaudeModel = .haiku,
        assignedWorkers: Int = 2,
        maxTokensPerIteration: Int = 128000,
        maxIterations: Int = 0,
        iterationDelaySeconds: Double = 0,
        autoRestartOnFailure: Bool = false,
        pauseOnUserQuestion: Bool = true,
        verboseLogging: Bool = false,
        autoCommitToGitHub: Bool = false,
        githubBranch: String = "main",
        systemPromptAddition: String = "",
        maxHistoryMessages: Int = 100,
        memoryEnabled: Bool = true,
        notifyOnCompletion: Bool = true,
        notifyOnFailure: Bool = true,
        notifyOnUserQuestion: Bool = true
    ) {
        self.id = id
        self.name = name
        self.goal = goal
        self.projectID = projectID
        self.projectName = projectName
        self.model = model
        self.workerModel = workerModel
        self.assignedWorkers = assignedWorkers
        self.maxTokensPerIteration = maxTokensPerIteration
        self.maxIterations = maxIterations
        self.iterationDelaySeconds = iterationDelaySeconds
        self.autoRestartOnFailure = autoRestartOnFailure
        self.pauseOnUserQuestion = pauseOnUserQuestion
        self.verboseLogging = verboseLogging
        self.autoCommitToGitHub = autoCommitToGitHub
        self.githubBranch = githubBranch
        self.systemPromptAddition = systemPromptAddition
        self.maxHistoryMessages = maxHistoryMessages
        self.memoryEnabled = memoryEnabled
        self.notifyOnCompletion = notifyOnCompletion
        self.notifyOnFailure = notifyOnFailure
        self.notifyOnUserQuestion = notifyOnUserQuestion
        self.createdAt = Date()
        self.status = .idle
        self.runLog = []
        self.currentTaskDescription = ""
        self.iterationCount = 0
        self.conversationHistory = []
        self.totalTokensUsed = 0
        self.totalCostSEK = 0
        self.workerTokensUsed = 0
        self.workerCostSEK = 0
        self.sessionTokensUsed = 0
        self.sessionCostSEK = 0
    }

    // Total kostnad inkl workers
    var grandTotalCostSEK: Double { totalCostSEK + workerCostSEK }
    var grandTotalTokens: Int { totalTokensUsed + workerTokensUsed }
    var sessionTotalCostSEK: Double { sessionCostSEK + workerCostSEK } // approx

    static func == (lhs: AgentDefinition, rhs: AgentDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Status

enum AutonomousAgentStatus: String, Codable, Equatable {
    case idle, running, paused, completed, failed

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
}

// MARK: - Log entry

struct AgentRunEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var type: EntryType
    var content: String
    var isError: Bool = false
    var costSEK: Double? = nil          // Kostnad för just detta steg (om känt)
    var tokensUsed: Int? = nil

    enum EntryType: String, Codable {
        case thought, action, result, tool, error, milestone, userMessage, assistantMessage, workerResult
    }
}

// MARK: - Stored message (conversation history)

struct StoredMessage: Codable {
    var role: String
    var content: String
    var timestamp: Date = Date()
}
