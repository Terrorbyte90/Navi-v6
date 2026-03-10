import SwiftUI

// MARK: - PipelinePhaseView
// Horizontal row of phase badges showing pipeline progress.
// Green = done, orange = active, gray = pending.

struct PipelinePhaseView: View {
    let currentPhase: PipelinePhase

    private let phases: [PipelinePhase] = [.spec, .research, .setup, .plan, .build, .push]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(phases, id: \.self) { phase in
                    PhaseBadge(phase: phase, state: badgeState(for: phase))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.chatBackground.opacity(0.95))
    }

    private func badgeState(for phase: PipelinePhase) -> PhaseBadgeState {
        if currentPhase == .idle || currentPhase == .done {
            return currentPhase == .done ? .done : .pending
        }
        if phase.ordinal < currentPhase.ordinal { return .done }
        if phase.ordinal == currentPhase.ordinal { return .active }
        return .pending
    }
}

// MARK: - PhaseBadge

enum PhaseBadgeState { case pending, active, done }

struct PhaseBadge: View {
    let phase: PipelinePhase
    let state: PhaseBadgeState

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state == .done ? "checkmark" : phase.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(phase.displayName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(badgeBackground)
        .foregroundColor(badgeForeground)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(borderColor, lineWidth: state == .active ? 1.5 : 0)
        )
        .scaleEffect(state == .active && pulse ? 1.04 : 1.0)
        .animation(
            state == .active
                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                : .default,
            value: pulse
        )
        .onAppear {
            if state == .active { pulse = true }
        }
        .onChange(of: state) { _, new in
            pulse = new == .active
        }
    }

    private var badgeBackground: Color {
        switch state {
        case .done:    return NaviTheme.success.opacity(0.12)
        case .active:  return Color.accentNavi.opacity(0.12)
        case .pending: return Color.sidebarBackground
        }
    }

    private var badgeForeground: Color {
        switch state {
        case .done:    return NaviTheme.success
        case .active:  return .accentNavi
        case .pending: return .secondary
        }
    }

    private var borderColor: Color {
        switch state {
        case .active: return Color.accentNavi.opacity(0.5)
        default:      return .clear
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PipelinePhaseView(currentPhase: .idle)
        PipelinePhaseView(currentPhase: .research)
        PipelinePhaseView(currentPhase: .build)
        PipelinePhaseView(currentPhase: .done)
    }
    .padding()
}
