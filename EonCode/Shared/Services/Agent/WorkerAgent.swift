import Foundation

// MARK: - WorkerAgent
// One independent agent handling a single WorkerTask.
// Has its own Claude session and ToolExecutor.

@MainActor
final class WorkerAgent: ObservableObject, Identifiable {
    let id: UUID
    let task: WorkerTask
    let projectRoot: URL?
    let model: ClaudeModel

    @Published var status: StepStatus = .pending
    @Published var output: String = ""
    @Published var filesWritten: [String] = []
    @Published var progress: Double = 0

    private let claude = ClaudeAPIClient.shared
    private let executor: ToolExecutor

    init(task: WorkerTask, projectRoot: URL?, model: ClaudeModel = .haiku, projectID: UUID? = nil) {
        self.id = task.id
        self.task = task
        self.projectRoot = projectRoot
        self.model = model
        let exec = ToolExecutor()
        exec.currentProjectID = projectID
        self.executor = exec
    }

    // MARK: - Run

    func run() async -> WorkerResult {
        let startTime = Date()
        status = .running

        var fullText = ""
        var toolCalls: [(id: String, name: String, input: [String: AnyCodable])] = []
        var blockType = ""
        var currentToolID = ""
        var currentToolName = ""
        var currentToolJSON = ""
        var stopReason = ""
        var iterationCount = 0
        let maxIterations = 20

        // Initial messages with task context
        var messages = [
            ChatMessage(
                role: .user,
                content: [.text(buildWorkerPrompt())]
            )
        ]

        while iterationCount < maxIterations {
            iterationCount += 1
            fullText = ""
            toolCalls = []
            blockType = ""

            do {
                try await claude.streamMessage(
                    messages: messages,
                    model: model,
                    systemPrompt: workerSystemPrompt,
                    tools: agentTools,
                    maxTokens: Constants.Agent.maxTokensDefault,
                    usePromptCaching: false,
                    onEvent: { [weak self] event in
                        Task { @MainActor in
                            self?.handleEvent(event,
                                              fullText: &fullText,
                                              toolCalls: &toolCalls,
                                              blockType: &blockType,
                                              currentToolID: &currentToolID,
                                              currentToolName: &currentToolName,
                                              currentToolJSON: &currentToolJSON,
                                              stopReason: &stopReason)
                            self?.output = fullText
                        }
                    }
                )
            } catch {
                status = .failed
                return makeResult(output: "FEL: \(error.localizedDescription)", succeeded: false, start: startTime)
            }

            // Add assistant turn
            var assistantContent: [MessageContent] = []
            if !fullText.isEmpty { assistantContent.append(.text(fullText)) }
            for tc in toolCalls {
                assistantContent.append(.toolUse(id: tc.id, name: tc.name, input: tc.input))
            }
            messages.append(ChatMessage(role: .assistant, content: assistantContent))

            // No tools → done
            if toolCalls.isEmpty || stopReason == "end_turn" { break }

            // Execute tools
            var toolResults: [MessageContent] = []
            for tc in toolCalls {
                let params = tc.input.compactMapValues { $0.value as? String }
                let result = await executor.execute(name: tc.name, params: params, projectRoot: projectRoot)

                // Track written/modified files
                if tc.name == "write_file" || tc.name == "create_directory", let path = params["path"] {
                    filesWritten.append(path)
                } else if tc.name == "move_file", let to = params["to"] {
                    filesWritten.append(to)
                }

                toolResults.append(.toolResult(id: tc.id, content: result, isError: result.hasPrefix("FEL:")))
                output += "\n🔧 \(tc.name): \(result.prefix(100))"
            }
            messages.append(ChatMessage(role: .user, content: toolResults))
            progress = Double(iterationCount) / Double(maxIterations)
        }

        status = .completed
        return makeResult(output: fullText, succeeded: true, start: startTime)
    }

    // MARK: - Event handler (mirrors AgentEngine's logic)

    private func handleEvent(
        _ event: StreamEvent,
        fullText: inout String,
        toolCalls: inout [(id: String, name: String, input: [String: AnyCodable])],
        blockType: inout String,
        currentToolID: inout String,
        currentToolName: inout String,
        currentToolJSON: inout String,
        stopReason: inout String
    ) {
        switch event {
        case .contentBlockStart(_, let type, let id, let name):
            blockType = type
            if type == "tool_use", let id = id, let name = name {
                currentToolID = id
                currentToolName = name
                currentToolJSON = ""
            }
        case .contentBlockDelta(_, let delta):
            switch delta {
            case .text(let t): fullText += t
            case .inputJSON(let j): currentToolJSON += j
            }
        case .contentBlockStop:
            if blockType == "tool_use", !currentToolID.isEmpty {
                let input = parseJSON(currentToolJSON)
                toolCalls.append((id: currentToolID, name: currentToolName, input: input))
                currentToolID = ""
                currentToolName = ""
                currentToolJSON = ""
            }
            blockType = ""
        case .messageDelta(let reason, _):
            if let r = reason { stopReason = r }
        default: break
        }
    }

    private func parseJSON(_ json: String) -> [String: AnyCodable] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict.mapValues { AnyCodable($0) }
    }

    // MARK: - Prompts

    private func buildWorkerPrompt() -> String {
        """
        Du är worker #\(task.id.uuidString.prefix(8)).

        Din uppgift (och BARA denna): \(task.instruction)

        Fokusera enbart på detta. Skriv inga onödiga förklaringar.
        Använd verktyg direkt. Rapportera när du är klar.
        """
    }

    private var workerSystemPrompt: String {
        #if os(macOS)
        return """
        Du är en Navi-worker på macOS med full systembehörighet.
        Du har ett avgränsat uppdrag och ska genomföra det effektivt och direkt.

        Tillgängliga verktyg: read_file, write_file, move_file, delete_file,
        create_directory, list_directory, run_command, search_files, get_api_key,
        build_project, download_file, zip_files

        Regler:
        - Använd run_command för bash/zsh, xcodebuild, swift, git, npm, pip etc.
        - Läs filer innan du skriver dem om du behöver förstå kontexten
        - Rapportera vad du gjort när du är klar
        - Var koncis — inga onödiga förklaringar
        """
        #else
        return """
        Du är en Navi-worker på iOS.
        Du har ett avgränsat uppdrag och ska genomföra det effektivt.

        Tillgängliga verktyg (kör direkt på iOS):
        read_file, write_file, move_file, delete_file, create_directory,
        list_directory, search_files, download_file, get_api_key

        Terminal-kommandon (run_command, build_project) köas automatiskt till Mac.
        Markera sådana steg med [REQUIRES_MAC] i din text.

        Regler:
        - Skriv kod direkt med write_file — behöver inte terminal
        - Ladda ned filer med download_file (URLSession, inte curl)
        - Var koncis — inga onödiga förklaringar
        """
        #endif
    }

    private func makeResult(output: String, succeeded: Bool, start: Date) -> WorkerResult {
        WorkerResult(
            id: UUID(),
            taskID: task.id,
            output: output,
            filesWritten: filesWritten,
            succeeded: succeeded,
            ranLocally: !task.requiresTerminal || UIDevice.isMac,
            durationSeconds: Date().timeIntervalSince(start)
        )
    }
}
