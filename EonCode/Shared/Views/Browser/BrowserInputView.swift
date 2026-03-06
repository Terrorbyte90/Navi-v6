import SwiftUI

// MARK: - BrowserInputView

struct BrowserInputView: View {
    @ObservedObject var agent: BrowserAgent
    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var isWaiting: Bool { agent.status == .waitingForUser }
    private var isWorking: Bool { agent.status == .working }

    var body: some View {
        VStack(spacing: 8) {
            if agent.status != .idle {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(dotColor)
                    Spacer()
                    if isWorking {
                        Button {
                            agent.cancel()
                        } label: {
                            Text("Avbryt")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack(alignment: .bottom, spacing: 0) {
                Image(systemName: dotIcon)
                    .font(.system(size: 14))
                    .foregroundColor(dotColor)
                    .frame(width: 32, height: 32)

                TextField(placeholderText, text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFocused)
                    .onSubmit { handleSend() }
                    .foregroundColor(isWaiting ? .yellow : .primary)
                    .disabled(isWorking && !isWaiting)
                    .padding(.vertical, 8)

                Button { handleSend() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(input.isBlank ? .secondary.opacity(0.3) : .black)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(input.isBlank ? Color.clear : isWaiting ? Color.yellow : Color.white)
                        )
                }
                .buttonStyle(.plain)
                .disabled(input.isBlank || (isWorking && !isWaiting))
                .padding(.trailing, 4)
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .strokeBorder(isWaiting ? Color.yellow.opacity(0.4) : Color.inputBorder, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var dotColor: Color {
        switch agent.status {
        case .working:        return .green
        case .waitingForUser: return .yellow
        case .complete:       return .accentEon
        case .failed:         return .red
        case .idle:           return .secondary
        }
    }

    private var dotIcon: String {
        switch agent.status {
        case .working:        return "cpu"
        case .waitingForUser: return "questionmark"
        case .complete:       return "checkmark"
        case .failed:         return "xmark"
        case .idle:           return "globe"
        }
    }

    private var statusLabel: String {
        switch agent.status {
        case .working:        return "Arbetar..."
        case .waitingForUser: return "Väntar på dig"
        case .complete:       return "Klar"
        case .failed:         return "Misslyckades"
        case .idle:           return ""
        }
    }

    private var placeholderText: String {
        switch agent.status {
        case .waitingForUser: return agent.userQuestion.isEmpty ? "Skriv ditt svar..." : agent.userQuestion
        case .working:        return "Agenten arbetar..."
        case .complete:       return "Klart! Ge ett nytt mål..."
        case .failed:         return "Misslyckades. Försök igen..."
        case .idle:           return "Ge webbläsaren ett mål..."
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
            // Reset status if previous task completed/failed — allow re-use
            if agent.status == .complete || agent.status == .failed {
                agent.status = .idle
            }
            Task { await agent.execute(goal: text) }
        }
    }
}

#Preview("BrowserInputView") {
    VStack {
        BrowserInputView(agent: BrowserAgent.shared)
    }
    .background(Color.chatBackground)
    .preferredColorScheme(.dark)
}
