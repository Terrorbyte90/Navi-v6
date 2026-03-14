import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
#endif

struct ChatView: View {
    @ObservedObject var agent: ProjectAgent
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var isAgentMode = false
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
                            AgentStreamingBubble(
                                text: agent.streamingText,
                                statusMessage: agent.currentStatus,
                                activeFiles: agent.activeFileNames,
                                codeSnippet: agent.activeCodeSnippet,
                                todoItems: agent.todoItems
                            )
                            .id("streaming")
                        } else if agent.isRunning {
                            HStack(alignment: .top, spacing: 12) {
                                AssistantAvatar()
                                    .padding(.top, 2)
                                NaviVisualActivity.forStatus(
                                    agent.currentStatus.isEmpty
                                        ? "Tänker"
                                        : agent.currentStatus.liveToolPillText
                                )
                                Spacer(minLength: 40)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .id("typing")
                        }

                        // Bottom anchor for reliable scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottomAnchor")
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissKeyboard() }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        AgentActivityOverlay()
                            .padding(.horizontal, 12)

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
                            costText: nil,
                            model: agent.conversation.model,
                            onShowQueue: { showQueuePanel.toggle() }
                        ) {
                            sendMessage()
                        }

                        Text("Navi kan göra misstag. Kontrollera viktig information.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
                    }
                }
                .onChange(of: agent.conversation.messages.count) { _ in
                    scrollToBottom(proxy: proxy, animated: true)
                }
                .onChange(of: agent.streamingText.count / 80) { _ in
                    // Throttled scroll during streaming — only scrolls every ~80 chars
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
        // Always scroll to the bottom anchor to avoid blank-space issues
        proxy.scrollTo("bottomAnchor", anchor: .bottom)
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
                            .foregroundColor(.accentNavi.opacity(0.8))
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
        case .running: return Color.accentNavi.opacity(0.06)
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
                .stroke(Color.accentNavi, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
                    let cleaned = ResponseCleaner.clean(t)
                    if !cleaned.isEmpty {
                        if message.role == .user {
                            Text(cleaned)
                                .font(.system(size: 15.5))
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        } else {
                            MarkdownTextView(text: cleaned)
                                .equatable()
                                .textSelection(.enabled)
                        }
                    }
                case .image(let data, _):
                    if let uiImage = PlatformImage(data: data) {
                        Image(platformImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .cornerRadius(12)
                    }
                case .toolUse(_, let name, let input):
                    ToolActionBadge(toolName: name, input: input)
                case .toolResult(_, let result, let isError):
                    if isError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                            Text(result.prefix(200))
                                .font(.system(size: 12))
                                .foregroundColor(.red.opacity(0.8))
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.06))
                        .cornerRadius(8)
                    }
                    // Hide successful tool results — the user cares about the outcome text, not raw output
                }
            }
        }
    }

    // Code block parsing is now handled by MarkdownTextView
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

/// Reveals streaming tokens smoothly. Runs at 30fps, reveals large chunks per tick
/// so fast API responses appear near-instantly while still animating nicely.
/// Also cleans internal tags in real-time so the user never sees raw XML.
@MainActor
final class StreamingBuffer: ObservableObject {
    @Published private(set) var displayText: String = ""

    private var targetText: String = ""
    private var cleanedTarget: String = ""
    private var timer: Timer?
    // 80 chars @ 30fps = ~2400 chars/sec — feels instant for most responses
    private let charsPerTick: Int = 80
    private let fps: Double = 30.0

    func update(_ newText: String) {
        targetText = newText
        cleanedTarget = ResponseCleaner.clean(newText)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
        }
    }

    func flush() {
        cleanedTarget = ResponseCleaner.clean(targetText)
        displayText = cleanedTarget
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard displayText.count < cleanedTarget.count else {
            if displayText == cleanedTarget {
                timer?.invalidate()
                timer = nil
            } else {
                displayText = cleanedTarget
            }
            return
        }
        let endIndex = cleanedTarget.index(
            cleanedTarget.startIndex,
            offsetBy: min(displayText.count + charsPerTick, cleanedTarget.count)
        )
        displayText = String(cleanedTarget[..<endIndex])
    }
}

