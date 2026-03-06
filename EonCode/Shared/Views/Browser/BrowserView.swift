import SwiftUI
import WebKit

// MARK: - BrowserView

struct BrowserView: View {
    @StateObject private var agent = BrowserAgent.shared
    @State private var showControlSheet = false
    @State private var controlSheetDetent: PresentationDetent = .medium

    var body: some View {
        #if os(iOS)
        iOSLayout
        #else
        macOSLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    var macOSLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                BrowserAddressBar(agent: agent)
                Divider()
                WebViewContainer(agent: agent)
            }
            BrowserGlassBar(agent: agent, showControlSheet: $showControlSheet)
        }
        .sheet(isPresented: $showControlSheet) {
            BrowserControlSheet(agent: agent)
                .frame(minWidth: 540, minHeight: 480)
        }
    }
    #endif

    // MARK: - iOS

    var iOSLayout: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                BrowserAddressBar(agent: agent)
                Divider()
                WebViewContainer(agent: agent)
                    .ignoresSafeArea(edges: .bottom)
            }
            BrowserGlassBar(agent: agent, showControlSheet: $showControlSheet)
        }
        .background(Color.chatBackground)
        .sheet(isPresented: $showControlSheet) {
            BrowserControlSheet(agent: agent)
                .presentationDetents([.medium, .large], selection: $controlSheetDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
        }
    }
}

// MARK: - Glass Bottom Bar

struct BrowserGlassBar: View {
    @ObservedObject var agent: BrowserAgent
    @Binding var showControlSheet: Bool
    @State private var input = ""
    @FocusState private var isFocused: Bool
    @State private var dotPulsing = false
    @State private var barExpanded = false

    private var isIdle: Bool { if case .idle = agent.status { return true }; return false }
    private var isComplete: Bool { if case .complete = agent.status { return true }; return false }
    private var isFailed: Bool { if case .failed = agent.status { return true }; return false }
    private var isWorking: Bool {
        switch agent.status { case .working, .planning: return true; default: return false }
    }
    private var isWaiting: Bool { if case .waitingForUser = agent.status { return true }; return false }
    private var canSend: Bool { !input.trimmingCharacters(in: .whitespaces).isEmpty && (!isWorking || isWaiting) }

    var body: some View {
        VStack(spacing: 0) {
            controlChip
            mainBar
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWorking)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaiting)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: agent.canTakeControl)
    }

    @ViewBuilder
    private var controlChip: some View {
        if agent.canTakeControl && (isWorking || isWaiting) {
            Button { showControlSheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: isWaiting ? "questionmark.circle.fill" : "cpu.fill")
                        .font(.system(size: 12))
                    Text(isWaiting ? "Navi behöver svar" : "Se vad Navi gör")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(isWaiting ? .black : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isWaiting ? Color.yellow : Color.chatBackground)
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                )
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var mainBar: some View {
        VStack(spacing: 0) {
            progressBar
            VStack(spacing: 8) {
                statusRow
                inputPill
            }
        }
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                Rectangle().fill(Color.primary.opacity(0.015))
            }
            .overlay(alignment: .top) { Divider() }
        )
    }

    @ViewBuilder
    private var progressBar: some View {
        if isWorking && agent.loadingProgress > 0 && agent.loadingProgress < 1 {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 1)
                    .fill(LinearGradient(
                        colors: [Color.accentEon, Color.accentEon.opacity(0.4)],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * agent.loadingProgress, height: 2)
                    .animation(.easeInOut(duration: 0.3), value: agent.loadingProgress)
            }
            .frame(height: 2)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if !isIdle || !agent.currentThought.isEmpty {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.2)).frame(width: 14, height: 14)
                        .scaleEffect(dotPulsing && isWorking ? 1.4 : 1.0)
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                }
                .onChange(of: isWorking) { working in
                    if working {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dotPulsing = true }
                    } else { dotPulsing = false }
                }
                Text(agent.currentThought.isEmpty ? statusText : agent.currentThought)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary.opacity(0.75))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if agent.sessionCost.apiCalls > 0 {
                    Text(agent.sessionCost.formatted)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                }
                if isWorking {
                    Button { agent.cancel() } label: {
                        ZStack {
                            Circle().fill(Color.primary.opacity(0.07)).frame(width: 24, height: 24)
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var inputPill: some View {
        let borderColor: Color = isWaiting ? Color.yellow.opacity(0.5) : isFocused ? Color.accentEon.opacity(0.45) : Color.primary.opacity(0.1)
        let borderWidth: CGFloat = (isFocused || isWaiting) ? 1.5 : 0.5
        HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06)).frame(width: 32, height: 32)
                Image(systemName: statusIconName).font(.system(size: 14, weight: .medium)).foregroundColor(statusColor)
            }
            TextField(placeholderText, text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit { handleSend() }
                .foregroundColor(isWaiting ? Color.yellow : .primary)
                .disabled(isWorking && !isWaiting)
                .padding(.vertical, 8)
            sendButton
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.inputBackground)
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(borderColor, lineWidth: borderWidth))
        )
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    @ViewBuilder
    private var sendButton: some View {
        let fg: Color = canSend ? (isWaiting ? .black : Color.chatBackground) : .secondary.opacity(0.3)
        let bg: Color = canSend ? (isWaiting ? Color.yellow : Color.primary) : Color.primary.opacity(0.08)
        Button { handleSend() } label: {
            ZStack {
                Circle().fill(bg).frame(width: 32, height: 32)
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundColor(fg)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }

    private var statusColor: Color {
        switch agent.status {
        case .working, .planning: return .green
        case .waitingForUser:     return .yellow
        case .complete:           return .accentEon
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
        case .planning:              return "Planerar…"
        case .working(let s, let t): return "Steg \(s) av \(t)"
        case .waitingForUser:        return "Väntar på ditt svar"
        case .complete:              return "Klart!"
        case .failed:                return "Misslyckades"
        case .idle:                  return ""
        }
    }

    private var placeholderText: String {
        switch agent.status {
        case .waitingForUser: return agent.userQuestion.isEmpty ? "Skriv ditt svar…" : agent.userQuestion
        case .working, .planning: return "Agenten arbetar…"
        case .complete:       return "Ge ett nytt mål…"
        case .failed:         return "Försök igen med ett annat mål…"
        case .idle:           return "Ge Navi ett mål att utföra…"
        }
    }

    private func handleSend() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        isFocused = false
        if isWaiting {
            agent.provideUserInput(text)
        } else {
            if isComplete || isFailed { agent.status = .idle }
            Task { await agent.execute(goal: text) }
        }
    }
}

