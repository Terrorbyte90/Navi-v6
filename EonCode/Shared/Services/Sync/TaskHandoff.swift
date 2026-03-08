import Foundation
import Combine
#if os(iOS)
import UserNotifications
#endif

// MARK: - Task Handoff: iOS ↔ macOS seamless task continuation

struct HandoffTask: Codable {
    var id: UUID
    var projectID: UUID
    var instruction: String
    var todoItems: [HandoffTodoItem]
    var currentStep: Int
    var totalSteps: Int
    var modifiedFiles: [String]
    var status: HandoffStatus
    var startedBy: String           // deviceID
    var continuedBy: String?        // deviceID of Mac that picked up
    var lastHeartbeat: Date
    var createdAt: Date
    var completedAt: Date?
    var result: String?
    var error: String?
    var costSEK: Double

    init(
        projectID: UUID,
        instruction: String,
        todoItems: [HandoffTodoItem] = [],
        totalSteps: Int = 0
    ) {
        self.id = UUID()
        self.projectID = projectID
        self.instruction = instruction
        self.todoItems = todoItems
        self.currentStep = 0
        self.totalSteps = totalSteps
        self.modifiedFiles = []
        self.status = .running
        self.startedBy = UIDevice.deviceID
        self.lastHeartbeat = Date()
        self.createdAt = Date()
        self.costSEK = 0
    }
}

struct HandoffTodoItem: Codable {
    var title: String
    var status: String // "waiting", "active", "done", "failed"
}

enum HandoffStatus: String, Codable {
    case running            // Originally running on starter device
    case interrupted        // Starter device went offline, not yet picked up
    case continuedOnMac     // Mac picked up and is continuing
    case completed          // Finished (by either device)
    case failed             // Failed

    var isActive: Bool { self == .running || self == .continuedOnMac }
}

// MARK: - Task Handoff Manager

@MainActor
final class TaskHandoffManager: ObservableObject {
    static let shared = TaskHandoffManager()

    @Published var activeHandoff: HandoffTask?
    @Published var completedNotifications: [HandoffTask] = []

    private let sync = iCloudSyncEngine.shared
    private var heartbeatTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var metadataQuery: NSMetadataQuery?

    private let heartbeatInterval: TimeInterval = 5
    private let staleThreshold: TimeInterval = 15 // If no heartbeat for 15s, consider interrupted

    private init() {
        #if os(macOS)
        startMonitoring()
        #endif
    }

    // MARK: - iCloud paths

    private var handoffRoot: URL? {
        sync.naviRoot?.appendingPathComponent("Handoff")
    }

    private var activeTaskURL: URL? {
        handoffRoot?.appendingPathComponent("active-task.json")
    }

    private var notificationsDir: URL? {
        handoffRoot?.appendingPathComponent("completed")
    }

    // MARK: - iOS: Start a handoff-tracked task

