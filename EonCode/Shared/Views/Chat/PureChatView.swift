import SwiftUI

// MARK: - Cost Badge (reusable across chat views)

struct CostBadge: View {
    let costSEK: Double
    let usage: TokenUsage?
    let model: ClaudeModel?

    @State private var showDetail = false

    private func formatSEK(_ v: Double) -> String {
        v < 0.001 ? "< 0.001 kr" : String(format: "%.3f kr", v)
    }

    var body: some View {
        Button {
            showDetail.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 10))
                Text(formatSEK(costSEK))
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundColor(.secondary.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(showDetail ? 0.06 : 0.0))
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
                Text("Kostnad")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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

// MARK: - Pure Chat View (ChatGPT style)

struct PureChatView: View {
    @StateObject private var manager = ChatManager.shared
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var isShowingImagePicker = false
    @State private var isShowingFilePicker = false
    @State private var showVoiceMode = false
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var inputFocused: Bool

    @StateObject private var projectStore = ProjectStore.shared

    var conversation: ChatConversation? { manager.activeConversation }

    var body: some View {
        VStack(spacing: 0) {
            macModelBar

            if let conv = conversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Context banner — shows active project/repo awareness
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

                            // Bottom anchor for reliable scrolling
                            Color.clear
                                .frame(height: 1)
                                .id("bottomAnchor")
                        }
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                        .onTapGesture { inputFocused = false }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        chatInputBar
                            .background(Color.chatBackground)
                    }
                    .onAppear { scrollProxy = proxy; scrollToBottom(proxy, animated: false) }
                    .onChange(of: conv.messages.count) { scrollToBottom(proxy, animated: true) }
                    .onChange(of: manager.streamingText.count / 80) { _ in
                        scrollToBottom(proxy, animated: false)
                    }
                }
            } else {
                ZStack(alignment: .bottom) {
                    chatEmptyState
                        .contentShape(Rectangle())
                        .onTapGesture { inputFocused = false }
                    chatInputBar
                        .background(Color.chatBackground)
                }
            }
        }
        .background(Color.chatBackground)
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
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

    // macOS top bar — Mockup11 / ChatGPT-style
    var modelPickerBar: some View {
        HStack(spacing: 8) {
            // "Navi  ModelName ⌄"
            if let conv = conversation {
                Menu {
                    Section("Anthropic") {
                        ForEach(ClaudeModel.anthropicModels) { model in
                            Button {
                                if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
                                    manager.conversations[idx].model = model
                                    manager.activeConversation?.model = model
                                }
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                    if model == conv.model { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("xAI / Grok") {
                        ForEach(ClaudeModel.xaiModels) { model in
                            Button {
                                if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
                                    manager.conversations[idx].model = model
                                    manager.activeConversation?.model = model
                                }
                            } label: {
                                HStack {
                                    Text(model.displayName)
                                    if model == conv.model { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("Navi")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color.primary)
                        Text(conv.model.displayName)
                            .font(.system(size: 14))
                            .foregroundColor(Color.secondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.secondary.opacity(0.6))
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 5) {
                    Text("Navi")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.primary)
                    Text("Chatt")
                        .font(.system(size: 14))
                        .foregroundColor(Color.secondary)
                }
            }

            Spacer()

            // Cost + new chat
            SessionCostLabel()

            Button { _ = manager.newConversation() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundColor(Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ny chatt")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    var chatEmptyState: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 14) {
                // ChatGPT-green sparkle avatar — larger for empty state
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red:0.455,green:0.667,blue:0.612), Color(red:0.3,green:0.55,blue:0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
                VStack(spacing: 5) {
                    Text("Hur kan jag hjälpa dig?")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color.primary)
                }
            }
            Spacer()
        }
        .padding(40)
    }

    // MARK: - Input bar (Mockup11 / ChatGPT-faithful pill)

    var chatInputBar: some View {
        VStack(spacing: 6) {
            // Agent activity is isolated to avoid triggering input bar redraws
            AgentActivityOverlay()

            // Image previews
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, data in
                            ZStack(alignment: .topTrailing) {
                                #if os(iOS)
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui).resizable().scaledToFill()
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                #else
                                if let ns = NSImage(data: data) {
                                    Image(nsImage: ns).resizable().scaledToFill()
                                        .frame(width: 52, height: 52)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                #endif
                                Button { selectedImages.remove(at: idx) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                }
            }

            // Pill — exact ChatGPT shape
            HStack(alignment: .center, spacing: 8) {
                Menu {
                    Button { isShowingImagePicker = true } label: {
                        Label("Bild", systemImage: "photo")
                    }
                    Button { isShowingFilePicker = true } label: {
                        Label("Fil", systemImage: "doc")
                    }
                    #if os(iOS)
                    Button { isShowingImagePicker = true } label: {
                        Label("Kamera", systemImage: "camera")
                    }
                    #endif
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.surfaceHover)
                            .frame(width: 30, height: 30)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.secondary)
                    }
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif

                TextField("Skicka ett meddelande till Navi", text: $inputText, axis: .vertical)
                    .focused($inputFocused)
                    .font(.callout)
                    .foregroundColor(Color.primary)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10)
                    .padding(.leading, 4)

                if manager.isStreaming {
                    Button(action: sendMessage) {
                        ZStack {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 30, height: 30)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.chatBackground)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .buttonStyle(.plain)
                } else if inputText.isBlank && selectedImages.isEmpty {
                    Button { showVoiceMode = true } label: {
                        ZStack {
                            Circle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "waveform")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.secondary.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: sendMessage) {
                        ZStack {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: 30, height: 30)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.chatBackground)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.userBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                    )
            )

            // Disclaimer + session cost
            HStack {
                Text("Navi kan göra misstag. Kontrollera viktig information.")
                    .font(.caption2)
                    .foregroundColor(Color.secondary.opacity(0.6))
                Spacer()
                SessionCostLabel(fontSize: 10, opacity: 0.36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        let action = {
            // Always scroll to the bottom anchor — avoids blank-space issues
            proxy.scrollTo("bottomAnchor", anchor: .bottom)
        }
        if animated { withAnimation(.easeOut(duration: 0.15)) { action() } }
        else { action() }
    }
}

// MARK: - Chat bubble (Mockup11 / ChatGPT-faithful)

struct PureChatBubble: View {
    let message: PureChatMessage
    @State private var isSpeaking = false

    var isUser: Bool { message.role == .user }

    private let userBubbleColor = Color.userBubble
    private let textPrimary = Color.primary
    private let textMuted = Color.secondary

    var body: some View {
        if isUser {
            // Right-aligned pill — no avatar
            HStack(alignment: .top) {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 6) {
                    if let imgs = message.imageData, !imgs.isEmpty {
                        imageRow(imgs)
                    }
                    Text(message.content)
                        .font(.system(size: 15.5))
                        .foregroundColor(textPrimary)
                        .lineSpacing(4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 18).fill(userBubbleColor))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        } else {
            // Left-aligned: sparkle avatar + text, no bubble
            HStack(alignment: .top, spacing: 12) {
                AssistantAvatar()
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    MarkdownTextView(text: ResponseCleaner.clean(message.content))
                        .equatable()
                        .textSelection(.enabled)

                    // Action row (ChatGPT-style)
                    HStack(spacing: 14) {
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = message.content
                            #else
                            NSPasteboard.general.setString(message.content, forType: .string)
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
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
                            Image(systemName: isSpeaking ? "stop.circle" : "speaker.wave.2")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)

                        if let cost = message.costSEK, cost > 0 {
                            CostBadge(costSEK: cost, usage: message.tokenUsage, model: message.model)
                        }
                    }
                    .foregroundColor(textMuted)
                    .padding(.top, 2)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

// MARK: - Previews

#Preview("PureChatView") {
    PureChatView()
        .frame(width: 500, height: 600)
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

    /// Renders markdown text with proper **bold**, *italic*, `code`, and ~~strikethrough~~ support.
    @ViewBuilder
    private static func renderMarkdownText(_ raw: String) -> some View {
        // Use AttributedString for rich markdown rendering (bold, italic, inline code, etc.)
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: 15.5))
                .lineSpacing(5)
        } else {
            // Fallback for malformed markdown
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

// MARK: - Markdown Code Block (with copy button)

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
                    .foregroundColor(copied ? .green : .secondary.opacity(0.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(copied ? Color.green.opacity(0.1) : Color.white.opacity(0.04))
                    )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: copied)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(red: 0.07, green: 0.07, blue: 0.07))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(14)
                    .textSelection(.enabled)
            }
        }
        .background(Color.codeBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
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

// MARK: - Isolated Session Cost Label (prevents parent redraw cascades)

/// Lightweight view that self-manages CostTracker observation.
/// Using this instead of observing CostTracker in parent views
/// prevents the entire chat UI from re-rendering on every cost update.
struct SessionCostLabel: View {
    var fontSize: CGFloat = 11
    var opacity: Double = 0.6

    @StateObject private var tracker = CostTracker.shared

    var body: some View {
        if tracker.sessionSEK > 0 {
            Text(tracker.formattedSession().components(separatedBy: " (").first ?? "")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundColor(Color.secondary.opacity(opacity))
        }
    }
}

// MARK: - Isolated Agent Activity Overlay (prevents input bar redraws)

/// Wraps AgentActivityView in its own struct so that orchestrator
/// activity updates only rebuild this small view — not the entire input bar.
struct AgentActivityOverlay: View {
    var body: some View {
        AgentActivityView(activity: NaviOrchestrator.shared.activity, compact: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
    }
}
