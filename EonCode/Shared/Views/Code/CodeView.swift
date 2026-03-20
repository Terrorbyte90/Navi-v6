import SwiftUI
#if os(iOS)
import PhotosUI
#endif

// MARK: - CodeView
// Autonomous coding agent — powered by server-side ReAct loop.
// Agent runs on Navi Brain server and persists when iOS closes.

struct CodeView: View {
    @StateObject private var session = ServerCodeSession.shared
    @StateObject private var settings = SettingsStore.shared
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool
    @State private var selectedModel: String = "minimax"
    @State private var showTodoPanel = false
    #if os(iOS)
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var selectedImages: [Data] = []
    #endif

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.06)
            mainArea
        }
        .background(Color.chatBackground)
        .onAppear {
            // Resume last session if we have one and not connected
            if let sid = session.sessionId, session.connectionState == .disconnected {
                session.resumeSession(sid)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Title + server indicator
                HStack(spacing: 6) {
                    Text("Kod")
                        .font(NaviTheme.headingFont(size: 17))
                        .foregroundColor(.primary)

                    serverBadge
                }

                Spacer()

                // TODO toggle (shows only when there are todos)
                if !session.todos.isEmpty {
                    Button {
                        withAnimation(NaviTheme.Spring.smooth) { showTodoPanel.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.system(size: 12))
                            Text("\(session.todos.filter { $0.done }.count)/\(session.todos.count)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(showTodoPanel ? .accentNavi : .secondary.opacity(0.6))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(showTodoPanel ? Color.accentNavi.opacity(0.1) : Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }

                // New session button
                if session.sessionId != nil {
                    Button {
                        withAnimation(NaviTheme.Spring.smooth) {
                            session.resetForNewSession()
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Model picker
                modelPicker

                // Stop button
                Button {
                    if session.isRunning { session.stop() }
                } label: {
                    Image(systemName: session.isRunning ? "stop.fill" : "stop")
                        .font(.system(size: 14))
                        .foregroundColor(session.isRunning ? NaviTheme.error : .secondary.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(!session.isRunning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)

            // TODO panel — inline expandable
            if showTodoPanel && !session.todos.isEmpty {
                todoPanelView
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(NaviTheme.Spring.smooth, value: showTodoPanel)
    }

    // MARK: - Server badge

    private var serverBadge: some View {
        HStack(spacing: 3) {
            connectionDot
            Text("SERVER")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.6)
        }
        .foregroundColor(connectionBadgeColor)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(connectionBadgeColor.opacity(0.1)))
    }

    private var connectionDot: some View {
        Circle()
            .fill(connectionBadgeColor)
            .frame(width: 5, height: 5)
    }

    private var connectionBadgeColor: Color {
        switch session.connectionState {
        case .connected:             return NaviTheme.success
        case .connecting:            return NaviTheme.warning
        case .reconnecting:          return NaviTheme.warning
        case .disconnected:          return Color.secondary.opacity(0.4)
        }
    }

    // MARK: - Phase strip

    private var phaseStrip: some View {
        HStack(spacing: 8) {
            // Spinner
            ProgressView()
                .scaleEffect(0.65)
                .tint(.accentNavi)

            // Label
            Text(session.phaseLabel.isEmpty ? phaseLabelFromPhase(session.phase) : session.phaseLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.accentNavi.opacity(0.8))

            Spacer()

            // Iteration counter
            if session.iteration > 0 {
                Text("steg \(session.iteration)/\(session.maxIteration)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.accentNavi.opacity(0.5))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.accentNavi.opacity(0.08))
                    .cornerRadius(4)
            }

            // Live tool indicator
            if let toolName = session.liveToolName {
                HStack(spacing: 4) {
                    Image(systemName: iconForTool(toolName))
                        .font(.system(size: 9))
                    Text(toolName)
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(.secondary.opacity(0.6))
                .lineLimit(1)
            }

            // Watcher status badge
            if session.watcherIntervened {
                HStack(spacing: 3) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .font(.system(size: 9))
                    Text("Watcher ingrep")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else if session.watcherChecking {
                HStack(spacing: 3) {
                    Image(systemName: "eye")
                        .font(.system(size: 9))
                    Text("Watcher")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(4)
            }
        }
        .animation(NaviTheme.Spring.smooth, value: session.watcherChecking)
        .animation(NaviTheme.Spring.smooth, value: session.watcherIntervened)
        .padding(.horizontal, 16)
        .padding(.bottom, 7)
    }

    private func phaseLabelFromPhase(_ p: String) -> String {
        switch p {
        case "thinking": return "Tänker…"
        case "tools":    return "Använder verktyg…"
        case "running":  return "Kör…"
        case "done":     return "Klar"
        case "error":    return "Fel"
        default:         return "Arbetar…"
        }
    }

    // MARK: - TODO panel

    private var todoPanelView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.06)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.todos) { todo in
                        todoPill(todo)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func todoPill(_ todo: ServerTodoItem) -> some View {
        HStack(spacing: 5) {
            Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundColor(todo.done ? NaviTheme.success : Color.secondary.opacity(0.4))
            Text(todo.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(todo.done ? Color.secondary.opacity(0.5) : Color.primary.opacity(0.8))
                .strikethrough(todo.done)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(todo.done ? NaviTheme.success.opacity(0.06) : Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .stroke(todo.done ? NaviTheme.success.opacity(0.2) : Color.primary.opacity(0.07), lineWidth: 0.5))
        )
    }

    // MARK: - Model picker

    private var modelPicker: some View {
        Menu {
            Button { selectedModel = "minimax" } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MiniMax M2.5")
                            .font(.system(size: 14, weight: .medium))
                        Text("80.2% SWE-bench · 900K ctx · snabbast")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedModel == "minimax" {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundColor(.accentNavi)
                    }
                }
            }
            Button { selectedModel = "qwen" } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Qwen3-Coder")
                            .font(.system(size: 14, weight: .medium))
                        Text("Gratis · 110K ctx · kodspecialist")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedModel == "qwen" {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundColor(.accentNavi)
                    }
                }
            }
            Button { selectedModel = "deepseek" } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DeepSeek R1")
                            .font(.system(size: 14, weight: .medium))
                        Text("110K ctx · chain-of-thought reasoning")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedModel == "deepseek" {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundColor(.accentNavi)
                    }
                }
            }
            Divider()
            Button { selectedModel = "claude" } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Sonnet 4.6")
                            .font(.system(size: 14, weight: .medium))
                        Text("Anthropic · 170K ctx · högsta kvalitet")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedModel == "claude" {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundColor(.accentNavi)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(modelDisplayName(selectedModel))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private func modelDisplayName(_ model: String) -> String {
        switch model {
        case "minimax":  return "MiniMax"
        case "qwen":     return "Qwen3"
        case "deepseek": return "DeepSeek"
        case "claude":   return "Claude"
        default:         return model
        }
    }

    // MARK: - Main area

    private var mainArea: some View {
        Group {
            if session.messages.isEmpty && !session.isRunning
                && session.sessionId == nil && session.connectionState == .disconnected {
                ScrollView { emptyState }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        inputBar.background(Color.chatBackground)
                    }
            } else {
                messagesArea
            }
        }
    }

    // MARK: - Messages area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(session.messages) { msg in
                        ServerMessageRow(message: msg)
                            .id(msg.id)
                    }

                    // Activity indicator when running but streaming hasn't started yet
                    if session.isRunning && session.streamingText.isEmpty {
                        ServerActivityRow(
                            phaseLabel: session.phaseLabel.isEmpty ? phaseLabelFromPhase(session.phase) : session.phaseLabel,
                            toolName: session.liveToolName
                        )
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .id("activity")
                    }

                    // Streaming text (live response being revealed)
                    if !session.streamingText.isEmpty {
                        ServerStreamingRow(
                            text: session.streamingText,
                            phaseLabel: session.phaseLabel
                        )
                        .id("streaming")
                    }

                    // Done badge
                    if !session.isRunning && session.phase == "done" && session.sessionId != nil {
                        doneBadge
                            .id("done")
                    }

                    // Error display
                    if let err = session.lastError, !session.isRunning {
                        errorBadge(err)
                            .id("error")
                    }

                    // Bottom spacer so last message clears the input bar
                    Color.clear.frame(height: 16).id("bottom")
                }
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar.background(Color.chatBackground)
            }
            .onChange(of: session.streamingText) { _, new in
                guard !new.isEmpty else { return }
                proxy.scrollTo("streaming", anchor: .bottom)
            }
            .onChange(of: session.messages.count) { _, _ in
                if let last = session.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: session.isRunning) { _, running in
                if running {
                    withAnimation { proxy.scrollTo("activity", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Done / Error badges

    private var doneBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(NaviTheme.success)
            Text(session.phaseLabel.isEmpty ? "Klar" : session.phaseLabel)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(NaviTheme.success.opacity(0.85))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(NaviTheme.success.opacity(0.08))
        .cornerRadius(9)
        .padding(.horizontal, 16).padding(.vertical, 4)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }

    private func errorBadge(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text(msg)
                .font(.system(size: 12)).lineLimit(2)
        }
        .foregroundColor(NaviTheme.error)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(NaviTheme.error.opacity(0.06))
        .cornerRadius(9)
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 16) {
                // Server orb
                ZStack {
                    Circle()
                        .fill(Color.accentNavi.opacity(0.07))
                        .frame(width: 80, height: 80)
                    Image(systemName: "server.rack")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.accentNavi.opacity(0.7))
                }

                VStack(spacing: 8) {
                    Text("Kod")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Agent kör på servern — fortsätter\näven när du stänger appen.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }

            VStack(spacing: 7) {
                quickChip("Bygg ett React dashboard för realtidsdata", icon: "chart.xyaxis.line")
                quickChip("Python API med FastAPI och PostgreSQL", icon: "terminal")
                quickChip("iOS app med SwiftUI och iCloud sync", icon: "iphone")
                quickChip("Next.js landing page med Tailwind", icon: "globe")
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickChip(_ text: String, icon: String) -> some View {
        Button { inputText = text; inputFocused = true } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentNavi.opacity(0.55))
                    .frame(width: 18)
                Text(text)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.25))
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                #if os(iOS)
                PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 3, matching: .images) {
                    ZStack {
                        Circle().fill(Color.primary.opacity(0.04)).frame(width: 32, height: 32)
                        Image(systemName: "photo")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary.opacity(0.4))
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

                TextField(
                    session.sessionId == nil ? "Beskriv ett projekt att bygga…" : "Fortsätt…",
                    text: $inputText,
                    axis: .vertical
                )
                .lineLimit(1...6)
                .font(NaviTheme.bodyFont(size: 15))
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit { sendMessage() }
                .submitLabel(.send)
                .padding(.vertical, 10)
                .padding(.leading, 4)

                Button { sendMessage() } label: {
                    ZStack {
                        Circle()
                            .fill(sendDisabled ? Color.secondary.opacity(0.18) : Color.accentNavi)
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(sendDisabled ? .secondary.opacity(0.4) : .white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.inputBackground)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            )

            Text("Agent kör på Navi Brain · \(connectionStateLabel)")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.35))
        }
        .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 8)
    }

    private var connectionStateLabel: String {
        switch session.connectionState {
        case .connected:           return "Ansluten"
        case .connecting:          return "Ansluter…"
        case .reconnecting(let n): return "Återansluter (\(n))…"
        case .disconnected:        return "Frånkopplad"
        }
    }

    private var sendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespaces).isEmpty || session.isRunning
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !session.isRunning else { return }
        inputText = ""
        dismissKeyboard()

        if session.sessionId == nil || session.connectionState == .disconnected {
            session.startNewSession(task: text, model: selectedModel)
        } else {
            session.sendUserMessage(text)
        }
    }
}

