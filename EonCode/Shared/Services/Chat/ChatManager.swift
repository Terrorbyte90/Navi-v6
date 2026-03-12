import Foundation
import Combine

// MARK: - ChatManager
// Manages pure chat conversations (no project/agent context).
// Supports GitHub tools when logged in.

@MainActor
final class ChatManager: ObservableObject {
    static let shared = ChatManager()

    @Published var conversations: [ChatConversation] = []
    @Published var activeConversation: ChatConversation?
    @Published var isStreaming = false
    @Published var streamingText = ""
    @Published var streamingScrollTick = 0   // increments every ~80 chars; used instead of .count to avoid O(n)
    @Published var isLoading = true
    @Published var lastError: String?
    /// Live tool call currently executing during streaming (shown as animated card)
    @Published var liveToolCall: String? = nil
    /// Current thinking phase — provides visual feedback about what the model is doing
    @Published var thinkingPhase: ThinkingPhase = .idle

    enum ThinkingPhase: Equatable {
        case idle
        case preparing       // Building context, loading memories
        case connecting      // Connecting to API
        case thinking        // Model is generating (streaming started but no text yet)
        case responding      // Model is streaming text
        case executingTools  // Tools are being executed
        case finishing       // Saving, extracting memories

        var label: String {
            switch self {
            case .idle:           return ""
            case .preparing:      return "Förbereder kontext…"
            case .connecting:     return "Ansluter till modell…"
            case .thinking:       return "Tänker…"
            case .responding:     return "Skriver svar…"
            case .executingTools: return "Kör verktyg…"
            case .finishing:      return "Slutför…"
            }
        }

        var icon: String {
            switch self {
            case .idle:           return ""
            case .preparing:      return "brain.head.profile"
            case .connecting:     return "antenna.radiowaves.left.and.right"
            case .thinking:       return "sparkles"
            case .responding:     return "text.cursor"
            case .executingTools: return "terminal.fill"
            case .finishing:      return "checkmark.circle"
            }
        }
    }

    private let store = iCloudChatStore.shared
    private let api = ClaudeAPIClient.shared
    private var cancellables = Set<AnyCancellable>()
    private let toolExecutor = ToolExecutor()

