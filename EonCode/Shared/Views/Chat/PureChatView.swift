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
                    .font(.system(size: 9))
                Text(formatSEK(costSEK))
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundColor(.secondary.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(showDetail ? 0.08 : 0.0))
            .cornerRadius(5)
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
                    .foregroundColor(.accentEon)
                Text("Kostnad för detta svar")
                    .font(.system(size: 13, weight: .semibold))
            }

            Divider().opacity(0.2)

            // Main cost
            HStack {
                Text("Kostnad")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formatSEK(costSEK))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(formatUSD(usd))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if let usage {
                Divider().opacity(0.15)

                // Token breakdown
                Group {
                    tokenRow("Indata-tokens", value: usage.inputTokens, color: .blue)
                    if let cache = usage.cacheReadInputTokens, cache > 0 {
                        tokenRow("Varav cache-läsning", value: cache, color: .green, note: "−90%")
                    }
                    if let cacheWrite = usage.cacheCreationInputTokens, cacheWrite > 0 {
                        tokenRow("Cache-skrivning", value: cacheWrite, color: .orange)
                    }
                    tokenRow("Utdata-tokens", value: usage.outputTokens, color: .purple)
                    tokenRow("Totalt", value: usage.inputTokens + usage.outputTokens, color: .primary)
                }
            }

            if let model {
                Divider().opacity(0.15)
                HStack {
                    Text("Modell")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(model.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentEon)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 220)
        .background(Color.chatBackground)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func tokenRow(_ label: String, value: Int, color: Color, note: String? = nil) -> some View {
        HStack {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let note {
                Text(note)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(3)
            }
            Spacer()
            Text("\(value)")
                .font(.system(size: 11, design: .monospaced))
        }
    }
}

// MARK: - Pure Chat View (ChatGPT/Claude.ai-style, no project context)

struct PureChatView: View {
    @StateObject private var manager = ChatManager.shared
    @StateObject private var memoryManager = MemoryManager.shared
    @StateObject private var costTracker = CostTracker.shared
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var isShowingImagePicker = false
    @State private var scrollProxy: ScrollViewProxy?

    var conversation: ChatConversation? { manager.activeConversation }

