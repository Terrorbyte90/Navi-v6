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

        ## Verktyg
        - Du har GitHub-verktyg: github_list_repos, github_get_repo, github_list_branches, github_list_commits, github_list_pull_requests, github_create_pull_request, github_get_file_content, github_search_repos, github_get_user
        - Använd ALLTID dessa verktyg för GitHub-frågor istället för att gissa
        - Vänta alltid på verktygsresultat innan du svarar — hoppa aldrig över dem

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
        defer { isStreaming = false; streamingText = "" }

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

        // Check if we have GitHub tools available
        let useTools = KeychainManager.shared.githubToken?.isEmpty == false
        let toolsToUse = useTools ? agentTools : nil

        // Route streaming by provider
        let eventHandler: (StreamEvent) -> Void = { [self] event in
            switch event {
            case .contentBlockStart(_, let type, let id, let name):
                blockType = type
                currentToolID = id ?? ""
                currentToolName = name ?? ""
                currentToolJSON = ""
                if type == "tool_use" {
                    onToken("🔧 ")
                }
            case .contentBlockDelta(_, let delta):
                switch delta {
                case .text(let chunk):
                    fullText += chunk
                    charsSinceScroll += chunk.count
                    onToken(chunk)
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

        // Execute tool calls if any
        if !toolCalls.isEmpty {
            NaviLog.info("Chat: executing \(toolCalls.count) tool calls: \(toolCalls.map { $0.name })")
            var toolResults: [MessageContent] = []
            
            for tc in toolCalls {
                NaviLog.info("Chat: calling tool \(tc.name) with params: \(tc.input.keys)")
                let params = tc.input.mapValues { String(describing: $0.value) }
                let result = await toolExecutor.execute(name: tc.name, params: params, projectRoot: nil)
                NaviLog.info("Chat: tool \(tc.name) result: \(result.prefix(200))")
                toolResults.append(.toolResult(id: tc.id, content: result, isError: result.hasPrefix("FEL:") || result.hasPrefix("❌")))
                fullText += "\n\n🔧 **\(tc.name)**:\n\(result)"
            }
            
            // Add tool results summary to conversation for UI display
            let toolSummary = toolResults.compactMap { tc -> String? in
                if case .toolResult(_, let content, _) = tc {
                    return content.prefix(300).description
                }
                return nil
            }.joined(separator: "\n\n")

            if !toolSummary.isEmpty {
                conversation.messages.append(PureChatMessage(
                    role: .assistant,
                    content: "🔧 **GitHub-resultat:**\n\n\(toolSummary)",
                    costSEK: 0,
                    model: conversation.model,
                    tokenUsage: nil,
                    memoriesInContext: []
                ))
            }
            
            // Continue with tool results for final response
            let secondPassMessages = apiMessages + [
                ChatMessage(role: .assistant, content: [.text(fullText)]),
                ChatMessage(role: .user, content: toolResults)
            ]
            
            // Second pass - get final response after tools
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
                // If second pass fails, use the first response
                NaviLog.error("Chat tool second pass failed: \(error)")
            }
        }

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
            memoriesInContext: relevantMems.map(\.fact)
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