    private init() {
        Task {
            await load()
            isLoading = false
        }

        // Reload conversations when iCloud syncs
        NotificationCenter.default.publisher(for: .iCloudDidSync)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.load()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load

    func load() async {
        do {
            let loaded = try await store.loadAll()
            let loadedIDs = Set(loaded.map(\.id))
            let unsaved = conversations.filter { !loadedIDs.contains($0.id) }
            conversations = loaded + unsaved
            // Re-sync activeConversation from the freshly loaded array
            // so the model picker and sendMessage() always agree on the same struct
            if let active = activeConversation,
               let refreshed = conversations.first(where: { $0.id == active.id }) {
                activeConversation = refreshed
            }
        } catch {
            NaviLog.error("ChatManager: kunde inte ladda konversationer", error: error)
        }
    }

    // MARK: - New conversation

    func newConversation(model: ClaudeModel? = nil) -> ChatConversation {
        let model = model ?? SettingsStore.shared.defaultModel
        let conv = ChatConversation(model: model)
        conversations.insert(conv, at: 0)
        activeConversation = conv
        Task {
            do {
                try await store.save(conv)
            } catch {
                NaviLog.error("ChatManager: kunde inte spara ny konversation", error: error)
            }
        }
        return conv
    }

    // MARK: - Send message (streaming)

    func send(
        text: String,
        images: [Data] = [],
        in conversation: inout ChatConversation,
        voiceInstruction: String? = nil,
        onToken: @escaping (String) -> Void
    ) async throws {
        let userMsg = PureChatMessage(role: .user, content: text, imageData: images.isEmpty ? nil : images)
        conversation.messages.append(userMsg)
        conversation.updatedAt = Date()

        // Immediately surface the user message in the UI
        activeConversation = conversation
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        }

        // Build API messages
        let apiMessages = buildAPIMessages(from: conversation)

        // Build system prompt with memories + active project context
        let memoryCtx = MemoryManager.shared.memoryContext()
        var systemPrompt = """
        Du är Navi — en expert AI-assistent specialiserad på kodning, design och teknik.

        ## Svarsstil
        - Skriv **levande, strukturerade** svar med tydlig hierarki
        - Använd **fetstil** för nyckelbegrepp och viktiga insikter
        - Bryt upp längre svar med rubriker (## och ###)
        - Använd punktlistor och numrerade listor för tydlighet
        - Inkludera kodblock med korrekt språkmarkering (```swift, ```python, etc.)
        - Var professionell men varm — inte torra faktasvar
        - Vid kodningsfrågor: ge komplett, fungerande kod — inga placeholders
        - Svara ALLTID på frågan direkt — ingen onödig inledning

        ## Verktyg tillgängliga
        **GitHub:** github_list_repos, github_get_repo, github_list_branches, github_list_commits, github_list_pull_requests, github_create_pull_request, github_get_file_content, github_search_repos, github_get_user
        **Webb:** web_search — sök på internet för aktuell information, nyheter, dokumentation
        **Brain-server:** server_ask (fråga Minimax), server_status (PM2, minne, disk), server_exec (kör shell), server_repos (lista repos)
        - Använd ALLTID dessa verktyg för relevanta frågor — gissa aldrig
        - web_search: använd för frågor om aktuell info, nyheter, API-dokumentation, prislistor etc.
        - server_*: använd när Ted frågar om servern, repos, eller vill att Brain ska göra något
        - Vänta alltid på verktygsresultat innan du svarar

        ## Minnen
        \(memoryCtx)
        """

        // Inject active project context so the chat knows about cloned repos
        if let project = ProjectStore.shared.activeProject {
            systemPrompt += "\n\n**AKTIVT PROJEKT:** \(project.name)"
            if let repo = project.githubRepoFullName {
                systemPrompt += "\n- GitHub: \(repo)"
                if let branch = project.githubBranch {
                    systemPrompt += " (branch: \(branch))"
                }
            }
            // Lägg till sökväg om projektet är lokalt
            if let path = project.localPath {
                systemPrompt += "\n- Lokal sökväg: \(path)"
            }
        }

        // Lägg till tillgängliga GitHub-repos (om inloggad)
        let githubToken = KeychainManager.shared.githubToken
        if let token = githubToken, !token.isEmpty {
            systemPrompt += "\n\n**DIN GITHUB:** Du har tillgång till GitHub och kan diskutera dina projekt, lista repos, skapa PRs, etc."
            
            // Lägg till info om lokala iCloud-repos
            let localRepos = GitHubManager.shared.getLocalRepos()
            if !localRepos.isEmpty {
                systemPrompt += "\n\n**LOKALA REPOS I ICLOUD:**"
                for repoName in localRepos.prefix(20) {
                    let path = GitHubManager.shared.getLocalRepoPath(for: repoName)?.path ?? "okänd sökväg"
                    let branch = GitHubManager.shared.getLocalCurrentBranch(fullName: repoName) ?? "main"
                    let latestCommit = GitHubManager.shared.getLocalLatestCommit(fullName: repoName) ?? ""
                    let status = GitHubManager.shared.getLocalStatus(fullName: repoName)
                    let hasChanges = !status.isEmpty
                    systemPrompt += "\n- \(repoName)"
                    systemPrompt += "\n  Branch: \(branch)"
                    if hasChanges {
                        systemPrompt += " ⚠️ OUTHÄNDRINGAR FINNS"
                    }
                    if !latestCommit.isEmpty {
                        systemPrompt += "\n  Senaste: \(latestCommit.prefix(7))"
                    }
                }
                if localRepos.count > 20 {
                    systemPrompt += "\n  ... och \(localRepos.count - 20) till"
                }
                systemPrompt += "\n\nDu kan läsa och ändra filer direkt i dessa lokala repos utan att behöva hämta från nätet!"
            }
        }

        // For non-Anthropic models: inject extra context since they can't execute tools natively
        if conversation.model.provider != .anthropic {
            // Inject cached GitHub repos so the model knows about them
            let ghRepos = GitHubManager.shared.repos
            if !ghRepos.isEmpty {
                systemPrompt += "\n\n**GITHUB REPOS (live data, \(ghRepos.count) repos):**"
                for repo in ghRepos.prefix(30) {
                    systemPrompt += "\n- **\(repo.fullName)**: \(repo.description ?? "Ingen beskrivning")"
                    systemPrompt += " [\(repo.language ?? "?"), \(repo.isPrivate ? "privat" : "publik")]"
                }
                if ghRepos.count > 30 {
                    systemPrompt += "\n  ... och \(ghRepos.count - 30) till"
                }
            }

            // Inject live server status
            if NaviBrainService.shared.isConnected {
                systemPrompt += "\n\n**BRAIN SERVER:** Online (209.38.98.107:3001)"
                if let status = NaviBrainService.shared.serverStatus {
                    if let v = status.version { systemPrompt += "\n- Version: \(v)" }
                    if let r = status.repos { systemPrompt += "\n- Repos på servern: \(r)" }
                }
            } else {
                systemPrompt += "\n\n**BRAIN SERVER:** Offline"
            }

            systemPrompt += "\n\nOBS: Du har INTE tillgång till verktyg (bara Anthropic-modeller har det). "
            systemPrompt += "Du har dock all kontext ovan — svara baserat på den informationen. "
            systemPrompt += "Om användaren frågar om repos, servern etc. — använd kontexten ovan, gissa aldrig."
        }

        // View context
        if !MessageBuilder.currentViewContext.isEmpty {
            systemPrompt += "\n\nAKTIV VY: \(MessageBuilder.currentViewContext)"
        }

        // Voice mode instruction (appended to system prompt, not visible in chat)
        if let voiceInst = voiceInstruction {
            systemPrompt += "\n\n[RÖSTLÄGE] \(voiceInst)"
        }

        isStreaming = true
        streamingText = ""
        liveToolCall = nil
        thinkingPhase = .preparing
        defer { isStreaming = false; streamingText = ""; liveToolCall = nil; thinkingPhase = .idle }

        var fullText = ""
        var finalUsage: TokenUsage?
        // Smooth streaming: publish every ~30ms (~33fps) for fluid text appearance
        var lastPublish = Date.distantPast
        var charsSinceScroll = 0

        // Track tool calls for GitHub integration
        var toolCalls: [(id: String, name: String, input: [String: AnyCodable])] = []
        var currentToolID: String = ""
        var currentToolName: String = ""
        var currentToolJSON: String = ""
        var blockType: String = ""

        // Only use tools with Anthropic models (OpenRouter/xAI use different streaming format
        // that doesn't parse tool_use blocks correctly, causing garbled output)
        let toolsToUse: [ClaudeTool]?
        if conversation.model.provider == .anthropic {
            // Build the chat tool set: GitHub (if connected) + web_search + server tools
            var chatTools = agentTools  // includes github + file + web_search + server tools
            // Filter to chat-appropriate tools (no file write/delete/shell for safety in chat)
            let chatToolNames: Set<String> = [
                "github_list_repos", "github_get_repo", "github_list_branches", "github_list_commits",
                "github_list_pull_requests", "github_create_pull_request", "github_get_file_content",
                "github_search_repos", "github_get_user",
                "web_search", "server_ask", "server_status", "server_exec", "server_repos"
            ]
            let githubConnected = KeychainManager.shared.githubToken?.isEmpty == false
            chatTools = agentTools.filter { tool in
                if tool.name.hasPrefix("github_") { return githubConnected }
                return chatToolNames.contains(tool.name)
            }
            toolsToUse = chatTools.isEmpty ? nil : chatTools
        } else {
            toolsToUse = nil
        }

        // Route streaming by provider
        thinkingPhase = .connecting
        let eventHandler: (StreamEvent) -> Void = { [self] event in
            switch event {
            case .contentBlockStart(_, let type, let id, let name):
                blockType = type
                currentToolID = id ?? ""
                currentToolName = name ?? ""
                currentToolJSON = ""
                if type == "tool_use", let toolName = name {
                    self.liveToolCall = toolName
                    self.thinkingPhase = .executingTools
                }
                if type == "text" && self.thinkingPhase == .connecting {
                    self.thinkingPhase = .thinking
                }
            case .contentBlockDelta(_, let delta):
                switch delta {
                case .text(let chunk):
                    fullText += chunk
                    charsSinceScroll += chunk.count
                    onToken(chunk)
                    if self.thinkingPhase != .responding {
                        self.thinkingPhase = .responding
                    }
                    let now = Date()
                    if now.timeIntervalSince(lastPublish) >= 0.03 {
                        self.streamingText = fullText
                        if charsSinceScroll >= 40 {
                            self.streamingScrollTick += 1
                            charsSinceScroll = 0
                        }
                        lastPublish = now
                    }
                case .inputJSON(let json):
                    currentToolJSON += json
                }
            case .contentBlockStop(_):
                if blockType == "tool_use" && !currentToolName.isEmpty {
                    // Parse the accumulated tool input JSON
                    var inputCodable: [String: AnyCodable] = [:]
                    if !currentToolJSON.isEmpty,
                       let data = currentToolJSON.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        inputCodable = json.mapValues { AnyCodable($0) }
                    }
                    toolCalls.append((id: currentToolID, name: currentToolName, input: inputCodable))
                    NaviLog.info("Chat: parsed tool call \(currentToolName) with \(inputCodable.count) params")
                    self.liveToolCall = nil
                }
                blockType = ""
                currentToolID = ""
                currentToolName = ""
                currentToolJSON = ""
            case .messageDelta(_, let usage):
                finalUsage = usage
            default:
                break
            }
        }