    var body: some View {
        VStack(spacing: 0) {
            // Model picker bar — macOS only; iOS uses the top nav bar in ContentView
            macModelBar

            if let conv = conversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(conv.messages) { msg in
                                PureChatBubble(message: msg)
                                    .id(msg.id)
                            }
                            if manager.isStreaming {
                                StreamingBubble(text: manager.streamingText)
                                    .id("streaming")
                            }
                        }
                        .padding()
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            Divider().opacity(0.15)
                            chatInputBar
                        }
                        .background(Color.chatBackground)
                    }
                    .onAppear { scrollProxy = proxy }
                    .onChange(of: conv.messages.count) { _ in scrollToBottom(proxy) }
                    .onChange(of: manager.streamingText) { _ in scrollToBottom(proxy) }
                }
            } else {
                ZStack(alignment: .bottom) {
                    chatEmptyState
                    VStack(spacing: 0) {
                        Divider().opacity(0.15)
                        chatInputBar
                    }
                    .background(Color.chatBackground)
                }
            }
        }
        .background(Color.chatBackground)
        .onAppear {
            if manager.activeConversation == nil && !manager.conversations.isEmpty {
                manager.activeConversation = manager.conversations.first
            }
        }
    }

    // MARK: - macOS-only model bar

    @ViewBuilder
    var macModelBar: some View {
        #if os(macOS)
        modelPickerBar
        Divider().opacity(0.15)
        #endif
    }

    // MARK: - Model picker bar (macOS)

    var modelPickerBar: some View {
        HStack(spacing: 12) {
            // Model picker
            if let conv = conversation {
                Menu {
                    ForEach(ClaudeModel.allCases) { model in
                        Button {
                            if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
                                manager.conversations[idx].model = model
                                manager.activeConversation?.model = model
                            }
                        } label: {
                            HStack {
                                Text(model.displayName)
                                if model == conv.model {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(conv.model.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Chatt")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Live cost display
            HStack(spacing: 10) {
                if costTracker.lastRequestSEK > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 9))
                        Text(costTracker.formattedLast().components(separatedBy: " (").first ?? "")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundColor(.secondary.opacity(0.55))
                }
                if costTracker.sessionSEK > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(costTracker.formattedSession().components(separatedBy: " (").first ?? "")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .foregroundColor(.secondary.opacity(0.4))
                }
            }

            // New chat button
            Button {
                _ = manager.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ny chatt")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty state

    var chatEmptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.accentEon.opacity(0.4))
            Text("Ny chatt")
                .font(.system(size: 22, weight: .bold))
            Text("Prata direkt med Claude — utan projektkontext.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            GlassButton("Starta ny chatt", icon: "plus", isPrimary: true) {
                _ = manager.newConversation()
            }
            Spacer()
        }
        .padding(40)
    }

    // MARK: - Input bar

    var chatInputBar: some View {
        VStack(spacing: 0) {
            // Image previews
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, data in
                            ZStack(alignment: .topTrailing) {
                                #if os(iOS)
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui)
                                        .resizable().scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                #else
                                if let ns = NSImage(data: data) {
                                    Image(nsImage: ns)
                                        .resizable().scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                #endif
                                Button { selectedImages.remove(at: idx) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.4)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Image attach
                Button { isShowingImagePicker = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Text input — TextField with axis: .vertical grows naturally, starts at 1 line
                TextField("Meddelande", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )

                // Send / stop
                Button(action: sendMessage) {
                    if manager.isStreaming {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.accentEon)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(inputText.isBlank && selectedImages.isEmpty ? .secondary.opacity(0.3) : .accentEon)
                    }
                }
                .buttonStyle(.plain)
                .disabled(inputText.isBlank && selectedImages.isEmpty && !manager.isStreaming)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Cost row
            if costTracker.lastRequestSEK > 0 || costTracker.sessionSEK > 0 {
                HStack(spacing: 10) {
                    if costTracker.lastRequestSEK > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle").font(.system(size: 9))
                            Text(costTracker.formattedLast().components(separatedBy: " (").first ?? "")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.secondary.opacity(0.5))
                    }
                    if costTracker.sessionSEK > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "clock").font(.system(size: 9))
                            Text(costTracker.formattedSession().components(separatedBy: " (").first ?? "")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.secondary.opacity(0.35))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Send

    private func sendMessage() {
        guard !inputText.isBlank || !selectedImages.isEmpty else { return }
        // Create a new conversation if none is active
        if manager.activeConversation == nil {
            _ = manager.newConversation()
        }
        guard let convID = manager.activeConversation?.id else { return }

        let text = inputText
        let images = selectedImages
        inputText = ""
        selectedImages = []

        Task {
            // Work on the conversation by ID to avoid stale-copy issues
            guard var conv = manager.conversations.first(where: { $0.id == convID })
                    ?? manager.activeConversation
            else { return }

            try? await manager.send(text: text, images: images, in: &conv) { _ in }
            // Sync back
            await MainActor.run {
                manager.activeConversation = conv
                if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
                    manager.conversations[idx] = conv
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = manager.activeConversation?.messages.last else {
            if manager.isStreaming { proxy.scrollTo("streaming", anchor: .bottom) }
            return
        }
        if manager.isStreaming {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

// MARK: - Chat bubble

struct PureChatBubble: View {
    let message: PureChatMessage
    @State private var isSpeaking = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Images
                if let imgs = message.imageData, !imgs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Array(imgs.enumerated()), id: \.offset) { _, data in
                                #if os(iOS)
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui).resizable().scaledToFit()
                                        .frame(maxHeight: 200).cornerRadius(10)
                                }
                                #else
                                if let ns = NSImage(data: data) {
                                    Image(nsImage: ns).resizable().scaledToFit()
                                        .frame(maxHeight: 200).cornerRadius(10)
                                }
                                #endif
                            }
                        }
                    }
                }

                // Text / Markdown
                if isUser {
                    Text(message.content)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentEon.opacity(0.2))
                        .cornerRadius(18)
                        .textSelection(.enabled)
                } else {
                    MarkdownTextView(text: message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(18)
                        .textSelection(.enabled)
                }

                // Cost + tokens + TTS
                if !isUser {
                    HStack(spacing: 8) {
                        if let cost = message.costSEK, cost > 0 {
                            CostBadge(costSEK: cost, usage: message.tokenUsage, model: message.model)
                        }
                        Spacer(minLength: 0)
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
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Previews

#Preview("PureChatView") {
    PureChatView()
        .frame(width: 400, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("PureChatBubble – user") {
    let msg = PureChatMessage(role: .user, content: "Vad är SwiftUI?")
    return PureChatBubble(message: msg)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("PureChatBubble – assistant") {
    let msg = PureChatMessage(role: .assistant, content: "SwiftUI är Apples deklarativa UI-ramverk för att bygga appar på alla Apple-plattformar med Swift-kod.")
    return PureChatBubble(message: msg)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("MarkdownTextView") {
    MarkdownTextView(text: "**Hej!** Här är ett kodexempel:\n\n```swift\nlet x = 42\nprint(x)\n```\n\nOch lite *kursiv* text.")
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

// MARK: - Simple Markdown text renderer (reuses existing MarkdownPreview patterns)

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        // Reuse the app's code block detection
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let t):
                    Text(.init(t)) // AttributedString markdown
                        .font(.system(size: 14))
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let lang, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        if !lang.isEmpty {
                            Text(lang)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 6)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(code)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(12)
                                .textSelection(.enabled)
                        }
                    }
                    .background(Color.codeBackground)
                    .cornerRadius(10)
                }
            }
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
