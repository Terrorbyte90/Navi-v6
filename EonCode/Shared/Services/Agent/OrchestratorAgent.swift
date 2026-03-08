import Foundation

// MARK: - OrchestratorAgent
// Takes a complex task, decomposes it into waves of parallel sub-tasks,
// executes each wave via WorkerPool, and aggregates results.

@MainActor
final class OrchestratorAgent: ObservableObject {
    static let shared = OrchestratorAgent()

    @Published var isRunning = false
    @Published var currentWave: Int = 0
    @Published var totalWaves: Int = 0
    @Published var waveDescription: String = ""
    @Published var workerStatuses: [UUID: WorkerStatus] = [:]
    @Published var aggregatedSummaries: [String] = []
    @Published var overallProgress: Double = 0

    private let pool = WorkerPool.shared
    private init() {}

    struct WorkerStatus: Identifiable {
        let id: UUID
        let taskDescription: String
        var status: StepStatus
        var output: String
        var ranLocally: Bool
        var isQueued: Bool
    }

    // MARK: - Execute orchestrated task

    func execute(
        instruction: String,
        project: NaviProject,
        model: ClaudeModel,
        onProgress: @escaping (String) -> Void
    ) async -> OrchestratorResult {
        isRunning = true
        pool.reset()
        workerStatuses = [:]
        aggregatedSummaries = []
        defer { isRunning = false }

        let projectRoot = project.resolvedURL

        // 1. Decompose into waves
        onProgress("🧠 Planerar uppgift med Claude…")
        let waves: [TaskWave]
        do {
            waves = try await TaskDecomposer.decompose(
                instruction: instruction,
                projectContext: "Projekt: \(project.name) @ \(project.rootPath)",
                model: model
            )
        } catch {
            return OrchestratorResult(succeeded: false, summary: "Planeringen misslyckades: \(error.localizedDescription)", waveResults: [])
        }

        totalWaves = waves.count
        onProgress("📋 Plan: \(waves.count) våg(or) med totalt \(waves.flatMap(\.tasks).count) uppgifter")

        var allWaveResults: [ResultAggregator.AggregatedResult] = []

        // 2. Execute wave by wave
        for wave in waves.sorted(by: { $0.index < $1.index }) {
            currentWave = wave.index
            waveDescription = wave.description
            onProgress("🌊 Våg \(wave.index + 1)/\(waves.count): \(wave.description)")

            // Register worker statuses for UI
            for task in wave.tasks {
                workerStatuses[task.id] = WorkerStatus(
                    id: task.id,
                    taskDescription: task.description,
                    status: .pending,
                    output: "",
                    ranLocally: !task.requiresTerminal,
                    isQueued: false
                )
            }

            // iOS in remote-only mode: queue terminal tasks
            let (localTasks, macTasks) = splitTasksByPlatform(wave.tasks)

            // Queue mac tasks
            for task in macTasks {
                await queueTaskToMac(task)
                var ws = workerStatuses[task.id]
                ws?.status = .running
                ws?.isQueued = true
                workerStatuses[task.id] = ws
                onProgress("🟡 Köad till Mac: \(task.description)")
            }

            // Run local tasks in parallel
            if !localTasks.isEmpty {
                let waveResults = await pool.executeTasks(
                    localTasks,
                    projectRoot: projectRoot,
                    model: model,
                    projectID: project.id
                ) { [weak self] worker in
                    Task { @MainActor in
                        self?.workerStatuses[worker.id] = WorkerStatus(
                            id: worker.id,
                            taskDescription: worker.task.description,
                            status: worker.status,
                            output: worker.output,
                            ranLocally: !worker.task.requiresTerminal,
                            isQueued: false
                        )
                        onProgress("✓ \(worker.task.description)")
                    }
                }

                // Aggregate results for this wave
                let aggregated = await ResultAggregator.merge(
                    results: waveResults,
                    waveIndex: wave.index,
                    projectRoot: projectRoot,
                    model: model
                )
                allWaveResults.append(aggregated)
                aggregatedSummaries.append(aggregated.summary)
                onProgress(aggregated.summary)

                // Auto-snapshot after each wave
                if SettingsStore.shared.autoSnapshot, let project = ProjectStore.shared.project(by: project.id) {
                    _ = try? await VersionStore.shared.createSnapshot(
                        for: project,
                        name: "wave-\(wave.index + 1)-\(wave.description.prefix(20))",
                        branch: "main",
                        changedFiles: waveResults.flatMap(\.filesWritten)
                    )
                }
            }

            overallProgress = Double(wave.index + 1) / Double(waves.count)
        }

        let totalSucceeded = allWaveResults.flatMap(\.workerResults).filter(\.succeeded).count
        let totalRan = allWaveResults.flatMap(\.workerResults).count
        let summary = """
        ✅ Klar! \(totalSucceeded)/\(totalRan) tasks lyckades över \(waves.count) våg(or).
        \(aggregatedSummaries.joined(separator: "\n"))
        """

        return OrchestratorResult(
            succeeded: totalSucceeded > 0,
            summary: summary,
            waveResults: allWaveResults
        )
    }

    // MARK: - Platform routing

    private func splitTasksByPlatform(_ tasks: [WorkerTask]) -> (local: [WorkerTask], mac: [WorkerTask]) {
        #if os(iOS)
        let mode = SettingsStore.shared.iosAgentMode
        if mode == .remoteOnly {
            return ([], tasks)
        }
        let local = tasks.filter { !$0.requiresTerminal }
        let mac = tasks.filter { $0.requiresTerminal }
        return (local, mac)
        #else
        return (tasks, [])
        #endif
    }

    private func queueTaskToMac(_ task: WorkerTask) async {
        let instr = Instruction(instruction: task.instruction)
        await InstructionQueue.shared.enqueue(instr)
    }
}

// MARK: - Result type

struct OrchestratorResult {
    let succeeded: Bool
    let summary: String
    let waveResults: [ResultAggregator.AggregatedResult]

    var totalTasksRun: Int { waveResults.flatMap(\.workerResults).count }
    var totalFilesWritten: Int { waveResults.flatMap { $0.workerResults.flatMap(\.filesWritten) }.count }
}
