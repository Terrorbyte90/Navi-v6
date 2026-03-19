import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

// MARK: - Cost Badge (Hidden - cost calculations removed for performance)

struct CostBadge: View {
    let costSEK: Double
    let usage: TokenUsage?
    let model: ClaudeModel?
    @State private var showDetail = false

    var body: some View {
        EmptyView()  // Cost display disabled for performance
    }
}

struct CostDetailPopover: View {
    let costSEK: Double
    let usage: TokenUsage?
    let model: ClaudeModel?

    private func formatSEK(_ v: Double) -> String {
        v < 0.001 ? "< 0.001 kr" : String(format: "%.4f kr", v)
    }
    private func formatUSD(_ v: Double) -> String {
        v < 0.00001 ? "< $0.00001" : String(format: "$%.5f", v)
    }

    var usd: Double {
        guard let usage, let model else { return 0 }
        let (u, _) = CostCalculator.shared.calculate(usage: usage, model: model)
        return u
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(.accentNavi)
                Text("Kostnad")
                    .font(.system(size: 14, weight: .semibold))
            }
            Divider().opacity(0.12)

            HStack {
                Text("Kostnad").font(.system(size: 13)).foregroundColor(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatSEK(costSEK))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    Text(formatUSD(usd))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if let usage {
                Divider().opacity(0.12)
                Group {
                    tokenRow("Indata-tokens", value: usage.inputTokens, color: .blue)
                    if let cache = usage.cacheReadInputTokens, cache > 0 {
                        tokenRow("Cache-läsning", value: cache, color: .green, note: "-90%")
                    }
                    if let cacheWrite = usage.cacheCreationInputTokens, cacheWrite > 0 {
                        tokenRow("Cache-skrivning", value: cacheWrite, color: .orange)
                    }
                    tokenRow("Utdata-tokens", value: usage.outputTokens, color: .purple)
                    tokenRow("Totalt", value: usage.inputTokens + usage.outputTokens, color: .primary)
                }
            }

            if let model {
                Divider().opacity(0.12)
                HStack {
                    Text("Modell").font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                    Text(model.displayName).font(.system(size: 12, weight: .medium)).foregroundColor(.accentNavi)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 240)
        .background(Color.sidebarBackground)
    }

    @ViewBuilder
    private func tokenRow(_ label: String, value: Int, color: Color, note: String? = nil) -> some View {
        HStack {
            Circle().fill(color.opacity(0.7)).frame(width: 6, height: 6)
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            if let note {
                Text(note)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.green.opacity(0.12)).cornerRadius(3)
            }
            Spacer()
            Text("\(value)").font(.system(size: 12, design: .monospaced))
        }
    }
}

// MARK: - Pure Chat View — Claude iOS style

struct PureChatView: View {
    @StateObject private var manager = ChatManager.shared
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var isShowingFilePicker = false
    @State private var showVoiceMode = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showCompletion = false

    @StateObject private var projectStore = ProjectStore.shared

    var conversation: ChatConversation? { manager.activeConversation }