        // Use ModelRouter - the model passed here is the EXACT model from conversation.model
        // No hidden switching allowed
        let requestedModel = conversation.model
        NaviLog.info("Chat: using model \(requestedModel.rawValue) (\(requestedModel.displayName))")
        
        do {
            let usedModel = try await ModelRouter.stream(
                messages: apiMessages,
                model: requestedModel,
                systemPrompt: systemPrompt,
                maxTokens: Constants.Agent.maxTokensDefault,
                tools: toolsToUse,
                onEvent: eventHandler
            )
            // Log model changes for debugging
            if usedModel != requestedModel {
                NaviLog.info("Chat: model changed from \(requestedModel.displayName) to \(usedModel.displayName) (fallback)")
                conversation.model = usedModel
            }
        } catch {
            NaviLog.error("Chat failed with model \(requestedModel.displayName): \(error)")
            throw error
        }

        // Capture executed tool names for visual display
        let executedToolNames = toolCalls.map { $0.name }

        // Execute tool calls if any (only happens with Anthropic models)
        if !toolCalls.isEmpty {
            thinkingPhase = .executingTools
            NaviLog.info("Chat: executing \(toolCalls.count) tool calls: \(toolCalls.map { $0.name })")
            var toolResults: [MessageContent] = []

            // Capture first-pass full text BEFORE executing tools (to build secondPassMessages)
            let firstPassText = fullText

            for tc in toolCalls {
                NaviLog.info("Chat: calling tool \(tc.name) with params: \(tc.input.keys)")
                let params = tc.input.mapValues { String(describing: $0.value) }
                let result = await toolExecutor.execute(name: tc.name, params: params, projectRoot: nil)
                NaviLog.info("Chat: tool \(tc.name) result: \(result.prefix(200))")
                toolResults.append(.toolResult(id: tc.id, content: result, isError: result.hasPrefix("FEL:") || result.hasPrefix("❌")))
            }

            // Build second pass with the first-pass assistant content + tool results as user
            let secondPassMessages = apiMessages + [
                ChatMessage(role: .assistant, content: [.text(firstPassText.isEmpty ? "(thinking)" : firstPassText)]),
                ChatMessage(role: .user, content: toolResults)
            ]

            // Second pass - get final response after tools
            thinkingPhase = .connecting
            fullText = ""
            toolCalls = []
            var lastSecondPublish = Date.distantPast
            var charsSinceScroll2 = 0

            let secondEventHandler: (StreamEvent) -> Void = { [self] event in
                switch event {
                case .contentBlockDelta(_, let delta):
                    if case .text(let chunk) = delta {
                        fullText += chunk
                        charsSinceScroll2 += chunk.count
                        onToken(chunk)
                        let now = Date()
                        if now.timeIntervalSince(lastSecondPublish) >= 0.03 {
                            self.streamingText = fullText
                            if charsSinceScroll2 >= 40 {
                                self.streamingScrollTick += 1
                                charsSinceScroll2 = 0
                            }
                            lastSecondPublish = now
                        }
                    }
                case .messageDelta(_, let usage):
                    finalUsage = usage
                default:
                    break
                }
            }

            do {
                _ = try await ModelRouter.stream(
                    messages: secondPassMessages,
                    model: conversation.model,
                    systemPrompt: systemPrompt,
                    maxTokens: Constants.Agent.maxTokensDefault,
                    tools: nil,  // No tools on second pass
                    onEvent: secondEventHandler
                )
            } catch {
                // If second pass fails, keep the first response text
                NaviLog.error("Chat tool second pass failed: \(error)")
                if fullText.isEmpty { fullText = firstPassText }
            }
        }