// MARK: - ServerMessageRow

struct ServerMessageRow: View {
    let message: ServerChatMessage

    var body: some View {
        if message.role == .user {  // ServerChatRole.user
            userRow
        } else {
            assistantRow
        }
    }

    private var userRow: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.text)
                .font(NaviTheme.bodyFont(size: 16))
                .foregroundColor(.black)
                .lineSpacing(4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.userBubble))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 22, isAnimating: false)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 8) {
                // Tool events (collapsed pill showing count + expandable)
                if !message.toolEvents.isEmpty {
                    ToolEventsSummary(events: message.toolEvents)
                }

                // Message text (markdown)
                if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    #if os(iOS)
                    MarkdownWebViewAutoHeight(text: message.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    #else
                    Text(message.text)
                        .font(NaviTheme.bodyFont(size: 16))
                        .textSelection(.enabled)
                    #endif
                }

                // Git checkpoint badge
                if let cp = message.gitCheckpoint {
                    GitCheckpointBadge(checkpoint: cp)
                }

                // Copy
                HStack(spacing: 0) {
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = message.text
                        #else
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 32)
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
    }
}

// MARK: - ToolEventsSummary — collapsible tool call list

struct ToolEventsSummary: View {
    let events: [ServerToolEvent]
    @State private var isExpanded = false

