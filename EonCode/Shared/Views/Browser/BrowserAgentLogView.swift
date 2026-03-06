import SwiftUI

// MARK: - BrowserAgentLogView
// Shows the browser agent's steps and thoughts in real time.

struct BrowserAgentLogView: View {
    @ObservedObject var agent: BrowserAgent

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .fill(statusColor.opacity(0.3))
                                .frame(width: 13, height: 13)
                                .opacity(agent.status == .working ? 1 : 0)
                        )
                    Text(statusLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(statusColor)
                }

                Spacer()

                if !agent.log.isEmpty {
                    Text("\(agent.log.count) steg")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(4)
                }

                if agent.status == .working {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.surfaceHover)

            Divider().opacity(0.1)

            // Log entries
            if agent.log.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(agent.log) { entry in
                                BrowserLogEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: agent.log.count) { _ in
                        if let last = agent.log.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.chatBackground)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.3))
            Text("Ingen aktivitet ännu")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status helpers

    private var statusColor: Color {
        switch agent.status {
        case .idle:           return .secondary
        case .working:        return .green
        case .waitingForUser: return .yellow
        case .complete:       return .accentEon
        case .failed:         return .red
        }
    }

    private var statusLabel: String {
        switch agent.status {
        case .idle:           return "Inaktiv"
        case .working:        return "Arbetar"
        case .waitingForUser: return "Väntar på dig"
        case .complete:       return "Klar"
        case .failed:         return "Misslyckades"
        }
    }
}

// MARK: - Log Entry Row

struct BrowserLogEntryRow: View {
    let entry: BrowserLogEntry

    private var entryIcon: String {
        let t = entry.displayText
        if t.hasPrefix("🎯") { return "target" }
        if t.hasPrefix("🌐") { return "globe" }
        if t.hasPrefix("👆") { return "cursorarrow.click" }
        if t.hasPrefix("⌨️") { return "keyboard" }
        if t.hasPrefix("📜") { return "arrow.down" }
        if t.hasPrefix("📸") { return "camera" }
        if t.hasPrefix("⏳") { return "clock" }
        if t.hasPrefix("❓") { return "questionmark.circle" }
        if t.hasPrefix("💬") { return "bubble.left" }
        if t.hasPrefix("✅") { return "checkmark.circle.fill" }
        if t.hasPrefix("❌") || entry.isError { return "xmark.circle.fill" }
        if t.hasPrefix("⚠️") { return "exclamationmark.triangle.fill" }
        if t.hasPrefix("🔄") { return "arrow.clockwise" }
        if t.hasPrefix("👁") { return "eye" }
        return "circle.fill"
    }

    private var iconColor: Color {
        if entry.isError { return .red }
        let t = entry.displayText
        if t.hasPrefix("✅") { return .green }
        if t.hasPrefix("❓") || t.hasPrefix("💬") { return .yellow }
        if t.hasPrefix("🎯") { return .accentEon }
        if t.hasPrefix("⚠️") { return .orange }
        return .secondary.opacity(0.6)
    }

    // Strip leading emoji for clean display
    private var cleanText: String {
        let emojis = ["🎯 ", "🌐 ", "👆 ", "⌨️ ", "📜 ", "📸 ", "⏳ ", "❓ ", "💬 ", "✅ ", "❌ ", "⚠️ ", "🔄 ", "👁 "]
        var t = entry.displayText
        for e in emojis {
            if t.hasPrefix(e) { t = String(t.dropFirst(e.count)); break }
        }
        return t
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entryIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 14, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanText)
                    .font(.system(size: 12))
                    .foregroundColor(entry.isError ? .red.opacity(0.9) : .primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.3))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            entry.isError
                ? Color.red.opacity(0.05)
                : Color.clear
        )
        .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview("BrowserAgentLogView") {
    BrowserAgentLogView(agent: BrowserAgent.shared)
        .frame(width: 300, height: 380)
        .preferredColorScheme(.dark)
}
