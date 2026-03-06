import SwiftUI

// MARK: - Agent View (Autonomous agents)

struct AgentView: View {
    @StateObject private var runner = AutonomousAgentRunner.shared
    @StateObject private var projectStore = ProjectStore.shared
    @State private var selectedAgentID: UUID? = nil
    @State private var showCreateSheet = false

    var selectedAgent: AgentDefinition? {
        guard let id = selectedAgentID else { return nil }
        return runner.agents.first { $0.id == id }
    }

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    var macLayout: some View {
        HSplitView {
            agentList
                .frame(minWidth: 260, maxWidth: 320)
            if let agent = selectedAgent {
                AgentDetailView(agentID: agent.id)
            } else {
                agentEmptyState
            }
        }
    }
    #endif

    // MARK: - iOS

    var iOSLayout: some View {
        NavigationView {
            agentList
                .navigationTitle("Agenter")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showCreateSheet = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                #endif
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateAgentSheet(projects: projectStore.projects)
        }
    }

    // MARK: - Agent list

    var agentList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agenter")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.surfaceHover, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if runner.agents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Inga agenter")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Skapa en agent och ge den ett mål att arbeta mot autonomt.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Skapa agent") { showCreateSheet = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(runner.agents) { agent in
                            AgentRowView(
                                agent: agent,
                                isSelected: selectedAgentID == agent.id,
                                onSelect: { selectedAgentID = agent.id },
                                onStart: { runner.start(agent.id) },
                                onPause: { runner.pause(agent.id) },
                                onDelete: { runner.delete(agent.id) }
                            )
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background(Color.sidebarBackground)
        .sheet(isPresented: $showCreateSheet) {
            CreateAgentSheet(projects: projectStore.projects)
        }
    }

    var agentEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.2))
            Text("Välj en agent")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Välj en agent i listan för att se dess aktivitet och logg i realtid.")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBackground)
    }
}

// MARK: - Agent Row

struct AgentRowView: View {
    let agent: AgentDefinition
    let isSelected: Bool
    let onSelect: () -> Void
    let onStart: () -> Void
    let onPause: () -> Void
    let onDelete: () -> Void

    @State private var pulsing = false

