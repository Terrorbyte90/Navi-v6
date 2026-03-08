import SwiftUI
import WebKit

// MARK: - BrowserView

struct BrowserView: View {
    @StateObject private var agent = BrowserAgent.shared

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        VStack(spacing: 0) {
            BrowserAddressBar(agent: agent)
            Divider().opacity(0.15)
            ZStack(alignment: .bottom) {
                WebViewContainer(agent: agent)
                BrowserAgentPanel(agent: agent)
            }
        }
        .background(Color.chatBackground)
    }
    #endif

    // MARK: - iOS Layout

    private var iOSLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                BrowserAddressBar(agent: agent)
                WebViewContainer(agent: agent)
                    .ignoresSafeArea(edges: .bottom)
            }
            BrowserAgentPanel(agent: agent)
        }
        .background(Color.chatBackground)
    }
}

// MARK: - Address Bar

struct BrowserAddressBar: View {
    @ObservedObject var agent: BrowserAgent
    @State private var isEditing = false
    @State private var urlText = ""
    @FocusState private var urlFocused: Bool

    private var isHTTPS: Bool { agent.currentURL?.scheme == "https" }

    private var displayURL: String {
        guard let url = agent.currentURL else { return "" }
        let str = url.absoluteString
        if str.hasPrefix("https://") { return String(str.dropFirst(8)) }
        if str.hasPrefix("http://")  { return String(str.dropFirst(7)) }
        return str
    }

    private var displayHost: String { agent.currentURL?.host ?? "" }

    var body: some View {
        HStack(spacing: 6) {
            navButtons
            addressCapsule
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.chatBackground)
    }

    // MARK: Back / Forward

    private var navButtons: some View {
        HStack(spacing: 0) {
            navButton(icon: "chevron.left",  enabled: agent.webView.canGoBack)  { agent.webView.goBack() }
            navButton(icon: "chevron.right", enabled: agent.webView.canGoForward) { agent.webView.goForward() }
        }
    }

    private func navButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(enabled ? .primary : .secondary.opacity(0.25))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Address capsule

