import Foundation
import Combine

// MARK: - Queued prompt item

struct QueuedPrompt: Identifiable, Codable {
    let id: UUID
    let text: String
    let isAgentMode: Bool
    let iterationsTotal: Int       // 1 = single run, N = repeat N times
    var iterationsDone: Int
    var status: QueuedPromptStatus
    var addedAt: Date

    init(
        id: UUID = UUID(),
        text: String,
        isAgentMode: Bool = true,
        iterations: Int = 1
    ) {
        self.id = id
        self.text = text
        self.isAgentMode = isAgentMode
        self.iterationsTotal = max(1, iterations)
        self.iterationsDone = 0
        self.status = .waiting
        self.addedAt = Date()
    }

    var progress: Double {
        guard iterationsTotal > 1 else { return status == .completed ? 1.0 : 0.0 }
        return Double(iterationsDone) / Double(iterationsTotal)
    }

    var displayLabel: String {
        if iterationsTotal > 1 {
            return "[\(iterationsDone)/\(iterationsTotal)] \(text.prefix(60))"
        }
        return String(text.prefix(60))
    }
}

enum QueuedPromptStatus: String, Codable {
    case waiting    // in queue, not started
    case running    // currently executing
    case completed  // all iterations done
    case failed     // error
    case cancelled  // user cancelled
}

// MARK: - PromptQueue

/// Per-project prompt queue. Prompts are processed one at a time, in order.
/// Supports N iterations: the same prompt is re-sent N times before moving to the next.
@MainActor
final class PromptQueue: ObservableObject {

    // One queue per project
    private static var queues: [UUID: PromptQueue] = [:]

    static func queue(for projectID: UUID) -> PromptQueue {
        if let existing = queues[projectID] { return existing }
        let q = PromptQueue(projectID: projectID)
        queues[projectID] = q
        return q
    }

    /// Remove and cancel the queue for a deleted project.
    static func remove(for projectID: UUID) {
        if let q = queues.removeValue(forKey: projectID) {
            q.processingTask?.cancel()
            q.items.removeAll()
        }
    }

    // MARK: - State

    let projectID: UUID

    @Published var items: [QueuedPrompt] = []
    @Published var isProcessing = false
    @Published var currentItemID: UUID?

    private var processingTask: Task<Void, Never>?

    private let sync = iCloudSyncEngine.shared

    private init(projectID: UUID) {
        self.projectID = projectID
        Task { await loadFromiCloud() }
    }

    // MARK: - Public API

    func enqueue(text: String, isAgentMode: Bool = true, iterations: Int = 1) {
        let item = QueuedPrompt(text: text, isAgentMode: isAgentMode, iterations: iterations)
        items.append(item)
        persistToiCloud()
        startProcessingIfNeeded()
    }

    /// Remove a waiting item from the queue.
    func cancel(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            if items[idx].status == .waiting {
                items[idx].status = .cancelled
            }
        }
    }

    /// Remove all waiting items.
    func clearWaiting() {
        for idx in items.indices where items[idx].status == .waiting {
            items[idx].status = .cancelled
        }
    }

    /// Remove completed/cancelled items from the display list.
    func clearFinished() {
        items.removeAll { $0.status == .completed || $0.status == .cancelled }
    }

    var waitingCount: Int { items.filter { $0.status == .waiting }.count }
    var hasActive: Bool { items.contains { $0.status == .waiting || $0.status == .running } }

    // MARK: - Processing loop

    private func startProcessingIfNeeded() {
        // processingTask is set to nil at the end of processLoop() — only start if truly idle
        guard processingTask == nil else { return }
        processingTask = Task { await processLoop() }
    }

    private func processLoop() async {
        while !Task.isCancelled {
            // Find next waiting item
            guard let idx = items.firstIndex(where: { $0.status == .waiting }) else {
                isProcessing = false
                currentItemID = nil
                processingTask = nil
                return
            }

            isProcessing = true
            items[idx].status = .running
            currentItemID = items[idx].id

            let item = items[idx]

            // Get the agent for this project
            guard let project = await ProjectStore.shared.project(by: projectID) else {
                items[idx].status = .failed
                continue
            }

            let agent = AgentPool.shared.agent(for: project)

            // Run iterations
            var success = true
            for iteration in 1...item.iterationsTotal {
                guard !Task.isCancelled else { break }

                // Check if user cancelled this item mid-run
                if let currentIdx = self.items.firstIndex(where: { $0.id == item.id }),
                   self.items[currentIdx].status == .cancelled {
                    break
                }

                let iterLabel = item.iterationsTotal > 1
                    ? " (iteration \(iteration)/\(item.iterationsTotal))"
                    : ""

                // Wait for agent to be free
                while agent.isRunning {
                    try? await Task.sleep(for: .milliseconds(200))
                }

                // Send the prompt — with 10-minute timeout guard against hung continuations
                let resumeOnce = ResumeOnce()
                let timeoutTask = Task { @MainActor [weak resumeOnce] in
                    try? await Task.sleep(for: .seconds(600))
                    if resumeOnce?.fire() == true {
                        NaviLog.warning("PromptQueue: agent svarade inte inom 10 min — hoppar över")
                        success = false
                    }
                }
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    resumeOnce.setContinuation(cont)
                    agent.sendMessage(
                        item.text + iterLabel,
                        isAgentMode: item.isAgentMode,
                        onComplete: {
                            timeoutTask.cancel()
                            _ = resumeOnce.fire()
                        }
                    )
                }
                if !success { break }

                // Update iteration count
                if let currentIdx = self.items.firstIndex(where: { $0.id == item.id }) {
                    self.items[currentIdx].iterationsDone = iteration
                }

                // Small pause between iterations
                if iteration < item.iterationsTotal {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }

            // Mark done
            if let currentIdx = items.firstIndex(where: { $0.id == item.id }) {
                if items[currentIdx].status != .cancelled {
                    items[currentIdx].status = success ? .completed : .failed
                }
            }

            currentItemID = nil
            persistToiCloud()
        }
    }

    // MARK: - iCloud persistence

    private var queueFileURL: URL? {
        sync.naviRoot?
            .appendingPathComponent("prompt_queues")
            .appendingPathComponent("\(projectID.uuidString).json")
    }

    private func persistToiCloud() {
        let waitingItems = items.filter { $0.status == .waiting || $0.status == .running }
        guard !waitingItems.isEmpty else { return }
        Task {
            guard let url = queueFileURL else { return }
            do {
                try await sync.write(waitingItems, to: url)
            } catch {
                NaviLog.error("PromptQueue: kunde inte spara kö", error: error)
            }
        }
    }

    private func loadFromiCloud() async {
        guard let url = queueFileURL else { return }
        do {
            let loaded = try await sync.read([QueuedPrompt].self, from: url)
            let restored = loaded.filter { $0.status == .waiting }
            if !restored.isEmpty {
                items.append(contentsOf: restored)
                startProcessingIfNeeded()
            }
        } catch {
            // File doesn't exist yet — that's fine
        }
    }
}

// MARK: - ResumeOnce — thread-safe single-fire continuation wrapper

private final class ResumeOnce: @unchecked Sendable {
    private var cont: CheckedContinuation<Void, Never>?
    private var fired = false
    private let lock = NSLock()

    func setContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        cont = continuation
    }

    /// Returns true if this was the first (and only) fire.
    @discardableResult
    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !fired, let c = cont else { return false }
        fired = true
        cont = nil
        c.resume()
        return true
    }
}