    var statusColor: Color {
        switch agent.status {
        case .running:   return .green
        case .paused:    return .orange
        case .completed: return .blue
        case .failed:    return .red
        case .idle:      return .secondary
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Status indicator
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .scaleEffect(pulsing && agent.status.isActive ? 1.2 : 1.0)
                    Image(systemName: agent.status.isActive ? "cpu.fill" : "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(statusColor)
                }
                .onAppear {
                    if agent.status.isActive {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }
                }
                .onChange(of: agent.status.isActive) { active in
                    if active {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulsing = true }
                    } else { pulsing = false }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(agent.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(agent.status.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(statusColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(statusColor.opacity(0.12), in: Capsule())
                    }

                    if !agent.currentTaskDescription.isEmpty {
                        Text(agent.currentTaskDescription)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else if let projectName = agent.projectName {
                        Text(projectName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Text("Iter. \(agent.iterationCount)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                        if agent.totalCostSEK > 0 {
                            Text(String(format: "%.2f kr", agent.totalCostSEK))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.surfaceHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if agent.status.isActive {
                Button { onPause() } label: { Label("Pausa", systemImage: "pause.fill") }
            } else {
                Button { onStart() } label: { Label("Starta", systemImage: "play.fill") }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("Ta bort", systemImage: "trash") }
        }
    }
}

// MARK: - Agent Detail View

struct AgentDetailView: View {
    let agentID: UUID
    @StateObject private var runner = AutonomousAgentRunner.shared
    @State private var selectedTab: DetailTab = .log
    @State private var showEditSheet = false
    @State private var logScrollProxy: ScrollViewProxy? = nil

    enum DetailTab: String, CaseIterable {
        case log = "Logg"
        case goal = "Mål"
        case stats = "Statistik"
    }

    var agent: AgentDefinition? {
        runner.agents.first { $0.id == agentID }
    }

    var body: some View {
        guard let agent = agent else {
            return AnyView(Text("Agent borttagen").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity))
        }
        return AnyView(content(agent: agent))
    }

    @ViewBuilder
    func content(agent: AgentDefinition) -> some View {
        VStack(spacing: 0) {
            // Header
            agentHeader(agent: agent)
            Divider()

            // Tab bar
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if selectedTab == tab {
                                    Rectangle()
                                        .fill(Color.accentEon)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Divider()

            // Content
            switch selectedTab {
            case .log:   agentLogView(agent: agent)
            case .goal:  agentGoalView(agent: agent)
            case .stats: agentStatsView(agent: agent)
            }
        }
        .background(Color.chatBackground)
    }

    @ViewBuilder
    func agentHeader(agent: AgentDefinition) -> some View {
        HStack(spacing: 14) {
            // Avatar with pulsing ring
            ZStack {
                Circle()
                    .stroke(agentStatusColor(agent).opacity(0.3), lineWidth: 2)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(agentStatusColor(agent).opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 18))
                    .foregroundColor(agentStatusColor(agent))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(.system(size: 16, weight: .semibold))
                if !agent.currentTaskDescription.isEmpty {
                    Text(agent.currentTaskDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 8) {
                if agent.status.isActive {
                    Button { runner.pause(agentID) } label: {
                        Label("Pausa", systemImage: "pause.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else if agent.status == .paused || agent.status == .idle {
                    Button { runner.start(agentID) } label: {
                        Label("Starta", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                } else if agent.status == .completed || agent.status == .failed {
                    Button { runner.restart(agentID) } label: {
                        Label("Starta om", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentEon)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.accentEon.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                Button { showEditSheet = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.surfaceHover, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .sheet(isPresented: $showEditSheet) {
            if let a = agent as AgentDefinition? {
                EditAgentSheet(agent: a)
            }
        }
    }

    @ViewBuilder
    func agentLogView(agent: AgentDefinition) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(agent.runLog) { entry in
                        AgentLogEntryRow(entry: entry)
                            .id(entry.id)
                    }

                    // Live streaming indicator
                    if runner.streamingAgentID == agentID && !runner.streamingText.isEmpty {
                        AgentStreamingRow(text: runner.streamingText)
                            .id("streaming")
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear { logScrollProxy = proxy }
            .onChange(of: agent.runLog.count) { _ in
                withAnimation { proxy.scrollTo(agent.runLog.last?.id, anchor: .bottom) }
            }
            .onChange(of: runner.streamingText) { _ in
                withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    func agentGoalView(agent: AgentDefinition) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Mål", systemImage: "target")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(agent.goal)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .padding(14)
                        .background(Color.surfaceHover, in: RoundedRectangle(cornerRadius: 10))
                }

                if let projectName = agent.projectName {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Projekt", systemImage: "folder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(projectName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Modell", systemImage: "cpu")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(agent.model.displayName)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                }

                if agent.maxIterations > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Max iterationer", systemImage: "repeat")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("\(agent.maxIterations)")
                            .font(.system(size: 14))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    func agentStatsView(agent: AgentDefinition) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                statCard(title: "Iterationer", value: "\(agent.iterationCount)", icon: "repeat", color: .accentEon)
                statCard(title: "Tokens använda", value: "\(agent.totalTokensUsed)", icon: "text.word.spacing", color: .purple)
                statCard(title: "Total kostnad", value: String(format: "%.4f kr", agent.totalCostSEK), icon: "dollarsign.circle", color: .green)
                statCard(title: "Logg-poster", value: "\(agent.runLog.count)", icon: "list.bullet", color: .orange)
                if let lastActive = agent.lastActiveAt {
                    statCard(title: "Senast aktiv", value: RelativeDateTimeFormatter().localizedString(for: lastActive, relativeTo: Date()), icon: "clock", color: .secondary)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 15)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12)).foregroundColor(.secondary)
                Text(value).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.surfaceHover, in: RoundedRectangle(cornerRadius: 12))
    }

    func agentStatusColor(_ agent: AgentDefinition) -> Color {
        switch agent.status {
        case .running:   return .green
        case .paused:    return .orange
        case .completed: return .blue
        case .failed:    return .red
        case .idle:      return .secondary
        }
    }
}

// MARK: - Log entry row

struct AgentLogEntryRow: View {
    let entry: AgentRunEntry

    var icon: String {
        switch entry.type {
        case .thought:          return "lightbulb"
        case .action:           return "bolt"
        case .result:           return "checkmark.circle"
        case .tool:             return "terminal"
        case .error:            return "exclamationmark.triangle"
        case .milestone:        return "flag.fill"
        case .userMessage:      return "person.fill"
        case .assistantMessage: return "cpu.fill"
        }
    }

    var color: Color {
        switch entry.type {
        case .thought:          return .yellow
        case .action:           return .accentEon
        case .result:           return .green
        case .tool:             return .purple
        case .error:            return .red
        case .milestone:        return .orange
        case .userMessage:      return .secondary
        case .assistantMessage: return .primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Icon
            ZStack {
                Circle().fill(color.opacity(0.1)).frame(width: 22, height: 22)
                Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                if entry.type == .assistantMessage {
                    // Show assistant messages as markdown-like text
                    Text(String(entry.content.prefix(800)))
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                } else if entry.type == .tool {
                    Text(entry.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.purple)
                        .padding(6)
                        .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(entry.content)
                        .font(.system(size: 12))
                        .foregroundColor(entry.isError ? .red : .primary.opacity(0.85))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }

                Text(entry.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Live streaming row

struct AgentStreamingRow: View {
    let text: String
    @StateObject private var buffer = StreamingBuffer()
    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 22, height: 22)
                Image(systemName: "cpu.fill").font(.system(size: 10)).foregroundColor(.green)
            }
            .padding(.top, 1)

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(buffer.displayText)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineSpacing(3)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 2, height: 12)
                    .opacity(cursorVisible ? 1 : 0)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onChange(of: text) { buffer.update($0) }
        .onAppear {
            buffer.update(text)
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { cursorVisible = false }
        }
    }
}

// MARK: - Create Agent Sheet

struct CreateAgentSheet: View {
    let projects: [EonProject]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = AutonomousAgentRunner.shared

    @State private var name = ""
    @State private var goal = ""
    @State private var selectedProjectID: UUID? = nil
    @State private var selectedModel: ClaudeModel = .sonnet45
    @State private var maxIterations = 0
    @State private var autoRestart = false
    @State private var startImmediately = true

    var selectedProjectName: String? {
        projects.first { $0.id == selectedProjectID }?.name
    }

    var canCreate: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !goal.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Agentens namn", text: $name)
                } header: {
                    Text("Namn")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if goal.isEmpty {
                            Text("Beskriv vad agenten skall uppnå. Kan vara ett långt, detaljerat mål som tar timmar eller dagar att genomföra...")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $goal)
                            .font(.system(size: 14))
                            .frame(minHeight: 160)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("Mål")
                } footer: {
                    Text("Agenten arbetar autonomt tills målet är uppnått. Ge ett tydligt, detaljerat mål.")
                }

                Section("Projekt (valfritt)") {
                    Picker("Projekt", selection: $selectedProjectID) {
                        Text("Inget projekt").tag(UUID?.none)
                        ForEach(projects) { project in
                            Text(project.name).tag(UUID?.some(project.id))
                        }
                    }
                }

                Section("Modell") {
                    Picker("Modell", selection: $selectedModel) {
                        ForEach(ClaudeModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                }

                Section("Avancerat") {
                    Stepper(
                        maxIterations == 0 ? "Max iterationer: Obegränsat" : "Max iterationer: \(maxIterations)",
                        value: $maxIterations, in: 0...1000, step: 10
                    )
                    Toggle("Starta om vid fel", isOn: $autoRestart)
                    Toggle("Starta direkt", isOn: $startImmediately)
                }
            }
            .navigationTitle("Ny agent")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skapa") {
                        let agent = runner.create(
                            name: name.trimmingCharacters(in: .whitespaces),
                            goal: goal.trimmingCharacters(in: .whitespaces),
                            projectID: selectedProjectID,
                            projectName: selectedProjectName,
                            model: selectedModel,
                            maxIterations: maxIterations
                        )
                        if startImmediately { runner.start(agent.id) }
                        dismiss()
                    }
                    .disabled(!canCreate)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Edit Agent Sheet

struct EditAgentSheet: View {
    let agent: AgentDefinition
    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = AutonomousAgentRunner.shared

    @State private var name: String
    @State private var goal: String
    @State private var maxIterations: Int
    @State private var autoRestart: Bool

    init(agent: AgentDefinition) {
        self.agent = agent
        _name = State(initialValue: agent.name)
        _goal = State(initialValue: agent.goal)
        _maxIterations = State(initialValue: agent.maxIterations)
        _autoRestart = State(initialValue: agent.autoRestartOnFailure)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Namn") {
                    TextField("Namn", text: $name)
                }
                Section("Mål") {
                    TextEditor(text: $goal)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                }
                Section("Avancerat") {
                    Stepper(
                        maxIterations == 0 ? "Max: Obegränsat" : "Max: \(maxIterations)",
                        value: $maxIterations, in: 0...1000, step: 10
                    )
                    Toggle("Starta om vid fel", isOn: $autoRestart)
                }
                Section {
                    Button("Rensa logg", role: .destructive) {
                        var updated = agent
                        updated.runLog = []
                        runner.update(updated)
                    }
                }
            }
            .navigationTitle("Redigera agent")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        var updated = agent
                        updated.name = name.trimmingCharacters(in: .whitespaces)
                        updated.goal = goal.trimmingCharacters(in: .whitespaces)
                        updated.maxIterations = maxIterations
                        updated.autoRestartOnFailure = autoRestart
                        runner.update(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview("AgentView") {
    AgentView()
        .frame(width: 900, height: 600)
}
