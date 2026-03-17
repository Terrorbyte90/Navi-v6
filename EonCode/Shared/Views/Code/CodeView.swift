import SwiftUI
#if os(iOS)
import PhotosUI
#endif

// MARK: - CodeView
// Server-backed code sessions via CodeServerService.
// All interactions go through the Navi Brain server for concurrent multi-session support.

struct CodeView: View {
    @StateObject private var serverService = CodeServerService.shared
    @StateObject private var settings = SettingsStore.shared
    @State private var inputText = ""
    @State private var showNewSessionSheet = false
    @State private var selectedModel: ClaudeModel = .minimaxM25
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.08)

            if let error = serverService.errorMessage {
                errorBanner(error)
            }

            if serverService.activeSession != nil {
                sessionDetailView
            } else {
                sessionListView
            }
        }
        .background(Color.chatBackground)
        .onAppear {
            // Default to a server-capable model
            if settings.defaultModel.serverModelKey != nil {
                selectedModel = settings.defaultModel
            }
            // Refresh session list on every appear
            Task { await serverService.loadSessions() }
        }
        .sheet(isPresented: $showNewSessionSheet) {
            NewSessionSheet(serverService: serverService, selectedModel: $selectedModel)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Back button when session is active
            if serverService.activeSession != nil {
                Button {
                    withAnimation(NaviTheme.Spring.smooth) {
                        serverService.activeSession = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Sessioner")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.accentNavi)
                }
                .buttonStyle(.plain)
            } else {
                Text("Navi Code")
                    .font(NaviTheme.headingFont(size: 17))
                    .foregroundColor(.accentNavi)
            }

            // Model picker
            modelPickerMenu

            Spacer()

            // Stop button (session detail only)
            if let session = serverService.activeSession, session.status == .working {
                Button {
                    Task { await serverService.stopSession(session) }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                        .foregroundColor(NaviTheme.error)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Avbryt session")
                #if os(macOS)
                .help("Avbryt session")
                #endif
            }

            // New session button
            Button {
                showNewSessionSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Ny session")
            .buttonStyle(.plain)
            #if os(macOS)
            .help("Ny kodsession")
            #endif

            // Refresh button
            Button {
                Task { await serverService.loadSessions() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(serverService.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    // MARK: - Model picker menu

    private var modelPickerMenu: some View {
        Menu {
            Section("Server — Navi Brain") {
                Button {
                    selectedModel = .minimaxM25
                } label: {
                    HStack {
                        Text("MiniMax M2.5")
                        Spacer()
                        if selectedModel == .minimaxM25 {
                            Image(systemName: "checkmark").foregroundColor(.accentNavi)
                        }
                    }
                }
                Button {
                    selectedModel = .kimiK25
                } label: {
                    HStack {
                        Text("Kimi K2.5")
                        Spacer()
                        if selectedModel == .kimiK25 {
                            Image(systemName: "checkmark").foregroundColor(.accentNavi)
                        }
                    }
                }
                Button {
                    selectedModel = .freeModels
                } label: {
                    HStack {
                        Text("Gratismodeller")
                        Spacer()
                        if selectedModel == .freeModels {
                            Image(systemName: "checkmark").foregroundColor(.accentNavi)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedModel.displayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.surfaceHover))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text(error)
                .font(NaviTheme.bodyFont(size: 12.5))
                .lineLimit(3)
            Spacer()
            Button { serverService.errorMessage = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(NaviTheme.error.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(NaviTheme.error)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(NaviTheme.error.opacity(0.06))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Session list

    private var sessionListView: some View {
        Group {
            if serverService.isLoading && serverService.sessions.isEmpty {
                loadingState
            } else if serverService.sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(serverService.sessions) { session in
                            CodeServerSessionCard(session: session) {
                                withAnimation(NaviTheme.Spring.smooth) {
                                    serverService.activeSession = session
                                }
                            } onDelete: {
                                Task { await serverService.deleteSession(session) }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                #if os(iOS)
                .refreshable { await serverService.loadSessions() }
                #endif
            }
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Hämtar sessioner…")
                .font(NaviTheme.bodyFont(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ThinkingOrb(size: 72, isAnimating: false)

            VStack(spacing: 10) {
                Text("Bygg projekt på servern.")
                    .font(NaviTheme.headingFont(size: 18))
                    .foregroundColor(.primary)
                Text("Navi planerar, kodar och pushar till GitHub åt dig.\nFlera sessioner kan köra parallellt.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button {
                showNewSessionSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    Text("Starta ny session")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.accentNavi)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session detail

    private var sessionDetailView: some View {
        Group {
            if let session = serverService.activeSession {
                SessionDetailView(
                    session: session,
                    serverService: serverService
                )
            }
        }
    }
}

// MARK: - CodeServerSessionCard

struct CodeServerSessionCard: View {
    let session: CodeServerSession
    var onTap: () -> Void
    var onDelete: () -> Void

    private var timeAgo: String {
        // Simple relative time from ISO8601 string
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: session.updatedAt)
                ?? ISO8601DateFormatter().date(from: session.updatedAt)
        else { return session.updatedAt }
        let diff = Int(-date.timeIntervalSinceNow)
        if diff < 60 { return "nyss" }
        if diff < 3600 { return "\(diff / 60)m sedan" }
        if diff < 86400 { return "\(diff / 3600)h sedan" }
        return "\(diff / 86400)d sedan"
    }

    private var modelShortName: String {
        // Strip provider prefix for display
        let m = session.model
        if let slash = m.lastIndex(of: "/") {
            return String(m[m.index(after: slash)...])
        }
        return m
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Top row: status pill + name
                HStack(spacing: 8) {
                    // Status pill
                    Text(session.status.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundColor(session.status.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(session.status.color.opacity(0.12))
                        .clipShape(Capsule())

                    Text(session.name)
                        .font(NaviTheme.bodyFont(size: 15))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    // Live pulse if working
                    if session.status == .working {
                        LivePulseDot()
                    }
                }

                // Bottom row: model, message count, tokens, time
                HStack(spacing: 10) {
                    Label(modelShortName, systemImage: "cpu")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))

                    if !session.messages.isEmpty {
                        Label("\(session.messages.count)", systemImage: "bubble.left.and.bubble.right")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                    }

                    if session.totalTokens > 0 {
                        Label("\(formatTokens(session.totalTokens))", systemImage: "bolt")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                    }

                    Spacer()

                    Text(timeAgo)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.surfaceHover.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                session.status == .working
                                    ? Color.accentNavi.opacity(0.25)
                                    : Color.primary.opacity(0.07),
                                lineWidth: session.status == .working ? 1 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Ta bort session", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Ta bort", systemImage: "trash")
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

// MARK: - LivePulseDot

private struct LivePulseDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Color.accentNavi)
            .frame(width: 7, height: 7)
            .scaleEffect(pulse ? 1.4 : 1.0)
            .opacity(pulse ? 0.5 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - SessionDetailView

struct SessionDetailView: View {
    let session: CodeServerSession
    @ObservedObject var serverService: CodeServerService
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    // Resolve live session from service (keeps updates reactive)
    private var liveSession: CodeServerSession {
        serverService.sessions.first { $0.id == session.id } ?? session
    }

    // Derive ThinkingPhase from server liveStatus.phase
    private var thinkingPhase: ChatManager.ThinkingPhase {
        guard liveSession.status == .working else { return .idle }
        guard let phase = liveSession.liveStatus?.phase else { return .thinking }
        switch phase.lowercased() {
        case "thinking", "reasoning": return .thinking
        case "executing", "tools":    return .executingTools
        case "responding", "writing": return .responding
        case "connecting":            return .connecting
        case "finishing", "done":     return .finishing
        default:                      return .thinking
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Todo list (if any)
                    if !liveSession.todos.isEmpty {
                        todoList
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }

                    // Empty-state placeholder for brand-new sessions
                    if liveSession.messages.isEmpty && liveSession.status == .idle {
                        VStack(spacing: 12) {
                            Image(systemName: "curlybraces.square")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.3))
                            Text("Beskriv vad du vill bygga…")
                                .font(NaviTheme.bodyFont(size: 15))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }

                    // Messages
                    ForEach(liveSession.messages) { msg in
                        ServerMessageRow(message: msg)
                            .id(msg.id)
                    }

                    // Live activity indicator
                    if liveSession.status == .working {
                        VStack(alignment: .leading, spacing: 6) {
                            NaviThinkingCard(
                                phase: thinkingPhase,
                                liveToolCall: liveSession.liveStatus?.tool,
                                elapsed: serverService.elapsedSeconds
                            )
                            .padding(.horizontal, 16)

                            // Worker chips
                            if !liveSession.workers.isEmpty {
                                workerChips
                                    .padding(.horizontal, 16)
                            }
                        }
                        .id("activityArea")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Done indicator
                    if liveSession.status == .done && !liveSession.messages.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(NaviTheme.success)
                            Text("Sessionen klar")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(NaviTheme.success.opacity(0.8))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(NaviTheme.success.opacity(0.08))
                        .cornerRadius(10)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .transition(.scale.combined(with: .opacity))
                        .id("sessionDone")
                    }

                    Color.clear.frame(height: 8).id("bottomAnchor")
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar.background(Color.chatBackground)
            }
            .onChange(of: liveSession.messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                }
            }
            .onChange(of: liveSession.status) { _, status in
                if status == .working {
                    withAnimation { proxy.scrollTo("activityArea", anchor: .bottom) }
                }
            }
        }
        .animation(NaviTheme.Spring.smooth, value: liveSession.status)
    }

    // MARK: Todo list

    private var todoList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("UPPGIFTER")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.bottom, 2)

            ForEach(liveSession.todos) { todo in
                HStack(spacing: 8) {
                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(todo.done ? NaviTheme.success : .secondary.opacity(0.5))
                    Text(todo.text)
                        .font(NaviTheme.bodyFont(size: 13))
                        .foregroundColor(todo.done ? .secondary : .primary)
                        .strikethrough(todo.done, color: .secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surfaceHover.opacity(0.5))
        )
    }

    // MARK: Worker chips

    private var workerChips: some View {
        let active = liveSession.workers.filter { $0.status == "running" || $0.status == "done" }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(active.prefix(8)) { worker in
                    WorkerChip(worker: worker)
                }
            }
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TextField(
                    liveSession.messages.isEmpty
                        ? "Beskriv ett projekt att bygga…"
                        : "Fortsätt konversationen…",
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
                            .fill(sendDisabled ? Color.secondary.opacity(0.2) : Color.accentNavi)
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(sendDisabled ? .secondary.opacity(0.5) : .white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
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
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    private var sendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespaces).isEmpty || liveSession.status == .working
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, liveSession.status != .working else { return }
        dismissKeyboard()
        Task {
            do {
                try await serverService.sendMessage(text, to: liveSession)
                inputText = "" // Clear only on success
            } catch {
                // Preserve inputText so user can retry
                serverService.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - WorkerChip

private struct WorkerChip: View {
    let worker: CodeServerWorker

    private var statusColor: Color {
        switch worker.status {
        case "done":    return Color(naviHex: "4CAF50")
        case "error":   return Color(naviHex: "FF5252")
        default:        return Color.accentNavi
        }
    }

    private var icon: String {
        switch worker.status {
        case "done":  return "checkmark.circle.fill"
        case "error": return "xmark.circle.fill"
        default:      return "circle.dotted"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(statusColor)
            Text("Worker \(worker.index + 1)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary.opacity(0.7))
            Text(worker.task.prefix(24))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.08))
                .overlay(
                    Capsule().strokeBorder(statusColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - ServerMessageRow

struct ServerMessageRow: View {
    let message: CodeServerMessage

    var body: some View {
        Group {
            if message.role == "user" {
                userRow
            } else {
                assistantRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var userRow: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .font(NaviTheme.bodyFont(size: 16))
                .foregroundColor(.primary)
                .lineSpacing(4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.userBubble)
                )
                .textSelection(.enabled)
        }
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 10) {
            // Worker badge if from a sub-agent
            if message.isWorker == true {
                Text("W\((message.workerIndex ?? 0) + 1)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentNavi.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .background(Color.accentNavi.opacity(0.1))
                    .clipShape(Circle())
                    .padding(.top, 2)
            } else {
                ThinkingOrb(size: 24, isAnimating: false)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Tool calls pill
                if let tools = message.toolCalls, !tools.isEmpty {
                    NaviActivityPill(
                        statusText: tools.count == 1 ? "1 verktyg" : "\(tools.count) verktyg",
                        items: tools,
                        isLive: false
                    )
                }

                MarkdownTextView(text: message.content)
                    .textSelection(.enabled)

                // Token count (subtle)
                if let tokens = message.tokens, tokens > 0 {
                    Text("\(tokens) tokens")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.3))
                }

                // Copy button
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = message.content
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                    #endif
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 40)
        }
    }
}

// MARK: - NewSessionSheet

struct NewSessionSheet: View {
    @ObservedObject var serverService: CodeServerService
    @Binding var selectedModel: ClaudeModel
    @Environment(\.dismiss) private var dismiss

    @State private var sessionName = ""
    @State private var firstMessage = ""
    @State private var isCreating = false
    @FocusState private var nameFocused: Bool

    private let serverModels: [(ClaudeModel, String)] = [
        (.minimaxM25, "minimax/minimax-m2.5"),
        (.kimiK25, "moonshotai/kimi-k2.5"),
        (.freeModels, "free")
    ]

    private var serverModelKey: String {
        selectedModel.serverModelKey ?? "minimax/minimax-m2.5"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sessionsnamn") {
                    TextField("t.ex. iOS Todo-app", text: $sessionName)
                        .focused($nameFocused)
                }

                Section("Modell") {
                    ForEach(serverModels, id: \.0) { model, key in
                        Button {
                            selectedModel = model
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    Text(model.description)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedModel == model {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentNavi)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Första instruktion (valfri)") {
                    TextField("Beskriv vad du vill bygga…", text: $firstMessage, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Ny kodsession")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skapa") { createSession() }
                        .disabled(sessionName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .onAppear { nameFocused = true }
        }
    }

    private func createSession() {
        let name = sessionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        Task {
            do {
                let session = try await serverService.createSession(
                    name: name,
                    model: serverModelKey
                )
                // Send first message if provided
                let msg = firstMessage.trimmingCharacters(in: .whitespaces)
                if !msg.isEmpty {
                    try await serverService.sendMessage(msg, to: session)
                }
            } catch {
                serverService.errorMessage = error.localizedDescription
            }
            isCreating = false
            dismiss()
        }
    }
}

// MARK: - Legacy components kept for backward compat (used by older code paths)

// MARK: - PhasePill — compact inline phase badge

struct PhasePill: View {
    let phase: PipelinePhase
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.accentNavi)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .opacity(pulse ? 0.6 : 1.0)

            Text(phase.displayName.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
        }
        .foregroundColor(.accentNavi.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.accentNavi.opacity(0.08))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - PhaseProgressBar — compact horizontal phase indicator

struct PhaseProgressBar: View {
    let currentPhase: PipelinePhase
    private let phases: [PipelinePhase] = [.spec, .research, .setup, .plan, .build, .push]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(phases, id: \.self) { phase in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: phase))
                        .frame(height: 3)

                    Text(phase.shortName)
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundColor(labelColor(for: phase))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func barColor(for phase: PipelinePhase) -> Color {
        if phase.ordinal < currentPhase.ordinal { return NaviTheme.success }
        if phase.ordinal == currentPhase.ordinal { return Color.accentNavi }
        return Color.secondary.opacity(0.15)
    }

    private func labelColor(for phase: PipelinePhase) -> Color {
        if phase.ordinal == currentPhase.ordinal { return .accentNavi }
        if phase.ordinal < currentPhase.ordinal { return NaviTheme.success.opacity(0.7) }
        return .secondary.opacity(0.3)
    }
}

// MARK: - CodeStreamingRow (kept for any remaining local usage)

struct CodeStreamingRow: View {
    let text: String
    let phase: PipelinePhase

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 24, isAnimating: true)

            VStack(alignment: .leading, spacing: 6) {
                if text.isEmpty {
                    NaviVisualActivity.forPhase(phase)
                } else {
                    MarkdownTextView(text: text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - CodeAPIInfoCard — shows current API request info

struct CodeAPIInfoCard: View {
    let info: CodeAPIInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.accentNavi.opacity(0.6))
            Text("POST")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.accentNavi.opacity(0.7))
            Text(info.provider.capitalized)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
            Spacer()
            Text(info.model)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.secondary.opacity(0.5))
            if info.toolCount > 0 {
                Text("\(info.toolCount) tools")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            if info.iteration > 1 {
                Text("iter \(info.iteration)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.accentNavi.opacity(0.5))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.accentNavi.opacity(0.08))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentNavi.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentNavi.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
    }
}

// MARK: - CodeThinkingCard — legacy component retained for compatibility

struct CodeThinkingCard: View {
    let phase: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentNavi)
                .frame(width: 6, height: 6)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .opacity(pulse ? 0.5 : 1.0)
            Text(phase)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - CodeToolCallCard — shows completed tool call with result

struct CodeToolCallCard: View {
    let event: CodeToolCallEvent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(NaviTheme.Spring.quick) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: event.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(event.isError ? NaviTheme.error : NaviTheme.success)

                    Image(systemName: event.icon)
                        .font(.system(size: 10))
                        .foregroundColor(.accentNavi.opacity(0.6))

                    Text(event.toolName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.7))

                    // Show key param
                    if let path = event.params["path"] ?? event.params["query"] ?? event.params["cmd"] ?? event.params["repo"] {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                            .lineLimit(1)
                    }

                    Spacer()

                    if event.duration > 0 {
                        Text(String(format: "%.1fs", event.duration))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.3))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            // Expanded result
            if isExpanded && !event.result.isEmpty {
                Divider().opacity(0.1)
                Text(event.result.prefix(800))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                    .lineLimit(12)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(event.isError ? NaviTheme.error.opacity(0.04) : Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(event.isError ? NaviTheme.error.opacity(0.15) : Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
    }
}

// MARK: - CodeMessageRow (kept for backward compat — wraps PureChatMessage)

struct CodeMessageRow: View, Equatable {
    let message: PureChatMessage

    static func == (lhs: CodeMessageRow, rhs: CodeMessageRow) -> Bool {
        lhs.message.id == rhs.message.id && lhs.message.content == rhs.message.content
    }

    var body: some View {
        Group {
            if message.role == .user {
                userRow
            } else {
                assistantRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var userRow: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .font(NaviTheme.bodyFont(size: 16))
                .foregroundColor(.primary)
                .lineSpacing(4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.userBubble)
                )
                .textSelection(.enabled)
        }
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 24, isAnimating: false)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
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

                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = message.content
                    #else
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                    #endif
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 40)
        }
    }
}