    var completedCount: Int { events.filter { $0.isComplete }.count }
    var errorCount:     Int { events.filter { $0.isError    }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary pill (tap to expand)
            Button {
                withAnimation(NaviTheme.Spring.quick) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: errorCount > 0 ? "exclamationmark.circle" : "wrench.adjustable")
                        .font(.system(size: 10))
                        .foregroundColor(errorCount > 0 ? NaviTheme.error : .accentNavi.opacity(0.6))
                    Text("\(events.count) verktyg")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    if errorCount > 0 {
                        Text("· \(errorCount) fel")
                            .font(.system(size: 10))
                            .foregroundColor(NaviTheme.error.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.025))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)

            // Expanded: individual tool call rows
            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(events) { ev in
                        ToolEventRow(event: ev)
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - ToolEventRow

struct ToolEventRow: View {
    let event: ServerToolEvent
    @State private var showResult = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(NaviTheme.Spring.quick) { showResult.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: event.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(event.isError ? NaviTheme.error : NaviTheme.success)

                    Image(systemName: event.icon)
                        .font(.system(size: 9))
                        .foregroundColor(.accentNavi.opacity(0.55))

                    Text(event.name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.65))

                    if let paramVal = event.params["path"] ?? event.params["command"] ?? event.params["pattern"] ?? event.params["query"] {
                        Text(URL(fileURLWithPath: paramVal).lastPathComponent)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.45))
                            .lineLimit(1)
                    }

