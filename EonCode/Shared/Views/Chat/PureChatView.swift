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
                                if !manager.streamingText.isEmpty && manager.thinkingPhase == .responding {
                                    // Actively streaming text — show streaming bubble
                                    StreamingBubble(text: manager.streamingText)
                                        .id("streaming")
                                } else {
                                    // Three-dot typing indicator while thinking/connecting/preparing/finishing
                                    ThinkingDots()
                                        .padding(.horizontal, 16)
                                        .id("activityPill")
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
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
                    .onChange(of: conv.messages.count) { scrollToBottom(proxy, animated: true) }
                    .onChange(of: manager.streamingScrollTick) { _ in
                        scrollToBottom(proxy, animated: false)
                    }
                    .onChange(of: manager.isStreaming) { streaming in
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
            // Right-aligned warm user bubble
            HStack(alignment: .top) {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 6) {
                    if let imgs = message.imageData, !imgs.isEmpty {
                        imageRow(imgs)
                    }
                    Text(message.content)
                        .font(NaviTheme.bodyFont(size: 17))
                        .foregroundColor(.primary)
                        .lineSpacing(5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.userBubble))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        } else {
            // Left-aligned: glass orb avatar, no bubble background
            HStack(alignment: .top, spacing: 10) {
                ThinkingOrb(size: 24, isAnimating: false)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    // Tool call pill — shown when model executed tools
                    if let tools = message.toolCallNames, !tools.isEmpty {
                        NaviActivityPill(
                            statusText: tools.count == 1 ? "1 verktyg" : "\(tools.count) verktyg",
                            items: tools,
                            isLive: false
                        )
                    }

                    MarkdownTextView(text: message.content)
                        .equatable()
                        .textSelection(.enabled)

                    // Actions row
                    HStack(spacing: 12) {
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = message.content
                            #else
                            NSPasteboard.general.setString(message.content, forType: .string)
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)

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
                        }
                        .buttonStyle(.plain)

                        // Cost badge
                        if let cost = message.costSEK, cost > 0 {
                            CostBadge(costSEK: cost, usage: message.tokenUsage, model: message.model)
                        }
                    }
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.top, 2)

                    // Memory chips
                    if !message.memoriesInContext.isEmpty {
                        MemoryChipsRow(facts: message.memoriesInContext)
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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

// MARK: - Streaming Bubble — smooth buffered text rendering

struct StreamingBubble: View {
    let text: String
    var statusMessage: String = ""
    var activeFiles: [String] = []
    var codeSnippet: String = ""
    var todoItems: [ProjectAgent.AgentTodoItem] = []

    /// Smooth character-by-character buffer — eliminates stutter when large chunks arrive
    @StateObject private var buffer = PureStreamingBuffer()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 24, isAnimating: true)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if !buffer.displayText.isEmpty {
                    MarkdownTextView(text: buffer.displayText)
                        .textSelection(.enabled)
                } else if !text.isEmpty {
                    // Buffer catching up — show raw text to avoid blank flash
                    MarkdownTextView(text: text)
                        .textSelection(.enabled)
                }
                // No visual here — the caller shows exactly one visual before this
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: text) { newText in
            buffer.update(newText)
        }
        .onDisappear {
            buffer.flush()
        }
    }
}

/// Smooth 30fps character-by-character reveal buffer for PureChatView streaming.
@MainActor
final class PureStreamingBuffer: ObservableObject {
    @Published private(set) var displayText: String = ""

    private var targetText: String = ""
    private var timer: Timer?
    private let charsPerTick: Int = 32   // ~960 chars/sec at 30fps — smooth but not instant
    private let fps: Double = 30.0

