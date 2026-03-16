import SwiftUI

// MARK: - ServerView

struct ServerView: View {
    @StateObject private var brain = NaviBrainService.shared
    @State private var selectedTab: ServerTab = .minimax
    @State private var showInfo = false

    enum ServerTab: String, CaseIterable {
        case minimax   = "Minimax"
        case qwen      = "Qwen"
        case opus      = "Opus"
        case tasks     = "Uppgifter"
        case terminal  = "Terminal"
        case logs      = "Loggar"
        case messages  = "Meddelanden"

        var icon: String {
            switch self {
            case .tasks:    return "play.circle.fill"
            case .terminal: return "terminal.fill"
            case .minimax:  return "sparkles"
            case .qwen:     return "bolt.fill"
            case .opus:     return "cpu.fill"
            case .logs:     return "list.bullet.rectangle.fill"
            case .messages: return "bubble.left.and.bubble.right.fill"
            }
        }
        var accentColor: Color {
            switch self {
            case .tasks:    return Color(naviHex: "4CAF50")
            case .terminal: return Color(naviHex: "a8ff78")
            case .minimax:  return NaviTheme.accent
            case .qwen:     return Color(naviHex: "5B8DEF")
            case .opus:     return Color(naviHex: "B06AFF")
            case .logs:     return Color(naviHex: "94A3B8")
            case .messages: return Color(naviHex: "FF9F43")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
            Divider().opacity(0.1)
            tabPicker
            Divider().opacity(0.08)
            tabContent
        }
        .background(Color.chatBackground)
        .sheet(isPresented: $showInfo) { connectionInfoSheet }
        .onAppear {
            brain.startPolling()
        }
        .onDisappear {
            brain.stopPolling()
        }
    }

    // MARK: - Status Header

    var statusHeader: some View {
        HStack(spacing: 12) {
            connectionDot

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Navi Brain")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("v\(brain.serverStatus?.version ?? "3.2")")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }
                HStack(spacing: 5) {
                    Text(brain.isConnected ? "Online" : "Offline")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(brain.isConnected ? NaviTheme.success : NaviTheme.error)
                    if brain.isConnected {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("3 brains aktiva")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }

            Spacer()

            // Opus cost chip (shows only when there's a cost)
            if brain.opusCostUSD > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 9))
                    Text(String(format: "$%.5f", brain.opusCostUSD))
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundColor(Color(naviHex: "B06AFF").opacity(0.7))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(naviHex: "B06AFF").opacity(0.08))
                .cornerRadius(6)
            }

