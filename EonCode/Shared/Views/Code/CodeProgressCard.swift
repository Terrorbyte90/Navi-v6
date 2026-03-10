import SwiftUI

// MARK: - CodeProgressCard
// Inline progress card shown in the chat message stream during active pipeline runs.
// Replaces the old PipelinePhaseView top bar + activityConsoleOverlay.

struct CodeProgressCard: View {
    @ObservedObject var agent: CodeAgent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // "N" avatar
            ZStack {
                Circle()
                    .fill(Color.accentNavi.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: agent.phase.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentNavi)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Phase row
                phaseRow

                // Worker orbs (during build)
                if agent.phase == .build && !agent.workerStatuses.isEmpty {
                    WorkerOrbsRow(statuses: agent.workerStatuses)
                }

                // Active file cards
                let activeCards = recentActiveCards
                if !activeCards.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(activeCards) { status in
                            LiveActivityCard(status: status)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: activeCards.map { $0.id })
                }

                // Quiet log
                if !agent.quietLog.isEmpty {
                    QuietLogLine(text: agent.quietLog)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var phaseRow: some View {
        HStack(spacing: 8) {
            Text(agent.phase.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)

            // Phase progress dots
            HStack(spacing: 4) {
                ForEach(PipelinePhase.activePhasesOrdered, id: \.self) { phase in
                    Circle()
                        .fill(dotColor(for: phase))
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private func dotColor(for phase: PipelinePhase) -> Color {
        guard agent.phase != .idle && agent.phase != .done else {
            return agent.phase == .done ? .green : Color.secondary.opacity(0.3)
        }
        if phase.ordinal < agent.phase.ordinal { return .green }
        if phase.ordinal == agent.phase.ordinal { return .orange }
        return Color.secondary.opacity(0.3)
    }

    private var recentActiveCards: [WorkerStatus] {
        let active = agent.workerStatuses.filter { $0.isActive && $0.currentFile != nil }
        let recent = agent.workerStatuses.filter { $0.isDone && $0.currentFile != nil }
        return Array((active + recent).prefix(3))
    }
}

// MARK: - PipelinePhase helper

extension PipelinePhase {
    static var activePhasesOrdered: [PipelinePhase] {
        [.spec, .research, .setup, .plan, .build, .push]
    }
}

#Preview {
    CodeProgressCard(agent: CodeAgent.shared)
        .padding()
        .background(Color.chatBackground)
}