        thinkingPhase = .finishing

        // Skip cost calculation for performance - can be added back if needed
        let costSEK: Double = 0

        // Find which memories were referenced in this response (zero-cost keyword match)
        let relevantMems = MemoryManager.shared.relevantMemories(for: fullText, max: 3)

        let assistantMsg = PureChatMessage(
            role: .assistant,
            content: ResponseCleaner.clean(fullText),
            costSEK: costSEK,
            model: conversation.model,
            tokenUsage: finalUsage,
            memoriesInContext: relevantMems.map(\.fact),
            toolCallNames: executedToolNames.isEmpty ? nil : executedToolNames
        )
        conversation.messages.append(assistantMsg)
        conversation.updatedAt = Date()

        // Auto-generate title from first exchange
        if conversation.title == "Ny chatt" && conversation.messages.count >= 2 {
            conversation.title = await generateTitle(for: conversation)
        }

        // Persist
        try? await store.save(conversation)

        // Update published list
        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx] = conversation
        }

        // Extract memories every 10 new messages (not every single message after the 6th)
        let msgCount = conversation.messages.count
        if msgCount >= 6 && msgCount % 10 == 0 {
            let messages = conversation.messages
            let convId = conversation.id
            Task {
                await MemoryManager.shared.extractMemories(
                    from: messages,
                    conversationId: convId
                )
            }
        }

        // Detect reminder / scheduled-task intent in user message (background, silent fail)
        let sentText = text
        let convId = conversation.id
        Task {
            _ = await ScheduledTaskManager.shared.detectAndSchedule(
                from: sentText,
                conversationId: convId
            )
        }
    }

    // MARK: - Update model (persists immediately to prevent iCloud sync race)
    // Bug: picking a model updates in-memory state but iCloud sync (debounced 1s)
    // reloads conversations from disk, overwriting the in-memory model change.
    // Fix: save immediately so any subsequent iCloud reload gets the correct model.

    func updateModel(_ model: ClaudeModel, for conversationID: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[idx].model = model
        // Re-assign activeConversation from the array (value-type copy with updated model)
        if activeConversation?.id == conversationID {
            activeConversation = conversations[idx]
        }
        // Persist immediately — this is the critical part
        let conv = conversations[idx]
        Task { try? await store.save(conv) }
    }

    // MARK: - Delete

    func delete(_ conversation: ChatConversation) async {
        try? await store.delete(id: conversation.id)
        conversations.removeAll { $0.id == conversation.id }
        if activeConversation?.id == conversation.id {
            activeConversation = conversations.first
        }
    }

    // MARK: - Search

    func search(query: String) async -> [ChatConversation] {
        await store.search(query: query)
    }

    // MARK: - Auto-generate title

    func generateTitle(for conversation: ChatConversation) async -> String {
        guard let first = conversation.messages.first(where: { $0.role == .user }) else {
            return "Ny chatt"
        }

        // Try AI-generated title via Haiku (fast + cheap)
        if KeychainManager.shared.anthropicAPIKey?.isEmpty == false {
            let prompt = "Ge denna konversation en kort titel (max 5 ord, inget citattecken). Konversation: \(first.content.prefix(300))"
            do {
                let (title, _) = try await api.sendMessage(
                    messages: [ChatMessage(role: .user, content: [.text(prompt)])],
                    model: .haiku,
                    systemPrompt: "Svara med BARA titeln. Max 5 ord. Inget citattecken.",
                    maxTokens: 30
                )
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !trimmed.isEmpty && trimmed.count < 60 {
                    return trimmed
                }
            } catch {
                // Fall back to truncation
            }
        }

        // Fallback: truncate first message
        let preview = String(first.content.prefix(50))
        return preview.isEmpty ? "Ny chatt" : preview
    }

    // MARK: - Build API messages

    private func buildAPIMessages(from conversation: ChatConversation) -> [ChatMessage] {
        conversation.messages.map { msg in
            ChatMessage(role: msg.role, content: msg.apiContent)
        }
    }
}
