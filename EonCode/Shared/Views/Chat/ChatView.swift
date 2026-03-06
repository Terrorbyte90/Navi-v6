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
                    LazyVStack(spacing: 0) {
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
                    .padding(.vertical, 16)
                }
                .dismissKeyboardOnTap()
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
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
                    }
                }
                .onChange(of: agent.conversation.messages.count) { _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: agent.streamingText) { _ in
                    // No animation during streaming — avoids layout thrash
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .background(Color.chatBackground)

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
            queue.enqueue(text: text, isAgentMode: isAgentMode, iterations: iterationCount)
            iterationCount = 1
        } else {
            agent.sendMessage(text, images: images, isAgentMode: isAgentMode)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { _scroll(proxy) }
        } else {
            _scroll(proxy)
        }
    }

    private func _scroll(_ proxy: ScrollViewProxy) {
        if agent.isRunning {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let last = agent.conversation.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
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
                Text("Kör prompt...")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.7))
            } else {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Väntar...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            let waiting = queue.waitingCount
            if waiting > 0 {
                Text("\(waiting) i kö")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
            }

            Button {
                queue.clearWaiting()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Rensa kö")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surfaceHover)
    }
}

// MARK: - Queue Panel

struct QueuePanel: View {
    @ObservedObject var queue: PromptQueue
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Prompt-kö")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    queue.clearFinished()
                } label: {
                    Text("Rensa klara")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(0.12)

            if queue.items.isEmpty {
                Text("Kön är tom")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
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
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.sidebarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.dividerColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: -4, y: 4)
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
            statusIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.text.prefix(80))
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if item.iterationsTotal > 1 {
                        Text("\(item.iterationsDone)/\(item.iterationsTotal)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.accentEon.opacity(0.8))
                    }
                    Text(item.isAgentMode ? "Agent" : "Chat")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if item.iterationsTotal > 1 && item.status == .running {
                CircularProgress(value: item.progress)
                    .frame(width: 18, height: 18)
            }

            if item.status == .waiting {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
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
                .stroke(Color.white.opacity(0.08), lineWidth: 2)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.accentEon, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Message Bubble (ChatGPT style)

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if message.role == .user {
                // User message: right-aligned subtle pill
                HStack {
                    Spacer(minLength: 60)
                    contentView
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.userBubble)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            } else {
                // Assistant message: full-width, no bubble, with icon
                HStack(alignment: .top, spacing: 12) {
                    AssistantAvatar()
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        // Model label
                        Text(message.model?.displayName ?? "Navi")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        contentView

                        // Cost badge
                        if message.costSEK > 0 {
                            let usage = message.inputTokens > 0
                                ? TokenUsage(inputTokens: message.inputTokens, outputTokens: message.outputTokens, cacheCreationInputTokens: nil, cacheReadInputTokens: nil)
                                : nil
                            CostBadge(costSEK: message.costSEK, usage: usage, model: message.model)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
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
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                case .image(let data, _):
                    if let uiImage = PlatformImage(data: data) {
                        Image(platformImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .cornerRadius(12)
                    }
                case .toolUse(_, let name, _):
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(name)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(8)
                case .toolResult(_, let result, let isError):
                    Text(result.prefix(300))
                        .font(.system(size: 13, design: .monospaced))
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
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
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

// MARK: - Code Block View (ChatGPT style)

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(language ?? "code")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
                Button {
                    copyCode()
                } label: {
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

            // Code
            ScrollView(.horizontal, showsIndicators: false) {
                LargeTextView(text: code.trimmed, fontSize: 13, fontDesign: .monospaced)
                    .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.codeBackground)
        )
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

// MARK: - Smooth streaming buffer

/// Reveals streaming tokens smoothly. Runs at 60fps, reveals up to 18 chars/tick
/// so fast responses feel instant while still animating nicely.
@MainActor
final class StreamingBuffer: ObservableObject {
    @Published private(set) var displayText: String = ""

    private var targetText: String = ""
    private var timer: Timer?
    // 18 chars @ 60fps = ~1080 chars/sec — fast enough to feel instant
    private let charsPerTick: Int = 18

    func update(_ newText: String) {
        targetText = newText
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
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
            if displayText == targetText {
                timer?.invalidate()
                timer = nil
            }
            return
        }
        let endIndex = targetText.index(
            targetText.startIndex,
            offsetBy: min(displayText.count + charsPerTick, targetText.count)
        )
        displayText = String(targetText[..<endIndex])
    }
}

// MARK: - Streaming bubble (smooth, ChatGPT-faithful)

struct StreamingBubble: View {
    let text: String
    @StateObject private var buffer = StreamingBuffer()
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AssistantAvatar()
                .padding(.top, 2)

            if text.isEmpty && buffer.displayText.isEmpty {
                TypingIndicator()
                    .padding(.top, 4)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Text(buffer.displayText)
                        .font(.callout)
                        .foregroundColor(Color.primary)
                        .lineSpacing(4)
                        .textSelection(.enabled)

                    // Blinking cursor
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: 15)
                        .opacity(cursorVisible ? 1 : 0)
                        .padding(.leading, 2)
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
        .onChange(of: text) { newText in
            buffer.update(newText)
        }
        .onDisappear {
            buffer.flush()
        }
    }
}

// MARK: - Typing indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
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

// MARK: - Input bar (ChatGPT style)

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
            // Images preview
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { i, data in
                            ZStack(alignment: .topTrailing) {
                                if let img = PlatformImage(data: data) {
                                    Image(platformImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Button {
                                    selectedImages.remove(at: i)
                                } label: {
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

            // Main input pill
            HStack(alignment: .bottom, spacing: 0) {
                HStack(spacing: 4) {
                    Button {
                        showImagePicker = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        isAgentMode.toggle()
                    } label: {
                        Image(systemName: isAgentMode ? "cpu.fill" : "cpu")
                            .font(.system(size: 15))
                            .foregroundColor(isAgentMode ? .accentEon : .secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Agent-läge: " + (isAgentMode ? "PÅ" : "AV"))
                }

                TextField(isAgentMode ? "Ge agenten en uppgift..." : "Skriv ett meddelande...", text: $text, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...8)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 8)

                HStack(spacing: 4) {
                    if isAgentMode {
                        Menu {
                            ForEach([1, 2, 3, 5, 10, 20, 50, 100], id: \.self) { n in
                                Button("\(n)x") { iterationCount = n }
                            }
                        } label: {
                            Text("\(iterationCount)x")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(iterationCount > 1 ? .accentEon : .secondary.opacity(0.5))
                                .frame(width: 28, height: 32)
                        }
                    }

                    Button(action: onSend) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.65)
                                .frame(width: 30, height: 30)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(text.isBlank && selectedImages.isEmpty ? .secondary.opacity(0.3) : .black)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(text.isBlank && selectedImages.isEmpty ? Color.clear : Color.white)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading || (text.isBlank && selectedImages.isEmpty))
                }
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

            // Status bar
            HStack(spacing: 8) {
                Text(model.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))

                if isAgentMode {
                    Text("Agent")
                        .font(.system(size: 12))
                        .foregroundColor(.accentEon.opacity(0.6))
                }

                Spacer()

                Button(action: onShowQueue) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10))
                        if queueCount > 0 {
                            Text("\(queueCount)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.accentEon)
                        }
                    }
                    .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)

                if let cost = costText {
                    Text(cost)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                let sessionCost = CostTracker.shared.sessionSEK
                if sessionCost > 0.001 {
                    Text(String(format: "%.2f kr", sessionCost))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.3))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Color.chatBackground)
    }
}

// MARK: - Previews

#Preview("ChatView") {
    let project = EonProject(name: "Navi Preview", rootPath: "/tmp/preview")
    let agent = ProjectAgent(project: project)
    return ChatView(agent: agent)
        .frame(width: 500, height: 600)
}

#Preview("MessageBubble – user") {
    let msg = ChatMessage(role: .user, content: [.text("Hej! Kan du hjälpa mig med en Swift-funktion?")])
    return MessageBubble(message: msg)
        .padding()
        .background(Color.chatBackground)
}

#Preview("MessageBubble – assistant") {
    let code = "```swift\nfunc hello() {\n    print(\"Hello, world!\")\n}\n```"
    let msg = ChatMessage(role: .assistant, content: [.text("Självklart! Här är ett exempel:\n\(code)")], model: .haiku)
    return MessageBubble(message: msg)
        .padding()
        .background(Color.chatBackground)
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
    .background(Color.chatBackground)
}

// MARK: - Reusable Assistant Avatar

struct AssistantAvatar: View {
    var size: CGFloat = 28

    // ChatGPT-green: #74aa9c
    private let gptGreen = Color(red: 0.455, green: 0.667, blue: 0.612)

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [gptGreen, gptGreen.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(.white)
        }
    }
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