// MARK: - Control Sheet (pull up to change goal / see log)

struct BrowserControlSheet: View {
    @ObservedObject var agent: BrowserAgent
    @Environment(\.dismiss) private var dismiss
    @State private var newGoal = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentEon)
                Text("Kontrollpanel")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                // Session cost
                if agent.sessionCost.apiCalls > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(agent.sessionCost.formatted)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentEon)
                        Text("\(agent.sessionCost.apiCalls) anrop")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.1)

            // Current goal
            if !agent.currentGoal.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aktivt mål")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(agent.currentGoal)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            // Sub-goals
            if !agent.subGoals.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delmål")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)

                    ForEach(agent.subGoals) { sg in
                        HStack(spacing: 8) {
                            Image(systemName: subGoalIcon(sg.status))
                                .font(.system(size: 11))
                                .foregroundColor(subGoalColor(sg.status))
                                .frame(width: 16)
                            Text(sg.description)
                                .font(.system(size: 12))
                                .foregroundColor(sg.status == .active ? .primary : .secondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.vertical, 8)
            }

            // Change goal
            VStack(alignment: .leading, spacing: 8) {
                Text("Ändra mål")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("Nytt mål…", text: $newGoal)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(Color.inputBackground)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.inputBorder, lineWidth: 0.5)
                        )

                    Button {
                        guard !newGoal.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        agent.updateGoal(newGoal)
                        newGoal = ""
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(newGoal.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary.opacity(0.3) : .accentEon)
                    }
                    .buttonStyle(.plain)
                    .disabled(newGoal.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().opacity(0.1)

            // Agent log
            BrowserAgentLogView(agent: agent)

            // Actions
            HStack(spacing: 16) {
                Button {
                    agent.cancel()
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").font(.system(size: 10))
                        Text("Stoppa").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Spacer()

                Button { dismiss() } label: {
                    Text("Stäng")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.chatBackground)
    }

    private func subGoalIcon(_ status: BrowserSubGoal.SubGoalStatus) -> String {
        switch status {
        case .pending:   return "circle"
        case .active:    return "circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    private func subGoalColor(_ status: BrowserSubGoal.SubGoalStatus) -> Color {
        switch status {
        case .pending:   return .secondary.opacity(0.4)
        case .active:    return .accentEon
        case .completed: return .green
        case .failed:    return .red
        }
    }
}

// MARK: - Address Bar

struct BrowserAddressBar: View {
    @ObservedObject var agent: BrowserAgent
    @State private var editingURL = false
    @State private var urlText = ""
    @FocusState private var urlFocused: Bool

    var displayURL: String {
        guard let url = agent.currentURL else { return "" }
        let str = url.absoluteString
        return str.hasPrefix("https://") ? String(str.dropFirst(8)) :
               str.hasPrefix("http://")  ? String(str.dropFirst(7)) : str
    }

    var displayHost: String {
        agent.currentURL?.host ?? ""
    }

    var body: some View {
        HStack(spacing: 8) {
            // Nav buttons
            HStack(spacing: 2) {
                Button { agent.webView.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(agent.webView.canGoBack ? .primary : .secondary.opacity(0.25))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!agent.webView.canGoBack)

                Button { agent.webView.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(agent.webView.canGoForward ? .primary : .secondary.opacity(0.25))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!agent.webView.canGoForward)
            }

            // URL capsule
            HStack(spacing: 8) {
                // SSL / globe icon
                Image(systemName: agent.currentURL?.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(agent.currentURL?.scheme == "https" ? .green.opacity(0.8) : .secondary.opacity(0.5))

                if editingURL {
                    TextField("Sök eller ange webbadress", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($urlFocused)
                        .onSubmit { navigateToInput() }
                        .onAppear {
                            urlText = agent.currentURL?.absoluteString ?? ""
                            urlFocused = true
                        }
                } else {
                    // Show just the host for a cleaner look, full URL on tap
                    Text(displayURL.isEmpty ? "Sök eller ange webbadress" : (displayHost.isEmpty ? displayURL : displayHost))
                        .font(.system(size: 14))
                        .foregroundColor(displayURL.isEmpty ? .secondary.opacity(0.4) : .primary.opacity(0.85))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture { editingURL = true }
                }

                // Reload button
                if !displayURL.isEmpty && !editingURL {
                    Button { agent.webView.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.inputBackground)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                editingURL ? Color.accentEon.opacity(0.5) : Color.primary.opacity(0.08),
                                lineWidth: editingURL ? 1.5 : 0.5
                            )
                    )
            )
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.15), value: editingURL)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.chatBackground)
    }

    private func navigateToInput() {
        editingURL = false
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

#Preview("BrowserView") {
    BrowserView()
}
