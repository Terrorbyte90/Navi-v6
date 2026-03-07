import Foundation
import Combine

// MARK: - Autonomous Agent Runner
// Runs a long-horizon goal autonomously, iteration by iteration.
// Persists state so it can survive app restarts and run for hours/days.

@MainActor
final class AutonomousAgentRunner: ObservableObject {
    static let shared = AutonomousAgentRunner()

    @Published var agents: [AgentDefinition] = []
    @Published var streamingAgentID: UUID? = nil
    @Published var streamingText: String = ""

    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private let api = ClaudeAPIClient.shared
    private let store = AgentDefinitionStore.shared

    private init() {
        // Quick local load first (legacy UserDefaults) so UI isn't empty
        agents = store.load()
        // Then load authoritative data from iCloud
        Task {
            let iCloudAgents = await store.loadFromiCloud()
            if !iCloudAgents.isEmpty {
                agents = iCloudAgents
            }
            // Resume any agents that were running when app closed
            for agent in agents where agent.status == .running {
                startRunLoop(agentID: agent.id)
            }
        }
        // Reload when iCloud syncs new changes from another device
        NotificationCenter.default.addObserver(
            forName: .iCloudDidSync, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let updated = await self.store.loadFromiCloud()
                // Merge: keep running agents' in-memory state, update idle/completed ones
                for agent in updated {
                    if let idx = self.agents.firstIndex(where: { $0.id == agent.id }) {
                        if !self.agents[idx].status.isActive {
                            self.agents[idx] = agent
                        }
                    } else {
                        self.agents.append(agent)
                    }
                }
            }
        }
    }

    // MARK: - CRUD

    func create(
        name: String,
        goal: String,
        projectID: UUID?,
        projectName: String?,
        model: ClaudeModel,
        workerModel: ClaudeModel = .haiku,
        assignedWorkers: Int = 2,
        maxTokensPerIteration: Int = 8000,
        maxIterations: Int = 0,
        iterationDelaySeconds: Double = 1.0,
        autoRestartOnFailure: Bool = false,
        pauseOnUserQuestion: Bool = true,
        verboseLogging: Bool = false,
        autoCommitToGitHub: Bool = false,
        githubBranch: String = "main",
        systemPromptAddition: String = "",
        maxHistoryMessages: Int = 30,
        memoryEnabled: Bool = true,
        notifyOnCompletion: Bool = true,
        notifyOnFailure: Bool = true,
        notifyOnUserQuestion: Bool = true
    ) -> AgentDefinition {
        let def = AgentDefinition(
            name: name, goal: goal,
            projectID: projectID, projectName: projectName,
            model: model, workerModel: workerModel,
            assignedWorkers: assignedWorkers,
            maxTokensPerIteration: maxTokensPerIteration,
            maxIterations: maxIterations,
            iterationDelaySeconds: iterationDelaySeconds,
            autoRestartOnFailure: autoRestartOnFailure,
            pauseOnUserQuestion: pauseOnUserQuestion,
            verboseLogging: verboseLogging,
            autoCommitToGitHub: autoCommitToGitHub,
            githubBranch: githubBranch,
            systemPromptAddition: systemPromptAddition,
            maxHistoryMessages: maxHistoryMessages,
            memoryEnabled: memoryEnabled,
            notifyOnCompletion: notifyOnCompletion,
            notifyOnFailure: notifyOnFailure,
            notifyOnUserQuestion: notifyOnUserQuestion
        )
        agents.append(def)
        store.save(agents)
        return def
    }

    func delete(_ id: UUID) {
        stop(id)
        agents.removeAll { $0.id == id }
        store.save(agents)
    }

    func update(_ def: AgentDefinition) {
        if let idx = agents.firstIndex(where: { $0.id == def.id }) {
            agents[idx] = def
            store.save(agents)
        }
    }

    // MARK: - Control

    func start(_ id: UUID) {
        guard let idx = agents.firstIndex(where: { $0.id == id }) else { return }
        guard agents[idx].status != .running else { return }
        agents[idx].status = .running
        agents[idx].lastActiveAt = Date()
        store.save(agents)
        startRunLoop(agentID: id)
    }

    func pause(_ id: UUID) {
        runningTasks[id]?.cancel()
        runningTasks[id] = nil
        if let idx = agents.firstIndex(where: { $0.id == id }) {
            agents[idx].status = .paused
            store.save(agents)
        }
    }

    func stop(_ id: UUID) {
        runningTasks[id]?.cancel()
        runningTasks[id] = nil
        if let idx = agents.firstIndex(where: { $0.id == id }) {
            agents[idx].status = .idle
            store.save(agents)
        }
    }

    func restart(_ id: UUID) {
        if let idx = agents.firstIndex(where: { $0.id == id }) {
            agents[idx].status = .idle
            agents[idx].currentTaskDescription = ""
            agents[idx].iterationCount = 0
        }
        start(id)
    }

    // MARK: - Run loop

    private func startRunLoop(agentID: UUID) {
        let task = Task<Void, Never> { [weak self] in
            await self?.runLoop(agentID: agentID)
        }
        runningTasks[agentID] = task
    }

    private func runLoop(agentID: UUID) async {
        while !Task.isCancelled {
            guard let idx = agents.firstIndex(where: { $0.id == agentID }) else { break }
            guard agents[idx].status == .running else { break }

            let maxIter = agents[idx].maxIterations
            if maxIter > 0 && agents[idx].iterationCount >= maxIter {
                agents[idx].status = .completed
                agents[idx].currentTaskDescription = "Nådde max antal iterationer (\(maxIter))"
                appendLog(agentID: agentID, type: .milestone, content: "Klart — \(maxIter) iterationer genomförda")
                store.save(agents)
                break
            }

            let goalAchieved = await runIteration(agentID: agentID)
            if goalAchieved { break }

            // Configurable pause between iterations
            let delay = agents.first(where: { $0.id == agentID })?.iterationDelaySeconds ?? 1.0
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    // Resets session cost counters when agent starts fresh
    func resetSessionCost(_ id: UUID) {
        if let idx = agents.firstIndex(where: { $0.id == id }) {
            agents[idx].sessionTokensUsed = 0
            agents[idx].sessionCostSEK = 0
        }
    }

    // Returns true if goal is achieved (agent should stop)
    private func runIteration(agentID: UUID) async -> Bool {
        guard let idx = agents.firstIndex(where: { $0.id == agentID }) else { return true }

        let agent = agents[idx]
        agents[idx].iterationCount += 1
        let iterNum = agents[idx].iterationCount

        // Build messages for this iteration (bounded by maxHistoryMessages)
        var messages: [ChatMessage] = buildMessages(for: agent)

        // Check for repetition before building prompt
        let isRepeating = detectRepetition(in: agent)
        let iterPrompt: String
        if iterNum == 1 {
            iterPrompt = "Börja arbeta mot målet. Tänk steg för steg. Beskriv vad du gör och varför."
        } else if isRepeating {
            iterPrompt = "VARNING: Du har upprepat dig i 3+ iterationer. BYT STRATEGI OMEDELBART. Försök en helt annan approach. Iteration \(iterNum)."
            appendLog(agentID: agentID, type: .action, content: "Repetition upptäckt — tvingar strategibyte")
        } else {
            iterPrompt = "Fortsätt arbeta mot målet. Iteration \(iterNum). Vad är nästa steg?"
        }

        messages.append(ChatMessage(role: .user, content: [.text(iterPrompt)]))

        let systemPrompt = buildSystemPrompt(for: agent)

        // Stream the response
        streamingAgentID = agentID
        streamingText = ""

        var fullResponse = ""
        var goalAchieved = false

        do {
            let (response, usage) = try await api.sendMessage(
                messages: messages,
                model: agent.model,
                systemPrompt: systemPrompt,
                maxTokens: agent.maxTokensPerIteration
            )
            fullResponse = response

            let (_, costSEK) = CostCalculator.shared.calculate(usage: usage, model: agent.model)
            let tokens = usage.inputTokens + usage.outputTokens
            CostTracker.shared.record(usage: usage, model: agent.model)

            if let i = agents.firstIndex(where: { $0.id == agentID }) {
                agents[i].totalTokensUsed += tokens
                agents[i].totalCostSEK += costSEK
                agents[i].sessionTokensUsed += tokens
                agents[i].sessionCostSEK += costSEK
                agents[i].currentTaskDescription = extractCurrentTask(from: fullResponse)
                agents[i].lastActiveAt = Date()

                agents[i].conversationHistory.append(StoredMessage(role: "user", content: iterPrompt))
                agents[i].conversationHistory.append(StoredMessage(role: "assistant", content: fullResponse))
            }

            // Check if goal is achieved
            goalAchieved = isGoalAchieved(response: fullResponse, goal: agent.goal)

            // Execute any tool calls embedded in the response
            let toolResults = await executeToolCalls(from: fullResponse, agentID: agentID)

            // Append tool results back to conversation for next iteration context
            if !toolResults.isEmpty {
                let resultsText = toolResults.map { "[\($0.command)]: \($0.output)" }.joined(separator: "\n\n")
                if let i = agents.firstIndex(where: { $0.id == agentID }) {
                    agents[i].conversationHistory.append(StoredMessage(role: "user", content: "[VERKTYGSRESULTAT]\n\(resultsText)"))
                }
            }

            // Handle worker delegation markers
            await handleWorkerDelegation(from: fullResponse, agentID: agentID)

            // Log with cost info
            appendLog(agentID: agentID, type: .assistantMessage, content: fullResponse,
                      costSEK: costSEK, tokensUsed: tokens)

            if goalAchieved {
                if let i = agents.firstIndex(where: { $0.id == agentID }) {
                    agents[i].status = .completed
                    agents[i].currentTaskDescription = "Mål uppnått!"
                }
                appendLog(agentID: agentID, type: .milestone,
                          content: "✅ Mål uppnått efter \(iterNum) iterationer · Totalt: \(String(format: "%.4f kr", agents.first(where: { $0.id == agentID })?.grandTotalCostSEK ?? 0))")
            }

        } catch {
            appendLog(agentID: agentID, type: .error, content: "Fel i iteration \(iterNum): \(error.localizedDescription)", isError: true)
            if let i = agents.firstIndex(where: { $0.id == agentID }) {
                let shouldRestart = agents[i].autoRestartOnFailure
                if !shouldRestart {
                    agents[i].status = .failed
                    agents[i].currentTaskDescription = "Fel: \(error.localizedDescription)"
                    goalAchieved = true
                }
            }
        }

        streamingAgentID = nil
        store.save(agents)
        return goalAchieved
    }

    // MARK: - Message building (sliding window + summary)

    private func buildMessages(for agent: AgentDefinition) -> [ChatMessage] {
        let history = agent.conversationHistory
        let windowSize = agent.maxHistoryMessages * 2

        if history.count <= windowSize {
            return history.map { stored in
                ChatMessage(role: stored.role == "user" ? .user : .assistant, content: [.text(stored.content)])
            }
        }

        let olderMessages = Array(history.prefix(history.count - windowSize))
        let recentMessages = Array(history.suffix(windowSize))

        let summaryText = summarizeOlderMessages(olderMessages)
        var messages: [ChatMessage] = []
        messages.append(ChatMessage(role: .user, content: [.text("[SAMMANFATTNING AV TIDIGARE ITERATIONER]\n\(summaryText)")]))
        messages.append(ChatMessage(role: .assistant, content: [.text("Förstått. Jag har kontexten från tidigare arbete och fortsätter därifrån.")]))
        messages += recentMessages.map { stored in
            ChatMessage(role: stored.role == "user" ? .user : .assistant, content: [.text(stored.content)])
        }
        return messages
    }

    private func summarizeOlderMessages(_ messages: [StoredMessage]) -> String {
        let assistantMsgs = messages.filter { $0.role == "assistant" }
        guard !assistantMsgs.isEmpty else { return "Inga tidigare iterationer." }

        var keyPoints: [String] = []
        for msg in assistantMsgs {
            let lines = msg.content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("```") }
            if let first = lines.first {
                keyPoints.append(String(first.prefix(200)))
            }
        }
        let truncated = keyPoints.suffix(10)
        return "Genomförda steg (\(assistantMsgs.count) iterationer):\n" +
               truncated.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    private func buildSystemPrompt(for agent: AgentDefinition) -> String {
        var prompt = """
        Du är "\(agent.name)", en autonom AI-agent. Du arbetar självständigt iteration för iteration tills ditt mål är uppnått.

        ═══════════════════════════════
        MÅL: \(agent.goal)
        ═══════════════════════════════

        ARBETSMETOD:
        1. ANALYSERA — Utvärdera nuläget. Vad har gjorts? Vad återstår?
        2. PLANERA — Bestäm nästa konkreta steg. Prioritera effektivitet.
        3. UTFÖR — Genomför steget. Skriv kod, kommandon eller filer.
        4. VERIFIERA — Kontrollera resultatet. Fungerade det?
        5. RAPPORTERA — Kort sammanfattning av vad som hände och vad som är nästa steg.

        REGLER:
        - Var KONKRET och HANDLINGSINRIKTAD. Ingen fluff.
        - Kommandon: skriv i ```bash\\n...\\n``` kodblock — de körs automatiskt.
        - Filer: ange fullständig sökväg som kommentar, hela innehållet i kodblock.
        - Dela upp komplexa uppgifter i hanterbara steg.
        - Om du stöter på ett fel: analysera, åtgärda, försök igen.
        - Om du kör fast efter 3 försök: byt strategi.
        - ALDRIG upprepa samma misslyckade approach.
        - Håll koll på dina workers — delegera parallelliserbara uppgifter.

        AVSLUT:
        - När målet är HELT uppnått, avsluta med: [MÅL UPPNÅTT]
        - Avsluta INTE förrän du verifierat att allt faktiskt fungerar.

        STATUS: Iteration \(agent.iterationCount + 1)\(agent.maxIterations > 0 ? " av \(agent.maxIterations)" : "")
        """

        if let projectName = agent.projectName {
            prompt += "\nPROJEKT: \(projectName)"
        }

        if agent.assignedWorkers > 1 {
            prompt += "\nWORKERS: \(agent.assignedWorkers) parallella workers tillgängliga (modell: \(agent.workerModel.displayName))"
        }

        if !agent.systemPromptAddition.isEmpty {
            prompt += "\n\nEXTRA INSTRUKTIONER:\n\(agent.systemPromptAddition)"
        }

        if agent.memoryEnabled {
            let memories = MemoryManager.shared.memories
            if !memories.isEmpty {
                let memoryText = memories.prefix(15).map { "- \($0.fact)" }.joined(separator: "\n")
                prompt += "\n\nKONTEXT (minnen):\n\(memoryText)"
            }
        }

        return prompt
    }

    // MARK: - Goal detection

    private func isGoalAchieved(response: String, goal: String) -> Bool {
        response.contains("[MÅL UPPNÅTT]") || response.lowercased().contains("målet är uppnått")
    }

    private func extractCurrentTask(from response: String) -> String {
        let lines = response.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("```") }
        return String((lines.first ?? "Arbetar…").prefix(120))
    }

    // MARK: - Repetition detection

    private func detectRepetition(in agent: AgentDefinition) -> Bool {
        let recent = agent.conversationHistory.suffix(6)
        let assistantMsgs = recent.filter { $0.role == "assistant" }.map { $0.content.prefix(300) }
        guard assistantMsgs.count >= 3 else { return false }
        let unique = Set(assistantMsgs.map { String($0) })
        return unique.count == 1
    }

    // MARK: - Tool execution

    struct ToolResult {
        let command: String
        let output: String
    }

    private func executeToolCalls(from response: String, agentID: UUID) async -> [ToolResult] {
        let pattern = "```(?:bash|sh|shell|zsh)\\n([\\s\\S]*?)\\n```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let nsResponse = response as NSString
        let matches = regex.matches(in: response, range: NSRange(location: 0, length: nsResponse.length))

        var results: [ToolResult] = []

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let cmdRange = match.range(at: 1)
            let cmd = nsResponse.substring(with: cmdRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else { continue }

            appendLog(agentID: agentID, type: .tool, content: "$ \(cmd)")

            #if os(macOS)
            let output = await runShellCommand(cmd)
            appendLog(agentID: agentID, type: .result, content: output)
            results.append(ToolResult(command: cmd, output: output))
            #else
            await InstructionComposer.shared.queue(instruction: cmd, projectID: agentID)
            let output = "Köad till Mac"
            appendLog(agentID: agentID, type: .action, content: "Köad till Mac: \(cmd)")
            results.append(ToolResult(command: cmd, output: output))
            #endif
        }
        return results
    }

    // MARK: - Worker delegation

    private func handleWorkerDelegation(from response: String, agentID: UUID) async {
        let pattern = "\\[DELEGERA:\\s*(.+?)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let nsResponse = response as NSString
        let matches = regex.matches(in: response, range: NSRange(location: 0, length: nsResponse.length))

        guard !matches.isEmpty,
              let idx = agents.firstIndex(where: { $0.id == agentID }) else { return }

        let agent = agents[idx]
        guard agent.assignedWorkers > 0 else { return }

        for match in matches.prefix(agent.assignedWorkers) {
            guard match.numberOfRanges > 1 else { continue }
            let taskRange = match.range(at: 1)
            let task = nsResponse.substring(with: taskRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !task.isEmpty else { continue }

            appendLog(agentID: agentID, type: .action, content: "Delegerar till worker: \(task)")

            #if os(macOS)
            let output = await runWorkerTask(task, model: agent.workerModel)
            appendLog(agentID: agentID, type: .result, content: "Worker-resultat: \(String(output.prefix(500)))")
            if let i = agents.firstIndex(where: { $0.id == agentID }) {
                agents[i].conversationHistory.append(StoredMessage(role: "user", content: "[WORKER-RESULTAT: \(task)]\n\(output)"))
            }
            #else
            appendLog(agentID: agentID, type: .action, content: "Worker-uppgift köad: \(task)")
            #endif
        }
    }

    #if os(macOS)
    private func runWorkerTask(_ task: String, model: ClaudeModel) async -> String {
        do {
            let (response, _) = try await api.sendMessage(
                messages: [ChatMessage(role: .user, content: [.text(task)])],
                model: model,
                systemPrompt: "Du är en worker-agent. Utför uppgiften direkt och koncist. Svara med resultatet.",
                maxTokens: 4000
            )
            return response
        } catch {
            return "Worker-fel: \(error.localizedDescription)"
        }
    }
    #endif

    #if os(macOS)
    private func runShellCommand(_ cmd: String) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", cmd]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    cont.resume(returning: output.isEmpty ? "(inget utdata)" : String(output.prefix(2000)))
                } catch {
                    cont.resume(returning: "Fel: \(error.localizedDescription)")
                }
            }
        }
    }
    #endif

    // MARK: - Logging

    private func appendLog(agentID: UUID, type: AgentRunEntry.EntryType, content: String,
                           isError: Bool = false, costSEK: Double? = nil, tokensUsed: Int? = nil) {
        guard let idx = agents.firstIndex(where: { $0.id == agentID }) else { return }
        var entry = AgentRunEntry(type: type, content: content, isError: isError)
        entry.costSEK = costSEK
        entry.tokensUsed = tokensUsed
        agents[idx].runLog.append(entry)
        if agents[idx].runLog.count > 500 {
            agents[idx].runLog = Array(agents[idx].runLog.suffix(500))
        }
    }
}