                    Spacer()

                    if event.durationMs > 0 {
                        Text(event.durationMs < 1000 ? "\(event.durationMs)ms" : String(format: "%.1fs", Double(event.durationMs)/1000))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.35))
                    }

                    Image(systemName: showResult ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary.opacity(0.25))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            if showResult && !event.result.isEmpty {
                Divider().opacity(0.07)
                Text(event.result.prefix(600))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.55))
                    .lineLimit(14)
                    .padding(.horizontal, 10).padding(.vertical, 5)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(event.isError ? NaviTheme.error.opacity(0.03) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(event.isError ? NaviTheme.error.opacity(0.12) : Color.primary.opacity(0.04), lineWidth: 0.5))
        )
    }
}

// MARK: - GitCheckpointBadge

struct GitCheckpointBadge: View {
    let checkpoint: ServerGitCheckpoint

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
                .foregroundColor(.accentNavi.opacity(0.6))
            Text(checkpoint.hash)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.accentNavi.opacity(0.7))
            Text(checkpoint.message)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
                .lineLimit(1)
            if !checkpoint.filesChanged.isEmpty {
                Text(checkpoint.filesChanged)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentNavi.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentNavi.opacity(0.12), lineWidth: 0.5))
        )
    }
}

// MARK: - ServerStreamingRow — live text with animated cursor

struct ServerStreamingRow: View {
    let text: String
    let phaseLabel: String
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 22, isAnimating: true)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                if text.isEmpty {
                    Text(phaseLabel)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                } else {
                    // Streaming markdown with blinking cursor
                    HStack(alignment: .bottom, spacing: 0) {
                        #if os(iOS)
                        MarkdownWebView(text: text)
                        #else
                        Text(text)
                            .font(NaviTheme.bodyFont(size: 16))
                        #endif
                        Rectangle()
                            .fill(Color.accentNavi)
                            .frame(width: 1.5, height: 16)
                            .opacity(cursorVisible ? 1 : 0)
                            .padding(.bottom, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 32)
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
    }
}

// MARK: - ServerActivityRow — thinking/tool activity indicator

struct ServerActivityRow: View {
    let phaseLabel: String
    let toolName: String?
    @State private var dot = false

    var body: some View {
        HStack(spacing: 10) {
            ThinkingOrb(size: 22, isAnimating: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(phaseLabel)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.6))
                    // Animated dots
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle()
                                .fill(Color.accentNavi.opacity(dot ? 0.8 : 0.25))
                                .frame(width: 4, height: 4)
                                .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: dot)
                        }
                    }
                }
                if let tool = toolName {
                    HStack(spacing: 4) {
                        Image(systemName: iconForTool(tool))
                            .font(.system(size: 9))
                        Text(tool)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(.accentNavi.opacity(0.55))
                }
            }

            Spacer()
        }
        .onAppear { dot = true }
    }
}

// MARK: - Helpers

private func iconForTool(_ name: String) -> String {
    switch name {
    case "read_file":   return "doc.text"
    case "write_file":  return "square.and.pencil"
    case "edit_file":   return "pencil.and.outline"
    case "run_command": return "terminal"
    case "grep":        return "magnifyingglass"
    case "list_files":  return "folder"
    case "todo_write":  return "checklist"
    case "git_commit":  return "arrow.triangle.branch"
    case "web_search":  return "globe"
    case "fetch_url":   return "globe.americas"
    default:            return "wrench"
    }
}
