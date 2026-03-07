import SwiftUI

// MARK: - Agent View

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

    #if os(macOS)
    var macLayout: some View {
        HSplitView {
            agentList.frame(minWidth: 260, maxWidth: 320)
            if let agent = selectedAgent {
                AgentDetailView(agentID: agent.id)
            } else {
                agentEmptyState
            }
        }
    }
    #endif

    var iOSLayout: some View {
        NavigationView {
            agentList
                .navigationTitle("Agenter")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showCreateSheet = true } label: { Image(systemName: "plus") }
                    }
                }
                #endif
        }
    }

    // MARK: - Agent list

    var agentList: some View {
        VStack(spacing: 0) {
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
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()

            if runner.agents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 32)).foregroundColor(.secondary.opacity(0.3))
                    Text("Inga agenter")
                        .font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
                    Text("Skapa en agent och ge den ett långsiktigt mål att arbeta mot autonomt.")
                        .font(.system(size: 12)).foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center).padding(.horizontal, 20)
                    Button("Skapa agent") { showCreateSheet = true }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
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
                .font(.system(size: 48)).foregroundColor(.secondary.opacity(0.2))
            Text("Välj en agent")
                .font(.system(size: 18, weight: .semibold)).foregroundColor(.secondary)
            Text("Välj en agent i listan för att se aktivitet, logg och inställningar.")
                .font(.system(size: 14)).foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center).frame(maxWidth: 300)
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
                ZStack {
                    Circle().fill(statusColor.opacity(0.15)).frame(width: 34, height: 34)
                        .scaleEffect(pulsing && agent.status.isActive ? 1.2 : 1.0)
                    Image(systemName: agent.status.isActive ? "cpu.fill" : "cpu")
                        .font(.system(size: 14)).foregroundColor(statusColor)
                }
                .onAppear {
                    if agent.status.isActive {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulsing = true }
                    }
                }
                .onChange(of: agent.status.isActive) { active in
                    if active { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulsing = true } }
                    else { pulsing = false }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(agent.name)
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
                        Spacer()
                        Text(agent.status.displayName)
                            .font(.system(size: 10, weight: .medium)).foregroundColor(statusColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(statusColor.opacity(0.12), in: Capsule())
                    }
                    if !agent.currentTaskDescription.isEmpty {
                        Text(agent.currentTaskDescription)
                            .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                    } else if let pn = agent.projectName {
                        Text(pn).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                    }
                    // Cost row
                    HStack(spacing: 8) {
                        Text("Iter. \(agent.iterationCount)")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary.opacity(0.6))
                        if agent.grandTotalCostSEK > 0 {
                            Text(String(format: "%.3f kr", agent.grandTotalCostSEK))
                                .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary.opacity(0.6))
                        }
                        if agent.assignedWorkers > 1 {
                            Label("\(agent.assignedWorkers) workers", systemImage: "person.2.fill")
                                .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
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
    @ObservedObject private var runner = AutonomousAgentRunner.shared
    @State private var selectedTab: DetailTab = .log
    @State private var showEditSheet = false

    enum DetailTab: String, CaseIterable {
        case log = "Logg"
        case settings = "Inställningar"
        case stats = "Statistik"
    }

    var agent: AgentDefinition? { runner.agents.first { $0.id == agentID } }

    var body: some View {
        if let agent = agent {
            VStack(spacing: 0) {
                agentHeader(agent: agent)
                costBanner(agent: agent)
                Divider()
                tabBar
                Divider()
                tabContent(agent: agent)
            }
            .background(Color.chatBackground)
            .sheet(isPresented: $showEditSheet) {
                EditAgentSheet(agent: agent)
            }
        } else {
            Text("Agent borttagen").foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    @ViewBuilder
    func agentHeader(agent: AgentDefinition) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(statusColor(agent).opacity(0.3), lineWidth: 2).frame(width: 44, height: 44)
                Circle().fill(statusColor(agent).opacity(0.1)).frame(width: 40, height: 40)
                Image(systemName: "cpu.fill").font(.system(size: 18)).foregroundColor(statusColor(agent))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name).font(.system(size: 16, weight: .semibold))
                if !agent.currentTaskDescription.isEmpty {
                    Text(agent.currentTaskDescription)
                        .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(2)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                controlButton(agent: agent)
                Button { showEditSheet = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14)).foregroundColor(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.surfaceHover, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Cost banner (always visible)

    @ViewBuilder
    func costBanner(agent: AgentDefinition) -> some View {
        HStack(spacing: 0) {
            costCell(
                title: "Session",
                value: String(format: "%.4f kr", agent.sessionCostSEK),
                subtitle: "\(agent.sessionTokensUsed) tok",
                color: .accentEon
            )
            Divider().frame(height: 32)
            costCell(
                title: "Workers",
                value: String(format: "%.4f kr", agent.workerCostSEK),
                subtitle: "\(agent.workerTokensUsed) tok",
                color: .purple
            )
            Divider().frame(height: 32)
            costCell(
                title: "Totalt",
                value: String(format: "%.4f kr", agent.grandTotalCostSEK),
                subtitle: "\(agent.grandTotalTokens) tok",
                color: .green,
                bold: true
            )
            Divider().frame(height: 32)
            costCell(
                title: "Iter.",
                value: "\(agent.iterationCount)",
                subtitle: agent.maxIterations > 0 ? "av \(agent.maxIterations)" : "obegränsat",
                color: .orange
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.surfaceHover)
    }

    @ViewBuilder
    func costCell(title: String, value: String, subtitle: String, color: Color, bold: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: bold ? .bold : .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(subtitle)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // MARK: - Tab bar

    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab {
                                Rectangle().fill(Color.accentEon).frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    func tabContent(agent: AgentDefinition) -> some View {
        switch selectedTab {
        case .log:      agentLogView(agent: agent)
        case .settings: agentSettingsView(agent: agent)
        case .stats:    agentStatsView(agent: agent)
        }
    }

    // MARK: - Log tab

    @ViewBuilder
    func agentLogView(agent: AgentDefinition) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(agent.runLog) { entry in
                        AgentLogEntryRow(entry: entry).id(entry.id)
                    }
                    if runner.streamingAgentID == agentID && !runner.streamingText.isEmpty {
                        AgentStreamingRow(text: runner.streamingText).id("streaming")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: agent.runLog.count) { _ in
                proxy.scrollTo(agent.runLog.last?.id, anchor: .bottom)
            }
            .onChange(of: runner.streamingText) { _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    // MARK: - Settings tab

    @ViewBuilder
    func agentSettingsView(agent: AgentDefinition) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                AgentSettingsEditor(agentID: agentID)
            }
        }
    }

    // MARK: - Stats tab

    @ViewBuilder
    func agentStatsView(agent: AgentDefinition) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                // Cost breakdown card
                VStack(alignment: .leading, spacing: 12) {
                    Label("Kostnadsfördelning", systemImage: "dollarsign.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                    HStack(spacing: 12) {
                        costBreakdownBar(
                            label: "Orkestrator",
                            cost: agent.totalCostSEK,
                            total: agent.grandTotalCostSEK,
                            color: .accentEon
                        )
                        costBreakdownBar(
                            label: "Workers",
                            cost: agent.workerCostSEK,
                            total: agent.grandTotalCostSEK,
                            color: .purple
                        )
                    }
                }
                .padding(16)
                .background(Color.surfaceHover, in: RoundedRectangle(cornerRadius: 12))

                statCard("Iterationer",         "\(agent.iterationCount)",                                      "repeat",           .accentEon)
                statCard("Orkestrator-tokens",  "\(agent.totalTokensUsed)",                                     "text.word.spacing", .blue)
                statCard("Worker-tokens",       "\(agent.workerTokensUsed)",                                    "person.2.fill",    .purple)
                statCard("Totala tokens",       "\(agent.grandTotalTokens)",                                    "sum",              .primary)
                statCard("Orkestrator-kostnad", String(format: "%.5f kr", agent.totalCostSEK),                  "dollarsign",       .accentEon)
                statCard("Worker-kostnad",      String(format: "%.5f kr", agent.workerCostSEK),                 "dollarsign.circle", .purple)
                statCard("Total kostnad",       String(format: "%.5f kr", agent.grandTotalCostSEK),             "dollarsign.circle.fill", .green)
                statCard("Logg-poster",         "\(agent.runLog.count)",                                        "list.bullet",      .orange)
                if let la = agent.lastActiveAt {
                    statCard("Senast aktiv", RelativeDateTimeFormatter().localizedString(for: la, relativeTo: Date()), "clock", .secondary)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    func costBreakdownBar(label: String, cost: Double, total: Double, color: Color) -> some View {
        let fraction = total > 0 ? cost / total : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", fraction * 100))
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
            Text(String(format: "%.5f kr", cost))
                .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    func statCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12)).foregroundColor(.secondary)
                Text(value).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.surfaceHover, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    func statusColor(_ agent: AgentDefinition) -> Color {
        switch agent.status {
        case .running:   return .green
        case .paused:    return .orange
        case .completed: return .blue
        case .failed:    return .red
        case .idle:      return .secondary
        }
    }

    @ViewBuilder
    func controlButton(agent: AgentDefinition) -> some View {
        if agent.status.isActive {
            Button { runner.pause(agentID) } label: {
                Label("Pausa", systemImage: "pause.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else if agent.status == .paused || agent.status == .idle {
            Button { runner.start(agentID) } label: {
                Label("Starta", systemImage: "play.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.green)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else {
            Button { runner.restart(agentID) } label: {
                Label("Starta om", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.accentEon)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accentEon.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Agent Settings Editor (inline, live-saving)

struct AgentSettingsEditor: View {
    let agentID: UUID
    @StateObject private var runner = AutonomousAgentRunner.shared
    @StateObject private var projectStore = ProjectStore.shared

    // Local state mirrors agent settings
    @State private var name = ""
    @State private var goal = ""
    @State private var model: ClaudeModel = .sonnet45
    @State private var workerModel: ClaudeModel = .haiku
    @State private var assignedWorkers = 2
    @State private var maxTokensPerIteration = 8000
    @State private var maxIterations = 0
    @State private var iterationDelaySeconds = 1.0
    @State private var autoRestartOnFailure = false
    @State private var pauseOnUserQuestion = true
    @State private var verboseLogging = false
    @State private var autoCommitToGitHub = false
    @State private var githubBranch = "main"
    @State private var systemPromptAddition = ""
    @State private var maxHistoryMessages = 30
    @State private var memoryEnabled = true
    @State private var notifyOnCompletion = true
    @State private var notifyOnFailure = true
    @State private var notifyOnUserQuestion = true
    @State private var selectedProjectID: UUID? = nil
    @State private var loaded = false

    var agent: AgentDefinition? { runner.agents.first { $0.id == agentID } }

    var body: some View {
        VStack(spacing: 0) {
            if let agent = agent {
                Form {
                    // ── Identitet ──────────────────────────────────────────
                    Section {
                        TextField("Namn", text: $name)
                            .onChange(of: name) { save() }
                    } header: { Text("Namn") }

                    Section {
                        ZStack(alignment: .topLeading) {
                            if goal.isEmpty {
                                Text("Beskriv agentens mål…")
                                    .font(.system(size: 14)).foregroundColor(.secondary.opacity(0.5))
                                    .padding(.top, 8).padding(.leading, 4)
                            }
                            TextEditor(text: $goal)
                                .font(.system(size: 14))
                                .frame(minHeight: 100)
                                .scrollContentBackground(.hidden)
                                .onChange(of: goal) { save() }
                        }
                    } header: { Text("Mål") }

                    Section("Projekt") {
                        Picker("Projekt", selection: $selectedProjectID) {
                            Text("Inget projekt").tag(UUID?.none)
                            ForEach(projectStore.projects) { p in
                                Text(p.name).tag(UUID?.some(p.id))
                            }
                        }
                        .onChange(of: selectedProjectID) { save() }
                    }

                    // ── Modell & Workers ───────────────────────────────────
                    Section {
                        AgentModelCard(
                            label: "Agentens modell",
                            subtitle: "Orkestratorn — planerar och resonerar",
                            icon: "cpu.fill",
                            color: .accentEon,
                            selection: $model
                        )
                        .onChange(of: model) { save() }

                        AgentModelCard(
                            label: "Worker-modell",
                            subtitle: "Utför parallella deluppgifter",
                            icon: "person.2.fill",
                            color: .purple,
                            selection: $workerModel
                        )
                        .onChange(of: workerModel) { save() }

                        workerStepper
                    } header: {
                        Text("Modell & Workers")
                    } footer: {
                        Text("Workers utför parallella deluppgifter. Fler workers = snabbare men dyrare.")
                    }

                    // ── Kapacitet ──────────────────────────────────────────
                    Section {
                        Stepper(
                            "Max tokens/iteration: \(maxTokensPerIteration)",
                            value: $maxTokensPerIteration,
                            in: 1000...100000, step: 1000
                        )
                        .onChange(of: maxTokensPerIteration) { save() }

                        Stepper(
                            maxIterations == 0 ? "Max iterationer: Obegränsat" : "Max iterationer: \(maxIterations)",
                            value: $maxIterations, in: 0...10000, step: 10
                        )
                        .onChange(of: maxIterations) { save() }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Paus mellan iterationer: \(String(format: "%.0f s", iterationDelaySeconds))")
                                .font(.system(size: 14))
                            Slider(value: $iterationDelaySeconds, in: 0...60, step: 1)
                                .onChange(of: iterationDelaySeconds) { save() }
                        }

                        Stepper(
                            "Kontext-historik: \(maxHistoryMessages) meddelanden",
                            value: $maxHistoryMessages, in: 5...100, step: 5
                        )
                        .onChange(of: maxHistoryMessages) { save() }
                    } header: { Text("Kapacitet") }

                    // ── Beteende ───────────────────────────────────────────
                    Section("Beteende") {
                        Toggle("Starta om vid fel", isOn: $autoRestartOnFailure)
                            .onChange(of: autoRestartOnFailure) { save() }
                        Toggle("Pausa vid fråga till användare", isOn: $pauseOnUserQuestion)
                            .onChange(of: pauseOnUserQuestion) { save() }
                        Toggle("Detaljerad loggning", isOn: $verboseLogging)
                            .onChange(of: verboseLogging) { save() }
                        Toggle("Använd Navi-minnen som kontext", isOn: $memoryEnabled)
                            .onChange(of: memoryEnabled) { save() }
                    }

                    // ── GitHub ─────────────────────────────────────────────
                    Section {
                        Toggle("Auto-commit till GitHub", isOn: $autoCommitToGitHub)
                            .onChange(of: autoCommitToGitHub) { save() }
                        if autoCommitToGitHub {
                            TextField("Branch", text: $githubBranch)
                                .onChange(of: githubBranch) { save() }
                        }
                    } header: { Text("GitHub") }

                    // ── Extra systemprompt ─────────────────────────────────
                    Section {
                        ZStack(alignment: .topLeading) {
                            if systemPromptAddition.isEmpty {
                                Text("Extra instruktioner till agenten (valfritt)…")
                                    .font(.system(size: 13)).foregroundColor(.secondary.opacity(0.5))
                                    .padding(.top, 8).padding(.leading, 4)
                            }
                            TextEditor(text: $systemPromptAddition)
                                .font(.system(size: 13))
                                .frame(minHeight: 80)
                                .scrollContentBackground(.hidden)
                                .onChange(of: systemPromptAddition) { save() }
                        }
                    } header: { Text("Extra instruktioner") }

                    // ── Notifikationer ─────────────────────────────────────
                    Section("Notifikationer") {
                        Toggle("Vid slutförande", isOn: $notifyOnCompletion)
                            .onChange(of: notifyOnCompletion) { save() }
                        Toggle("Vid fel", isOn: $notifyOnFailure)
                            .onChange(of: notifyOnFailure) { save() }
                        Toggle("Vid fråga", isOn: $notifyOnUserQuestion)
                            .onChange(of: notifyOnUserQuestion) { save() }
                    }

                    // ── Farliga åtgärder ───────────────────────────────────
                    Section {
                        Button("Rensa logg", role: .destructive) {
                            var updated = agent
                            updated.runLog = []
                            runner.update(updated)
                        }
                        Button("Nollställ kostnad & statistik", role: .destructive) {
                            var updated = agent
                            updated.totalTokensUsed = 0
                            updated.totalCostSEK = 0
                            updated.workerTokensUsed = 0
                            updated.workerCostSEK = 0
                            updated.sessionTokensUsed = 0
                            updated.sessionCostSEK = 0
                            updated.iterationCount = 0
                            runner.update(updated)
                        }
                    } header: { Text("Åtgärder") }
                }
                .onAppear { loadFromAgent(agent) }
                .onChange(of: agentID) { _ in if let a = self.agent { loadFromAgent(a) } }
            }
        }
    }

    // Worker stepper with visual indicator
    @ViewBuilder
    var workerStepper: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tilldelade workers")
                    .font(.system(size: 14))
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        if assignedWorkers > 1 { assignedWorkers -= 1; save() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20)).foregroundColor(assignedWorkers > 1 ? .accentEon : .secondary.opacity(0.3))
                    }
                    .buttonStyle(.plain)

                    Text("\(assignedWorkers)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .frame(width: 32, alignment: .center)

                    Button {
                        if assignedWorkers < 10 { assignedWorkers += 1; save() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20)).foregroundColor(assignedWorkers < 10 ? .accentEon : .secondary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Visual worker dots
            HStack(spacing: 5) {
                ForEach(1...10, id: \.self) { i in
                    Circle()
                        .fill(i <= assignedWorkers ? Color.accentEon : Color.primary.opacity(0.1))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle().stroke(Color.accentEon.opacity(i <= assignedWorkers ? 0 : 0.2), lineWidth: 1)
                        )
                        .animation(.easeInOut(duration: 0.15), value: assignedWorkers)
                        .onTapGesture { assignedWorkers = i; save() }
                }
            }

            Text(workerDescription)
                .font(.system(size: 11)).foregroundColor(.secondary.opacity(0.7))
        }
    }

    var workerDescription: String {
        switch assignedWorkers {
        case 1:     return "1 worker — sekventiell körning, lägst kostnad"
        case 2...3: return "\(assignedWorkers) workers — bra balans mellan hastighet och kostnad"
        case 4...6: return "\(assignedWorkers) workers — snabb parallell körning"
        case 7...9: return "\(assignedWorkers) workers — hög parallellism, högre kostnad"
        case 10:    return "10 workers — maximal parallellism"
        default:    return ""
        }
    }

    private func loadFromAgent(_ agent: AgentDefinition) {
        name = agent.name
        goal = agent.goal
        model = agent.model
        workerModel = agent.workerModel
        assignedWorkers = agent.assignedWorkers
        maxTokensPerIteration = agent.maxTokensPerIteration
        maxIterations = agent.maxIterations
        iterationDelaySeconds = agent.iterationDelaySeconds
        autoRestartOnFailure = agent.autoRestartOnFailure
        pauseOnUserQuestion = agent.pauseOnUserQuestion
        verboseLogging = agent.verboseLogging
        autoCommitToGitHub = agent.autoCommitToGitHub
        githubBranch = agent.githubBranch
        systemPromptAddition = agent.systemPromptAddition
        maxHistoryMessages = agent.maxHistoryMessages
        memoryEnabled = agent.memoryEnabled
        notifyOnCompletion = agent.notifyOnCompletion
        notifyOnFailure = agent.notifyOnFailure
        notifyOnUserQuestion = agent.notifyOnUserQuestion
        selectedProjectID = agent.projectID
        loaded = true
    }

    private func save() {
        guard loaded, var updated = agent else { return }
        updated.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? updated.name : name
        updated.goal = goal
        updated.model = model
        updated.workerModel = workerModel
        updated.assignedWorkers = assignedWorkers
        updated.maxTokensPerIteration = maxTokensPerIteration
        updated.maxIterations = maxIterations
        updated.iterationDelaySeconds = iterationDelaySeconds
        updated.autoRestartOnFailure = autoRestartOnFailure
        updated.pauseOnUserQuestion = pauseOnUserQuestion
        updated.verboseLogging = verboseLogging
        updated.autoCommitToGitHub = autoCommitToGitHub
        updated.githubBranch = githubBranch
        updated.systemPromptAddition = systemPromptAddition
        updated.maxHistoryMessages = maxHistoryMessages
        updated.memoryEnabled = memoryEnabled
        updated.notifyOnCompletion = notifyOnCompletion
        updated.notifyOnFailure = notifyOnFailure
        updated.notifyOnUserQuestion = notifyOnUserQuestion
        updated.projectID = selectedProjectID
        updated.projectName = projectStore.projects.first { $0.id == selectedProjectID }?.name
        runner.update(updated)
    }
}

// MARK: - Agent Model Card (visual model picker row)

struct AgentModelCard: View {
    let label: String
    let subtitle: String
    let icon: String
    let color: Color
    @Binding var selection: ClaudeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.12)).frame(width: 30, height: 30)
                    Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(ClaudeModel.allCases, id: \.self) { m in
                        Button {
                            selection = m
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.displayName)
                                    Text(modelCostHint(m))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                if m == selection { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selection.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(color)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(color.opacity(0.6))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            // Cost hint for selected model
            Text(modelCostHint(selection))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.leading, 40)
        }
        .padding(.vertical, 4)
    }

    private func modelCostHint(_ m: ClaudeModel) -> String {
        let inCost = m.inputPricePerMTok
        let outCost = m.outputPricePerMTok
        return String(format: "$%.2f / $%.2f per Mtok in/out", inCost, outCost)
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
        case .workerResult:     return "person.2.fill"
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
        case .workerResult:     return .purple
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.1)).frame(width: 22, height: 22)
                Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                if entry.type == .assistantMessage || entry.type == .workerResult {
                    Text(String(entry.content.prefix(800)))
                        .font(.system(size: 12)).foregroundColor(.primary).lineSpacing(3).textSelection(.enabled)
                } else if entry.type == .tool {
                    Text(entry.content)
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.purple)
                        .padding(6).background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(entry.content)
                        .font(.system(size: 12))
                        .foregroundColor(entry.isError ? .red : .primary.opacity(0.85))
                        .lineSpacing(2).textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    Text(entry.timestamp, style: .time)
                        .font(.system(size: 10)).foregroundColor(.secondary.opacity(0.5))
                    if let cost = entry.costSEK, cost > 0 {
                        Text(String(format: "%.4f kr", cost))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.green.opacity(0.7))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if let tok = entry.tokensUsed, tok > 0 {
                        Text("\(tok) tok")
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary.opacity(0.4))
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
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
                    .font(.system(size: 12)).foregroundColor(.primary.opacity(0.85)).lineSpacing(3)
                RoundedRectangle(cornerRadius: 1).fill(Color.green.opacity(0.7))
                    .frame(width: 2, height: 12).opacity(cursorVisible ? 1 : 0).padding(.leading, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
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
    @State private var model: ClaudeModel = .sonnet45
    @State private var workerModel: ClaudeModel = .haiku
    @State private var assignedWorkers = 2
    @State private var maxIterations = 0
    @State private var maxTokensPerIteration = 8000
    @State private var iterationDelaySeconds = 1.0
    @State private var autoRestart = false
    @State private var pauseOnUserQuestion = true
    @State private var startImmediately = true
    @State private var verboseLogging = false
    @State private var memoryEnabled = true

    var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !goal.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Agentens namn", text: $name)
                } header: { Text("Namn") }

                Section {
                    ZStack(alignment: .topLeading) {
                        if goal.isEmpty {
                            Text("Beskriv vad agenten skall uppnå. Kan vara ett långt, detaljerat mål som tar timmar eller dagar att genomföra...")
                                .font(.system(size: 14)).foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 8).padding(.leading, 4)
                        }
                        TextEditor(text: $goal)
                            .font(.system(size: 14)).frame(minHeight: 160).scrollContentBackground(.hidden)
                    }
                } header: { Text("Mål") }
                  footer: { Text("Agenten arbetar autonomt tills målet är uppnått.") }

                Section("Projekt (valfritt)") {
                    Picker("Projekt", selection: $selectedProjectID) {
                        Text("Inget projekt").tag(UUID?.none)
                        ForEach(projects) { p in Text(p.name).tag(UUID?.some(p.id)) }
                    }
                }

                Section {
                    AgentModelCard(
                        label: "Agentens modell",
                        subtitle: "Orkestratorn — planerar och resonerar",
                        icon: "cpu.fill",
                        color: .accentEon,
                        selection: $model
                    )
                    AgentModelCard(
                        label: "Worker-modell",
                        subtitle: "Utför parallella deluppgifter",
                        icon: "person.2.fill",
                        color: .purple,
                        selection: $workerModel
                    )
                    // Worker count
                    HStack {
                        Text("Tilldelade workers")
                        Spacer()
                        HStack(spacing: 6) {
                            Button { if assignedWorkers > 1 { assignedWorkers -= 1 } } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 20))
                                    .foregroundColor(assignedWorkers > 1 ? .accentEon : .secondary.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                            Text("\(assignedWorkers)").font(.system(size: 16, weight: .bold, design: .monospaced)).frame(width: 28)
                            Button { if assignedWorkers < 10 { assignedWorkers += 1 } } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 20))
                                    .foregroundColor(assignedWorkers < 10 ? .accentEon : .secondary.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: { Text("Modell & Workers") }
                  footer: { Text("Agenten orkestrar, workers utför. Välj billigare modell för workers för lägre kostnad.") }

                Section("Kapacitet") {
                    Stepper(
                        maxIterations == 0 ? "Max iterationer: Obegränsat" : "Max: \(maxIterations)",
                        value: $maxIterations, in: 0...10000, step: 10
                    )
                    Stepper("Max tokens/iter: \(maxTokensPerIteration)", value: $maxTokensPerIteration, in: 1000...100000, step: 1000)
                }

                Section("Beteende") {
                    Toggle("Starta om vid fel", isOn: $autoRestart)
                    Toggle("Pausa vid fråga", isOn: $pauseOnUserQuestion)
                    Toggle("Detaljerad loggning", isOn: $verboseLogging)
                    Toggle("Använd Navi-minnen", isOn: $memoryEnabled)
                    Toggle("Starta direkt", isOn: $startImmediately)
                }
            }
            .navigationTitle("Ny agent")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skapa") {
                        let agent = runner.create(
                            name: name.trimmingCharacters(in: .whitespaces),
                            goal: goal.trimmingCharacters(in: .whitespaces),
                            projectID: selectedProjectID,
                            projectName: projects.first { $0.id == selectedProjectID }?.name,
                            model: model,
                            workerModel: workerModel,
                            assignedWorkers: assignedWorkers,
                            maxTokensPerIteration: maxTokensPerIteration,
                            maxIterations: maxIterations,
                            autoRestartOnFailure: autoRestart,
                            pauseOnUserQuestion: pauseOnUserQuestion,
                            verboseLogging: verboseLogging,
                            memoryEnabled: memoryEnabled
                        )
                        if startImmediately { runner.start(agent.id) }
                        dismiss()
                    }
                    .disabled(!canCreate).fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Edit Agent Sheet (opens settings inline)

struct EditAgentSheet: View {
    let agent: AgentDefinition
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            AgentSettingsEditor(agentID: agent.id)
                .navigationTitle("Inställningar")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Klar") { dismiss() }.fontWeight(.semibold)
                    }
                }
        }
    }
}

#Preview("AgentView") {
    AgentView().frame(width: 900, height: 600)
}