// MARK: - Persistence (iCloud Drive, one JSON file per agent)

@MainActor
final class AgentDefinitionStore {
    static let shared = AgentDefinitionStore()
    private let engine = iCloudSyncEngine.shared
    private let legacyKey = "navi_autonomous_agents_v1"

    // Synchronous save — fire-and-forget async write to iCloud
    func save(_ agents: [AgentDefinition]) {
        Task { await saveAsync(agents) }
    }

    private func saveAsync(_ agents: [AgentDefinition]) async {
        guard let root = engine.agentsRoot else {
            // iCloud unavailable — fall back to UserDefaults
            if let data = try? JSONEncoder().encode(agents) {
                UserDefaults.standard.set(data, forKey: legacyKey)
            }
            return
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for agent in agents {
            let url = root.appendingPathComponent("\(agent.id.uuidString).json")
            try? await engine.write(agent, to: url)
        }
        // Remove files for deleted agents
        let existingIDs = Set(agents.map { $0.id.uuidString })
        if let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                let name = file.deletingPathExtension().lastPathComponent
                if !existingIDs.contains(name) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    func load() -> [AgentDefinition] {
        // Synchronous load from UserDefaults (legacy) used only at init before iCloud is ready
        guard let data = UserDefaults.standard.data(forKey: legacyKey),
              let agents = try? JSONDecoder().decode([AgentDefinition].self, from: data)
        else { return [] }
        return agents
    }

    /// Async load from iCloud — call after init to get the authoritative data
    func loadFromiCloud() async -> [AgentDefinition] {
        guard let root = engine.agentsRoot else {
            return load() // fallback
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var loaded: [AgentDefinition] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let agent = try? await engine.read(AgentDefinition.self, from: file) {
                    loaded.append(agent)
                }
            }
        }

        // One-time migration from UserDefaults
        let legacy = load()
        if loaded.isEmpty, !legacy.isEmpty {
            loaded = legacy
            await saveAsync(loaded)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }

        return loaded.sorted { ($0.lastActiveAt ?? $0.createdAt) > ($1.lastActiveAt ?? $1.createdAt) }
    }
}
