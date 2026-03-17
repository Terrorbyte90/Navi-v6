import Foundation
import Combine

// MARK: - ChatManager
// Manages pure chat conversations (no project/agent context).
// Supports tool calling for ALL models with full tool call loop.

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
    /// All tool call events during current streaming session (for rich visual display)
    @Published var toolCallEvents: [ToolCallEvent] = []
    /// Current thinking phase — provides visual feedback about what the model is doing
    @Published var thinkingPhase: ThinkingPhase = .idle
    /// Current API call info for visual display
    @Published var currentAPIInfo: APICallInfo? = nil
    /// Elapsed seconds since the current request started (for UI display)
    @Published var elapsedSeconds: Int = 0

    private var elapsedTimer: Timer?

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

    /// Tracks a tool call event for visual display in the chat
    struct ToolCallEvent: Identifiable {
        let id = UUID()
        let toolName: String
        let params: [String: String]
        var result: String?
        var isError: Bool = false
        var isComplete: Bool = false
        let startTime: Date = Date()
        var duration: TimeInterval?
    }

    /// API call info for visual display
    struct APICallInfo: Equatable {
        let provider: String
        let model: String
        let toolCount: Int
        let iteration: Int
    }

    private let store = iCloudChatStore.shared
    private let api = ClaudeAPIClient.shared
    private var cancellables = Set<AnyCancellable>()
    private let toolExecutor = ToolExecutor()

    /// Maximum tool call loop iterations — set high to ensure complex tasks complete
    private let maxToolIterations = 20

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

    // MARK: - Send message (streaming with full tool call loop)

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

        // Build system prompt with memories + active project context
        let systemPrompt = buildSystemPrompt(for: conversation, voiceInstruction: voiceInstruction)

        // Build the chat tool set — ALL models get tools now
        let toolsToUse = buildChatTools()

        isStreaming = true
        streamingText = ""
        liveToolCall = nil
        toolCallEvents = []
        thinkingPhase = .preparing
        currentAPIInfo = nil
        elapsedSeconds = 0
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
        defer {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            isStreaming = false
            streamingText = ""
            liveToolCall = nil
            thinkingPhase = .idle
            currentAPIInfo = nil
        }

        // Build initial API messages
        var apiMessages = buildAPIMessages(from: conversation)
        var allExecutedToolNames: [String] = []
        var finalUsage: TokenUsage?
        var fullText = ""

        // MARK: — Tool Call Loop (runs until model gives a non-tool response or max iterations)
        let requestedModel = conversation.model
        NaviLog.info("Chat: using model \(requestedModel.rawValue) (\(requestedModel.displayName))")

        for iteration in 0..<maxToolIterations {
            fullText = ""
            var toolCalls: [(id: String, name: String, input: [String: AnyCodable])] = []
            var currentToolID = ""
            var currentToolName = ""
            var currentToolJSON = ""
            var blockType = ""
            var stopReason = "end_turn"

            // Smooth streaming state
            var lastPublish = Date.distantPast
            var charsSinceScroll = 0

            // Update API call info for visual display
            currentAPIInfo = APICallInfo(
                provider: requestedModel.providerDisplayName,
                model: requestedModel.displayName,
                toolCount: toolsToUse?.count ?? 0,
                iteration: iteration + 1
            )

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
                case .messageDelta(let reason, let usage):
                    finalUsage = usage
                    if let r = reason { stopReason = r }
                default:
                    break
                }
            }

            // Route streaming by provider
            do {
                let usedModel = try await ModelRouter.stream(
                    messages: apiMessages,
                    model: requestedModel,
                    systemPrompt: systemPrompt,
                    maxTokens: Constants.Agent.maxTokensDefault,
                    tools: toolsToUse,
                    onEvent: eventHandler
                )
                if usedModel != requestedModel {
                    NaviLog.info("Chat: model changed from \(requestedModel.displayName) to \(usedModel.displayName) (fallback)")
                    conversation.model = usedModel
                }
            } catch {
                NaviLog.error("Chat failed with model \(requestedModel.displayName): \(error)")
                throw error
            }

            // Flush any remaining streamed text
            streamingText = fullText

            // If no tool calls, we're done — break the loop
            if toolCalls.isEmpty || stopReason != "tool_use" {
                NaviLog.info("Chat: iteration \(iteration + 1) complete — no more tool calls (stop: \(stopReason))")
                break
            }

            // Execute tool calls — clear stale streaming text so visual switches to tool indicator
            thinkingPhase = .executingTools
            streamingText = ""
            let executedNames = toolCalls.map { $0.name }
            allExecutedToolNames.append(contentsOf: executedNames)
            NaviLog.info("Chat: iteration \(iteration + 1) — executing \(toolCalls.count) tool calls: \(executedNames)")

            // Build assistant message content with text + tool_use blocks
            var assistantContent: [MessageContent] = []
            if !fullText.isEmpty {
                assistantContent.append(.text(fullText))
            }
            for tc in toolCalls {
                assistantContent.append(.toolUse(id: tc.id, name: tc.name, input: tc.input))
            }

            // Add assistant message to history
            apiMessages.append(ChatMessage(role: .assistant, content: assistantContent))

            // Execute each tool and collect results
            var toolResultContent: [MessageContent] = []
            for tc in toolCalls {
                // Show live tool call in UI
                liveToolCall = tc.name
                let params = tc.input.mapValues { String(describing: $0.value) }

                // Create visual event
                var event = ToolCallEvent(toolName: tc.name, params: params)

                let startTime = Date()
                let result = await toolExecutor.execute(name: tc.name, params: params, projectRoot: nil)
                let duration = Date().timeIntervalSince(startTime)

                let isError = result.hasPrefix("FEL:") || result.hasPrefix("❌")
                event.result = String(result.prefix(500))
                event.isError = isError
                event.isComplete = true
                event.duration = duration
                toolCallEvents.append(event)

                NaviLog.info("Chat: tool \(tc.name) result (\(String(format: "%.1f", duration))s): \(result.prefix(200))")
                toolResultContent.append(.toolResult(id: tc.id, content: result, isError: isError))
                liveToolCall = nil
            }

            // Add tool results to history
            apiMessages.append(ChatMessage(role: .user, content: toolResultContent))

            // Continue loop — send updated history back to model
            NaviLog.info("Chat: sending tool results back to model (iteration \(iteration + 2))")
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
            toolCallNames: allExecutedToolNames.isEmpty ? nil : allExecutedToolNames
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

    // MARK: - Build System Prompt

    private func buildSystemPrompt(for conversation: ChatConversation, voiceInstruction: String?) -> String {
        let memoryCtx = MemoryManager.shared.memoryContext()
        var systemPrompt = """
        Du är Navi — en intelligent AI-assistent skapad av Ted Svärd.
        Specialiserad på kodning, design, teknik och generella frågor.

        ## Svarsstil
        - **Strukturerade** svar med rubriker, **fetstil**, kodblock (```swift, ```python)
        - Punktlistor och numrerade steg för tydlighet
        - Professionell men engagerad — inte torra faktasvar
        - Komplett, fungerande kod vid kodningsfrågor — inga placeholders
        - Svara DIREKT på frågan — ingen onödig inledning

        ## KRITISKA REGLER — FÖLJ ALLTID
        1. **SLUTFÖR ALLTID uppgiften** — stanna aldrig mitt i. Fortsätt tills du har ett komplett svar.
        2. **ANVÄND ALLTID verktyg** för frågor om GitHub, server, projekt, filer — gissa ALDRIG.
        3. **PRESENTERA resultatet** efter varje verktygsanrop — analysera och svara direkt.
        4. **Kedja verktyg** — du kan anropa flera verktyg i sekvens, loopen fortsätter (upp till 20 iterationer).
        5. **Om ett verktyg misslyckas** — försök alternativ metod eller rapportera felet tydligt.

        ## TEXTFORMATERING
        - Börja alltid med det direkta svaret. Ge svaret FÖRST, förklaring sedan.
        - Enkla/konversationella frågor: 1–3 meningar ren text. Inga rubriker. Inga punktlistor.
        - Använd punktlistor (- punkt) BARA för 3+ parallella objekt utan naturlig ordning.
        - Använd numrerade listor (1. steg) BARA för sekventiella instruktioner.
        - Använd ## rubriker BARA för svar med 3+ stora sektioner som läsaren vill navigera.
        - Använd ### för undersektioner. Använd ALDRIG # (H1) i svar.
        - Använd **fetstil** för kritiska termer, varningar, första förekomst av nyckelbegrepp. Inte dekorativt.
        - Använd `inline-kod` för: funktionsnamn, variabler, filnamn, klasser, kommandon, paketnamn.
        - Använd kodblock (```språk) för ALL kod. Inkludera alltid språkidentifierare (swift, js, python, bash…).
        - Använd tabeller BARA för jämförelse av 3+ objekt med samma attribut.
        - Inga emoji i tekniska eller formella svar.
        - Håll svaret proportionellt. En enrads-fråga → kort svar. Putta inte ut onödig text.
        - Upprepa inte användarens fråga. Sammanfatta inte ditt eget svar i slutet.
        - Varningar/noter: skriv inline med fetstil: **Obs:** eller **Varning:** — inga speciella block.

        ## Verktyg
        **GitHub (kräver GitHub-token i Keychain):**
        - github_list_repos — lista alla repos
        - github_get_repo — detaljer om ett repo
        - github_list_branches — visa branches
        - github_list_commits — senaste commits
        - github_list_pull_requests — öppna PRs
        - github_create_pull_request — skapa PR
        - github_get_file_content — läs fil direkt från GitHub
        - github_search_repos — sök repos
        - github_get_user — GitHub-profilinfo

        **Webb:** web_search — sök internet för aktuell info, dokumentation

        **Brain Server (209.38.98.107:3001):**
        - server_ask — fråga Brain AI (MiniMax/Qwen)
        - server_status — PM2-processer, minne, CPU
        - server_exec — kör shell-kommando på servern
        - server_repos — lista repos på servern

        **Filer (iCloud):**
        - read_file — läs fil (absolut sökväg eller relativ till projekt)
        - write_file — skriv/uppdatera fil
        - list_directory — lista filer i mapp
        - search_files — sök i filer

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

        // Inject iCloud container path so model can read/write files
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: Constants.iCloud.containerID) {
            let naviRoot = containerURL.appendingPathComponent("Documents").appendingPathComponent(Constants.iCloud.rootFolder)
            systemPrompt += "\n\n**iCLOUD FILER:** Du kan läsa och skriva filer via read_file / write_file / list_directory."
            systemPrompt += "\n- Navi-rot: \(naviRoot.path)"
            systemPrompt += "\n- Projekt: \(naviRoot.appendingPathComponent(Constants.iCloud.projectsFolder).path)"
            systemPrompt += "\n- GitHub-repos: \(containerURL.appendingPathComponent("Documents").appendingPathComponent(Constants.iCloud.githubReposFolder).path)"
        }

        // Inject server status for context
        if NaviBrainService.shared.isConnected {
            systemPrompt += "\n\n**BRAIN SERVER:** Online (209.38.98.107:3001)"
            if let status = NaviBrainService.shared.serverStatus {
                if let v = status.version { systemPrompt += "\n- Version: \(v)" }
                if let r = status.repos { systemPrompt += "\n- Repos på servern: \(r)" }
            }
        } else {
            systemPrompt += "\n\n**BRAIN SERVER:** Offline"
        }

        // View context
        if !MessageBuilder.currentViewContext.isEmpty {
            systemPrompt += "\n\nAKTIV VY: \(MessageBuilder.currentViewContext)"
        }

        // Voice mode instruction (appended to system prompt, not visible in chat)
        if let voiceInst = voiceInstruction {
            systemPrompt += "\n\n[RÖSTLÄGE] \(voiceInst)"
        }

        return systemPrompt
    }

    // MARK: - Build Chat Tools (for ALL models)

    private func buildChatTools() -> [ClaudeTool]? {
        var chatTools = agentTools
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
        return chatTools.isEmpty ? nil : chatTools
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

    func deleteAll() async {
        await store.deleteAll()
        conversations = []
        activeConversation = nil
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