    var body: some View {
        VStack(spacing: 0) {
            macModelBar

            if let conv = conversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Project context banner
                            if let project = projectStore.activeProject {
                                ProjectContextBanner(project: project)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                            }

                            ForEach(conv.messages.filter { $0.role != .system }) { msg in
                                PureChatBubble(message: msg)
                                    .equatable()
                                    .id(msg.id)
                            }
                            if manager.isStreaming {
                                // Single unified activity pill — priority: live tool > thinking phase
                                if !manager.streamingText.isEmpty {
                                    // Model is writing text — no extra pill, StreamingBubble handles it
                                } else if let liveToolName = manager.liveToolCall {
                                    NaviActivityPill(
                                        statusText: liveToolName.liveToolPillText,
                                        items: [liveToolName]
                                    )
                                    .padding(.horizontal, 16)
                                    .id("activityPill")
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                } else if manager.thinkingPhase != .idle && manager.thinkingPhase != .responding {
                                    NaviActivityPill(statusText: manager.thinkingPhase.pillText)
                                        .padding(.horizontal, 16)
                                        .id("activityPill")
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }

                                StreamingBubble(text: manager.streamingText)
                                    .id("streaming")
                            }

                            // Completion indicator
                            if showCompletion && !manager.isStreaming {
                                CompletionIndicator()
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                    .id("completion")
                                    .transition(.scale.combined(with: .opacity))
                            }

                            Color.clear.frame(height: 1).id("bottomAnchor")
                        }
                        .padding(.vertical, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { dismissKeyboard() }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        chatInputBar.background(Color.chatBackground)
                    }
                    .onAppear { scrollProxy = proxy; scrollToBottom(proxy, animated: false) }
                    .onChange(of: conv.messages.count) { _, _ in scrollToBottom(proxy, animated: true) }
                    .onChange(of: manager.streamingScrollTick) { _, _ in
                        scrollToBottom(proxy, animated: false)
                    }
                    .onChange(of: manager.isStreaming) { _, streaming in
                        if !streaming && conv.messages.last?.role == .assistant {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showCompletion = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { showCompletion = false }
                            }
                        } else if streaming {
                            showCompletion = false
                        }
                    }
                }
            } else {
                ScrollView { chatEmptyState }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { dismissKeyboard() }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        chatInputBar.background(Color.chatBackground)
                    }
            }
        }
        .background(Color.chatBackground)
        #if os(iOS)
        .fullScreenCover(isPresented: $showVoiceMode) {
            VoiceModeOverlay(isPresented: $showVoiceMode)
        }
        #else
        .sheet(isPresented: $showVoiceMode) {
            VoiceModeOverlay(isPresented: $showVoiceMode)
                .frame(minWidth: 500, minHeight: 400)
        }
        #endif
        .onAppear {
            if manager.activeConversation == nil && !manager.conversations.isEmpty {
                manager.activeConversation = manager.conversations.first
            }
        }
    }

    @ViewBuilder
    var macModelBar: some View {
        modelPickerBar
        Divider().opacity(0.08)
    }

    var modelPickerBar: some View {
        HStack(spacing: 12) {
            if let conv = conversation {
                Menu {
                    Section("Anthropic") {
                        ForEach(ClaudeModel.anthropicModels) { model in
                            modelMenuButton(model: model, currentModel: conv.model, convID: conv.id)
                        }
                    }
                    Section("xAI / Grok") {
                        ForEach(ClaudeModel.xaiModels) { model in
                            modelMenuButton(model: model, currentModel: conv.model, convID: conv.id)
                        }
                    }
                    Section("OpenRouter") {
                        ForEach(ClaudeModel.openRouterModels) { model in
                            modelMenuButton(model: model, currentModel: conv.model, convID: conv.id)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(conv.model.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
            } else {
                Text("Chatt")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
            }

            Spacer()

            Button { _ = manager.newConversation() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help("Ny chatt")
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func modelMenuButton(model: ClaudeModel, currentModel: ClaudeModel, convID: UUID) -> some View {
        let hasKey = Self.hasAPIKey(for: model)
        Button {
            // Switching model opens a fresh conversation with the new model
            // so each chat stays tied to a single model
            if model != currentModel {
                _ = manager.newConversation(model: model)
            }
            manager.lastError = nil
        } label: {
            HStack {
                Text(model.displayName)
                if !hasKey {
                    Image(systemName: "key.slash")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
                Spacer()
                if model == currentModel { Image(systemName: "checkmark") }
            }
        }
    }

    private static func hasAPIKey(for model: ClaudeModel) -> Bool {
        switch model.provider {
        case .anthropic:   return KeychainManager.shared.anthropicAPIKey?.isEmpty == false
        case .xai:         return KeychainManager.shared.xaiAPIKey?.isEmpty == false
        case .openRouter:  return KeychainManager.shared.openRouterAPIKey?.isEmpty == false
        }
    }

    // MARK: - Empty state — glass orb instead of sparkle

    var chatEmptyState: some View {
        VStack(spacing: 32) {
            Spacer()
            VStack(spacing: 16) {
                ThinkingOrb(size: 64, isAnimating: false)

                VStack(spacing: 8) {
                    Text("Hur kan jag hjälpa dig?")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.primary)
                }
            }

            VStack(spacing: 8) {
                QuickActionChip(text: "Skriv kod", icon: "chevron.left.forwardslash.chevron.right") {
                    inputText = "Hjälp mig skriva "
                }
                QuickActionChip(text: "Analysera filer", icon: "doc.text.magnifyingglass") {
                    inputText = "Analysera den här filen: "
                }
                QuickActionChip(text: "Felsök ett problem", icon: "ant") {
                    inputText = "Hjälp mig felsöka: "
                }
                QuickActionChip(text: "Förklara något", icon: "lightbulb") {
                    inputText = "Förklara "
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Input bar

    var chatInputBar: some View {
        VStack(spacing: 0) {
            // Error banner
            if let error = manager.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 12))
                        .lineLimit(2)
                    Spacer()
                    Button { manager.lastError = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(NaviTheme.error)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NaviTheme.error.opacity(0.08))
            }

            PureChatInputBar(
            inputText: $inputText,
            selectedImages: $selectedImages,
            isShowingFilePicker: $isShowingFilePicker,
            showVoiceMode: $showVoiceMode,
            isStreaming: manager.isStreaming,
            onSend: sendMessage
        )
        }
    }

    // MARK: - Send

    private func sendMessage() {
        guard !inputText.isBlank || !selectedImages.isEmpty else { return }
        if manager.activeConversation == nil {
            _ = manager.newConversation()
        }
        guard let convID = manager.activeConversation?.id else { return }

        // Validate API key before sending
        if let conv = manager.activeConversation {
            if let missing = missingAPIKey(for: conv.model) {
                manager.lastError = "Ingen \(missing)-nyckel. Gå till Inställningar."
                return
            }
        }

        let text = inputText
        let images = selectedImages
        inputText = ""
        selectedImages = []
        dismissKeyboard()
        manager.lastError = nil

        Task {
            guard var conv = manager.conversations.first(where: { $0.id == convID })
                    ?? manager.activeConversation
            else { return }

            do {
                try await manager.send(text: text, images: images, in: &conv) { _ in }
            } catch {
                manager.lastError = error.localizedDescription
            }
            await MainActor.run {
                manager.activeConversation = conv
                if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
                    manager.conversations[idx] = conv
                }
            }
        }
    }

    private func missingAPIKey(for model: ClaudeModel) -> String? {
        switch model.provider {
        case .anthropic:
            if KeychainManager.shared.anthropicAPIKey?.isEmpty != false { return "Anthropic API" }
        case .xai:
            if KeychainManager.shared.xaiAPIKey?.isEmpty != false { return "xAI API" }
        case .openRouter:
            if KeychainManager.shared.openRouterAPIKey?.isEmpty != false { return "OpenRouter API" }
        }
        return nil
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = false) {
        let action = { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
        if animated { withAnimation(.easeOut(duration: 0.15)) { action() } }
        else { action() }
    }
}

// MARK: - Chat bubble — Claude iOS style (no sparkle avatar)

struct PureChatBubble: View, Equatable {
    let message: PureChatMessage

    static func == (lhs: PureChatBubble, rhs: PureChatBubble) -> Bool {
        lhs.message.id == rhs.message.id && lhs.message.content == rhs.message.content
    }

    @State private var isSpeaking = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            // Right-aligned warm user bubble — generous padding, tight leading
            HStack(alignment: .top) {
                Spacer(minLength: 72)
                VStack(alignment: .trailing, spacing: 8) {
                    if let imgs = message.imageData, !imgs.isEmpty {
                        imageRow(imgs)
                    }
                    Text(message.content)
                        .font(NaviTheme.bodyFont(size: 17))
                        .foregroundColor(.primary)
                        .lineSpacing(5)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.userBubble)
                        )
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)
        } else {
            // Left-aligned: glass orb avatar, full-width content area
            HStack(alignment: .top, spacing: 12) {
                ThinkingOrb(size: 26, isAnimating: false)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 10) {
                    // Tool call pill — shown when model executed tools
                    if let tools = message.toolCallNames, !tools.isEmpty {
                        NaviActivityPill(
                            statusText: tools.count == 1 ? "1 verktyg användes" : "\(tools.count) verktyg användes",
                            items: tools,
                            isLive: false
                        )
                    }

                    MarkdownTextView(text: message.content)
                        .textSelection(.enabled)

                    // Actions row — subtle, appears below message
                    assistantActionsRow

                    // Memory chips
                    if !message.memoriesInContext.isEmpty {
                        MemoryChipsRow(facts: message.memoriesInContext)
                    }
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Assistant action row (extracted for readability)

    @ViewBuilder
    private var assistantActionsRow: some View {
        HStack(spacing: 4) {
            // Copy button
            Button {
                #if os(iOS)
                UIPasteboard.general.string = message.content
                #else
                NSPasteboard.general.setString(message.content, forType: .string)
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // TTS button
            Button {
                if isSpeaking {
                    ElevenLabsClient.shared.stop()
                    isSpeaking = false
                } else {
                    isSpeaking = true
                    Task {
                        await ElevenLabsClient.shared.speak(message.content)
                        isSpeaking = false
                    }
                }
            } label: {
                Image(systemName: isSpeaking ? "stop.circle" : "speaker.wave.1")
                    .font(.system(size: 11))
                    .foregroundStyle(isSpeaking ? Color.accentNavi : .secondary.opacity(0.45))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Cost badge
            if let cost = message.costSEK, cost > 0 {
                CostBadge(costSEK: cost, usage: message.tokenUsage, model: message.model)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func imageRow(_ imgs: [Data]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(Array(imgs.enumerated()), id: \.offset) { _, data in
                    #if os(iOS)
                    if let ui = UIImage(data: data) {
                        Image(uiImage: ui).resizable().scaledToFit()
                            .frame(maxHeight: 200).cornerRadius(12)
                    }
                    #else
                    if let ns = NSImage(data: data) {
                        Image(nsImage: ns).resizable().scaledToFit()
                            .frame(maxHeight: 200).cornerRadius(12)
                    }
                    #endif
                }
            }
        }
    }
}

// MARK: - Streaming Bubble — glass orb with live typing cursor

struct StreamingBubble: View {
    let text: String
    var statusMessage: String = ""
    var activeFiles: [String] = []
    var codeSnippet: String = ""
    var todoItems: [ProjectAgent.AgentTodoItem] = []

    @StateObject private var markdownBuffer = StreamingMarkdownBuffer()
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 24, isAnimating: true)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if text.isEmpty {
                    // Empty state: three-bar wave animation
                    StreamingThinkingView()
                } else {
                    // Text is streaming: render markdown + blinking cursor at end
                    VStack(alignment: .leading, spacing: 0) {
                        MarkdownTextView(text: text, isStreaming: true, buffer: markdownBuffer)
                            .textSelection(.enabled)

                        // Blinking cursor appended after last line
                        Rectangle()
                            .fill(Color.accentNavi.opacity(cursorVisible ? 0.7 : 0.0))
                            .frame(width: 2, height: 16)
                            .cornerRadius(1)
                            .padding(.top, 3)
                    }
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.52).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
    }
}

// MARK: - Streaming Thinking View — three dot wave shown before text arrives

private struct StreamingThinkingView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentNavi.opacity(0.55))
                    .frame(width: 5, height: phase ? 14 : 5)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.14),
                        value: phase
                    )
            }
        }
        .frame(height: 18, alignment: .center)
        .onAppear { phase = true }
    }
}

// MARK: - Memory Chips Row

struct MemoryChipsRow: View {
    let facts: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 9))
                    Text(expanded ? "Minnen använda" : "Minnen: \(facts.count)")
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundColor(.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)

            if expanded {
                FlowLayout(spacing: 4) {
                    ForEach(facts, id: \.self) { fact in
                        Text(fact)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.75))
                            .lineLimit(2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.accentNavi.opacity(0.08))
                                    .overlay(Capsule().strokeBorder(Color.accentNavi.opacity(0.18), lineWidth: 0.5))
                            )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Quick Action Chip — Claude style

