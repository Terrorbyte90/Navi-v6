import Foundation

struct AgentTask: Identifiable, Codable, Equatable {
    var id: UUID
    var projectID: UUID
    var conversationID: UUID?
    var instruction: String
    var status: AgentTaskStatus
    var steps: [AgentStep]
    var currentStepIndex: Int
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var error: String?
    var result: String?
    var checkpointData: Data?
    var iCloudPath: String?       // Path to task file in iCloud

    init(
        id: UUID = UUID(),
        projectID: UUID,
        instruction: String,
        conversationID: UUID? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.instruction = instruction
        self.conversationID = conversationID
        self.status = .pending
        self.steps = []
        self.currentStepIndex = 0
        self.createdAt = Date()
    }

    var currentStep: AgentStep? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        let completed = steps.filter { $0.status == .completed }.count
        return Double(completed) / Double(steps.count)
    }

    var progressText: String {
        "Steg \(currentStepIndex + 1) av \(steps.count)"
    }

    static func == (lhs: AgentTask, rhs: AgentTask) -> Bool {
        lhs.id == rhs.id
    }
}

enum AgentTaskStatus: String, Codable, Equatable {
    case pending
    case planning
    case running
    case paused
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .pending: return "Väntar"
        case .planning: return "Planerar"
        case .running: return "Kör"
        case .paused: return "Pausad"
        case .completed: return "Klar"
        case .failed: return "Misslyckad"
        case .cancelled: return "Avbruten"
        }
    }

    var isActive: Bool {
        self == .running || self == .planning
    }
}

struct AgentStep: Identifiable, Codable, Equatable {
    var id: UUID
    var taskID: UUID
    var index: Int
    var action: AgentAction
    var status: StepStatus
    var output: String?
    var error: String?
    var startedAt: Date?
    var completedAt: Date?
    var tokensUsed: Int
    var ranLocally: Bool        // true = ran on this device, false = queued to Mac
    var workerID: UUID?         // set when run by a parallel worker

    init(id: UUID = UUID(), taskID: UUID, index: Int, action: AgentAction, ranLocally: Bool = true) {
        self.id = id
        self.taskID = taskID
        self.index = index
        self.action = action
        self.status = .pending
        self.tokensUsed = 0
        self.ranLocally = ranLocally
    }

    static func == (lhs: AgentStep, rhs: AgentStep) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Agent mode (iOS Autonomous vs Remote-only)

enum AgentMode: String, Codable, CaseIterable {
    case autonomous   // iOS does what it can; queues the rest
    case remoteOnly   // Queue everything to Mac

    var displayName: String {
        switch self {
        case .autonomous: return "Autonom"
        case .remoteOnly: return "Remote"
        }
    }

    var description: String {
        switch self {
        case .autonomous: return "iOS gör allt den kan. Terminkommandon köas till Mac."
        case .remoteOnly: return "Alla instruktioner skickas till Mac."
        }
    }
}

// MARK: - Worker task (for parallel execution)

struct WorkerTask: Identifiable, Codable {
    var id: UUID = UUID()
    var description: String
    var instruction: String
    var requiresTerminal: Bool
    var dependsOn: [UUID]   // IDs of tasks that must complete first
    var waveIndex: Int
    var status: StepStatus = .pending
    var result: String?
    var ranLocally: Bool = false
}

struct TaskWave: Codable {
    var index: Int
    var description: String
    var tasks: [WorkerTask]
    var dependsOnWave: Int?
}

struct WorkerResult: Identifiable {
    let id: UUID
    let taskID: UUID
    let output: String
    let filesWritten: [String]
    let succeeded: Bool
    let ranLocally: Bool
    let durationSeconds: Double
}

enum StepStatus: String, Codable, Equatable {
    case pending, running, completed, failed, skipped
}

enum AgentAction: Codable, Equatable {
    case research(query: String)
    case readFile(path: String)
    case writeFile(path: String, content: String)
    case moveFile(from: String, to: String)
    case deleteFile(path: String)
    case createDirectory(path: String)
    case listDirectory(path: String)
    case runCommand(cmd: String)
    case buildProject(path: String)
    case deployTestFlight(scheme: String)
    case searchFiles(query: String)
    case downloadFile(url: String, destination: String)
    case extractArchive(path: String, destination: String)
    case createArchive(source: String, destination: String)
    case getAPIKey(service: String)
    case think(reasoning: String)
    case askUser(question: String)
    case custom(name: String, params: [String: String])

    var displayName: String {
        switch self {
        case .research: return "Forskar"
        case .readFile(let p): return "Läser \((p as NSString).lastPathComponent)"
        case .writeFile(let p, _): return "Skriver \((p as NSString).lastPathComponent)"
        case .moveFile: return "Flyttar fil"
        case .deleteFile(let p): return "Tar bort \((p as NSString).lastPathComponent)"
        case .createDirectory(let p): return "Skapar mapp \((p as NSString).lastPathComponent)"
        case .listDirectory: return "Listar katalog"
        case .runCommand(let cmd): return "Kör: \(String(cmd.prefix(40)))"
        case .buildProject: return "Bygger projekt"
        case .deployTestFlight(let s): return "Deploy till TestFlight: \(s)"
        case .searchFiles(let q): return "Söker: \(q)"
        case .downloadFile(let url, _): return "Laddar ned \((url as NSString).lastPathComponent)"
        case .extractArchive: return "Packar upp arkiv"
        case .createArchive: return "Skapar arkiv"
        case .getAPIKey(let s): return "Hämtar nyckel: \(s)"
        case .think: return "Tänker"
        case .askUser(let q): return "Frågar: \(q)"
        case .custom(let n, _): return n
        }
    }

    var isDestructive: Bool {
        switch self {
        case .deleteFile, .runCommand, .deployTestFlight: return true
        default: return false
        }
    }
}