            if brain.isConnected, let costs = brain.serverCosts,
               let total = costs.totalCost, total > 0 {
                Text(String(format: "$%.4f", total))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.4))
            }

            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.35))
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.chatBackground)
    }

    var connectionDot: some View {
        ZStack {
            Circle()
                .fill(brain.isConnected
                      ? NaviTheme.success.opacity(0.15)
                      : NaviTheme.error.opacity(0.12))
                .frame(width: 36, height: 36)
            Circle()
                .fill(brain.isConnected ? NaviTheme.success : NaviTheme.error)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Tab Picker (scrollable for 5 tabs)

    var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(ServerTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(NaviTheme.Spring.quick) { selectedTab = tab }
                    } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11))
                                Text(tab.rawValue)
                                    .font(.system(size: 13,
                                                  weight: selectedTab == tab ? .semibold : .regular))

                                // Activity indicator for active operations
                                if isTabBusy(tab) {
                                    Circle()
                                        .fill(tab.accentColor)
                                        .frame(width: 5, height: 5)
                                        .scaleEffect(1.0)
                                        .animation(
                                            .easeInOut(duration: 0.6)
                                                .repeatForever(autoreverses: true),
                                            value: isTabBusy(tab)
                                        )
                                }

                                // Badge for tasks tab showing active count
                                if tab == .tasks {
                                    let activeCount = brain.serverTasks.filter { $0.status.isActive }.count
                                    if activeCount > 0 {
                                        Text("\(activeCount)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(width: 16, height: 16)
                                            .background(tab.accentColor)
                                            .clipShape(Circle())
                                    }
                                }

                                // Badge for messages tab showing unread count
                                if tab == .messages {
                                    let msgCount = brain.serverMessages.count
                                    if msgCount > 0 {
                                        Text("\(min(msgCount, 99))")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .padding(.horizontal, 3)
                                            .background(tab.accentColor)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .foregroundColor(selectedTab == tab
                                             ? tab.accentColor
                                             : Color.secondary.opacity(0.45))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(tab.accentColor)
                                    .frame(height: 2)
                                    .cornerRadius(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.chatBackground)
    }

    private func isTabBusy(_ tab: ServerTab) -> Bool {
        switch tab {
        case .tasks:    return brain.serverTasks.contains { $0.status.isActive }
        case .terminal: return brain.isTerminalSending
        case .minimax:  return brain.isSendingMinimax
        case .qwen:     return brain.isSendingQwen
        case .opus:     return brain.isSendingOpus
        case .logs:     return brain.isLoadingLogs
        case .messages: return brain.isLoadingMessages
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .tasks:    ServerTasksView()
        case .terminal: TerminalView()
        case .minimax:  BrainSessionsView(mode: .minimax)
        case .qwen:     BrainSessionsView(mode: .qwen)
        case .opus:     BrainSessionsView(mode: .opus)
        case .logs:     LogsView()
        case .messages: MessagesView()
        }
    }

    // MARK: - Connection Info Sheet

    var connectionInfoSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    infoCard("Server") {
                        CopyableInfoRow(label: "Adress",   value: "209.38.98.107:3001")
                        CopyableInfoRow(label: "HTTP URL", value: "http://209.38.98.107:3001")
                        CopyableInfoRow(label: "SSH",      value: "ssh root@209.38.98.107")
                        InfoRow(label: "Status",
                                value: brain.isConnected ? "Online ✓" : "Offline ✗")
                        if let v = brain.serverStatus?.version {
                            InfoRow(label: "Version", value: v)
                        }
                        if let repos = brain.serverStatus?.repos {
                            InfoRow(label: "Repos", value: "\(repos)")
                        }
                    }

                    infoCard("Brain-modeller") {
                        InfoRow(label: "Minimax",  value: "MiniMax M2.5 (OpenRouter)")
                        InfoRow(label: "Qwen",     value: "MiMo-V2-Flash / Devstral-2512 (gratis)")
                        InfoRow(label: "Opus",     value: "Claude Sonnet 4.6 (Anthropic)")
                    }

                    infoCard("Endpoints") {
                        endpointRow("GET  /health",            desc: "Hälsokontroll")
                        endpointRow("POST /ask",              desc: "Minimax chat")
                        endpointRow("POST /qwen/ask",         desc: "Qwen chat")
                        endpointRow("POST /opus/ask",         desc: "Opus-Brain chat")
                        endpointRow("POST /task/start",       desc: "Starta bakgrundsuppgift")
                        endpointRow("POST /exec",             desc: "Shell-kommando")
                        endpointRow("GET  /costs",            desc: "Kostnader")
                        endpointRow("GET  /opus/status",      desc: "Opus statistik")
                        endpointRow("GET  /logs",             desc: "Serverloggar")
                        endpointRow("GET  /tasks",            desc: "Alla uppgifter")
                    }

                    if let costs = brain.serverCosts {
                        infoCard("Kostnader — Minimax") {
                            if let total = costs.totalCost {
                                InfoRow(label: "Total",
                                        value: String(format: "$%.6f", total))
                            }
                            if let reqs = costs.totalRequests {
                                InfoRow(label: "Anrop", value: "\(reqs)")
                            }
                        }
                    }

                    if brain.opusCostUSD > 0 || brain.opusTokensTotal > 0 {
                        infoCard("Kostnader — Opus-Brain") {
                            InfoRow(label: "Total kostnad",
                                    value: String(format: "$%.6f", brain.opusCostUSD))
                            InfoRow(label: "Tokens totalt",
                                    value: "\(brain.opusTokensTotal)")
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.chatBackground)
            .navigationTitle("Serverinfo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Stäng") { showInfo = false }
                        .foregroundColor(NaviTheme.accent)
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func infoCard<Content: View>(_ title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.5))
                .tracking(0.5)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func endpointRow(_ endpoint: String, desc: String) -> some View {
        HStack {
            Text(endpoint)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(NaviTheme.accent)
            Spacer()
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - InfoRow

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - CopyableInfoRow

private struct CopyableInfoRow: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = value
            #else
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            #endif
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { copied = false }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(NaviTheme.accent)
                    .lineLimit(1)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundColor(copied ? NaviTheme.success : NaviTheme.accent.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TerminalView

struct TerminalView: View {
    @StateObject private var brain = NaviBrainService.shared
    @State private var inputText  = ""
    @State private var didAutoStart = false
    @FocusState private var focused: Bool

    private let quickCommands = [
        "pm2 status", "ls /root/brain", "free -h",
        "df -h", "cat /proc/loadavg", "curl -s localhost:3001/"
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if brain.terminalLines.isEmpty {
                            emptyTerminalState
                        } else {
                            ForEach(brain.terminalLines) { line in
                                terminalLine(line)
                                    .id(line.id)
                            }
                        }
                        if brain.isTerminalSending {
                            HStack(spacing: 4) {
                                Text("▋")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(Color(naviHex: "a8ff78"))
                                    .opacity(0.8)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                            .id("cursor")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.vertical, 12)
                }
                .background(Color(naviHex: "0d1117"))
                .onChange(of: brain.terminalLines.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: brain.isTerminalSending) { sending in
                    if sending {
                        withAnimation { proxy.scrollTo("cursor", anchor: .bottom) }
                    }
                }
                .onAppear {
                    // Auto-run pm2 status on first open so terminal is never empty
                    guard !didAutoStart, brain.terminalLines.isEmpty else { return }
                    didAutoStart = true
                    Task {
                        await brain.execCommand(
                            "echo '=== Navi Brain Terminal ===' && echo 'Server: 209.38.98.107:3001' && echo '' && /root/.bun/bin/bun x pm2 status 2>/dev/null"
                        )
                    }
                }
            }

            Divider().background(Color.white.opacity(0.08))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(NaviTheme.Spring.quick) { brain.clearTerminal() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Rensa")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(brain.terminalLines.isEmpty)

                    Divider().frame(height: 14).opacity(0.3)

                    ForEach(quickCommands, id: \.self) { cmd in
                        Button(cmd) {
                            Task { await brain.execCommand(cmd) }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(naviHex: "a8ff78").opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color(naviHex: "0d1117"))

            HStack(spacing: 10) {
                Text("$")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(naviHex: "a8ff78"))

                TextField("Kommando…", text: $inputText)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.primary)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { Task { await submit() } }

                if brain.isTerminalSending {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color(naviHex: "a8ff78"))
                } else {
                    Button {
                        Task { await submit() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(inputText.isEmpty
                                             ? .secondary.opacity(0.25)
                                             : Color(naviHex: "a8ff78"))
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.chatBackground)
        }
    }

    private var emptyTerminalState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundColor(Color(naviHex: "a8ff78").opacity(0.25))
            Text("Skriv ett kommando nedan")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color(naviHex: "a8ff78").opacity(0.3))
            Text("root@209.38.98.107")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.15))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    @ViewBuilder
    private func terminalLine(_ line: TerminalLine) -> some View {
        let text: String
        let color: Color
        let prefix: String

        switch line.type {
        case .command:
            text   = line.text
            color  = Color(naviHex: "a8ff78")
            prefix = "$ "
        case .output:
            text   = line.text
            color  = Color.white.opacity(0.8)
            prefix = ""
        case .error:
            text   = line.text
            color  = Color(naviHex: "ff6b6b")
            prefix = ""
        case .info:
            text   = line.text
            color  = Color.white.opacity(0.35)
            prefix = "  "
        }

        return Text(prefix + text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .textSelection(.enabled)
    }

    private func submit() async {
        let cmd = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        inputText = ""
        focused   = false
        await brain.execCommand(cmd)
    }
}

// MARK: - BrainSessionsView (multi-session wrapper)

struct BrainSessionsView: View {
    let mode: BrainSessionMode
    @StateObject private var brain = NaviBrainService.shared
    @State private var activeSessionId: UUID?

    private var sessions: [BrainSession] {
        brain.sessionsFor(mode)
    }

    private var activeSession: BrainSession? {
        if let id = activeSessionId { return sessions.first { $0.id == id } }
        return sessions.first
    }

    private var accentColor: Color {
        Color(naviHex: mode.accentHex)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Session picker bar
            if sessions.count > 1 || !sessions.isEmpty {
                sessionPicker
                Divider().opacity(0.08)
            }

            // Active session chat
            if let session = activeSession {
                BrainChatView(session: session, mode: mode)
            } else {
                Spacer()
            }
        }
        .onAppear {
            if sessions.isEmpty {
                let session = brain.createBrainSession(mode: mode)
                activeSessionId = session.id
            } else if activeSessionId == nil {
                activeSessionId = sessions.first?.id
            }
        }
    }

    var sessionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sessions) { session in
                    Button {
                        withAnimation(NaviTheme.Spring.quick) { activeSessionId = session.id }
                    } label: {
                        HStack(spacing: 5) {
                            if session.isSending {
                                ProgressView()
                                    .scaleEffect(0.45)
                                    .tint(accentColor)
                            } else {
                                Circle()
                                    .fill(session.messages.isEmpty
                                          ? Color.secondary.opacity(0.2)
                                          : accentColor.opacity(0.5))
                                    .frame(width: 6, height: 6)
                            }
                            Text(session.name)
                                .font(.system(size: 11, weight: activeSessionId == session.id ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundColor(activeSessionId == session.id
                                         ? accentColor
                                         : .secondary.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(activeSessionId == session.id
                                    ? accentColor.opacity(0.1)
                                    : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            let id = session.id
                            if activeSessionId == id {
                                activeSessionId = sessions.first { $0.id != id }?.id
                            }
                            brain.removeBrainSession(id)
                            // If we removed the last session, create a fresh one
                            if brain.sessionsFor(mode).isEmpty {
                                let fresh = brain.createBrainSession(mode: mode)
                                activeSessionId = fresh.id
                            }
                        } label: {
                            Label("Ta bort session", systemImage: "trash")
                        }
                        Button {
                            withAnimation(NaviTheme.Spring.quick) {
                                brain.clearSession(session)
                            }
                        } label: {
                            Label("Rensa historik", systemImage: "eraser")
                        }
                    }
                }

                // New session button
                Button {
                    let session = brain.createBrainSession(mode: mode)
                    withAnimation(NaviTheme.Spring.quick) { activeSessionId = session.id }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(accentColor.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.chatBackground)
    }
}

// MARK: - BrainChatView (single session chat)

struct BrainChatView: View {
    @ObservedObject var session: BrainSession
    let mode: BrainSessionMode

    @StateObject private var brain = NaviBrainService.shared
    @State private var inputText   = ""
    @State private var showCompletion = false
    @FocusState private var focused: Bool

    private var messages: [BrainMessage] { session.messages }
    private var isSending: Bool { session.isSending }
    private var modelLabel: String { mode.displayName }
    private var accentColor: Color { Color(naviHex: mode.accentHex) }
    private var avatarIcon: String { mode.icon }

    private var opusAPIKey: String? {
        mode == .opus ? KeychainManager.shared.anthropicAPIKey : nil
    }
    private var hasOpusKey: Bool {
        mode != .opus || opusAPIKey != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Opus cost bar
            if mode == .opus && (brain.opusCostUSD > 0 || brain.opusTokensTotal > 0) {
                opusCostBar
                Divider().opacity(0.08)
            }
            messageList
            Divider().opacity(0.1)
            inputBar
        }
    }

    // MARK: - Opus Cost Bar

    var opusCostBar: some View {
        HStack(spacing: 14) {
            Label(String(format: "$%.6f", brain.opusCostUSD),
                  systemImage: "dollarsign.circle.fill")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(naviHex: "B06AFF").opacity(0.7))

            if brain.opusTokensTotal > 0 {
                Label("\(brain.opusTokensTotal) tokens",
                      systemImage: "text.bubble")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(naviHex: "B06AFF").opacity(0.05))
    }

    // MARK: - Message list

    var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { msg in
                            messageRow(msg).id(msg.id)
                        }
                    }

                    if isSending {
                        HStack {
                            thinkingIndicator
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            Spacer()
                        }
                        .id("thinking")
                    }

                    if showCompletion && !isSending {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(NaviTheme.success)
                            Text("Klar")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(NaviTheme.success.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(NaviTheme.success.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .transition(.scale.combined(with: .opacity))
                        .id("completion")
                    }

                    Color.clear.frame(height: 1).id("brainBottom")
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("brainBottom", anchor: .bottom)
                }
            }
            .onChange(of: isSending) { sending in
                if sending {
                    showCompletion = false
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                } else {
                    // Show completion indicator briefly when model finishes
                    if !messages.isEmpty, messages.last?.role == .assistant {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showCompletion = true
                        }
                        // Auto-hide after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { showCompletion = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: avatarIcon)
                    .font(.system(size: 26))
                    .foregroundColor(accentColor.opacity(0.8))
            }
            VStack(spacing: 5) {
                Text(modelLabel)
                    .font(NaviTheme.heading(16))
                    .foregroundColor(.primary)

                if mode == .minimax {
                    Text("Kraftfull reasoning-modell på din server")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else if mode == .qwen {
                    Text("MiMo-V2-Flash, Devstral-2512, Llama 3.3 70B (gratis)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else if mode == .opus {
                    Text("Claude på din server — agerar bara på begäran")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    if !hasOpusKey {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text("Ingen Anthropic API-nyckel — lägg till i Inställningar")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(NaviTheme.warning)
                        .padding(.top, 4)
                    }
                }

                if !brain.isConnected {
                    Text("⚠ Servern är offline")
                        .font(.system(size: 12))
                        .foregroundColor(NaviTheme.warning)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, 28)
    }

    // MARK: - Message row

    @ViewBuilder
    func messageRow(_ msg: BrainMessage) -> some View {
        if msg.role == .user {
            HStack(alignment: .bottom) {
                Spacer(minLength: 56)
                userBubble(msg)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: avatarIcon)
                        .font(.system(size: 12))
                        .foregroundColor(accentColor)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    // Tool call strip (shown if model executed tools)
                    if let tools = msg.toolCalls, !tools.isEmpty {
                        toolCallStrip(tools: tools)
                    }

                    MarkdownTextView(text: msg.content)
                        .equatable()
                        .textSelection(.enabled)

                    HStack(spacing: 4) {
                        if let model = msg.model {
                            Text(model.components(separatedBy: "/").last ?? model)
                                .foregroundColor(.secondary.opacity(0.35))
                        }
                        if let tokens = msg.tokens, tokens > 0 {
                            if msg.model != nil {
                                Text("·").foregroundColor(.secondary.opacity(0.25))
                            }
                            Text("\(tokens) tok")
                                .foregroundColor(.secondary.opacity(0.35))
                        }
                        // Opus: show per-message cost
                        if mode == .opus, let cost = msg.cost, cost > 0 {
                            Text("·").foregroundColor(.secondary.opacity(0.25))
                            Text(String(format: "$%.6f", cost))
                                .foregroundColor(Color(naviHex: "B06AFF").opacity(0.5))
                        }
                        // Copy button
                        Spacer()
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = msg.content
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(msg.content, forType: .string)
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 10))
                }
                Spacer(minLength: 28)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    /// Visual strip showing which tools the model executed — enhanced with icons and expandable
    @ViewBuilder
    func toolCallStrip(tools: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.7))
                Text("\(tools.count) verktyg kördes")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accentColor.opacity(0.7))
                Spacer()
                // POST indicator
                Text("ReAct")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor.opacity(0.4))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(accentColor.opacity(0.08))
                    .cornerRadius(3)
            }
            ForEach(Array(tools.prefix(6).enumerated()), id: \.offset) { idx, tool in
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(NaviTheme.success.opacity(0.6))
                    Image(systemName: toolIcon(tool))
                        .font(.system(size: 9))
                        .foregroundColor(accentColor.opacity(0.5))
                    Text(tool)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(accentColor.opacity(0.65))
                        .lineLimit(1)
                }
            }
            if tools.count > 6 {
                Text("+ \(tools.count - 6) till…")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accentColor.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private func toolIcon(_ tool: String) -> String {
        if tool.hasPrefix("bash") || tool.hasPrefix("run_command") { return "terminal" }
        if tool.hasPrefix("read_file")  { return "doc.text" }
        if tool.hasPrefix("write_file") { return "square.and.pencil" }
        if tool.hasPrefix("list_files") { return "folder" }
        return "wrench"
    }

    func userBubble(_ msg: BrainMessage) -> some View {
        Text(msg.content)
            .font(NaviTheme.body(15))
            .foregroundColor(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.userBubble)
            .cornerRadius(NaviTheme.Radius.bubble)
            .textSelection(.enabled)
    }

    // MARK: - Thinking indicator

    var thinkingIndicator: some View {
        let tool = brain.liveStatus?.active == true ? brain.liveStatus?.tool : nil
        let elapsed = session.elapsedSeconds
        // Route to the right visual based on the active tool (or default to .thinking)
        let state = tool.map { ActivityState.fromTool($0) } ?? .thinking

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                NaviVisualActivity(state: state)

                // Elapsed time + human-readable tool label
                HStack(spacing: 5) {
                    if elapsed > 0 {
                        Text(elapsed < 60 ? "\(elapsed)s" : "\(elapsed / 60)m \(elapsed % 60)s")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    if let tool, !tool.isEmpty {
                        Text("· \(tool.liveToolPillText)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.32))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
            }
        )
    }

    // MARK: - Input bar

    var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                withAnimation(NaviTheme.Spring.quick) {
                    brain.clearSession(session)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(messages.isEmpty
                                     ? .secondary.opacity(0.2)
                                     : .secondary.opacity(0.4))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(messages.isEmpty)

            TextField("Meddelande till \(modelLabel)…",
                      text: $inputText,
                      axis: .vertical)
                .font(NaviTheme.body(15))
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(NaviTheme.Radius.md)

            Button {
                Task { await send() }
            } label: {
                ZStack {
                    Circle()
                        .fill(canSend ? accentColor : Color.primary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.55)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(canSend ? .white : .secondary.opacity(0.25))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.chatBackground)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
            && brain.isConnected
            && hasOpusKey
    }

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        focused   = false
        let anthropicKey = mode == .opus ? opusAPIKey : nil
        await brain.sendToSession(session, prompt: text, anthropicKey: anthropicKey)
    }
}

// MARK: - LogsView

struct LogsView: View {
    @StateObject private var brain = NaviBrainService.shared

    var body: some View {
        VStack(spacing: 0) {
            if brain.isLoadingLogs && brain.logs.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text("Hämtar loggar…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if brain.logs.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary.opacity(0.2))
                    Text("Inga loggar ännu")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Aktivitet på servern visas här")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(brain.logs) { entry in
                                logRow(entry)
                                    .id(entry.id)
                                Divider().opacity(0.06).padding(.horizontal, 14)
                            }
                        }
                        .padding(.vertical, 4)
                        Color.clear.frame(height: 1).id("logsBottom")
                    }
                    .onChange(of: brain.logs.count) { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("logsBottom", anchor: .bottom)
                        }
                    }
                }
            }

            Divider().opacity(0.1)

            // Footer bar
            HStack(spacing: 8) {
                if brain.isLoadingLogs {
                    ProgressView().scaleEffect(0.55)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 5, height: 5)
                }
                Text(brain.isLoadingLogs ? "Uppdaterar…" : "Uppdateras var 10:e sek")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.35))
                Spacer()
                if !brain.logs.isEmpty {
                    Text("\(brain.logs.count) poster")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.3))
                }
                Button {
                    Task { await brain.fetchLogs() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Uppdatera")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(NaviTheme.accent.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(NaviTheme.accent.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(brain.isLoadingLogs)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.chatBackground)
        }
    }

    @ViewBuilder
    private func logRow(_ entry: BrainLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {

            // Action badge
            Text(entry.displayAction.prefix(8))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(badgeColor(entry.actionColor))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(badgeColor(entry.actionColor).opacity(0.12))
                .cornerRadius(4)
                .frame(minWidth: 56, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayDetails)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    // Project tag
                    Text(entry.displayProject)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.45))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3)

                    // Token count (if available)
                    if let tokens = entry.tokens, tokens > 0 {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.2))
                        Text("\(tokens) tok")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.35))
                    }
                }
            }

            Spacer(minLength: 0)

            // Timestamp
            if let ts = entry.timestamp {
                Text(formatTimestamp(ts))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.3))
                    .padding(.top, 3)
                    .frame(minWidth: 50, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func badgeColor(_ key: String) -> Color {
        switch key {
        case "error":   return Color(naviHex: "ff6b6b")
        case "opus":    return Color(naviHex: "B06AFF")
        case "minimax": return NaviTheme.accent
        case "qwen":    return Color(naviHex: "5B8DEF")
        case "warning": return NaviTheme.warning
        default:        return Color(naviHex: "94A3B8")
        }
    }

    private func formatTimestamp(_ ts: String) -> String {
        // Try to extract HH:MM:SS from ISO 8601 (e.g. "2025-01-01T14:32:11.000Z")
        if let tIdx = ts.firstIndex(of: "T") {
            let after = ts[ts.index(after: tIdx)...]
            return String(after.prefix(8))
        }
        return String(ts.suffix(8))
    }
}

