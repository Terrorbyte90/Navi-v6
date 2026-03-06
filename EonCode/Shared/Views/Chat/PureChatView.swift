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
                    .foregroundColor(.accentEon)
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
                    Text(model.displayName).font(.system(size: 12, weight: .medium)).foregroundColor(.accentEon)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 240)
        .background(Color.sidebarBackground)
        .preferredColorScheme(.dark)
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
    @StateObject private var memoryManager = MemoryManager.shared
    @StateObject private var costTracker = CostTracker.shared
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var isShowingImagePicker = false
    @State private var scrollProxy: ScrollViewProxy?

    var conversation: ChatConversation? { manager.activeConversation }

    var body: some View {
        VStack(spacing: 0) {
            macModelBar

            if let conv = conversation {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(conv.messages) { msg in
                                PureChatBubble(message: msg)
                                    .id(msg.id)
                            }
                            if manager.isStreaming {
                                StreamingBubble(text: ResponseCleaner.clean(manager.streamingText))
                                    .id("streaming")
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        chatInputBar
                            .background(Color.chatBackground)
                    }
                    .onAppear { scrollProxy = proxy }
                    .onChange(of: conv.messages.count) { scrollToBottom(proxy) }
                    .onChange(of: manager.streamingText) { scrollToBottom(proxy) }
                }
            } else {
                ZStack(alignment: .bottom) {
                    chatEmptyState
                    chatInputBar
                        .background(Color.chatBackground)
                }
            }
        }
        .background(Color.chatBackground)
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(selectedImages: $selectedImages)
        }
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
                    ForEach(ClaudeModel.allCases) { model in
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
                } label: {
                    HStack(spacing: 5) {
                        Text(conv.model.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("Chatt")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Spacer()

            HStack(spacing: 10) {
                if costTracker.lastRequestSEK > 0 {
                    Text(costTracker.formattedLast().components(separatedBy: " (").first ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                if costTracker.sessionSEK > 0 {
                    Text(costTracker.formattedSession().components(separatedBy: " (").first ?? "")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.3))
                }
            }

            Button { _ = manager.newConversation() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ny chatt")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    var chatEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentEon.opacity(0.1))
                        .frame(width: 64, height: 64)
                    Image(systemName: "sparkle")
                        .font(.system(size: 28))
                        .foregroundColor(.accentEon)
                }
                Text("EonCode")
                    .font(.system(size: 26, weight: .bold))
                Text("Hur kan jag hjälpa dig?")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(40)
    }

    // MARK: - Input bar (ChatGPT style pill)

    var chatInputBar: some View {
        VStack(spacing: 0) {
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, data in
                            ZStack(alignment: .topTrailing) {
                                #if os(iOS)
                                if let ui = UIImage(data: data) {
                                    Image(uiImage: ui).resizable().scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                #else
                                if let ns = NSImage(data: data) {
                                    Image(nsImage: ns).resizable().scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                #endif
                                Button { selectedImages.remove(at: idx) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 0) {
                Button { isShowingImagePicker = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                TextField("Meddelande", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...8)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 8)

                Button(action: sendMessage) {
                    if manager.isStreaming {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(inputText.isBlank && selectedImages.isEmpty ? .secondary.opacity(0.3) : .black)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(inputText.isBlank && selectedImages.isEmpty ? Color.clear : Color.white)
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(inputText.isBlank && selectedImages.isEmpty && !manager.isStreaming)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(Color.inputBorder, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if costTracker.lastRequestSEK > 0 || costTracker.sessionSEK > 0 {
                HStack(spacing: 10) {
                    if costTracker.lastRequestSEK > 0 {
                        Text(costTracker.formattedLast().components(separatedBy: " (").first ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    if costTracker.sessionSEK > 0 {
                        Text(costTracker.formattedSession().components(separatedBy: " (").first ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
        }
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

// MARK: - Chat bubble (ChatGPT style)

struct PureChatBubble: View {
    let message: PureChatMessage
    @State private var isSpeaking = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    if let imgs = message.imageData, !imgs.isEmpty {
                        imageRow(imgs)
                    }
                    Text(message.content)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.userBubble))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        } else {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentEon.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkle")
                        .font(.system(size: 13))
                        .foregroundColor(.accentEon)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("EonCode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    MarkdownTextView(text: message.content)
                        .textSelection(.enabled)

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
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
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
        .preferredColorScheme(.dark)
}

// MARK: - Markdown text renderer

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let t):
                    Text(.init(t))
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let lang, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            if !lang.isEmpty {
                                Text(lang)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.08, green: 0.08, blue: 0.08))

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
                            .strokeBorder(Color.dividerColor, lineWidth: 1)
                    )
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
