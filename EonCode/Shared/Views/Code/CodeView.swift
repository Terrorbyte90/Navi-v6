import SwiftUI

// MARK: - CodeView
// Code generation with pipeline agent. Model selection now properly syncs.

struct CodeView: View {
    @StateObject private var agent = CodeAgent.shared
    @StateObject private var settings = SettingsStore.shared
    @State private var inputText = ""
    @State private var showModelPicker = false
    @FocusState private var inputFocused: Bool

    /// The model to use — defaults to the user's chosen default model,
    /// updated when the user picks a different model in the popover.
    @State private var selectedModel: ClaudeModel = .sonnet46

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.08)

            if agent.usedFallback {
                fallbackNotice
            }

            messagesArea
        }
        .background(Color.chatBackground)
        .onAppear {
            // FIX: Use the user's default model instead of hardcoded .sonnet46
            selectedModel = settings.defaultModel
        }
    }

    // MARK: - Top bar — Claude style

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Kod")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            // Model picker — shows current model, grouped by provider
            Menu {
                Section("Anthropic") {
                    ForEach(ClaudeModel.anthropicModels) { model in
                        modelButton(model)
                    }
                }
                Section("xAI / Grok") {
                    ForEach(ClaudeModel.xaiModels) { model in
                        modelButton(model)
                    }
                }
                Section("OpenRouter") {
                    ForEach(ClaudeModel.openRouterModels) { model in
                        modelButton(model)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(selectedModel.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.surfaceHover)
                )
            }
            .buttonStyle(.plain)

            // Opus review toggle
            Button {
                agent.opusReviewEnabled.toggle()
            } label: {
                Image(systemName: agent.opusReviewEnabled ? "shield.checkmark.fill" : "shield")
                    .font(.system(size: 14))
                    .foregroundColor(agent.opusReviewEnabled ? .accentNavi : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            #if os(macOS)
            .help(agent.opusReviewEnabled ? "Opus-granskning aktiv" : "Aktivera Opus-kodgranskning")
            #endif

            // Stop button
            if agent.isRunning {
                Button { agent.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14))
                        .foregroundColor(NaviTheme.error)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .animation(NaviTheme.Spring.smooth, value: agent.isRunning)
    }

    @ViewBuilder
    private func modelButton(_ model: ClaudeModel) -> some View {
        Button {
            selectedModel = model
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
        }
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
                        inputBar.background(Color.chatBackground)
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
                        inputBar.background(Color.chatBackground)
                    }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ThinkingOrb(size: 64, isAnimating: false)

            VStack(spacing: 8) {
                Text("Kod")
                    .font(.system(size: 24, weight: .bold))
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.surfaceHover.opacity(0.6))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
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
        .foregroundColor(NaviTheme.warning)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NaviTheme.warningBg)
    }

    // MARK: - Input bar — Claude style

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
            .padding(.vertical, 10)
            .padding(.leading, 12)

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
            .padding(.trailing, 8)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespaces).isEmpty || agent.isRunning
    }

    // MARK: - Send — passes selected model to agent

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !agent.isRunning else { return }
        inputText = ""
        dismissKeyboard()

        if agent.activeProject == nil {
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
                .font(.system(size: 15.5))
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
            ThinkingOrb(size: 24, isAnimating: false)
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
            ThinkingOrb(size: 24, isAnimating: true)

            VStack(alignment: .leading, spacing: 4) {
                Text(phase.displayName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.7))
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