// MARK: - MessagesView
// Shows messages from the server — autonomous run reports, health alerts, etc.
// Minimax (server manager) sends these via the /messages endpoint.

struct MessagesView: View {
    @StateObject private var brain = NaviBrainService.shared
    @State private var isComposing = false
    @State private var composeTitle = ""
    @State private var composeBody = ""
    @FocusState private var composeFocused: Bool

    private let accentColor = Color(naviHex: "FF9F43")

    var body: some View {
        VStack(spacing: 0) {
            if brain.isLoadingMessages && brain.serverMessages.isEmpty {
                VStack(spacing: 14) {
                    ProgressView().scaleEffect(0.9)
                    Text("Hämtar meddelanden…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if brain.serverMessages.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary.opacity(0.2))
                    Text("Inga meddelanden")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Minimax rapporterar autonoma körningar och serverhälsa här")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(brain.serverMessages) { msg in
                                messageRow(msg)
                                    .id(msg.id)
                                Divider().opacity(0.07).padding(.horizontal, 14)
                            }
                        }
                        .padding(.vertical, 4)
                        Color.clear.frame(height: 1).id("msgsBottom")
                    }
                }
            }

            // Compose panel (for manual notes/messages to server)
            if isComposing {
                Divider().opacity(0.1)
                VStack(spacing: 8) {
                    TextField("Titel (valfri)", text: $composeTitle)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    TextEditor(text: $composeBody)
                        .font(.system(size: 12))
                        .frame(height: 80)
                        .focused($composeFocused)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, 12)
                    HStack(spacing: 8) {
                        Button("Avbryt") {
                            isComposing = false
                            composeTitle = ""
                            composeBody = ""
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)

                        Spacer()

                        Button("Skicka") {
                            let title = composeTitle.isEmpty ? "Anteckning" : composeTitle
                            let body = composeBody
                            Task { await brain.postServerMessage(title: title, body: body, type: "info") }
                            isComposing = false
                            composeTitle = ""
                            composeBody = ""
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(accentColor)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                        .disabled(composeBody.isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .background(accentColor.opacity(0.04))
            }

            Divider().opacity(0.1)

            // Footer bar
            HStack(spacing: 8) {
                if brain.isLoadingMessages {
                    ProgressView().scaleEffect(0.55)
                } else {
                    Circle()
                        .fill(accentColor.opacity(0.4))
                        .frame(width: 5, height: 5)
                }
                Text(brain.isLoadingMessages ? "Uppdaterar…" : "\(brain.serverMessages.count) meddelanden")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.35))

                Spacer()

                // Compose button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isComposing.toggle()
                        if isComposing { composeFocused = true }
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundColor(accentColor.opacity(0.7))
                }
                .buttonStyle(.plain)

                // Refresh button
                Button {
                    Task { await brain.fetchServerMessages() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Uppdatera")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(accentColor.opacity(0.6))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accentColor.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(brain.isLoadingMessages)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.chatBackground)
        }
        .onAppear {
            Task { await brain.fetchServerMessages() }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: ServerMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Type icon
            Image(systemName: msg.typeIcon)
                .font(.system(size: 12))
                .foregroundColor(msgColor(msg.typeColor))
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                // Title + model
                HStack(spacing: 6) {
                    Text(msg.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))

                    Text(msg.displayModel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.45))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3)

                    if !msg.displayProject.isEmpty {
                        Text(msg.displayProject)
                            .font(.system(size: 10))
                            .foregroundColor(accentColor.opacity(0.6))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(accentColor.opacity(0.08))
                            .cornerRadius(3)
                    }
                }