// MARK: - Streaming bubble (smooth, markdown-aware)

struct AgentStreamingBubble: View {
    let text: String
    var statusMessage: String = ""
    var activeFiles: [String] = []
    var codeSnippet: String = ""
    var todoItems: [ProjectAgent.AgentTodoItem] = []
    @StateObject private var buffer = StreamingBuffer()
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AssistantAvatar()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                // Single unified activity visual — exactly ONE at a time.
                // Visual only shown while NO text has arrived yet; once text
                // streams in the visual disappears and text takes over.
                if !codeSnippet.isEmpty {
                    // Writing code → Visual 2
                    Visual2_StreamingCode()
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if text.isEmpty && buffer.displayText.isEmpty {
                    // No text yet — show the most relevant visual for current status
                    NaviVisualActivity.forStatus(
                        statusMessage.isEmpty ? "Tänker" : statusMessage
                    )
                    .transition(.opacity)
                }
                // When text IS present: no visual — text itself signals activity

                if !text.isEmpty || !buffer.displayText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        MarkdownTextView(text: buffer.displayText)
                            .equatable()
                            .textSelection(.enabled)

                        // Blinking cursor
                        HStack(spacing: 0) {
                            Spacer().frame(width: 0)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.accentNavi.opacity(0.8))
                                .frame(width: 2, height: 16)
                                .opacity(cursorVisible ? 1 : 0)
                        }
                        .frame(height: 4)
                    }
                }
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.25), value: activeFiles)
        .animation(.easeInOut(duration: 0.25), value: todoItems.count)
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

// MARK: - Activity Status Bar (shows agent file actions + status)