    func update(_ newText: String) {
        targetText = newText
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
        }
    }

    func flush() {
        displayText = targetText
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard displayText.count < targetText.count else {
            if displayText != targetText { displayText = targetText }
            timer?.invalidate()
            timer = nil
            return
        }
        let end = targetText.index(
            targetText.startIndex,
            offsetBy: min(displayText.count + charsPerTick, targetText.count)
        )
        displayText = String(targetText[..<end])
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

// MARK: - Markdown text renderer

struct MarkdownTextView: View, Equatable {
    let text: String
    private let blocks: [MDBlock]

    init(text: String) {
        self.text = text
        self.blocks = Self.parseBlocks(text)
    }

    static func == (lhs: MarkdownTextView, rhs: MarkdownTextView) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let t):
                    Self.renderHeading(t, level: level)
                        .fixedSize(horizontal: false, vertical: true)
                case .paragraph(let t):
                    Self.renderParagraph(t)
                        .fixedSize(horizontal: false, vertical: true)
                case .bulletList(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(NaviTheme.bodyFont(size: 16))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .frame(width: 10, alignment: .leading)
                                Self.renderParagraph(item)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .numberedList(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(i + 1).")
                                    .font(NaviTheme.bodyFont(size: 16))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .frame(width: 22, alignment: .leading)
                                Self.renderParagraph(item)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .code(let lang, let code):
                    MarkdownCodeBlock(language: lang, code: code)
                case .divider:
                    Divider().opacity(0.15).padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private static func renderHeading(_ raw: String, level: Int) -> some View {
        let size: CGFloat = level == 1 ? 20 : level == 2 ? 18 : 16
        let weight: Font.Weight = level == 1 ? .bold : .semibold
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: size, weight: weight))
                .padding(.top, level == 1 ? 6 : 3)
        } else {
            Text(raw)
                .font(.system(size: size, weight: weight))
                .padding(.top, level == 1 ? 6 : 3)
        }
    }

    @ViewBuilder
    private static func renderParagraph(_ raw: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(NaviTheme.bodyFont(size: 16))
                .lineSpacing(5)
        } else {
            Text(raw)
                .font(NaviTheme.bodyFont(size: 16))
                .lineSpacing(5)
        }
    }

    enum MDBlock {
        case heading(Int, String)
        case paragraph(String)
        case bulletList([String])
        case numberedList([String])
        case code(String, String)
        case divider
    }

    // Keep legacy type alias for code blocks used in MarkdownCodeBlock
    enum Block { case text(String); case code(String, String) }

    static func parseBlocks(_ raw: String) -> [MDBlock] {
        var result: [MDBlock] = []
        let lines = raw.components(separatedBy: "\n")
        var inCode = false
        var codeLang = ""
        var codeBuf: [String] = []

        // Accumulates lines for the current paragraph / list
        var pendingLines: [String] = []

        func flushPending() {
            guard !pendingLines.isEmpty else { return }
            let trimmed = pendingLines.map { $0.trimmingCharacters(in: .whitespaces) }
            let nonEmpty = trimmed.filter { !$0.isEmpty }

            // Determine if pending block is a list
            let isBullet = nonEmpty.allSatisfy { $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.hasPrefix("• ") }
            let isNumbered = nonEmpty.allSatisfy {
                guard let first = $0.first, first.isNumber else { return false }
                return $0.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
            }

            if isBullet && !nonEmpty.isEmpty {
                let items = nonEmpty.map { line -> String in
                    if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
                    if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
                    if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
                    return line
                }
                result.append(.bulletList(items))
            } else if isNumbered && !nonEmpty.isEmpty {
                let items = nonEmpty.map { line -> String in
                    if let range = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        return String(line[range.upperBound...])
                    }
                    return line
                }
                result.append(.numberedList(items))
            } else {
                // Merge as paragraph — group by blank lines
                var paragraphs: [[String]] = []
                var cur: [String] = []
                for t in trimmed {
                    if t.isEmpty {
                        if !cur.isEmpty { paragraphs.append(cur); cur = [] }
                    } else {
                        cur.append(t)
                    }
                }
                if !cur.isEmpty { paragraphs.append(cur) }

                for para in paragraphs {
                    let joined = para.joined(separator: " ")
                    if !joined.isEmpty { result.append(.paragraph(joined)) }
                }
            }
            pendingLines = []
        }

        for line in lines {
            if line.hasPrefix("```") {
                if inCode {
                    result.append(.code(codeLang, codeBuf.joined(separator: "\n")))
                    codeBuf = []; inCode = false; codeLang = ""
                } else {
                    flushPending()
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
                continue
            }

            if inCode { codeBuf.append(line); continue }

            // Headings
            if line.hasPrefix("### ") { flushPending(); result.append(.heading(3, String(line.dropFirst(4)))); continue }
            if line.hasPrefix("## ")  { flushPending(); result.append(.heading(2, String(line.dropFirst(3)))); continue }
            if line.hasPrefix("# ")   { flushPending(); result.append(.heading(1, String(line.dropFirst(2)))); continue }

            // Horizontal rule
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped == "---" || stripped == "***" || stripped == "___" {
                flushPending(); result.append(.divider); continue
            }

            pendingLines.append(line)
        }

        if inCode && !codeBuf.isEmpty { result.append(.code(codeLang, codeBuf.joined(separator: "\n"))) }
        flushPending()
        return result
    }
}

// MARK: - Markdown Code Block

struct MarkdownCodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: language label + copy button
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .textCase(.uppercase)
                Spacer()
                Button { copyCode() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5))
                        Text(copied ? "Kopierad!" : "Kopiera")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundColor(copied ? NaviTheme.success : .secondary.opacity(0.45))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(copied ? NaviTheme.success.opacity(0.1) : Color.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: copied)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(NaviTheme.codeHeader)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundColor(NaviTheme.codeText)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
            }
        }
        .background(NaviTheme.codeBG)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(NaviTheme.codeBorder, lineWidth: 0.5)
        )
    }

    private func copyCode() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }
}

// MARK: - Typing Indicator (legacy, kept for compatibility)

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

// MARK: - ThinkingDots — clean three-dot animation shown while model is active

struct ThinkingDots: View {
    @State private var phase = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            // Navi orb avatar (matches chat bubbles)
            ThinkingOrb(size: 28, isAnimating: false)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase ? 1.0 : 0.55)
                        .opacity(phase ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.18),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.surfaceHover.opacity(0.7))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { phase = true }
        .onDisappear { phase = false }
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
        .padding(.bottom, 22)
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
            NaviVisualActivity.forStatus(activity.phase.displayText)
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(NaviTheme.success)
            Text("Klar")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(NaviTheme.success.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(NaviTheme.success.opacity(0.08))
        .cornerRadius(8)
        .scaleEffect(appeared ? 1.0 : 0.8)
        .opacity(appeared ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
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
