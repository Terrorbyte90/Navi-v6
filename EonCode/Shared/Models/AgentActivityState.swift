import Foundation
import SwiftUI

// MARK: - Agent Activity State (drives all visual feedback across views)

@MainActor
@Observable
final class AgentActivityState {
    // Current phase
    var phase: AgentPhase = .idle

    // Structured TODO
    var todoItems: [AgentTodoItem] = []

    // Code changes with diff data
    var codeChanges: [CodeChange] = []

    // Timeline of all actions
    var timeline: [TimelineEntry] = []

    // Metrics
    var currentCostSEK: Double = 0
    var tokensUsed: Int = 0
    var startTime: Date?
    var progress: Double = 0 // 0.0 - 1.0

    // Streaming code display
    var activeFileContent: String = ""
    var activeFileName: String = ""

    var isActive: Bool { phase != .idle }

    var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    var totalLinesAdded: Int { codeChanges.reduce(0) { $0 + $1.linesAdded } }
    var totalLinesRemoved: Int { codeChanges.reduce(0) { $0 + $1.linesRemoved } }
    var todoCompletedCount: Int { todoItems.filter { $0.status == .done }.count }

    // MARK: - Phase updates

    func begin() {
        startTime = Date()
        phase = .idle
        todoItems = []
        codeChanges = []
        timeline = []
        currentCostSEK = 0
        tokensUsed = 0
        progress = 0
        activeFileContent = ""
        activeFileName = ""
    }

    func setPhase(_ newPhase: AgentPhase) {
        phase = newPhase
        addTimelineEntry(for: newPhase)
    }

    func complete(summary: AgentSummary) {
        phase = .complete(summary: summary)
        progress = 1.0
        addTimelineEntry(
            icon: "checkmark.circle.fill",
            title: "Klart",
            detail: "\(summary.filesModified) filer ändrade, +\(summary.totalLinesAdded)/-\(summary.totalLinesRemoved) rader"
        )
    }

    func fail(message: String) {
        phase = .error(message: message)
        addTimelineEntry(icon: "xmark.circle.fill", title: "Fel", detail: message)
    }

    func reset() {
        phase = .idle
        todoItems = []
        codeChanges = []
        timeline = []
        currentCostSEK = 0
        tokensUsed = 0
        startTime = nil
        progress = 0
        activeFileContent = ""
        activeFileName = ""
    }

    // MARK: - TODO management

    func setTodoItems(_ items: [(String, String?)]) {
        todoItems = items.enumerated().map { index, item in
            AgentTodoItem(
                title: item.0,
                status: index == 0 ? .active : .waiting,
                detail: item.1
            )
        }
    }

    func advanceTodo() {
        if let currentIndex = todoItems.firstIndex(where: { $0.status == .active }) {
            todoItems[currentIndex].status = .done
            if currentIndex + 1 < todoItems.count {
                todoItems[currentIndex + 1].status = .active
            }
            progress = Double(todoCompletedCount) / Double(max(todoItems.count, 1))
        }
    }

    func failCurrentTodo(error: String) {
        if let currentIndex = todoItems.firstIndex(where: { $0.status == .active }) {
            todoItems[currentIndex].status = .failed
            todoItems[currentIndex].detail = error
        }
    }

    // MARK: - Code change tracking

    func recordFileChange(file: String, oldContent: String, newContent: String) {
        let hunks = DiffEngine.diff(old: oldContent, new: newContent)
        let added = hunks.reduce(0) { $0 + $1.lines.filter { $0.type == .added }.count }
        let removed = hunks.reduce(0) { $0 + $1.lines.filter { $0.type == .removed }.count }
        let diffLines = hunks.flatMap { $0.lines }

        if let existingIndex = codeChanges.firstIndex(where: { $0.file == file }) {
            codeChanges[existingIndex].linesAdded += added
            codeChanges[existingIndex].linesRemoved += removed
            codeChanges[existingIndex].diffLines = diffLines
        } else {
            codeChanges.append(CodeChange(
                file: file,
                linesAdded: added,
                linesRemoved: removed,
                diffLines: diffLines,
                isNewFile: oldContent.isEmpty
            ))
        }

        // Update streaming display
        activeFileName = (file as NSString).lastPathComponent
        activeFileContent = newContent
    }

    func recordNewFile(file: String, content: String) {
        let lineCount = content.components(separatedBy: "\n").count
        codeChanges.append(CodeChange(
            file: file,
            linesAdded: lineCount,
            linesRemoved: 0,
            diffLines: content.components(separatedBy: "\n").map { DiffLine(type: .added, content: $0) },
            isNewFile: true
        ))
        activeFileName = (file as NSString).lastPathComponent
        activeFileContent = content
    }

    // MARK: - Cost tracking

    func addCost(usage: TokenUsage, model: ClaudeModel) {
        tokensUsed += usage.inputTokens + usage.outputTokens
        let (_, sek) = CostCalculator.shared.calculate(usage: usage, model: model)
        currentCostSEK += sek
    }

    // MARK: - Timeline

    private func addTimelineEntry(for phase: AgentPhase) {
        let (icon, title) = phase.timelineInfo
        addTimelineEntry(icon: icon, title: title)
    }

