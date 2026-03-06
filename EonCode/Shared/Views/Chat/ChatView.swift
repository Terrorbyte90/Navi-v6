import SwiftUI

struct ChatView: View {
    @ObservedObject var agent: ProjectAgent
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var isAgentMode = false
    @State private var showImagePicker = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showQueuePanel = false
    @State private var iterationCount = 1
    @State private var showIterationPicker = false

    @ObservedObject private var queue: PromptQueue

    init(agent: ProjectAgent) {
        self.agent = agent
        self._queue = ObservedObject(wrappedValue: PromptQueue.queue(for: agent.project.id))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(agent.conversation.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if agent.isRunning && !agent.streamingText.isEmpty {
                            StreamingBubble(text: agent.streamingText)
                                .id("streaming")
                        } else if agent.isRunning {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        // Queue status bar (shown when queue has items)
                        if queue.hasActive {
                            QueueStatusBar(queue: queue)
                        }

                        InputBar(
                            text: $inputText,
                            selectedImages: $selectedImages,
                            isAgentMode: $isAgentMode,
                            iterationCount: $iterationCount,
                            isLoading: agent.isRunning,
                            queueCount: queue.waitingCount,
                            costText: agent.lastCostSEK > 0 ? CostCalculator.shared.formatSEK(agent.lastCostSEK) : nil,
                            model: agent.conversation.model,
                            onShowQueue: { showQueuePanel.toggle() }
                        ) {
                            sendMessage()
                        }
                        .background(Color.chatBackground)
                    }
                }
                .onChange(of: agent.conversation.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: agent.streamingText) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy)
                }
            }
            .background(Color.chatBackground)

            // Queue panel overlay
            if showQueuePanel {
                QueuePanel(queue: queue, onClose: { showQueuePanel = false })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showQueuePanel)
    }

    private func sendMessage() {
        let text = inputText.trimmed
        guard !text.isBlank || !selectedImages.isEmpty else { return }
        let images = selectedImages

        inputText = ""
        selectedImages = []

        if iterationCount > 1 || agent.isRunning {
            // Queue it (with iterations)
            queue.enqueue(text: text, isAgentMode: isAgentMode, iterations: iterationCount)
            iterationCount = 1
        } else {
            agent.sendMessage(text, images: images, isAgentMode: isAgentMode)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if agent.isRunning {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let last = agent.conversation.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Queue Status Bar

struct QueueStatusBar: View {
    @ObservedObject var queue: PromptQueue

    var body: some View {
        HStack(spacing: 8) {
            if queue.isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
                Text("Kör prompt…")
                    .font(.system(size: 11))
                    .foregroundColor(.accentEon)
            } else {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Väntar…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            let waiting = queue.waitingCount
            if waiting > 0 {
                Text("\(waiting) i kö")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Button {
                queue.clearWaiting()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Rensa kö")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04))
        .overlay(Divider().opacity(0.15), alignment: .top)
    }
}

// MARK: - Queue Panel

struct QueuePanel: View {
    @ObservedObject var queue: PromptQueue
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Prompt-kö")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    queue.clearFinished()
                } label: {
                    Text("Rensa klara")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.2)

            if queue.items.isEmpty {
                Text("Kön är tom")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(queue.items) { item in
                            QueueItemRow(item: item) {
                                queue.cancel(id: item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.chatBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 16, x: -4, y: 4)
        )
        .padding(.top, 8)
        .padding(.trailing, 8)
    }
}

// MARK: - Queue Item Row

struct QueueItemRow: View {
    let item: QueuedPrompt
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Status icon
            statusIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text.prefix(80))
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if item.iterationsTotal > 1 {
                        Text("\(item.iterationsDone)/\(item.iterationsTotal) iter.")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.accentEon.opacity(0.8))
                    }
                    Text(item.isAgentMode ? "Agent" : "Chat")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Progress for multi-iteration
            if item.iterationsTotal > 1 && item.status == .running {
                CircularProgress(value: item.progress)
                    .frame(width: 18, height: 18)
            }

            // Cancel button for waiting items
            if item.status == .waiting {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(rowBackground)
        )
    }

    @ViewBuilder
    var statusIcon: some View {
        switch item.status {
        case .waiting:
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .running:
            ProgressView()
                .scaleEffect(0.55)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.red)
        case .cancelled:
            Image(systemName: "minus.circle")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.4))
        }
    }

    var rowBackground: Color {
        switch item.status {
        case .running: return Color.accentEon.opacity(0.06)
        case .completed: return Color.green.opacity(0.04)
        case .failed: return Color.red.opacity(0.04)
        default: return Color.white.opacity(0.03)
        }
    }
}