                // Body
                Text(msg.body)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            // Timestamp
            if let ts = msg.timestamp {
                Text(formatMsgTimestamp(ts))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.3))
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func msgColor(_ key: String) -> Color {
        switch key {
        case "error":   return Color(naviHex: "ff6b6b")
        case "warning": return NaviTheme.warning
        case "minimax": return NaviTheme.accent
        case "qwen":    return Color(naviHex: "5B8DEF")
        case "opus":    return Color(naviHex: "B06AFF")
        default:        return Color(naviHex: "FF9F43")
        }
    }

    private func formatMsgTimestamp(_ ts: String) -> String {
        if let tIdx = ts.firstIndex(of: "T") {
            let after = ts[ts.index(after: tIdx)...]
            return String(after.prefix(5))
        }
        return String(ts.suffix(5))
    }
}

// MARK: - ServerTasksView (launch & monitor persistent server tasks)

struct ServerTasksView: View {
    @StateObject private var brain = NaviBrainService.shared
    @State private var taskInput = ""
    @State private var selectedModel: ServerTaskModel = .minimax
    @State private var showBatchPanel = false
    @State private var batchInput = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pending queue strip
            if !brain.pendingTaskQueue.isEmpty {
                pendingQueueStrip
                Divider().opacity(0.08)
            }
            taskList
            Divider().opacity(0.1)
            taskInputBar
        }
    }

    // MARK: - Pending Queue Strip

    var pendingQueueStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("\(brain.pendingTaskQueue.count) köade")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                Divider().frame(height: 12).opacity(0.3)
                ForEach(brain.pendingTaskQueue) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.model.icon)
                            .font(.system(size: 9))
                        Text(item.prompt.prefix(30).description + (item.prompt.count > 30 ? "…" : ""))
                            .font(.system(size: 10))
                        Button {
                            brain.removeQueuedPrompt(item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(Color(naviHex: item.model.accentColor).opacity(0.8))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color(naviHex: item.model.accentColor).opacity(0.08))
                    .cornerRadius(5)
                }
                Button {
                    brain.clearPendingQueue()
                } label: {
                    Text("Rensa kö")
                        .font(.system(size: 10))
                        .foregroundColor(NaviTheme.error.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Task List

    var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if brain.serverTasks.isEmpty {
                    emptyState
                } else {
                    ForEach(brain.serverTasks) { task in
                        taskRow(task)
                        Divider().opacity(0.06).padding(.horizontal, 14)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(naviHex: "4CAF50").opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(Color(naviHex: "4CAF50").opacity(0.8))
            }
            VStack(spacing: 5) {
                Text("Serveruppgifter")
                    .font(NaviTheme.heading(16))
                    .foregroundColor(.primary)
                Text("Starta en uppgift som kör på servern.\nDu kan stänga appen — servern arbetar vidare.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                if !brain.isConnected {
                    Text("Servern är offline")
                        .font(.system(size: 12))
                        .foregroundColor(NaviTheme.warning)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    func taskRow(_ task: ServerTask) -> some View {
        let color = Color(naviHex: task.model.accentColor)

        HStack(alignment: .top, spacing: 10) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor(task.status).opacity(0.12))
                    .frame(width: 32, height: 32)
                if task.status.isActive {
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(color)
                } else {
                    Image(systemName: statusIcon(task.status))
                        .font(.system(size: 13))
                        .foregroundColor(statusColor(task.status))
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                // Model + status
                HStack(spacing: 6) {
                    Image(systemName: task.model.icon)
                        .font(.system(size: 10))
                        .foregroundColor(color)
                    Text(task.model.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(color)
                    Spacer()
                    Text(task.status.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(statusColor(task.status))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusColor(task.status).opacity(0.1))
                        .cornerRadius(4)
                }

                // Prompt
                Text(task.prompt)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(3)

                // Progress info
                HStack(spacing: 8) {
                    if let dur = task.durationString {
                        Text(dur)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    if task.toolCallCount > 0 {
                        Text("\(task.toolCallCount) verktyg")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    if let progress = task.progressInfo {
                        Text(progress)
                            .font(.system(size: 10))
                            .foregroundColor(color.opacity(0.7))
                    }
                    Spacer()

                    // Cancel button for active tasks
                    if task.status.isActive {
                        Button {
                            Task { await brain.cancelServerTask(task.serverTaskId ?? task.id) }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Result or error
                if let result = task.result, !result.isEmpty {
                    Text(result)
                        .font(.system(size: 12))
                        .foregroundColor(NaviTheme.success.opacity(0.8))
                        .lineLimit(5)
                        .padding(.top, 2)
                }
                if let error = task.error, !error.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(NaviTheme.error.opacity(0.8))
                            .lineLimit(3)
                        Spacer()
                        Button {
                            withAnimation { brain.dismissTask(task.id) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(NaviTheme.error.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !task.status.isActive {
                Button(role: .destructive) {
                    withAnimation { brain.dismissTask(task.id) }
                } label: {
                    Label("Ta bort", systemImage: "trash")
                }
            }
        }
        #endif
    }

    private func statusColor(_ status: ServerTaskStatus) -> Color {
        switch status {
        case .starting: return NaviTheme.warning
        case .running:  return Color(naviHex: "5B8DEF")
        case .completed: return NaviTheme.success
        case .failed:   return NaviTheme.error
        case .cancelled: return .secondary
        }
    }

    private func statusIcon(_ status: ServerTaskStatus) -> String {
        switch status {
        case .starting:  return "hourglass"
        case .running:   return "play.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    // MARK: - Input Bar

    var taskInputBar: some View {
        VStack(spacing: 0) {
            // Batch queue panel (collapsible)
            if showBatchPanel {
                batchQueuePanel
                Divider().opacity(0.08)
            }

            VStack(spacing: 8) {
                // Model picker + controls
                HStack(spacing: 0) {
                    ForEach(ServerTaskModel.allCases, id: \.self) { model in
                        Button {
                            withAnimation(NaviTheme.Spring.quick) { selectedModel = model }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: model.icon)
                                    .font(.system(size: 10))
                                Text(model.displayName)
                                    .font(.system(size: 11, weight: selectedModel == model ? .semibold : .regular))
                            }
                            .foregroundColor(selectedModel == model
                                             ? Color(naviHex: model.accentColor)
                                             : .secondary.opacity(0.5))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selectedModel == model
                                        ? Color(naviHex: model.accentColor).opacity(0.1)
                                        : Color.clear)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()

                    // Batch queue toggle
                    Button {
                        withAnimation(NaviTheme.Spring.quick) { showBatchPanel.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet.clipboard")
                                .font(.system(size: 10))
                            Text("Kö")
                                .font(.system(size: 10, weight: .medium))
                            if !brain.pendingTaskQueue.isEmpty {
                                Text("\(brain.pendingTaskQueue.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 14, height: 14)
                                    .background(Color(naviHex: "4CAF50"))
                                    .clipShape(Circle())
                            }
                        }
                        .foregroundColor(showBatchPanel ? Color(naviHex: "4CAF50") : .secondary.opacity(0.5))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(showBatchPanel ? Color(naviHex: "4CAF50").opacity(0.1) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    if !brain.serverTasks.filter({ !$0.status.isActive }).isEmpty {
                        Button {
                            withAnimation { brain.clearCompletedTasks() }
                        } label: {
                            Text("Rensa")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.4))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)

                // Single-task input field + send
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Beskriv uppgiften...", text: $taskInput, axis: .vertical)
                        .font(NaviTheme.body(15))
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(NaviTheme.Radius.md)

                    Button {
                        Task { await startTask() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(canStart
                                      ? Color(naviHex: selectedModel.accentColor)
                                      : Color.primary.opacity(0.08))
                                .frame(width: 36, height: 36)
                            if brain.isStartingTask {
                                ProgressView()
                                    .scaleEffect(0.55)
                                    .tint(.white)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(canStart ? .white : .secondary.opacity(0.25))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStart)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .padding(.top, 8)
        }
        .background(Color.chatBackground)
    }

    // MARK: - Batch Queue Panel

    var batchQueuePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.number")
                    .font(.system(size: 11))
                Text("Batch-kö")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("En prompt per rad · separera med ---")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .foregroundColor(Color(naviHex: "4CAF50"))

            // Multi-line prompt input
            ZStack(alignment: .topLeading) {
                TextEditor(text: $batchInput)
                    .font(.system(size: 13))
                    .frame(height: 120)
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(naviHex: "4CAF50").opacity(0.2), lineWidth: 1)
                    )
                if batchInput.isEmpty {
                    Text("Ange en uppgift per rad.\nAnvänd --- för att separera.\n\nExempel:\nFixa bugg i LoginView\n---\nLägg till dark mode\n---\nSkriv tester för API")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.3))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 8) {
                // Parse and show count
                let prompts = parseBatchPrompts(batchInput)
                if !prompts.isEmpty {
                    Text("\(prompts.count) uppgifter")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(naviHex: "4CAF50").opacity(0.8))
                }
                Spacer()

                Button {
                    batchInput = ""
                } label: {
                    Text("Rensa")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(batchInput.isEmpty)

                // Queue all button
                Button {
                    let prompts = parseBatchPrompts(batchInput)
                    guard !prompts.isEmpty else { return }
                    let key = selectedModel == .opus ? KeychainManager.shared.anthropicAPIKey : nil
                    brain.enqueuePrompts(prompts, model: selectedModel, anthropicKey: key)
                    batchInput = ""
                    withAnimation(NaviTheme.Spring.quick) { showBatchPanel = false }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 12))
                        Text("Köa alla (\(parseBatchPrompts(batchInput).count))")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(parseBatchPrompts(batchInput).isEmpty ? .secondary : .white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(parseBatchPrompts(batchInput).isEmpty
                                ? Color.primary.opacity(0.08)
                                : Color(naviHex: "4CAF50"))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(parseBatchPrompts(batchInput).isEmpty || !brain.isConnected)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(naviHex: "4CAF50").opacity(0.04))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Parse a multi-line text into individual prompts (split by blank lines or "---")
    private func parseBatchPrompts(_ text: String) -> [String] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }
        // Split on "---" separator (full line) or double newlines
        let parts = cleaned
            .components(separatedBy: "\n---\n")
            .flatMap { $0.components(separatedBy: "\n\n") }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canStart: Bool {
        !taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !brain.isStartingTask
            && brain.isConnected
    }

    private func startTask() async {
        let text = taskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        taskInput = ""
        focused = false

        let anthropicKey = selectedModel == .opus ? KeychainManager.shared.anthropicAPIKey : nil
        await brain.startServerTask(prompt: text, model: selectedModel, anthropicKey: anthropicKey)
    }
}

// MARK: - Preview

#Preview("ServerView") {
    ServerView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