struct QuickActionChip: View {
    let text: String
    var icon: String = "chevron.left.forwardslash.chevron.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentNavi.opacity(0.7))
                Text(text)
                    .font(.system(size: 14))
            }
            .foregroundColor(.primary.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surfaceHover.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project Context Banner

struct ProjectContextBanner: View {
    let project: NaviProject

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(project.color.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)

                if let repo = project.githubRepoFullName {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text(project.githubBranch ?? repo)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                }
            }

            Spacer()

            Image(systemName: "link")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surfaceHover.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.dividerColor.opacity(0.3), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.accentNavi.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.15 : 0.7)
                    .opacity(animating ? 1.0 : 0.35)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: animating
                    )
            }
        }
        .drawingGroup()
        .onAppear { animating = true }
    }
}

// MARK: - Isolated Input Bar — Claude iOS style

private struct PureChatInputBar: View {
    @Binding var inputText: String
    @Binding var selectedImages: [Data]
    @Binding var isShowingFilePicker: Bool
    @Binding var showVoiceMode: Bool
    let isStreaming: Bool
    let onSend: () -> Void

    @FocusState private var inputFocused: Bool
    #if os(iOS)
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    #endif

    var body: some View {
        VStack(spacing: 8) {
            AgentActivityOverlay()

            // Image thumbnails
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, data in
                            InputImageThumb(data: data) {
                                selectedImages.remove(at: idx)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
            }

            // Input pill — Claude iOS warm rounded style
            HStack(alignment: .center, spacing: 8) {
                // Single + button with photo & file options
                Menu {
                    #if os(iOS)
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("Bild", systemImage: "photo")
                    }
                    #else
                    Button {
                        pickImageMacOS()
                    } label: {
                        Label("Bild", systemImage: "photo")
                    }
                    #endif
                    Button { isShowingFilePicker = true } label: {
                        Label("Fil", systemImage: "doc")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 32, height: 32)
                        Image(systemName: selectedImages.isEmpty ? "plus" : "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(selectedImages.isEmpty ? .primary.opacity(0.4) : .accentNavi)
                    }
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                #if os(iOS)
                .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems, maxSelectionCount: 5, matching: .images)
                .onChange(of: photoPickerItems) { _, items in
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                await MainActor.run { selectedImages.append(data) }
                            }
                        }
                        await MainActor.run { photoPickerItems = [] }
                    }
                }
                #endif

                // Text field
                TextField("Skriv till Navi", text: $inputText, axis: .vertical)
                    .focused($inputFocused)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)

                // Send / voice / stop
                if isStreaming {
                    Button(action: onSend) {
                        ZStack {
                            Circle().fill(Color.accentNavi).frame(width: 32, height: 32)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                } else if inputText.isBlank && selectedImages.isEmpty {
                    Button { showVoiceMode = true } label: {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 32, height: 32)
                            Image(systemName: "waveform")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary.opacity(0.4))
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSend) {
                        ZStack {
                            Circle().fill(Color.accentNavi).frame(width: 32, height: 32)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )

            Text("Navi kan göra fel. Verifiera viktig information.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    #if os(macOS)
    private func pickImageMacOS() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let data = try? Data(contentsOf: url) {
                    selectedImages.append(data)
                }
            }
        }
    }
    #endif
}