// MARK: - Circular Progress

struct CircularProgress: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 2)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.accentEon, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Role label
                if message.role == .assistant {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 10))
                            .foregroundColor(.accentEon)
                        Text(message.model?.displayName ?? "EonCode")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Content
                contentView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user ? Color.userBubble : Color.assistantBubble)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )

                // Cost badge with token detail
                if message.costSEK > 0 && message.role == .assistant {
                    let usage = message.inputTokens > 0
                        ? TokenUsage(inputTokens: message.inputTokens, outputTokens: message.outputTokens, cacheCreationInputTokens: nil, cacheReadInputTokens: nil)
                        : nil
                    CostBadge(costSEK: message.costSEK, usage: usage, model: message.model)
                }
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    var contentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(message.content.enumerated()), id: \.offset) { _, content in
                switch content {
                case .text(let t):
                    if containsCode(t) {
                        renderTextWithCodeBlocks(t)
                    } else {
                        Text(t)
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                case .image(let data, _):
                    if let uiImage = PlatformImage(data: data) {
                        Image(platformImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 250)
                            .cornerRadius(8)
                    }
                case .toolUse(_, let name, _):
                    Label("Verktyg: \(name)", systemImage: "wrench.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                case .toolResult(_, let result, let isError):
                    Text(result.prefix(300))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(isError ? .red : .secondary)
                        .lineLimit(8)
                }
            }
        }
    }

    private func containsCode(_ text: String) -> Bool {
        text.contains("```")
    }

    @ViewBuilder
    private func renderTextWithCodeBlocks(_ text: String) -> some View {
        let parts = parseCodeBlocks(text)
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
            if part.isCode {
                CodeBlockView(code: part.content, language: part.language)
            } else if !part.content.trimmed.isEmpty {
                Text(part.content)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
        }
    }

    private func parseCodeBlocks(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        let lines = text.components(separatedBy: "\n")
        var currentText = ""
        var currentCode = ""
        var currentLang = ""
        var inCode = false

        for line in lines {
            if line.hasPrefix("```") && !inCode {
                if !currentText.isEmpty {
                    parts.append(TextPart(content: currentText, isCode: false, language: nil))
                    currentText = ""
                }
                currentLang = String(line.dropFirst(3)).trimmed
                inCode = true
            } else if line.hasPrefix("```") && inCode {
                parts.append(TextPart(content: currentCode, isCode: true, language: currentLang.isEmpty ? nil : currentLang))
                currentCode = ""
                currentLang = ""
                inCode = false
            } else if inCode {
                currentCode += line + "\n"
            } else {
                currentText += line + "\n"
            }
        }

        if !currentText.isEmpty { parts.append(TextPart(content: currentText, isCode: false, language: nil)) }
        if !currentCode.isEmpty { parts.append(TextPart(content: currentCode, isCode: true, language: nil)) }

        return parts
    }

    struct TextPart {
        let content: String
        let isCode: Bool
        let language: String?
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(language ?? "code")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    copyCode()
                } label: {
                    Label(copied ? "Kopierad!" : "Kopiera", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))

            Divider().opacity(0.3)

            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                LargeTextView(text: code.trimmed, fontSize: 12, fontDesign: .monospaced)
                    .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.codeBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
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

// MARK: - Streaming bubble

struct StreamingBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .top) {
            if text.isEmpty {
                // Three dots while waiting for first token
                TypingIndicator()
            } else {
                // Stream text directly — no "Genererar" label
                Text(text.suffix(3000))
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.assistantBubble)
                    )
            }
            Spacer(minLength: 40)
        }
    }
}

// MARK: - Typing indicator (iMessage-style three dots)

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                        value: animating
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.assistantBubble))
        .onAppear { animating = true }
    }
}

// MARK: - Input bar

struct InputBar: View {
    @Binding var text: String
    @Binding var selectedImages: [Data]
    @Binding var isAgentMode: Bool
    @Binding var iterationCount: Int
    let isLoading: Bool
    let queueCount: Int
    let costText: String?
    let model: ClaudeModel
    let onShowQueue: () -> Void
    let onSend: () -> Void