    func startTracking(projectID: UUID, instruction: String, todoItems: [AgentTodoItem]) async {
        guard SettingsStore.shared.macHandoffEnabled else { return }

        // Ensure directories exist
        if let root = handoffRoot {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        if let notifDir = notificationsDir {
            try? FileManager.default.createDirectory(at: notifDir, withIntermediateDirectories: true)
        }

        var task = HandoffTask(
            projectID: projectID,
            instruction: instruction,
            todoItems: todoItems.map { HandoffTodoItem(title: $0.title, status: todoStatusString($0.status)) },
            totalSteps: todoItems.count
        )

        activeHandoff = task
        await writeActiveTask(task)
        startHeartbeat()
    }

    func updateProgress(step: Int, modifiedFiles: [String], costSEK: Double) async {
        guard var task = activeHandoff else { return }
        task.currentStep = step
        task.modifiedFiles = modifiedFiles
        task.costSEK = costSEK
        task.lastHeartbeat = Date()
        activeHandoff = task
        await writeActiveTask(task)
    }

    func markCompleted(result: String?) async {
        guard var task = activeHandoff else { return }
        task.status = .completed
        task.completedAt = Date()
        task.result = result
        activeHandoff = nil
        stopHeartbeat()
        await writeActiveTask(task)

        // Clean up active file
        if let url = activeTaskURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func stopTracking() {
        activeHandoff = nil
        stopHeartbeat()
        if let url = activeTaskURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Heartbeat (iOS)

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                if var task = activeHandoff {
                    task.lastHeartbeat = Date()
                    activeHandoff = task
                    await writeActiveTask(task)
                }
                try? await Task.sleep(for: .seconds(heartbeatInterval))
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - macOS: Monitor for interrupted tasks

    #if os(macOS)
    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task {
            while !Task.isCancelled {
                await checkForInterruptedTasks()
                try? await Task.sleep(for: .seconds(10))
            }
        }

        // Also use NSMetadataQuery for instant detection
        setupMetadataQuery()
    }

    private func setupMetadataQuery() {
        guard let root = handoffRoot else { return }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, root.path)

        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForInterruptedTasks()
            }
        }
        query.start()
        metadataQuery = query
    }

    private func checkForInterruptedTasks() async {
        guard let url = activeTaskURL else { return }
        guard let task = try? await sync.read(HandoffTask.self, from: url) else { return }

        // Only pick up if task is "running" and heartbeat is stale
        guard task.status == .running else { return }
        let age = Date().timeIntervalSince(task.lastHeartbeat)

        if age > staleThreshold {
            NaviLog.info("TaskHandoff: iOS-uppgift avbruten (heartbeat \(Int(age))s gammal), tar över")
            await continueTask(task)
        }
    }

    private func continueTask(_ task: HandoffTask) async {
        var continued = task
        continued.status = .continuedOnMac
        continued.continuedBy = UIDevice.deviceID
        continued.lastHeartbeat = Date()
        await writeActiveTask(continued)

        // Find the project
        guard let project = await ProjectStore.shared.project(by: task.projectID) else {
            NaviLog.error("TaskHandoff: Kunde inte hitta projekt \(task.projectID)")
            continued.status = .failed
            continued.error = "Projekt hittades inte"
            await writeActiveTask(continued)
            return
        }

        // Resume execution via AgentEngine
        let engine = AgentEngine.shared
        engine.setProject(project)

        // Build instruction that includes context about where we left off
        let resumeInstruction = """
        FORTSÄTT en uppgift som påbörjades på iOS men avbröts vid steg \(task.currentStep) av \(task.totalSteps).

        Ursprunglig instruktion: \(task.instruction)

        Filer som redan ändrats: \(task.modifiedFiles.joined(separator: ", "))

        Läs de ändrade filerna först för att förstå vad som redan gjorts, och fortsätt sedan.
        """

        var conversation = Conversation(projectID: task.projectID, model: project.activeModel)
        let agentTask = AgentTask(projectID: task.projectID, instruction: resumeInstruction)

        await engine.run(task: agentTask, conversation: &conversation) { update in
            Task { @MainActor in
                continued.lastHeartbeat = Date()
                Task { await self.writeActiveTask(continued) }
            }
        }

        // Completed
        continued.status = .completed
        continued.completedAt = Date()
        continued.result = "Uppgiften slutfördes av macOS efter iOS-avbrott"
        await writeActiveTask(continued)

        // Write notification for iOS
        await writeCompletionNotification(continued)

        // Clean up active file
        if let url = activeTaskURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func writeCompletionNotification(_ task: HandoffTask) async {
        guard let dir = notificationsDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("completed-\(task.id.uuidString).json")
        try? await sync.write(task, to: url)
    }
    #endif

    // MARK: - iOS: Check for completion notifications on foreground

    func checkForCompletions() async {
        guard let dir = notificationsDir else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "json" {
            guard let task = try? await sync.read(HandoffTask.self, from: file),
                  task.status == .completed
            else { continue }

            completedNotifications.append(task)

            // Schedule local notification
            scheduleLocalNotification(for: task)

            // Clean up
            try? fm.removeItem(at: file)
        }
    }

    private func scheduleLocalNotification(for task: HandoffTask) {
        #if os(iOS)
        let content = UNMutableNotificationContent()
        content.title = "Navi"
        content.body = "Uppgiften '\(String(task.instruction.prefix(50)))' är klar!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
        #endif
    }

    // MARK: - Helpers

    private func writeActiveTask(_ task: HandoffTask) async {
        guard let url = activeTaskURL else { return }
        if let root = handoffRoot {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        try? await sync.write(task, to: url)
    }

    private func todoStatusString(_ status: AgentTodoStatus) -> String {
        switch status {
        case .waiting: return "waiting"
        case .active: return "active"
        case .done: return "done"
        case .failed: return "failed"
        }
    }
}