// MARK: - Image Thumbnail

struct InputImageThumb: View {
    let data: Data
    let onRemove: () -> Void

    #if os(iOS)
    @State private var cached: UIImage?
    #else
    @State private var cached: NSImage?
    #endif

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let cached {
                    #if os(iOS)
                    Image(uiImage: cached).resizable().scaledToFill()
                    #else
                    Image(nsImage: cached).resizable().scaledToFill()
                    #endif
                } else {
                    Color.surfaceHover
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
        .task(id: data) {
            #if os(iOS)
            cached = UIImage(data: data)
            #else
            cached = NSImage(data: data)
            #endif
        }
    }
}

// MARK: - Agent Activity Overlay

struct AgentActivityOverlay: View {
    @ObservedObject private var activity = NaviOrchestrator.shared.activity

    var body: some View {
        if activity.isActive {
            NaviActivityPill(statusText: activity.phase.displayText)
                .padding(.horizontal, 4)
                .padding(.top, 4)
        }
    }
}

// MARK: - Chat Tool Call Strip — visual card for tool calls in Chat + Code views

struct ChatToolCallStrip: View {
    let tools: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentNavi.opacity(0.7))
                    Text("\(tools.count) \(tools.count == 1 ? "verktyg" : "verktyg") kördes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentNavi.opacity(0.7))
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentNavi.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(tools.prefix(8), id: \.self) { tool in
                        HStack(spacing: 5) {
                            Image(systemName: toolIcon(tool))
                                .font(.system(size: 8))
                                .foregroundColor(.accentNavi.opacity(0.5))
                            Text(tool)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.accentNavi.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    if tools.count > 8 {
                        Text("+ \(tools.count - 8) till…")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentNavi.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentNavi.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func toolIcon(_ tool: String) -> String {
        ChatToolCallStrip.toolIconStatic(tool)
    }

    static func toolIconStatic(_ tool: String) -> String {
        let t = tool.lowercased()
        if t.hasPrefix("bash") || t.hasPrefix("run_command") || t.hasPrefix("execute") { return "terminal" }
        if t.hasPrefix("read_file") || t.hasPrefix("get_file") { return "doc.text" }
        if t.hasPrefix("write_file") || t.hasPrefix("create_file") { return "square.and.pencil" }
        if t.hasPrefix("list_files") || t.hasPrefix("list_dir") { return "folder" }
        if t.hasPrefix("github_create_pull") { return "arrow.triangle.pull" }
        if t.hasPrefix("github_create") { return "plus.circle" }
        if t.hasPrefix("github") { return "arrow.triangle.branch" }
        if t.hasPrefix("web_search") { return "globe" }
        if t.hasPrefix("server_exec") { return "server.rack" }
        if t.hasPrefix("server_ask") { return "brain" }
        if t.hasPrefix("server_status") { return "chart.bar" }
        if t.hasPrefix("server_repos") { return "tray.2" }
        if t.hasPrefix("server") { return "server.rack" }
        if t.hasPrefix("search") { return "magnifyingglass" }
        if t.hasPrefix("memory") { return "brain.head.profile" }
        if t.hasPrefix("image") { return "photo" }
        return "wrench.and.screwdriver"
    }
}

// MARK: - Completion Indicator — shows when model is done with a task

struct CompletionIndicator: View {
    @State private var appeared = false
    @State private var checkScale: CGFloat = 0.4

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(NaviTheme.success.opacity(0.12))
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NaviTheme.success)
                    .scaleEffect(checkScale)
            }
            Text("Klar")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NaviTheme.success.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(NaviTheme.success.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(NaviTheme.success.opacity(0.2), lineWidth: 0.75)
                )
        )
        .scaleEffect(appeared ? 1.0 : 0.75)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                appeared = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(0.1)) {
                checkScale = 1.0
            }
        }
    }
}

// MARK: - Enhanced Tool Call Strip (shown in saved messages)

struct EnhancedToolCallStrip: View {
    let tools: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentNavi.opacity(0.7))
                    Text("\(tools.count) \(tools.count == 1 ? "verktyg" : "verktyg") kördes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentNavi.opacity(0.7))
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentNavi.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { idx, tool in
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(NaviTheme.success.opacity(0.6))
                            Image(systemName: ChatToolCallStrip.toolIconStatic(tool))
                                .font(.system(size: 8))
                                .foregroundColor(.accentNavi.opacity(0.5))
                            Text(tool)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.accentNavi.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentNavi.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentNavi.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(10)
    }
}
