import SwiftUI

struct AgentStatusView: View {
    @ObservedObject var agent: ProjectAgent
    @ObservedObject private var orchestrator = OrchestratorAgent.shared
    @State private var expandedSteps = Set<UUID>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent-status")
                            .font(.system(size: 16, weight: .bold))
                        Text(agent.project.name)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if agent.isRunning || orchestrator.isRunning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(orchestrator.isRunning ? "Orchestrator" : "Kör")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                Divider().opacity(0.2)

                // Orchestrator wave progress
                if orchestrator.isRunning && orchestrator.totalWaves > 0 {
                    OrchestratorProgressView(orchestrator: orchestrator)
                }

                // Worker statuses
                if orchestrator.isRunning && !orchestrator.workerStatuses.isEmpty {
                    WorkerStatusListView(statuses: orchestrator.workerStatuses)
                }

                // Current status
                if !agent.currentStatus.isEmpty {
                    GlassCard(cornerRadius: 12, padding: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.accentEon)
                            Text(agent.currentStatus)
                                .font(.system(size: 13))
                            Spacer()
                        }
                    }
                }

                // Streaming output
                if !agent.streamingText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Agentens output", systemImage: "text.alignleft")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        ScrollView {
                            Text(agent.streamingText.suffix(3000))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.codeBackground)
                        )
                    }
                }

                // Session cost
                HStack {
                    Image(systemName: "coloncurrencysign.circle")
                        .foregroundColor(.secondary)
                    Text("Session: \(ExchangeRateService.shared.formatSEK(agent.sessionCostSEK))")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                    if agent.lastCostSEK > 0 {
                        Text("Senaste: \(ExchangeRateService.shared.formatSEK(agent.lastCostSEK))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }

                // Stop button
                if agent.isRunning {
                    GlassButton("Stoppa agent", icon: "stop.fill", isDestructive: true) {
                        agent.stop()
                    }
                }
            }
            .padding()
        }
        .background(Color.chatBackground)
    }
}

// MARK: - Orchestrator wave progress

struct OrchestratorProgressView: View {
    @ObservedObject var orchestrator: OrchestratorAgent

    var body: some View {
        GlassCard(cornerRadius: 12, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cpu.fill")
                        .foregroundColor(.accentEon)
                        .font(.system(size: 13))
                    Text("Orchestrator — Våg \(orchestrator.currentWave + 1)/\(orchestrator.totalWaves)")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(Int(orchestrator.overallProgress * 100))%")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                ProgressView(value: orchestrator.overallProgress)
                    .tint(.accentEon)

                if !orchestrator.waveDescription.isEmpty {
                    Text(orchestrator.waveDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Worker status list

struct WorkerStatusListView: View {
    let statuses: [UUID: OrchestratorAgent.WorkerStatus]

    var sorted: [OrchestratorAgent.WorkerStatus] {
        statuses.values.sorted { $0.taskDescription < $1.taskDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Workers (\(statuses.count))", systemImage: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            ForEach(sorted) { ws in
                WorkerStatusRow(status: ws)
            }
        }
    }
}

struct WorkerStatusRow: View {
    let status: OrchestratorAgent.WorkerStatus

    var body: some View {
        HStack(spacing: 10) {
            // Platform + state badge
            Text(platformEmoji)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(status.taskDescription.prefix(60))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(statusLabel)
                    .font(.system(size: 11))
                    .foregroundColor(statusColor)
            }

            Spacer()

            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var platformEmoji: String {
        if status.isQueued { return "🟡" }
        if status.ranLocally { return "🟢" }
        return "🔵"
    }

    private var statusLabel: String {
        if status.isQueued { return "Köad till Mac" }
        switch status.status {
        case .pending:    return "Väntar…"
        case .running:    return status.ranLocally ? "Körs lokalt" : "Väntar på Mac…"
        case .completed:  return "Klar ✓"
        case .failed:     return "Misslyckades ✗"
        case .skipped:    return "Hoppades över"
        }
    }

    private var statusColor: Color {
        if status.isQueued { return .yellow }
        switch status.status {
        case .pending:    return .secondary
        case .running:    return status.ranLocally ? .green : .blue
        case .completed:  return .green
        case .failed:     return .red
        case .skipped:    return .secondary
        }
    }
}

// MARK: - Multi Project Dashboard

struct MultiProjectDashboard: View {
    @StateObject private var pool = AgentPool.shared
    @StateObject private var store = ProjectStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.projects) { project in
                    ProjectStatusCard(project: project, pool: pool)
                }
            }
            .padding()
        }
        .background(Color.chatBackground)
        .navigationTitle("Alla agenter")
    }
}

struct ProjectStatusCard: View {
    let project: EonProject
    @ObservedObject var pool: AgentPool

