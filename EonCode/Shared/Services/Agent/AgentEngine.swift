import Foundation
import Combine

// MARK: - Agent tools definition

let agentTools: [ClaudeTool] = [
    ClaudeTool(name: "read_file", description: "Läs innehållet i en fil",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Filsökväg")], required: ["path"])),
    ClaudeTool(name: "write_file", description: "Skriv/skapa en fil med innehåll",
               inputSchema: ToolInputSchema(properties: [
                   "path": ToolProperty(type: "string", description: "Filsökväg"),
                   "content": ToolProperty(type: "string", description: "Filinnehåll")
               ], required: ["path", "content"])),
    ClaudeTool(name: "move_file", description: "Flytta eller döp om en fil/mapp",
               inputSchema: ToolInputSchema(properties: [
                   "from": ToolProperty(type: "string", description: "Källsökväg"),
                   "to": ToolProperty(type: "string", description: "Målsökväg")
               ], required: ["from", "to"])),
    ClaudeTool(name: "delete_file", description: "Ta bort en fil eller mapp",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Sökväg att ta bort")], required: ["path"])),
    ClaudeTool(name: "create_directory", description: "Skapa en mapp",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Mappsökväg")], required: ["path"])),
    ClaudeTool(name: "list_directory", description: "Lista innehållet i en katalog",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Katalogsökväg")], required: ["path"])),
    ClaudeTool(name: "run_command", description: "Kör ett terminalkommando (macOS)",
               inputSchema: ToolInputSchema(properties: ["cmd": ToolProperty(type: "string", description: "Kommandot att köra")], required: ["cmd"])),
    ClaudeTool(name: "search_files", description: "Sök i alla filer i projektet",
               inputSchema: ToolInputSchema(properties: ["query": ToolProperty(type: "string", description: "Sökterm")], required: ["query"])),
    ClaudeTool(name: "get_api_key", description: "Hämta API-nyckel från keychain",
               inputSchema: ToolInputSchema(properties: ["service": ToolProperty(type: "string", description: "Tjänstens namn")], required: ["service"])),
    ClaudeTool(name: "build_project", description: "Bygg ett Xcode-projekt",
               inputSchema: ToolInputSchema(properties: ["path": ToolProperty(type: "string", description: "Sökväg till .xcodeproj eller Package.swift")], required: ["path"])),
    ClaudeTool(name: "download_file", description: "Ladda ned en fil",
               inputSchema: ToolInputSchema(properties: [
                   "url": ToolProperty(type: "string", description: "URL att ladda ned"),
                   "destination": ToolProperty(type: "string", description: "Lokal målsökväg")
               ], required: ["url", "destination"])),
    ClaudeTool(name: "zip_files", description: "Skapa en zip-fil",
               inputSchema: ToolInputSchema(properties: [
                   "source": ToolProperty(type: "string", description: "Källsökväg"),
                   "destination": ToolProperty(type: "string", description: "Mål zip-fil")
               ], required: ["source", "destination"])),
    
    // MARK: - GitHub Tools
    ClaudeTool(name: "github_list_repos", description: "Lista alla dina GitHub-repositories",
               inputSchema: ToolInputSchema(properties: [:], required: [])),
    ClaudeTool(name: "github_get_repo", description: "Hämta information om ett specifikt GitHub-repo",
               inputSchema: ToolInputSchema(properties: ["repo": ToolProperty(type: "string", description: "Repo-namn (t.ex. 'användare/repo')")], required: ["repo"])),
    ClaudeTool(name: "github_list_branches", description: "Lista branches i ett repo",
               inputSchema: ToolInputSchema(properties: ["repo": ToolProperty(type: "string", description: "Repo-namn")], required: ["repo"])),
    ClaudeTool(name: "github_list_commits", description: "Lista commits i ett repo",
               inputSchema: ToolInputSchema(properties: [
                   "repo": ToolProperty(type: "string", description: "Repo-namn"),
                   "branch": ToolProperty(type: "string", description: "Branch-namn (valfritt)")
               ], required: ["repo"])),
    ClaudeTool(name: "github_list_pull_requests", description: "Lista pull requests i ett repo",
               inputSchema: ToolInputSchema(properties: [
                   "repo": ToolProperty(type: "string", description: "Repo-namn"),
                   "state": ToolProperty(type: "string", description: "Filtrera på state: 'open', 'closed', 'all' (default: 'open')")
               ], required: ["repo"])),
    ClaudeTool(name: "github_create_pull_request", description: "Skapa en ny pull request",
               inputSchema: ToolInputSchema(properties: [
                   "repo": ToolProperty(type: "string", description: "Repo-namn"),
                   "title": ToolProperty(type: "string", description: "PR-titel"),
                   "body": ToolProperty(type: "string", description: "PR-beskrivning"),
                   "head": ToolProperty(type: "string", description: "Branch att merga från"),
                   "base": ToolProperty(type: "string", description: "Mål-branch (t.ex. 'main')")
               ], required: ["repo", "title", "head", "base"])),
    ClaudeTool(name: "github_get_file_content", description: "Hämta innehållet av en fil från GitHub",
               inputSchema: ToolInputSchema(properties: [
                   "repo": ToolProperty(type: "string", description: "Repo-namn"),
                   "path": ToolProperty(type: "string", description: "Sökväg till filen"),
                   "branch": ToolProperty(type: "string", description: "Branch (valfritt, default: main)")
               ], required: ["repo", "path"])),
    ClaudeTool(name: "github_search_repos", description: "Sök efter repositories",
               inputSchema: ToolInputSchema(properties: ["query": ToolProperty(type: "string", description: "Sökterm")], required: ["query"])),
    ClaudeTool(name: "github_get_user", description: "Hämta din GitHub-användarinformation",
               inputSchema: ToolInputSchema(properties: [:], required: [])),

    // MARK: - Web Search
    ClaudeTool(name: "web_search",
               description: "Sök på internet efter information, nyheter, dokumentation eller valfritt ämne",
               inputSchema: ToolInputSchema(
                   properties: ["query": ToolProperty(type: "string", description: "Sökfrågan att söka på internet")],
                   required: ["query"])),

    // MARK: - Brain Server Tools
    ClaudeTool(name: "server_ask",
               description: "Ställ en fråga eller ge en uppgift till Navi Brain-servern (Minimax AI på servern)",
               inputSchema: ToolInputSchema(
                   properties: ["prompt": ToolProperty(type: "string", description: "Frågan eller uppgiften till Brain")],
                   required: ["prompt"])),
    ClaudeTool(name: "server_status",
               description: "Hämta serverstatistik: uptime, PM2-processer, minne, disk, anslutna repos",
               inputSchema: ToolInputSchema(properties: [:], required: [])),
    ClaudeTool(name: "server_exec",
               description: "Kör ett shell-kommando på Brain-servern som root (Ubuntu). Kräver bekräftelse för destruktiva kommandon.",
               inputSchema: ToolInputSchema(
                   properties: ["cmd": ToolProperty(type: "string", description: "Shell-kommandot att köra på servern")],
                   required: ["cmd"])),
    ClaudeTool(name: "server_repos",
               description: "Lista alla repos synkade på Brain-servern med branch-info",
               inputSchema: ToolInputSchema(properties: [:], required: [])),
]

// MARK: - Agent Engine

@MainActor
final class AgentEngine: ObservableObject {
    static let shared = AgentEngine()

    @Published var currentTask: AgentTask?
    @Published var isRunning = false
    @Published var statusMessage = ""
    @Published var streamingText = ""

    private let claude = ClaudeAPIClient.shared
    private let checkpoint = CheckpointManager.shared
    private var cancellable: AnyCancellable?
    private var currentProject: NaviProject?

    // Tool executor — platform-specific
    private let toolExecutor = ToolExecutor()

    func setProject(_ project: NaviProject) {
        currentProject = project
        toolExecutor.currentProjectID = project.id
    }

    // MARK: - Run agent task

    func run(
        task: AgentTask,
        conversation: inout Conversation,
        onUpdate: @escaping (String) -> Void
    ) async {
        guard !isRunning else { return }
        isRunning = true
        currentTask = task
        toolExecutor.currentProjectID = currentProject?.id
        toolExecutor.currentConversationID = conversation.id
        defer {
            isRunning = false
            currentTask = nil
        }

        var task = task
        task.status = .running
        task.startedAt = Date()
        statusMessage = "Planerar uppgift…"

        // MARK: Route complex tasks to Orchestrator
        let shouldParallelize = TaskDecomposer.shouldParallelize(instruction: task.instruction)

        if shouldParallelize, let project = currentProject {
            onUpdate("🌊 Komplex uppgift — planerar med parallella workers…")
            let result = await OrchestratorAgent.shared.execute(
                instruction: task.instruction,
                project: project,
                model: project.activeModel,
                onProgress: onUpdate
            )
            task.status = result.succeeded ? .completed : .failed
            task.completedAt = Date()
            task.result = result.summary
            streamingText = ""
            statusMessage = result.succeeded ? "Klar ✓" : "Misslyckad"
            onUpdate(result.summary)
            return
        }

        // MARK: Sequential execution (simple tasks)

        // Build initial messages
        var messages = conversation.messages
        messages.append(ChatMessage(
            role: .user,
            content: [.text(task.instruction)]
        ))

        var iterationCount = 0
        let maxIterations = 50
        var consecutiveErrors = 0
        let maxConsecutiveErrors = 3

        while iterationCount < maxIterations {
            iterationCount += 1
            streamingText = ""

            var fullText = ""
            var toolCalls: [(id: String, name: String, input: [String: AnyCodable])] = []
            var currentToolID = ""
            var currentToolName = ""
            var currentToolJSON = ""
            var blockType = ""
            var stopReason = ""
            var inputTokens = 0
            var outputTokens = 0

            statusMessage = "Tänker… (steg \(iterationCount)/\(maxIterations))"

            do {
                try await ModelRouter.stream(
                    messages: messages,
                    model: currentProject?.activeModel ?? .sonnet46,
                    systemPrompt: MessageBuilder.agentSystemPrompt(for: currentProject),
                    maxTokens: Constants.Agent.maxTokensLarge,
                    tools: agentTools,
                    onEvent: { [weak self] event in
                        self?.handleStreamEvent(
                            event,
                            fullText: &fullText,
                            toolCalls: &toolCalls,
                            currentToolID: &currentToolID,
                            currentToolName: &currentToolName,
                            currentToolJSON: &currentToolJSON,
                            blockType: &blockType,
                            stopReason: &stopReason,
                            inputTokens: &inputTokens,
                            outputTokens: &outputTokens
                        )
                        self?.streamingText = ResponseCleaner.clean(fullText)
                    }
                )
                consecutiveErrors = 0
            } catch let error as ClaudeError {
                consecutiveErrors += 1
                let msg = "⚠️ API-fel (försök \(consecutiveErrors)/\(maxConsecutiveErrors)): \(error.localizedDescription)"
                onUpdate(msg)
                if consecutiveErrors >= maxConsecutiveErrors {
                    task.status = .failed
                    task.error = error.localizedDescription
                    break
                }
                // Exponential backoff
                try? await Task.sleep(for: .seconds(Double(consecutiveErrors) * 2))
                continue
            } catch {
                onUpdate("❌ Oväntat fel: \(error.localizedDescription)")
                task.status = .failed
                task.error = error.localizedDescription
                break
            }

            // Build assistant message (clean response text from internal artifacts)
            let cleanedText = ResponseCleaner.clean(fullText)
            var assistantContent: [MessageContent] = []
            if !cleanedText.isEmpty { assistantContent.append(.text(cleanedText)) }
            for tool in toolCalls {
                assistantContent.append(.toolUse(id: tool.id, name: tool.name, input: tool.input))
            }
            let assistantMsg = ChatMessage(role: .assistant, content: assistantContent, model: currentProject?.activeModel)
            messages.append(assistantMsg)

            if !fullText.isEmpty { onUpdate(ResponseCleaner.clean(fullText)) }

            // Save checkpoint
            checkpoint.save(taskID: task.id, step: iterationCount, data: ["messages": messages.count, "tools": toolCalls.count])

            // Done if no tool calls
            if toolCalls.isEmpty || stopReason == "end_turn" {
                task.status = .completed
                task.completedAt = Date()
                break
            }

            // Execute tool calls
            statusMessage = "Exekverar \(toolCalls.count) verktyg…"
            var toolResults: [MessageContent] = []

            for toolCall in toolCalls {
                let params = toolCall.input.compactMapValues { $0.value as? String }
                let result: String

                #if os(iOS)
                let action = agentActionFromTool(name: toolCall.name, params: params)
                let actionResult = await LocalAgentEngine.shared.execute(
                    action: action,
                    projectRoot: currentProject?.resolvedURL
                )
                result = actionResult.output
                let badge = actionResult.isQueued ? "🟡" : "✅"
                onUpdate("\(badge) \(toolCall.name): \(result.prefix(300))")
                #else
                result = await toolExecutor.execute(
                    name: toolCall.name,
                    params: params,
                    projectRoot: currentProject?.resolvedURL
                )
                let badge = result.hasPrefix("FEL:") ? "❌" : "✅"
                onUpdate("\(badge) \(toolCall.name): \(result.prefix(300))")
                #endif

                toolResults.append(.toolResult(id: toolCall.id, content: result, isError: result.hasPrefix("FEL:")))
            }

            messages.append(ChatMessage(role: .user, content: toolResults))
        }

        // Final update
        streamingText = ""
        if task.status == .completed {
            statusMessage = "Uppgift klar ✓"
        }

        // Extract memories from agent conversation (best-effort, background)
        if messages.count >= 6 {
            let convId = conversation.id
            Task {
                await MemoryManager.shared.extractMemoriesFromAgent(
                    messages: messages,
                    conversationId: convId
                )
            }
        }
    }

    // MARK: - Stream event handler

    private func handleStreamEvent(
        _ event: StreamEvent,
        fullText: inout String,
        toolCalls: inout [(id: String, name: String, input: [String: AnyCodable])],
        currentToolID: inout String,
        currentToolName: inout String,
        currentToolJSON: inout String,
        blockType: inout String,
        stopReason: inout String,
        inputTokens: inout Int,
        outputTokens: inout Int
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
            case .text(let t):
                fullText += t
            case .inputJSON(let j):
                currentToolJSON += j
            }
        case .contentBlockStop(_):
            if blockType == "tool_use" && !currentToolID.isEmpty {
                let input = parseToolInput(currentToolJSON)
                toolCalls.append((id: currentToolID, name: currentToolName, input: input))
                currentToolID = ""
                currentToolName = ""
                currentToolJSON = ""
            }
            blockType = ""
        case .messageDelta(let reason, let usage):
            if let reason = reason { stopReason = reason }
            if let usage = usage { outputTokens = usage.outputTokens }
        case .messageStart(_, _):
            break
        case .messageStop:
            break
        case .error(let msg):
            fullText += "\n[Stream Error: \(msg)]"
        case .ping:
            break
        }
    }

    private func parseToolInput(_ json: String) -> [String: AnyCodable] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict.mapValues { AnyCodable($0) }
    }

    // MARK: - Simple chat (non-agent)

    func sendChat(
        userText: String,
        images: [Data] = [],
        conversation: inout Conversation,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (TokenUsage) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        var content: [MessageContent] = []
        for img in images {
            content.append(.image(img, mimeType: "image/jpeg"))
        }
        content.append(.text(userText))

        let userMsg = ChatMessage(role: .user, content: content)
        conversation.addMessage(userMsg)

        var fullText = ""
        var finalUsage: TokenUsage?
        var inputTokens = 0

        do {
            try await claude.streamMessage(
                messages: conversation.messages,
                model: conversation.model,
                systemPrompt: conversation.systemPrompt ?? MessageBuilder.agentSystemPrompt(for: currentProject),
                onEvent: { event in
                    switch event {
                    case .contentBlockDelta(_, let delta):
                        if case .text(let t) = delta {
                            fullText += t
                            onToken(t)
                        }
                    case .messageDelta(_, let usage):
                        if let u = usage {
                            finalUsage = u
                        }
                    case .messageStart(_, _):
                        break
                    default: break
                    }
                }
            )
        } catch {
            onError(error)
            return
        }

        let usage = finalUsage ?? TokenUsage(inputTokens: inputTokens, outputTokens: 0, cacheCreationInputTokens: nil, cacheReadInputTokens: nil)
        let (_, costSEK) = CostCalculator.shared.calculate(usage: usage, model: conversation.model)

        let cleanedFullText = ResponseCleaner.clean(fullText)
        var assistantMsg = ChatMessage(role: .assistant, content: [.text(cleanedFullText)], model: conversation.model)
        assistantMsg.inputTokens = usage.inputTokens
        assistantMsg.outputTokens = usage.outputTokens
        assistantMsg.costSEK = costSEK
        conversation.addMessage(assistantMsg)
        conversation.updateCost(inputTokens: usage.inputTokens, outputTokens: usage.outputTokens, costSEK: costSEK)
        CostTracker.shared.record(usage: usage, model: conversation.model)

        onComplete(usage)
    }
}

// MARK: - Tool name → AgentAction helper (used on iOS)

func agentActionFromTool(name: String, params: [String: String]) -> AgentAction {
    switch name {
    case "read_file":       return .readFile(path: params["path"] ?? "")
    case "write_file":      return .writeFile(path: params["path"] ?? "", content: params["content"] ?? "")
    case "move_file":       return .moveFile(from: params["from"] ?? "", to: params["to"] ?? "")
    case "delete_file":     return .deleteFile(path: params["path"] ?? "")
    case "create_directory":return .createDirectory(path: params["path"] ?? "")
    case "list_directory":  return .listDirectory(path: params["path"] ?? "")
    case "run_command":     return .runCommand(cmd: params["cmd"] ?? "")
    case "search_files":    return .searchFiles(query: params["query"] ?? "")
    case "get_api_key":     return .getAPIKey(service: params["service"] ?? "")
    case "build_project":   return .buildProject(path: params["path"] ?? "")
    case "download_file":   return .downloadFile(url: params["url"] ?? "", destination: params["destination"] ?? "")
    case "zip_files":       return .createArchive(source: params["source"] ?? "", destination: params["destination"] ?? "")
    default:                return .custom(name: name, params: params)
    }
}
