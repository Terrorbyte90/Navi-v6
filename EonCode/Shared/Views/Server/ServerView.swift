import SwiftUI

// MARK: - ServerView

struct ServerView: View {
    @StateObject private var brain = NaviBrainService.shared
    @State private var selectedTab: ServerTab = .minimax
    @State private var showInfo = false

    enum ServerTab: String, CaseIterable {
        case terminal = "Terminal"
        case minimax  = "Minimax"
        case qwen     = "Qwen"
        case opus     = "Opus"
        case logs     = "Loggar"

        var icon: String {
            switch self {
            case .terminal: return "terminal.fill"
            case .minimax:  return "sparkles"
            case .qwen:     return "bolt.fill"
            case .opus:     return "cpu.fill"
            case .logs:     return "list.bullet.rectangle.fill"
            }
        }
        var accentColor: Color {
            switch self {
            case .terminal: return Color(naviHex: "a8ff78")
            case .minimax:  return NaviTheme.accent
            case .qwen:     return Color(naviHex: "5B8DEF")
            case .opus:     return Color(naviHex: "B06AFF")
            case .logs:     return Color(naviHex: "94A3B8")
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
                    Text("v3")
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
        case .terminal: return brain.isTerminalSending
        case .minimax:  return brain.isSendingMinimax
        case .qwen:     return brain.isSendingQwen
        case .opus:     return brain.isSendingOpus
        case .logs:     return brain.isLoadingLogs
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .terminal: TerminalView()
        case .minimax:  BrainChatView(mode: .minimax)
        case .qwen:     BrainChatView(mode: .qwen)
        case .opus:     BrainChatView(mode: .opus)
        case .logs:     LogsView()
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
                        InfoRow(label: "Qwen",     value: "DeepSeek R1 / Qwen3 (gratis)")
                        InfoRow(label: "Opus",     value: "Claude Sonnet 4.6 (Anthropic)")
                    }

                    infoCard("Endpoints") {
                        endpointRow("POST /ask",              desc: "Minimax chat")
                        endpointRow("POST /qwen/ask",         desc: "Qwen chat")
                        endpointRow("POST /opus/ask",         desc: "Opus-Brain chat")
                        endpointRow("POST /exec",             desc: "Shell-kommando")
                        endpointRow("GET  /costs",            desc: "Minimax kostnader")
                        endpointRow("GET  /opus/status",      desc: "Opus statistik")
                        endpointRow("GET  /logs",             desc: "Serverloggar")
                        endpointRow("GET  /repos",            desc: "GitHub repos")
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

// MARK: - BrainChatView (Minimax / Qwen / Opus)

struct BrainChatView: View {
    enum Mode { case minimax, qwen, opus }
    let mode: Mode

    @StateObject private var brain = NaviBrainService.shared
    @State private var inputText   = ""
    @FocusState private var focused: Bool

    private var messages: [BrainMessage] {
        switch mode {
        case .minimax: return brain.minimaxMessages
        case .qwen:    return brain.qwenMessages
        case .opus:    return brain.opusMessages
        }
    }
    private var isSending: Bool {
        switch mode {
        case .minimax: return brain.isSendingMinimax
        case .qwen:    return brain.isSendingQwen
        case .opus:    return brain.isSendingOpus
        }
    }
    private var modelLabel: String {
        switch mode {
        case .minimax: return "MiniMax M2.5"
        case .qwen:    return "DeepSeek R1 / Qwen3"
        case .opus:    return "Claude Sonnet 4.6"
        }
    }
    private var accentColor: Color {
        switch mode {
        case .minimax: return NaviTheme.accent
        case .qwen:    return Color(naviHex: "5B8DEF")
        case .opus:    return Color(naviHex: "B06AFF")
        }
    }
    private var avatarIcon: String {
        switch mode {
        case .minimax: return "sparkles"
        case .qwen:    return "bolt.fill"
        case .opus:    return "cpu.fill"
        }
    }
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
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isSending) { sending in
                if sending {
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
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

                switch mode {
                case .minimax:
                    Text("Kraftfull reasoning-modell på din server")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                case .qwen:
                    Text("Gratis kodningsmodell via OpenRouter")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                case .opus:
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

                    Text(msg.content)
                        .font(NaviTheme.body(15))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

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
                    }
                    .font(.system(size: 10))
                }
                Spacer(minLength: 28)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    /// Visual strip showing which tools the model executed
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
            }
            ForEach(tools.prefix(4), id: \.self) { tool in
                HStack(spacing: 5) {
                    Image(systemName: toolIcon(tool))
                        .font(.system(size: 8))
                        .foregroundColor(accentColor.opacity(0.5))
                    Text(tool)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(accentColor.opacity(0.65))
                        .lineLimit(1)
                }
            }
            if tools.count > 4 {
                Text("+ \(tools.count - 4) till…")
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

    // MARK: - Thinking indicator (shows live tool status when available)

    var thinkingIndicator: some View {
        let live = brain.liveStatus
        let hasLiveStatus = live?.active == true && live?.tool != nil

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                // Animated dots
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(accentColor.opacity(0.5))
                            .frame(width: 7, height: 7)
                            .scaleEffect(isSending ? 1.0 : 0.4)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.18),
                                value: isSending
                            )
                    }
                }
                // Rotating tool indicator
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10))
                    .foregroundColor(accentColor.opacity(0.4))
                    .rotationEffect(.degrees(isSending ? 360 : 0))
                    .animation(
                        .linear(duration: 2.0).repeatForever(autoreverses: false),
                        value: isSending
                    )
                // Activity label
                if hasLiveStatus, let iter = live?.iter {
                    Text("iter \(iter + 1)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(accentColor.opacity(0.5))
                } else {
                    Text(mode == .opus ? "Opus arbetar…" : mode == .minimax ? "Minimax arbetar…" : "Qwen arbetar…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }

            // Live tool call card
            if hasLiveStatus, let tool = live?.tool {
                HStack(spacing: 5) {
                    Image(systemName: toolIcon(tool))
                        .font(.system(size: 9))
                        .foregroundColor(accentColor.opacity(0.7))
                    Text(tool)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(accentColor.opacity(0.8))
                        .lineLimit(2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(accentColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hasLiveStatus)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(accentColor.opacity(0.06))
        .cornerRadius(10)
    }

    // MARK: - Input bar

    var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                withAnimation(NaviTheme.Spring.quick) {
                    switch mode {
                    case .minimax: brain.clearMinimaxHistory()
                    case .qwen:    brain.clearQwenHistory()
                    case .opus:    brain.clearOpusHistory()
                    }
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
        switch mode {
        case .minimax: await brain.sendMinimax(text)
        case .qwen:    await brain.sendQwen(text)
        case .opus:
            guard let key = opusAPIKey else { return }
            await brain.sendOpus(text, anthropicKey: key)
        }
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

// MARK: - Preview

#Preview("ServerView") {
    ServerView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}