    var agent: ProjectAgent? { pool.agents[project.id] }

    var body: some View {
        GlassCard(cornerRadius: 14, padding: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(project.color.color)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(agentStatusText)
                        .font(.system(size: 12))
                        .foregroundColor(agentStatusColor)
                }

                Spacer()

                if agent?.isRunning == true {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
        }
    }

    var agentStatusText: String {
        guard let agent = agent else { return "Ingen agent" }
        if agent.isRunning { return agent.currentStatus.isEmpty ? "Kör…" : agent.currentStatus }
        return "Inaktiv"
    }

    var agentStatusColor: Color {
        agent?.isRunning == true ? .green : .secondary.opacity(0.5)
    }
}

// MARK: - Previews

#Preview("AgentStatusView – idle") {
    let project = EonProject(name: "Navi Preview", rootPath: "/tmp/preview", color: .blue)
    let agent = ProjectAgent(project: project)
    return AgentStatusView(agent: agent)
        .frame(width: 400, height: 500)
}

#Preview("MultiProjectDashboard") {
    let store = ProjectStore.shared
    store.projects = [
        EonProject(name: "Navi v2", rootPath: "/tmp/eon", color: .blue),
        EonProject(name: "Lunaflix iOS", rootPath: "/tmp/luna", color: .purple),
        EonProject(name: "Medo Test", rootPath: "/tmp/medo", color: .green),
    ]
    return MultiProjectDashboard()
}

#Preview("ProjectStatusCard") {
    let project = EonProject(name: "Navi v2", rootPath: "/tmp/eon", color: .blue)
    return ProjectStatusCard(project: project, pool: AgentPool.shared)
        .padding()
        .background(Color.black)
}

#Preview("WorkerStatusRow") {
    let status = OrchestratorAgent.WorkerStatus(
        id: UUID(),
        taskDescription: "Analyserar Swift-filer i projektet",
        status: .running,
        output: "",
        ranLocally: true,
        isQueued: false
    )
    WorkerStatusRow(status: status)
        .padding()
        .background(Color.black)
}

// MARK: - iOS Remote Status View

#if os(iOS)
struct RemoteStatusView: View {
    @StateObject private var broadcaster = DeviceStatusBroadcaster.shared
    @StateObject private var composer = InstructionComposer.shared
    @StateObject private var store = ProjectStore.shared
    @State private var newInstruction = ""

    var body: some View {
        NavigationView {
            List {
                // Mac status
                Section("Mac-status") {
                    if let remote = broadcaster.remoteStatus {
                        LabeledContent("Enhet", value: remote.deviceName)
                        LabeledContent("Status", value: broadcaster.remoteMacIsOnline ? "Online ✓" : "Offline")
                        if remote.agentRunning {
                            LabeledContent("Agent", value: remote.agentStatus)
                            if remote.totalSteps > 0 {
                                ProgressView(value: Double(remote.currentStep), total: Double(remote.totalSteps))
                                LabeledContent("Framsteg", value: "\(remote.currentStep)/\(remote.totalSteps)")
                            }
                        }
                    } else {
                        Text("Söker efter Mac…")
                            .foregroundColor(.secondary)
                    }
                }

                // Send instruction
                Section("Kö instruktion") {
                    TextField("Instruktion till macOS…", text: $newInstruction, axis: .vertical)
                        .lineLimit(3...8)

                    Button("Skicka till Mac") {
                        guard !newInstruction.isBlank else { return }
                        Task {
                            await composer.queue(
                                instruction: newInstruction,
                                projectID: store.activeProject?.id
                            )
                            newInstruction = ""
                        }
                    }
                    .disabled(newInstruction.isBlank || !broadcaster.remoteMacIsOnline)
                }

                // Pending instructions
                if !composer.pendingInstructions.isEmpty {
                    Section("Köade instruktioner") {
                        ForEach(composer.pendingInstructions) { instr in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(instr.instruction.prefix(80))
                                    .font(.system(size: 13))
                                Text(instr.status.rawValue)
                                    .font(.system(size: 11))
                                    .foregroundColor(instr.status == .completed ? .green : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mac-status")
            .refreshable {
                await broadcaster.fetchRemoteStatus()
            }
        }
    }
}
#endif
