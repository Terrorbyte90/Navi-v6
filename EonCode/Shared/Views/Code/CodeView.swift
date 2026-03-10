import SwiftUI

// MARK: - CodeView
// Main Code view: pipeline-based project creation with live agent feedback.

struct CodeView: View {
    @StateObject private var agent = CodeAgent.shared
    @State private var inputText = ""
    @State private var selectedModel: ClaudeModel = .sonnet46
    @State private var showModelPicker = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            Divider()

            // Qwen fallback notice
            if agent.usedFallback {
                fallbackNotice
            }

            // Message area (inline progress card + input bar via safeAreaInset)
            messagesArea
        }
        .background(Color.chatBackground)
        .onAppear { selectedModel = SettingsStore.shared.defaultModel }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Kod")
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            // Model picker
            Button {
                showModelPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(selectedModel.displayName)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.sidebarBackground))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModelPicker) {
                modelPickerPopover
            }

            // Opus review toggle
            Button {
                agent.opusReviewEnabled.toggle()
            } label: {
                Image(systemName: agent.opusReviewEnabled ? "shield.fill" : "shield")
                    .font(.system(size: 14))
                    .foregroundColor(agent.opusReviewEnabled ? .accentNavi : .secondary)
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(agent.opusReviewEnabled ? "Opus-granskning aktiv — klicka för att stänga av" : "Aktivera Opus-kodgranskning efter bygget")
            #endif

            // Stop button
            if agent.isRunning {
                Button { agent.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .animation(.easeInOut(duration: 0.2), value: agent.isRunning)
    }

    // MARK: - Messages area

    private var messagesArea: some View {
        Group {
            if let proj = agent.activeProject, !proj.messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(proj.messages) { msg in
                                CodeMessageRow(message: msg)
                                    .id(msg.id)
                            }
                            if !agent.streamingText.isEmpty {
                                CodeStreamingRow(text: agent.streamingText, phase: agent.phase)
                                    .id("streaming")
                            }
                            // Inline progress card (shown during active pipeline)
                            if agent.isRunning && agent.phase != .idle && agent.phase != .done {
                                CodeProgressCard(agent: agent)
                                    .id("progressCard")
                                    .transition(.opacity)
                            }
                            Color.clear.frame(height: 8).id("bottomAnchor")
                        }
                        .padding(.vertical, 8)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        inputBar
                            .background(Color.chatBackground)
                    }
                    .onChange(of: agent.streamingText) { _, _ in
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                    .onChange(of: agent.isRunning) { _, running in
                        if running { proxy.scrollTo("progressCard", anchor: .bottom) }
                    }
                    .onChange(of: proj.messages.count) { _, _ in
                        if let last = proj.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            } else {
                ScrollView { emptyState }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        inputBar
                            .background(Color.chatBackground)
                    }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentNavi.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentNavi, .accentNavi.opacity(0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(spacing: 8) {
                Text("Kod")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Beskriv ett projekt. Navi bygger det åt dig.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 8) {
                quickStartChip("Starta en iOS ToDo-app med iCloud sync")
                quickStartChip("Python CLI-tool för JSON-transformation")
                quickStartChip("React dashboard för realtidsdata")
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickStartChip(_ text: String) -> some View {
        Button {
            inputText = text
            inputFocused = true
        } label: {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.sidebarBackground)
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fallback notice

    private var fallbackNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11))
            Text("Qwen3-Coder timeout — \(agent.actualModel.displayName) används")
                .font(.system(size: 12))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                agent.activeProject == nil
                    ? "Beskriv ett projekt att bygga…"
                    : "Fortsätt konversationen…",
                text: $inputText,
                axis: .vertical
            )
            .lineLimit(1...6)
            .font(.system(size: 15))
            .focused($inputFocused)
            .onSubmit { sendMessage() }
            .submitLabel(.send)

            Button { sendMessage() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        sendDisabled
                            ? AnyShapeStyle(Color.secondary.opacity(0.3))
                            : AnyShapeStyle(Color.accentNavi)
                    )
            }
            .buttonStyle(.plain)
            .disabled(sendDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespaces).isEmpty || agent.isRunning
    }

    // MARK: - Model picker popover

    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Modell")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ForEach(ClaudeModel.allCases) { model in
                Button {
                    selectedModel = model
                    showModelPicker = false
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.system(size: 14, weight: .medium))
                            Text(model.description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if selectedModel == model {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.accentNavi)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if model != ClaudeModel.allCases.last {
                    Divider().padding(.horizontal, 16)
                }
            }
        }
        .frame(width: 280)
        .padding(.bottom, 8)
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !agent.isRunning else { return }
        inputText = ""
        if agent.activeProject == nil {
            // No active project — use intent detection to decide what to do
            agent.handleMessage(text: text, model: selectedModel)
        } else {
            agent.continueChat(text: text, model: selectedModel)
        }
    }
}

// MARK: - CodeMessageRow

struct CodeMessageRow: View {
    let message: PureChatMessage

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
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.userBubble)
                )
        }
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentNavi.opacity(0.12))
                    .frame(width: 28, height: 28)
                Text("N")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.accentNavi)
            }
            MarkdownTextView(text: message.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - CodeStreamingRow

struct CodeStreamingRow: View {
    let text: String
    let phase: PipelinePhase

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentNavi.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: phase.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentNavi)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(phase.displayName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)

                if text.isEmpty {
                    TypingIndicator()
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
