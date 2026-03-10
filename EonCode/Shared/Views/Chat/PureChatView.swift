import SwiftUI
#if os(iOS)
import PhotosUI
#endif

// MARK: - Cost Badge

struct CostBadge: View {
    let costSEK: Double
    let usage: TokenUsage?
    let model: ClaudeModel?
    @State private var showDetail = false

    private func formatSEK(_ v: Double) -> String {
        v < 0.001 ? "< 0.001 kr" : String(format: "%.3f kr", v)
    }

    var body: some View {
        Button { showDetail.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 10))
                Text(formatSEK(costSEK))
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundColor(.secondary.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(showDetail ? 0.04 : 0.0))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDetail) {
            CostDetailPopover(costSEK: costSEK, usage: usage, model: model)
        }
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

                            ForEach(conv.messages) { msg in
                                PureChatBubble(message: msg)
                                    .id(msg.id)
                            }
                            if manager.isStreaming {
                                StreamingBubble(text: manager.streamingText)
                                    .id("streaming")
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
        #if os(macOS)
        modelPickerBar
        Divider().opacity(0.08)
        #endif
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
        Button {
            manager.updateModel(model, for: convID)
        } label: {
            HStack {
                Text(model.displayName)
                if model == currentModel { Image(systemName: "checkmark") }
            }
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
                QuickActionChip(text: "Skriv kod", icon: "chevron.left.forwardslash.chevron.right") {}
                QuickActionChip(text: "Analysera filer", icon: "doc.text.magnifyingglass") {}
                QuickActionChip(text: "Felsök ett problem", icon: "ant") {}
                QuickActionChip(text: "Förklara något", icon: "lightbulb") {}
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Input bar

    var chatInputBar: some View {
        PureChatInputBar(
            inputText: $inputText,
            selectedImages: $selectedImages,
            isShowingFilePicker: $isShowingFilePicker,
            showVoiceMode: $showVoiceMode,
            isStreaming: manager.isStreaming,
            onSend: sendMessage
        )
    }

    // MARK: - Send

    private func sendMessage() {
        guard !inputText.isBlank || !selectedImages.isEmpty else { return }
        if manager.activeConversation == nil {
            _ = manager.newConversation()
        }
        guard let convID = manager.activeConversation?.id else { return }

        let text = inputText
        let images = selectedImages
        inputText = ""
        selectedImages = []
        dismissKeyboard()

        Task {
            guard var conv = manager.conversations.first(where: { $0.id == convID })
                    ?? manager.activeConversation
            else { return }

            try? await manager.send(text: text, images: images, in: &conv) { _ in }
            await MainActor.run {
                manager.activeConversation = conv
                if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
                    manager.conversations[idx] = conv
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = false) {
        let action = { proxy.scrollTo("bottomAnchor", anchor: .bottom) }
        if animated { withAnimation(.easeOut(duration: 0.15)) { action() } }
        else { action() }
    }
}

// MARK: - Chat bubble — Claude iOS style (no sparkle avatar)

struct PureChatBubble: View {
    let message: PureChatMessage
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
                        .font(.system(size: 15.5))
                        .foregroundColor(.primary)
                        .lineSpacing(4)
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

// MARK: - Streaming Bubble — glass orb breathing animation

struct StreamingBubble: View {
    let text: String
    var statusMessage: String = ""
    var activeFiles: [String] = []
    var codeSnippet: String = ""
    var todoItems: [ProjectAgent.AgentTodoItem] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 24, isAnimating: true)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if text.isEmpty {
                    TypingIndicator()
                } else {
                    MarkdownTextView(text: text)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

    static func == (lhs: MarkdownTextView, rhs: MarkdownTextView) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let t):
                    Self.renderMarkdownText(t)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let lang, let code):
                    MarkdownCodeBlock(language: lang, code: code)
                }
            }
        }
    }

    @ViewBuilder
    private static func renderMarkdownText(_ raw: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: 15.5))
                .lineSpacing(5)
        } else {
            Text(raw)
                .font(.system(size: 15.5))
                .lineSpacing(5)
        }
    }

    enum Block { case text(String); case code(String, String) }

    func parseBlocks(_ raw: String) -> [Block] {
        var blocks: [Block] = []
        let lines = raw.components(separatedBy: "\n")
        var inCode = false
        var lang = ""
        var codeBuf: [String] = []
        var textBuf: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(lang, codeBuf.joined(separator: "\n")))
                    codeBuf = []; inCode = false; lang = ""
                } else {
                    if !textBuf.isEmpty {
                        blocks.append(.text(textBuf.joined(separator: "\n")))
                        textBuf = []
                    }
                    lang = String(line.dropFirst(3))
                    inCode = true
                }
            } else if inCode {
                codeBuf.append(line)
            } else {
                textBuf.append(line)
            }
        }
        if !codeBuf.isEmpty { blocks.append(.code(lang, codeBuf.joined(separator: "\n"))) }
        if !textBuf.isEmpty { blocks.append(.text(textBuf.joined(separator: "\n"))) }
        return blocks
    }
}

// MARK: - Markdown Code Block

struct MarkdownCodeBlock: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
                Button { copyCode() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Kopierad!" : "Kopiera")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(copied ? NaviTheme.success : .secondary.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(copied ? NaviTheme.success.opacity(0.1) : Color.white.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: copied)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(NaviTheme.codeHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(14)
                    .textSelection(.enabled)
            }
        }
        .background(NaviTheme.codeBG)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
                #if os(iOS)
                PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 5, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 32, height: 32)
                        Image(systemName: selectedImages.isEmpty ? "photo" : "photo.badge.checkmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
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

                // Attachment menu
                Menu {
                    #if os(macOS)
                    Button { } label: { Label("Image", systemImage: "photo") }
                    #endif
                    Button { isShowingFilePicker = true } label: {
                        Label("File", systemImage: "doc")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 32, height: 32)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary.opacity(0.4))
                    }
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
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
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

// MARK: - Image Thumbnail

private struct InputImageThumb: View {
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
    var body: some View {
        AgentActivityView(activity: NaviOrchestrator.shared.activity, compact: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }
}
