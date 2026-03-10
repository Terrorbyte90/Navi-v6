import SwiftUI

// MARK: - CodeProgressCard
// Inline progress card shown in the chat message stream during active pipeline runs.

struct CodeProgressCard: View {
    @ObservedObject var agent: CodeAgent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThinkingOrb(size: 28, isAnimating: true)

            VStack(alignment: .leading, spacing: 8) {
                phaseRow

                if agent.phase == .build && !agent.workerStatuses.isEmpty {
                    WorkerOrbsRow(statuses: agent.workerStatuses)
                }

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
            PhasePill(phase: agent.phase)

            Spacer()

            // Phase dots
            HStack(spacing: 4) {
                ForEach(PipelinePhase.activePhasesOrdered, id: \.self) { phase in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(dotColor(for: phase))
                        .frame(width: phase.ordinal == agent.phase.ordinal ? 14 : 5, height: 5)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: agent.phase)
                }
            }
        }
    }

    private func dotColor(for phase: PipelinePhase) -> Color {
        guard agent.phase != .idle && agent.phase != .done else {
            return agent.phase == .done ? NaviTheme.success : Color.secondary.opacity(0.3)
        }
        if phase.ordinal < agent.phase.ordinal { return NaviTheme.success }
        if phase.ordinal == agent.phase.ordinal { return Color.accentNavi }
        return Color.secondary.opacity(0.15)
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