    private var addressCapsule: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 8) {
                // Lock / globe icon
                Image(systemName: isHTTPS ? "lock.fill" : "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHTTPS ? .green.opacity(0.85) : .secondary.opacity(0.45))

                if isEditing {
                    TextField("Search or enter address", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($urlFocused)
                        .onSubmit { commitNavigation() }
                        .onAppear {
                            urlText = agent.currentURL?.absoluteString ?? ""
                            urlFocused = true
                        }
                        .foregroundColor(.primary)
                } else {
                    Text(displayURL.isEmpty
                         ? "Search or enter address"
                         : (displayHost.isEmpty ? displayURL : displayHost))
                        .font(.system(size: 14))
                        .foregroundColor(displayURL.isEmpty ? .secondary.opacity(0.4) : .primary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture { isEditing = true }
                }

                // Reload / stop button
                if !displayURL.isEmpty && !isEditing {
                    Button {
                        if agent.webView.isLoading { agent.webView.stopLoading() }
                        else { agent.webView.reload() }
                    } label: {
                        Image(systemName: agent.webView.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isEditing
                                    ? Color.accentNavi.opacity(0.5)
                                    : Color.primary.opacity(0.08),
                                lineWidth: isEditing ? 1.5 : 0.5
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isEditing)

            // Page load progress integrated into bottom edge of address bar
            if agent.loadingProgress > 0 && agent.loadingProgress < 1 {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            LinearGradient(
                                colors: [Color.accentNavi, Color.accentNavi.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * agent.loadingProgress, height: 2)
                        .animation(.easeInOut(duration: 0.3), value: agent.loadingProgress)
                }
                .frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func commitNavigation() {
        isEditing = false
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let urlStr: String
        if raw.contains(".") && !raw.contains(" ") {
            urlStr = raw.hasPrefix("http") ? raw : "https://\(raw)"
        } else {
            let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            urlStr = "https://www.google.com/search?q=\(encoded)"
        }
        Task { try? await agent.navigate(to: urlStr) }
    }
}

// MARK: - Agent Panel (bottom overlay, no sheet)

struct BrowserAgentPanel: View {
    @ObservedObject var agent: BrowserAgent
    @State private var goalInput = ""
    @FocusState private var inputFocused: Bool
    @State private var dotPulsing = false
    @State private var showLog = false

    private var isIdle: Bool    { if case .idle    = agent.status { return true }; return false }
    private var isWorking: Bool { switch agent.status { case .working, .planning: return true; default: return false } }
    private var isWaiting: Bool { if case .waitingForUser = agent.status { return true }; return false }
    private var isComplete: Bool { if case .complete = agent.status { return true }; return false }
    private var isFailed: Bool  { if case .failed  = agent.status { return true }; return false }

    private var canSend: Bool {
        !goalInput.trimmingCharacters(in: .whitespaces).isEmpty && (!isWorking || isWaiting)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Log drawer (toggle)
            if showLog {
                logPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Glass panel
            glassPanel
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isWorking)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showLog)
    }

    // MARK: - Glass panel

    private var glassPanel: some View {
        VStack(spacing: 0) {
            agentStatusRow
            inputRow
        }
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.chatBackground.opacity(0.4))
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentNavi.opacity(isWorking ? 0.18 : 0.06), Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
        )
    }

    // MARK: - Status row

    @ViewBuilder
    private var agentStatusRow: some View {
        if !isIdle || !agent.currentThought.isEmpty {
            HStack(spacing: 10) {
                // Pulsing status dot
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 18, height: 18)
                        .scaleEffect(dotPulsing && isWorking ? 1.5 : 1.0)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }
                .onChange(of: isWorking) { _, working in
                    if working {
                        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                            dotPulsing = true
                        }
                    } else {
                        dotPulsing = false
                    }
                }

                // Thought / status text
                Text(agent.currentThought.isEmpty ? statusText : agent.currentThought)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary.opacity(0.75))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Session cost badge
                if agent.sessionCost.apiCalls > 0 {
                    Text(agent.sessionCost.formatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                }

                // Log toggle
                Button {
                    showLog.toggle()
                } label: {
                    Image(systemName: showLog ? "chevron.down.circle.fill" : "list.bullet.circle")
                        .font(.system(size: 16))
                        .foregroundColor(showLog ? Color.accentNavi : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)

                // Cancel button while working
                if isWorking {
                    Button { agent.cancel() } label: {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.1))
                                .frame(width: 26, height: 26)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red.opacity(0.75))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Input row

    private var inputRow: some View {
        let borderColor: Color = isWaiting
            ? Color.yellow.opacity(0.5)
            : inputFocused ? Color.accentNavi.opacity(0.45) : Color.primary.opacity(0.08)
        let borderWidth: CGFloat = (inputFocused || isWaiting) ? 1.5 : 0.5

        return HStack(alignment: .bottom, spacing: 10) {
            // Status icon
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 32, height: 32)
                Image(systemName: statusIconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(statusColor)
            }

            TextField(placeholder, text: $goalInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit { handleSend() }
                .foregroundColor(isWaiting ? Color.yellow : .primary)
                .disabled(isWorking && !isWaiting)
                .padding(.vertical, 8)

            sendButton
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(borderColor, lineWidth: borderWidth)
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var sendButton: some View {
        let active = canSend
        let fg: Color = active ? (isWaiting ? .black : Color.chatBackground) : .secondary.opacity(0.3)
        let bg: Color = active ? (isWaiting ? Color.yellow : Color.primary) : Color.primary.opacity(0.07)

        Button { handleSend() } label: {
            ZStack {
                Circle().fill(bg).frame(width: 32, height: 32)
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(fg)
            }
        }
        .buttonStyle(.plain)
        .disabled(!active)
        .animation(.easeInOut(duration: 0.15), value: active)
    }

    // MARK: - Log panel

    private var logPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Agent log")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if !agent.log.isEmpty {
                    Text("\(agent.log.count) steps")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
            }

            // Log entries
            if agent.log.isEmpty {
                HStack {
                    Image(systemName: "cpu.fill")
                        .foregroundColor(.secondary.opacity(0.25))
                    Text("No activity yet")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(.ultraThinMaterial)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(agent.log.suffix(60)) { entry in
                                BrowserLogEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: agent.log.count) { _, _ in
                        if let last = agent.log.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                .background(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: - Helpers

    private func handleSend() {
        let text = goalInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        goalInput = ""
        inputFocused = false
        if isWaiting {
            agent.provideUserInput(text)
        } else {
            if isComplete || isFailed { agent.status = .idle }
            agent.execute(goal: text)
        }
    }

    private var statusColor: Color {
        switch agent.status {
        case .working, .planning: return .green
        case .waitingForUser:     return .yellow
        case .complete:           return .accentNavi
        case .failed:             return .red
        case .idle:               return .secondary
        }
    }

    private var statusIconName: String {
        switch agent.status {
        case .working, .planning: return "cpu.fill"
        case .waitingForUser:     return "questionmark"
        case .complete:           return "checkmark"
        case .failed:             return "exclamationmark"
        case .idle:               return "globe"
        }
    }

    private var statusText: String {
        switch agent.status {
        case .planning:              return "Planning…"
        case .working(let s, let t): return "Step \(s) of \(t)"
        case .waitingForUser:        return "Waiting for your input"
        case .complete:              return "Done!"
        case .failed:                return "Failed"
        case .idle:                  return ""
        }
    }

    private var placeholder: String {
        switch agent.status {
        case .waitingForUser: return agent.userQuestion.isEmpty ? "Type your answer…" : agent.userQuestion
        case .working, .planning: return "Agent is working…"
        case .complete:       return "Give a new goal…"
        case .failed:         return "Try again with a different goal…"
        case .idle:           return "Give Navi a goal to perform…"
        }
    }
}

// MARK: - Preview

#Preview("BrowserView") {
    BrowserView()
}