struct ActivityStatusBar: View {
    let status: String
    let files: [String]
    var codeSnippet: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if !status.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text(status)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentNavi)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !files.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentNavi.opacity(0.5))
                        Text(files.joined(separator: ", "))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            // Code snippet preview — brief glimpse of what's being written
            if !codeSnippet.isEmpty {
                Divider().opacity(0.08)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(codeSnippet)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                        .lineLimit(3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 48)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentNavi.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentNavi.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Tool Action Badge (clean display of agent tool usage)

struct ToolActionBadge: View {
    let toolName: String
    let input: [String: AnyCodable]
    @State private var isExpanded = false

    private var icon: String {
        switch toolName {
        case "write_file": return "doc.badge.plus"
        case "read_file": return "doc.text"
        case "move_file": return "arrow.right.doc.on.clipboard"
        case "delete_file": return "trash"
        case "create_directory": return "folder.badge.plus"
        case "list_directory": return "folder"
        case "run_command": return "terminal"
        case "search_files": return "magnifyingglass"
        case "build_project": return "hammer"
        case "download_file": return "arrow.down.circle"
        case "zip_files": return "doc.zipper"
        default: return "wrench"
        }
    }

    private var label: String {
        switch toolName {
        case "write_file": return "Skrev"
        case "read_file": return "Läste"
        case "move_file": return "Flyttade"
        case "delete_file": return "Tog bort"
        case "create_directory": return "Skapade mapp"
        case "list_directory": return "Listade"
        case "run_command": return "Körde"
        case "search_files": return "Sökte"
        case "build_project": return "Byggde"
        case "download_file": return "Laddade ned"
        case "zip_files": return "Skapade arkiv"
        default: return toolName
        }
    }

    private var fileName: String {
        if let path = input["path"]?.value as? String {
            return (path as NSString).lastPathComponent
        }
        return ""
    }

    private var detail: String {
        if !fileName.isEmpty { return fileName }
        if let cmd = input["cmd"]?.value as? String {
            return String(cmd.prefix(40))
        }
        if let query = input["query"]?.value as? String {
            return "\"\(query.prefix(30))\""
        }
        return ""
    }

    /// Code preview for write_file actions (first ~8 lines)
    private var codePreview: String? {
        guard toolName == "write_file",
              let content = input["content"]?.value as? String,
              !content.isEmpty
        else { return nil }
        let lines = content.components(separatedBy: "\n")
        let preview = lines.prefix(8).joined(separator: "\n")
        return preview + (lines.count > 8 ? "\n  …(\(lines.count) rader)" : "")
    }

    /// File extension for syntax hint
    private var fileExtension: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ext.isEmpty ? "code" : ext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Action header
            Button {
                if codePreview != nil {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(.accentNavi.opacity(0.7))
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer()
                    if codePreview != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            // Expandable code preview
            if isExpanded, let preview = codePreview {
                Divider().opacity(0.1)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .frame(maxHeight: 140)
                .background(Color.codeBackground.opacity(0.5))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentNavi.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentNavi.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - File Activity Card (shows file being edited with live code preview during streaming)

struct FileActivityCard: View {
    let fileName: String
    let status: String
    let codeSnippet: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // File header
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentNavi)
                Text(fileName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.8))
                Spacer()
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentNavi)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentNavi.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if !codeSnippet.isEmpty {
                Divider().opacity(0.08)
                // Code snippet that "swishes by"
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(codeSnippet)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 72)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.codeBackground.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentNavi.opacity(0.08), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Agent TODO List Card (displays agent task progress)

struct AgentTodoCard: View {
    let items: [TodoItem]

    struct TodoItem: Identifiable {
        let id = UUID()
        let text: String
        let isDone: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12))
                    .foregroundColor(.accentNavi)
                Text("Uppgifter")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.8))
                Spacer()
                let done = items.filter(\.isDone).count
                Text("\(done)/\(items.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            ForEach(items) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(item.isDone ? .green : .secondary.opacity(0.4))
                    Text(item.text)
                        .font(.system(size: 12))
                        .foregroundColor(item.isDone ? .secondary : .primary.opacity(0.8))
                        .strikethrough(item.isDone, color: .secondary.opacity(0.3))
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surfaceHover.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.dividerColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Typing indicator (agent)

struct AgentTypingIndicator: View {
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

    @State private var showIterPicker = false
    @FocusState private var inputFocused: Bool
    #if os(iOS)
    @State private var chatPickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    #endif

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
                    Menu {
                        #if os(iOS)
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Label("Bild", systemImage: "photo")
                        }
                        #else
                        Button {
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
                        } label: {
                            Label("Bild", systemImage: "photo")
                        }
                        #endif
                        Button { } label: {
                            Label("Fil", systemImage: "doc")
                        }
                    } label: {
                        Image(systemName: selectedImages.isEmpty ? "plus" : "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(selectedImages.isEmpty ? .secondary : .accentNavi)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
                    #if os(iOS)
                    .photosPicker(isPresented: $showPhotoPicker, selection: $chatPickerItems, maxSelectionCount: 5, matching: .images)
                    .onChange(of: chatPickerItems) { _, items in
                        Task {
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    await MainActor.run { selectedImages.append(data) }
                                }
                            }
                            await MainActor.run { chatPickerItems = [] }
                        }
                    }
                    #endif

                    Button {
                        isAgentMode.toggle()
                    } label: {
                        Image(systemName: isAgentMode ? "cpu.fill" : "cpu")
                            .font(.system(size: 15))
                            .foregroundColor(isAgentMode ? .accentNavi : .secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Agent-läge: " + (isAgentMode ? "PÅ" : "AV"))
                }

                TextField(isAgentMode ? "Ge agenten en uppgift..." : "Skriv ett meddelande...", text: $text, axis: .vertical)
                    .focused($inputFocused)
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
                                .foregroundColor(iterationCount > 1 ? .accentNavi : .secondary.opacity(0.5))
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
                        .foregroundColor(.accentNavi.opacity(0.6))
                }

                Spacer()

                Button(action: onShowQueue) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10))
                        if queueCount > 0 {
                            Text("\(queueCount)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.accentNavi)
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Color.chatBackground)
    }
}

// MARK: - Previews

#Preview("ChatView") {
    let project = NaviProject(name: "Navi Preview", rootPath: "/tmp/preview")
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

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentNavi.opacity(0.12))
                .frame(width: size, height: size)
            Text("N")
                .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                .foregroundColor(.accentNavi)
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
