import SwiftUI
#if os(iOS)
import PhotosUI
#endif

// MARK: - CodeView
// Code generation with pipeline agent. Model selection now properly syncs.

struct CodeView: View {
    @StateObject private var agent = CodeAgent.shared
    @StateObject private var settings = SettingsStore.shared
    @State private var inputText = ""
    @State private var showModelPicker = false
    @State private var selectedImages: [Data] = []
    @State private var isShowingFilePicker = false
    @FocusState private var inputFocused: Bool
    #if os(iOS)
    @State private var photoPickerItems: [PhotosPickerItem] = []
    #endif

    /// The model to use — persisted via settings.defaultModel
    @State private var selectedModel: ClaudeModel = .sonnet46
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.08)

            if agent.usedFallback {
                fallbackNotice
            }

            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                    Text(error)
                        .font(NaviTheme.bodyFont(size: 12.5))
                        .lineLimit(3)
                    Spacer()
                    Button { errorMessage = nil } label: {
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

            messagesArea
        }
        .background(Color.chatBackground)
        .onAppear {
            selectedModel = settings.defaultModel
        }
    }

    // MARK: - Top bar — Claude style with inline phase progress

    private var topBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Kod")
                    .font(NaviTheme.headingFont(size: 17))
                    .foregroundColor(.primary)

                Spacer()

                // New session button
                if agent.activeProject != nil {
                    Button {
                        withAnimation(NaviTheme.Spring.smooth) {
                            agent.activeProject = nil
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary.opacity(0.55))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .help("Ny kodsession")
                    #endif
                }

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
                            .font(.system(size: 13, weight: .medium, design: .rounded))
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

            // Phase progress bar when running
            if agent.isRunning && agent.phase != .idle {
                PhaseProgressBar(currentPhase: agent.phase)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(NaviTheme.Spring.smooth, value: agent.isRunning)
        .animation(NaviTheme.Spring.smooth, value: agent.phase)
    }

    @ViewBuilder
    private func modelButton(_ model: ClaudeModel) -> some View {
        let hasKey = Self.hasAPIKey(for: model)
        Button {
            selectedModel = model
            settings.defaultModel = model
            errorMessage = nil
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(model.displayName)
                            .font(.system(size: 14, weight: .medium))
                        if !hasKey {
                            Image(systemName: "key.slash")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                        }
                    }
                    Text(hasKey ? model.description : "Saknar API-nyckel")
                        .font(.system(size: 11))
                        .foregroundColor(hasKey ? .secondary : .orange)
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

    private static func hasAPIKey(for model: ClaudeModel) -> Bool {
        switch model.provider {
        case .anthropic:   return KeychainManager.shared.anthropicAPIKey?.isEmpty == false
        case .xai:         return KeychainManager.shared.xaiAPIKey?.isEmpty == false
        case .openRouter:  return KeychainManager.shared.openRouterAPIKey?.isEmpty == false
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
                                    .equatable()
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
        VStack(spacing: 24) {
            Spacer()

            ThinkingOrb(size: 72, isAnimating: false)

            VStack(spacing: 10) {
                Text("Kod")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Beskriv ett projekt — Navi planerar, bygger\noch pushar till GitHub åt dig.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(spacing: 8) {
                quickStartChip("Starta en iOS ToDo-app med iCloud sync", icon: "iphone")
                quickStartChip("Python CLI-tool för JSON-transformation", icon: "terminal")
                quickStartChip("React dashboard för realtidsdata", icon: "chart.bar")
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickStartChip(_ text: String, icon: String = "sparkle") -> some View {
        Button {
            inputText = text
            inputFocused = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.accentNavi.opacity(0.6))
                    .frame(width: 20)
                Text(text)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surfaceHover.opacity(0.5))
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

    // MARK: - Input bar — with attachment support

    private var inputBar: some View {
        VStack(spacing: 8) {
            // Image thumbnails
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, data in
                            InputImageThumb(data: data) { selectedImages.remove(at: idx) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                #if os(iOS)
                PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 5, matching: .images) {
                    ZStack {
                        Circle().fill(Color.primary.opacity(0.05)).frame(width: 32, height: 32)
                        Image(systemName: selectedImages.isEmpty ? "photo" : "photo.badge.checkmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary.opacity(0.5))
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

                // Attachment menu
                Menu {
                    #if os(macOS)
                    Button { } label: { Label("Bild", systemImage: "photo") }
                    #endif
                    Button { isShowingFilePicker = true } label: {
                        Label("Fil", systemImage: "doc")
                    }
                } label: {
                    ZStack {
                        Circle().fill(Color.primary.opacity(0.05)).frame(width: 32, height: 32)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary.opacity(0.4))
                    }
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif

                TextField(
                    agent.activeProject == nil
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
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    private var sendDisabled: Bool {
        inputText.trimmingCharacters(in: .whitespaces).isEmpty || agent.isRunning
    }

    // MARK: - Send — passes selected model to agent

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !agent.isRunning else { return }

        // Validate API key
        if !Self.hasAPIKey(for: selectedModel) {
            let provider = selectedModel.providerDisplayName
            errorMessage = "Ingen \(provider) API-nyckel. Gå till Inställningar."
            return
        }

        inputText = ""
        errorMessage = nil
        dismissKeyboard()

        if agent.activeProject == nil {
            agent.handleMessage(text: text, model: selectedModel)
        } else {
            agent.continueChat(text: text, model: selectedModel)
        }
    }
}

// MARK: - CodeMessageRow

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
                MarkdownTextView(text: message.content)
                    .equatable()
                    .textSelection(.enabled)

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

// MARK: - CodeStreamingRow

struct CodeStreamingRow: View {
    let text: String
    let phase: PipelinePhase

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 24, isAnimating: true)

            VStack(alignment: .leading, spacing: 6) {
                // Phase badge with pulse indicator
                PhasePill(phase: phase)

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
