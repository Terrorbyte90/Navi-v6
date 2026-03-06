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
        agents = store.load()
        // Resume any agents that were running when app closed
        for agent in agents where agent.status == .running {
            startRunLoop(agentID: agent.id)
        }
    }

    // MARK: - CRUD

    func create(name: String, goal: String, projectID: UUID?, projectName: String?, model: ClaudeModel, maxIterations: Int) -> AgentDefinition {
        let def = AgentDefinition(
            name: name, goal: goal,
            projectID: projectID, projectName: projectName,
            model: model, maxIterations: maxIterations
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

            // Small pause between iterations to avoid hammering the API
            try? await Task.sleep(for: .seconds(1))
        }
    }

    // Returns true if goal is achieved (agent should stop)
    private func runIteration(agentID: UUID) async -> Bool {
        guard let idx = agents.firstIndex(where: { $0.id == agentID }) else { return true }

        let agent = agents[idx]
        agents[idx].iterationCount += 1
        let iterNum = agents[idx].iterationCount

        // Build messages for this iteration
        var messages: [ChatMessage] = buildMessages(for: agent)

        // Append current iteration prompt
        let iterPrompt = iterNum == 1
            ? "Börja arbeta mot målet. Tänk steg för steg. Beskriv vad du gör och varför."
            : "Fortsätt arbeta mot målet. Iteration \(iterNum). Vad är nästa steg?"

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
                maxTokens: 8000
            )
            fullResponse = response

            // Update cost
            let costUSD = Double(usage.inputTokens) * agent.model.inputPricePerMTok / 1_000_000
                        + Double(usage.outputTokens) * agent.model.outputPricePerMTok / 1_000_000
            let costSEK = costUSD * 10.5

            if let i = agents.firstIndex(where: { $0.id == agentID }) {
                agents[i].totalTokensUsed += usage.inputTokens + usage.outputTokens
                agents[i].totalCostSEK += costSEK
                agents[i].currentTaskDescription = extractCurrentTask(from: fullResponse)
                agents[i].lastActiveAt = Date()

                // Store in conversation history
                agents[i].conversationHistory.append(StoredMessage(role: "user", content: iterPrompt))
                agents[i].conversationHistory.append(StoredMessage(role: "assistant", content: fullResponse))

                // Keep history bounded (last 60 messages = 30 back-and-forth)
                if agents[i].conversationHistory.count > 60 {
                    agents[i].conversationHistory = Array(agents[i].conversationHistory.suffix(60))
                }
            }

            // Check if goal is achieved
            goalAchieved = isGoalAchieved(response: fullResponse, goal: agent.goal)

            // Execute any tool calls embedded in the response
            await executeToolCalls(from: fullResponse, agentID: agentID)

            // Log
            appendLog(agentID: agentID, type: .assistantMessage, content: fullResponse)

            if goalAchieved {
                if let i = agents.firstIndex(where: { $0.id == agentID }) {
                    agents[i].status = .completed
                    agents[i].currentTaskDescription = "Mål uppnått!"
                }
                appendLog(agentID: agentID, type: .milestone, content: "✅ Mål uppnått efter \(iterNum) iterationer")
            }

        } catch {
            appendLog(agentID: agentID, type: .error, content: "Fel i iteration \(iterNum): \(error.localizedDescription)", isError: true)
            if let i = agents.firstIndex(where: { $0.id == agentID }) {
                let shouldRestart = agents[i].autoRestartOnFailure
                if !shouldRestart {
                    agents[i].status = .failed
                    agents[i].currentTaskDescription = "Fel: \(error.localizedDescription)"
                    goalAchieved = true // stop loop
                }
            }
        }

        streamingAgentID = nil
        store.save(agents)
        return goalAchieved
    }

    // MARK: - Message building

    private func buildMessages(for agent: AgentDefinition) -> [ChatMessage] {
        // Use stored conversation history for full context
        return agent.conversationHistory.map { stored in
            let role: MessageRole = stored.role == "user" ? .user : .assistant
            return ChatMessage(role: role, content: [.text(stored.content)])
        }
    }

    private func buildSystemPrompt(for agent: AgentDefinition) -> String {
        var prompt = """
        Du är en autonom AI-agent med namnet "\(agent.name)".
        
        ÖVERGRIPANDE MÅL:
        \(agent.goal)
        
        INSTRUKTIONER:
        - Arbeta metodiskt och iterativt mot målet.
        - Varje svar ska innehålla: vad du just gjort, vad du planerar att göra härnäst, och om målet är uppnått.
        - Om du behöver köra kod eller kommandon, skriv dem i kodblock med språket specificerat.
        - Om du skriver filer, ange hela filinnehållet i kodblock med filnamnet som kommentar.
        - Var konkret och handlingsinriktad. Undvik onödiga förklaringar.
        - Om målet är UPPNÅTT, avsluta ditt svar med exakt texten: [MÅL UPPNÅTT]
        - Iteration \(agent.iterationCount + 1) av \(agent.maxIterations > 0 ? String(agent.maxIterations) : "∞")
        """

        if let projectName = agent.projectName {
            prompt += "\n\nAktivt projekt: \(projectName)"
        }

        return prompt
    }

    // MARK: - Goal detection

    private func isGoalAchieved(response: String, goal: String) -> Bool {
        response.contains("[MÅL UPPNÅTT]") || response.lowercased().contains("målet är uppnått")
    }

    private func extractCurrentTask(from response: String) -> String {
        // Extract the first meaningful line as current task description
        let lines = response.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("```") }
        return String((lines.first ?? "Arbetar…").prefix(120))
    }

    // MARK: - Tool execution

    private func executeToolCalls(from response: String, agentID: UUID) async {
        // Extract and execute shell commands from code blocks
        let pattern = "```(?:bash|sh|shell|zsh)\\n([\\s\\S]*?)\\n```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        let nsResponse = response as NSString
        let matches = regex.matches(in: response, range: NSRange(location: 0, length: nsResponse.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let cmdRange = match.range(at: 1)
            let cmd = nsResponse.substring(with: cmdRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else { continue }

            appendLog(agentID: agentID, type: .tool, content: "$ \(cmd)")

            #if os(macOS)
            let output = await runShellCommand(cmd)
            appendLog(agentID: agentID, type: .result, content: output)
            #else
            // On iOS, queue to Mac
            await InstructionComposer.shared.queue(instruction: cmd, projectID: agentID)
            appendLog(agentID: agentID, type: .action, content: "Köad till Mac: \(cmd)")
            #endif
        }
    }

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

    private func appendLog(agentID: UUID, type: AgentRunEntry.EntryType, content: String, isError: Bool = false) {
        guard let idx = agents.firstIndex(where: { $0.id == agentID }) else { return }
        let entry = AgentRunEntry(type: type, content: content, isError: isError)
        agents[idx].runLog.append(entry)
        // Keep log bounded
        if agents[idx].runLog.count > 500 {
            agents[idx].runLog = Array(agents[idx].runLog.suffix(500))
        }
    }
}

// MARK: - Persistence

final class AgentDefinitionStore {
    static let shared = AgentDefinitionStore()
    private let key = "navi_autonomous_agents_v1"

    func save(_ agents: [AgentDefinition]) {
        if let data = try? JSONEncoder().encode(agents) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() -> [AgentDefinition] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let agents = try? JSONDecoder().decode([AgentDefinition].self, from: data)
        else { return [] }
        return agents
    }
}
