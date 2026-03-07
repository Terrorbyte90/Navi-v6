import Foundation

// iOS queues instructions → iCloud → macOS picks up and executes
@MainActor
final class InstructionQueue: ObservableObject {
    static let shared = InstructionQueue()

    @Published var pendingCount = 0
    @Published var isProcessing = false

    private let sync = iCloudSyncEngine.shared
    private var pollTask: Task<Void, Never>?
    private var metadataQuery: NSMetadataQuery?

    private init() {
        #if os(macOS)
        startProcessingLoop()
        startMetadataQuery()
        #endif
    }

    deinit {
        metadataQuery?.stop()
    }

    private func startMetadataQuery() {
        guard let root = sync.eonCodeRoot,
              let dir = sync.instructionsRoot else { return }

        let signalPath = root.appendingPathComponent("instruction-signal.json").path

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, dir.path),
            NSPredicate(format: "%K == %@", NSMetadataItemPathKey, signalPath)
        ])
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForNewInstructions()
            }
        }
        query.start()
        metadataQuery = query
    }

    // MARK: - Enqueue (iOS side)

    func enqueue(_ instruction: Instruction) async {
        if let url = sync.urlForInstruction(instruction) {
            do {
                try await sync.write(instruction, to: url)
            } catch {
                NaviLog.error("InstructionQueue: kunde inte skriva instruktion till iCloud", error: error)
            }
        }

        await writeInstructionSignal()

        try? await LocalNetworkClient.shared.postInstruction(instruction)

        pendingCount += 1
        NotificationCenter.default.post(name: .instructionEnqueued, object: instruction)
    }

    private func writeInstructionSignal() async {
        guard let root = sync.eonCodeRoot else { return }
        let signalURL = root.appendingPathComponent("instruction-signal.json")
        let signal: [String: String] = [
            "from": UIDevice.deviceID,
            "timestamp": Date().iso8601
        ]
        if let data = try? JSONSerialization.data(withJSONObject: signal) {
            try? await sync.writeData(data, to: signalURL)
        }
    }

    // MARK: - Process (macOS side)

    func startProcessingLoop() {
        pollTask = Task {
            while !Task.isCancelled {
                await checkForNewInstructions()
                try? await Task.sleep(seconds: Constants.Sync.instructionPollInterval)
            }
        }
    }

    func stopProcessingLoop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func checkForNewInstructions() async {
        guard let dir = sync.instructionsRoot else { return }
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }

        for file in jsonFiles {
            guard let instruction = try? await sync.read(Instruction.self, from: file),
                  instruction.status == .pending
            else { continue }

            await processInstruction(instruction, at: file)
        }
    }

    func processInstruction(_ instruction: Instruction, at url: URL) async {
        var instr = instruction
        instr.status = .running
        try? await sync.write(instr, to: url)

        isProcessing = true
        defer {
            isProcessing = false
            if pendingCount > 0 { pendingCount -= 1 }
        }

        let project = await ProjectStore.shared.project(by: instr.projectID)
        // Use the project's active model, fall back to settings default, then Sonnet
        let model = project?.activeModel ?? SettingsStore.shared.defaultModel

        do {
            var conversation = Conversation(
                projectID: instr.projectID ?? UUID(),
                model: model
            )

            let agentTask = AgentTask(
                projectID: instr.projectID ?? UUID(),
                instruction: instr.instruction
            )

            await AgentEngine.shared.run(
                task: agentTask,
                conversation: &conversation,
                onUpdate: { [url] update in
                    var updated = instr
                    updated.steps.append(InstructionStepRecord(
                        index: updated.steps.count,
                        action: "agent_step",
                        status: "running",
                        output: update
                    ))
                    Task { try? await iCloudSyncEngine.shared.write(updated, to: url) }
                }
            )

            instr.status = .completed
            instr.result = "Uppgift slutförd"
        } catch {
            instr.status = .failed
            instr.error = error.localizedDescription
        }

        try? await sync.write(instr, to: url)
    }

    // MARK: - Read pending (for Mac to list)

    func pendingInstructions() async -> [Instruction] {
        guard let dir = sync.instructionsRoot,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }

        var result: [Instruction] = []
        for file in files where file.pathExtension == "json" {
            if let instr = try? await sync.read(Instruction.self, from: file),
               instr.status.isActive {
                result.append(instr)
            }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }
}

extension Notification.Name {
    static let instructionEnqueued = Notification.Name("instructionEnqueued")
}
