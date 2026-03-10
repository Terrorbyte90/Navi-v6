import Foundation

// MARK: - PipelinePhase

enum PipelinePhase: String, Codable, CaseIterable {
    case idle
    case spec
    case research
    case setup
    case plan
    case build
    case push
    case done

    var displayName: String {
        switch self {
        case .idle:     return "Idle"
        case .spec:     return "Spec"
        case .research: return "Research"
        case .setup:    return "Setup"
        case .plan:     return "Plan"
        case .build:    return "Build"
        case .push:     return "Push"
        case .done:     return "Klar"
        }
    }

    var icon: String {
        switch self {
        case .idle:     return "circle"
        case .spec:     return "doc.text"
        case .research: return "magnifyingglass"
        case .setup:    return "hammer"
        case .plan:     return "list.bullet.clipboard"
        case .build:    return "bolt"
        case .push:     return "arrow.up.circle"
        case .done:     return "checkmark.circle.fill"
        }
    }

    var ordinal: Int {
        switch self {
        case .idle: return 0
        case .spec: return 1
        case .research: return 2
        case .setup: return 3
        case .plan: return 4
        case .build: return 5
        case .push: return 6
        case .done: return 7
        }
    }

    /// Short name for compact phase bar
    var shortName: String {
        switch self {
        case .idle:     return ""
        case .spec:     return "Spec"
        case .research: return "Sök"
        case .setup:    return "Setup"
        case .plan:     return "Plan"
        case .build:    return "Bygg"
        case .push:     return "Push"
        case .done:     return "Klar"
        }
    }
}

// MARK: - WorkerStatus

struct WorkerStatus: Identifiable, Codable {
    var id: UUID = UUID()
    var workerIndex: Int
    var isActive: Bool = false
    var currentFile: String?
    var liveCode: String = ""
    var filesWritten: [String] = []
    var isDone: Bool = false
}

// MARK: - CodeProject

struct CodeProject: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var idea: String          // original user input
    var spec: String = ""     // expanded spec from AI
    var researchNotes: String = ""
    var plan: String = ""     // phased plan from AI
    var githubRepoURL: String?
    var model: ClaudeModel
    var parallelWorkers: Int
    var currentPhase: PipelinePhase = .idle
    var messages: [PureChatMessage] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

// MARK: - CodeStoreError

enum CodeStoreError: LocalizedError {
    case iCloudUnavailable
    var errorDescription: String? { "iCloud är inte tillgängligt" }
}