    @State private var showImagePicker = false
    @State private var showIterPicker = false

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.2)

            // Images preview
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { i, data in
                            ZStack(alignment: .topTrailing) {
                                if let img = PlatformImage(data: data) {
                                    Image(platformImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Button {
                                    selectedImages.remove(at: i)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Agent mode toggle
                Button {
                    isAgentMode.toggle()
                } label: {
                    Image(systemName: isAgentMode ? "cpu.fill" : "cpu")
                        .font(.system(size: 17))
                        .foregroundColor(isAgentMode ? .accentEon : .secondary)
                }
                .buttonStyle(.plain)
                .help("Agent-läge: " + (isAgentMode ? "PÅ" : "AV"))

                // Image attach
                Button {
                    showImagePicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                // Text input
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(isAgentMode ? "Ge agenten en uppgift…" : "Skriv ett meddelande…")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                    }

                    #if os(iOS)
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .frame(minHeight: 36, maxHeight: 120)
                        .background(Color.clear)
                        .scrollContentBackground(.hidden)
                    #else
                    TextEditor(text: $text)
                        .font(.system(size: 14))
                        .frame(minHeight: 36, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                    #endif
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )

                // Iteration picker (agent mode only)
                if isAgentMode {
                    Menu {
                        ForEach([1, 2, 3, 5, 10, 20, 50, 100], id: \.self) { n in
                            Button("\(n)×") { iterationCount = n }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(iterationCount)×")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(iterationCount > 1 ? .accentEon : .secondary.opacity(0.6))
                        }
                        .frame(minWidth: 28)
                    }
                    .help("Antal iterationer")
                }

                // Send button
                Button(action: onSend) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(text.isBlank && selectedImages.isEmpty ? .secondary.opacity(0.3) : .accentEon)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoading || (text.isBlank && selectedImages.isEmpty))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Status bar
            HStack {
                Text(model.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))

                if isAgentMode {
                    Text("· Agent")
                        .font(.system(size: 11))
                        .foregroundColor(.accentEon.opacity(0.7))
                }

                Spacer()

                // Queue button
                Button(action: onShowQueue) {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 9))
                        if queueCount > 0 {
                            Text("\(queueCount)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.accentEon)
                        } else {
                            Text("Kö")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                // Last request cost + session total
                HStack(spacing: 6) {
                    if let cost = costText {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 9))
                            Text(cost)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.secondary.opacity(0.55))
                    }
                    let sessionCost = CostTracker.shared.sessionSEK
                    if sessionCost > 0.001 {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(String(format: "%.2f kr", sessionCost))
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundColor(.secondary.opacity(0.38))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Color.chatBackground)
    }
}

// MARK: - Previews

#Preview("ChatView") {
    let project = EonProject(name: "EonCode Preview", rootPath: "/tmp/preview")
    let agent = ProjectAgent(project: project)
    return ChatView(agent: agent)
        .frame(width: 400, height: 600)
        .preferredColorScheme(.dark)
}

#Preview("MessageBubble – user") {
    let msg = ChatMessage(role: .user, content: [.text("Hej! Kan du hjälpa mig med en Swift-funktion?")])
    return MessageBubble(message: msg)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("MessageBubble – assistant") {
    let code = "```swift\nfunc hello() {\n    print(\"Hello, world!\")\n}\n```"
    let msg = ChatMessage(role: .assistant, content: [.text("Självklart! Här är ett exempel:\n\(code)")], model: .haiku)
    return MessageBubble(message: msg)
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("CodeBlockView") {
    CodeBlockView(
        code: "func greet(_ name: String) -> String {\n    return \"Hej, \\(name)!\"\n}",
        language: "swift"
    )
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("StreamingBubble") {
    StreamingBubble(text: "Jag analyserar din kod och identifierar eventuella problem…")
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("TypingIndicator") {
    TypingIndicator()
        .padding()
        .background(Color.black)
        .preferredColorScheme(.dark)
}

#Preview("InputBar") {
    InputBar(
        text: .constant(""),
        selectedImages: .constant([]),
        isAgentMode: .constant(false),
        iterationCount: .constant(1),
        isLoading: false,
        queueCount: 0,
        costText: "0,12 kr",
        model: .haiku,
        onShowQueue: {}
    ) {}
    .background(Color.black)
    .preferredColorScheme(.dark)
}

// MARK: - Platform image helpers

extension Image {
    #if os(macOS)
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
    #else
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
    #endif
}