    func addTimelineEntry(icon: String, title: String, detail: String? = nil) {
        timeline.append(TimelineEntry(
            timestamp: Date(),
            icon: icon,
            title: title,
            detail: detail
        ))
    }

    // MARK: - Build summary

    func buildSummary() -> AgentSummary {
        AgentSummary(
            filesModified: codeChanges.filter { !$0.isNewFile }.count,
            filesCreated: codeChanges.filter { $0.isNewFile }.count,
            totalLinesAdded: totalLinesAdded,
            totalLinesRemoved: totalLinesRemoved,
            costSEK: currentCostSEK,
            duration: elapsedTime,
            todoCompleted: todoCompletedCount,
            todoTotal: todoItems.count
        )
    }
}

// MARK: - Agent Phase

enum AgentPhase: Equatable {
    case idle
    case scanning(fileCount: Int)
    case planning(description: String)
    case thinking(about: String)
    case reading(file: String)
    case writing(file: String, added: Int, removed: Int)
    case creating(file: String)
    case running(command: String)
    case building(progress: Double)
    case browsing(url: String, action: String)
    case complete(summary: AgentSummary)
    case error(message: String)

    var displayText: String {
        switch self {
        case .idle: return ""
        case .scanning(let count): return "Skannar projektet (\(count) filer)…"
        case .planning(let desc): return "Planerar: \(desc)"
        case .thinking(let about): return "Tänker på \(about)…"
        case .reading(let file): return "Läser \((file as NSString).lastPathComponent)…"
        case .writing(let file, let added, let removed):
            return "Skriver \((file as NSString).lastPathComponent) (+\(added)/-\(removed))"
        case .creating(let file): return "Skapar \((file as NSString).lastPathComponent)…"
        case .running(let cmd): return "Kör: \(String(cmd.prefix(50)))"
        case .building(let p): return "Bygger… \(Int(p * 100))%"
        case .browsing(_, let action): return "Webbläsare: \(action)"
        case .complete: return "Klart!"
        case .error(let msg): return "Fel: \(msg)"
        }
    }

    var iconName: String {
        switch self {
        case .idle: return "circle"
        case .scanning: return "doc.text.magnifyingglass"
        case .planning: return "list.bullet.clipboard"
        case .thinking: return "brain"
        case .reading: return "doc.text"
        case .writing: return "pencil.line"
        case .creating: return "doc.badge.plus"
        case .running: return "terminal"
        case .building: return "hammer"
        case .browsing: return "globe"
        case .complete: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .idle: return .secondary
        case .scanning: return .blue
        case .planning: return .purple
        case .thinking: return .orange
        case .reading: return .cyan
        case .writing: return .green
        case .creating: return .mint
        case .running: return .yellow
        case .building: return .orange
        case .browsing: return .blue
        case .complete: return .green
        case .error: return .red
        }
    }

    var timelineInfo: (icon: String, title: String) {
        switch self {
        case .idle: return ("circle", "")
        case .scanning(let c): return ("doc.text.magnifyingglass", "Skannar \(c) filer")
        case .planning(let d): return ("list.bullet.clipboard", "Planerar: \(d)")
        case .thinking(let a): return ("brain", "Tänker: \(a)")
        case .reading(let f): return ("doc.text", "Läser \((f as NSString).lastPathComponent)")
        case .writing(let f, _, _): return ("pencil.line", "Skriver \((f as NSString).lastPathComponent)")
        case .creating(let f): return ("doc.badge.plus", "Skapar \((f as NSString).lastPathComponent)")
        case .running(let c): return ("terminal", "Kör: \(String(c.prefix(40)))")
        case .building: return ("hammer", "Bygger projekt")
        case .browsing(_, let a): return ("globe", a)
        case .complete: return ("checkmark.circle.fill", "Klart")
        case .error(let m): return ("xmark.circle.fill", "Fel: \(m)")
        }
    }

    static func == (lhs: AgentPhase, rhs: AgentPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.scanning(let a), .scanning(let b)): return a == b
        case (.complete, .complete): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Supporting types

struct AgentTodoItem: Identifiable {
    let id = UUID()
    var title: String
    var status: AgentTodoStatus
    var detail: String?
}

enum AgentTodoStatus {
    case waiting, active, done, failed

    var icon: String {
        switch self {
        case .waiting: return "circle"
        case .active: return "arrow.right.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .waiting: return .secondary
        case .active: return .accentNavi
        case .done: return .green
        case .failed: return .red
        }
    }
}

struct CodeChange: Identifiable {
    let id = UUID()
    var file: String
    var linesAdded: Int
    var linesRemoved: Int
    var diffLines: [DiffLine]
    var isNewFile: Bool

    var fileName: String { (file as NSString).lastPathComponent }
}

struct TimelineEntry: Identifiable {
    let id = UUID()
    var timestamp: Date
    var icon: String
    var title: String
    var detail: String?
}

struct AgentSummary: Equatable {
    var filesModified: Int
    var filesCreated: Int
    var totalLinesAdded: Int
    var totalLinesRemoved: Int
    var costSEK: Double
    var duration: TimeInterval
    var todoCompleted: Int
    var todoTotal: Int

    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}
