import SwiftUI

// MARK: - AgentActivityView: Reusable visual component for all views

struct AgentActivityView: View {
    @ObservedObject var activity: AgentActivityState
    var compact: Bool = false

    @State private var showTodo = true
    @State private var showCode = false
    @State private var showTimeline = true   // default visible — shows real-time step log
    @State private var pulseAnimation = false

    var body: some View {
        if activity.isActive || activity.phase.isTerminal {
            VStack(spacing: compact ? 8 : 12) {
                // 1. Status header with progress
                statusHeader

                // 2. Progress bar
                progressBar

                // 3. TODO panel
                if showTodo && !activity.todoItems.isEmpty {
                    todoPanel
                }

                // 4. Code diff panel
                if showCode && !activity.codeChanges.isEmpty {
                    codeDiffPanel
                }

                // 5. Timeline
                if showTimeline && !activity.timeline.isEmpty {
                    timelinePanel
                }

                // 6. Summary (when complete)
                if case .complete(let summary) = activity.phase {
                    summaryCard(summary)
                }

                // 7. Bottom metrics bar
                metricsBar
            }
            .padding(compact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [activity.phase.iconColor.opacity(0.4), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activity.phase)
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 10) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(activity.phase.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                if activity.isActive && !isComplete {
                    Circle()
                        .fill(activity.phase.iconColor.opacity(0.08))
                        .frame(width: 36, height: 36)
                        .scaleEffect(pulseAnimation ? 1.6 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.5)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                                pulseAnimation = true
                            }
                        }
                }

                Image(systemName: activity.phase.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(activity.phase.iconColor)
                    .rotationEffect(isReading ? .degrees(360) : .zero)
                    .animation(isReading ? .linear(duration: 2).repeatForever(autoreverses: false) : .default, value: isReading)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.phase.displayText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !activity.todoItems.isEmpty {
                    Text("\(activity.todoCompletedCount) av \(activity.todoItems.count) steg klara")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Section toggles
            HStack(spacing: 4) {
                toggleButton(icon: "checklist", isOn: $showTodo, badge: activity.todoItems.count)
                toggleButton(icon: "chevron.left.forwardslash.chevron.right", isOn: $showCode, badge: activity.codeChanges.count)
                toggleButton(icon: "clock", isOn: $showTimeline, badge: activity.timeline.count)
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [activity.phase.iconColor, activity.phase.iconColor.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * activity.progress)
                    .animation(.spring(response: 0.5), value: activity.progress)
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - TODO Panel

    private var todoPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(activity.todoItems) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.status.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(item.status.color)
                        .frame(width: 18)

                    Text(item.title)
                        .font(.system(size: 13, weight: item.status == .active ? .semibold : .regular))
                        .foregroundColor(item.status == .done ? .secondary : .primary)
                        .strikethrough(item.status == .done, color: .secondary)

                    Spacer()

                    if item.status == .active {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(item.status == .active ? activity.phase.iconColor.opacity(0.08) : .clear)
                )
                .animation(.spring(response: 0.3), value: item.status)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.codeBackground.opacity(0.5))
        )
    }

    // MARK: - Code Diff Panel

    private var codeDiffPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with line counts
            HStack {
                Text("Kodändringar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    Label("+\(activity.totalLinesAdded)", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)

                    Label("-\(activity.totalLinesRemoved)", systemImage: "minus")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.red)
                }
            }

            // File list with inline diffs
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(activity.codeChanges) { change in
                        codeChangeRow(change)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.codeBackground)
        )
    }

    private func codeChangeRow(_ change: CodeChange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // File header
            HStack(spacing: 6) {
                Image(systemName: change.isNewFile ? "doc.badge.plus" : "pencil.line")
                    .font(.system(size: 11))
                    .foregroundColor(change.isNewFile ? .mint : .orange)

                Text(change.fileName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)

                Spacer()

                Text("+\(change.linesAdded)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.green)
                Text("-\(change.linesRemoved)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red)
            }

            // Diff lines (show last few)
            let visibleLines = Array(change.diffLines.suffix(8))
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 4) {
                    Text(line.type == .added ? "+" : line.type == .removed ? "-" : " ")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(line.type == .added ? .green : line.type == .removed ? .red : .secondary)
                        .frame(width: 12)

                    Text(line.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(line.type == .added ? .green.opacity(0.9) :
                                        line.type == .removed ? .red.opacity(0.9) : .secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 4)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
        )
    }

    // MARK: - Timeline Panel

    private var timelinePanel: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(activity.timeline) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            // Timeline dot and line
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(Color.accentNavi)
                                    .frame(width: 8, height: 8)

                                if entry.id != activity.timeline.last?.id {
                                    Rectangle()
                                        .fill(Color.accentNavi.opacity(0.3))
                                        .frame(width: 1)
                                        .frame(minHeight: 20)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: entry.icon)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)

                                    Text(entry.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text(entry.timestamp, style: .time)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }

                                if let detail = entry.detail {
                                    Text(detail)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .id(entry.id)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 180)
            .onChange(of: activity.timeline.count) { _, _ in
                if let last = activity.timeline.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.codeBackground.opacity(0.5))
        )
    }

    // MARK: - Summary Card

    private func summaryCard(_ summary: AgentSummary) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                Text("Uppgift slutförd")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(summary.durationFormatted)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                summaryMetric(value: "\(summary.filesModified + summary.filesCreated)", label: "Filer", icon: "doc.fill")
                summaryMetric(value: "+\(summary.totalLinesAdded)", label: "Tillagda", icon: "plus", color: .green)
                summaryMetric(value: "-\(summary.totalLinesRemoved)", label: "Borttagna", icon: "minus", color: .red)
                summaryMetric(value: String(format: "%.2f kr", summary.costSEK), label: "Kostnad", icon: "creditcard")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.green.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    private func summaryMetric(value: String, label: String, icon: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Metrics Bar

    private var metricsBar: some View {
        HStack(spacing: 16) {
            Label("\(activity.tokensUsed.formatted()) tokens", systemImage: "number")
            Label(String(format: "%.2f kr", activity.currentCostSEK), systemImage: "creditcard")
            if let start = activity.startTime {
                Label(
                    Duration.seconds(Date().timeIntervalSince(start)).formatted(.units(allowed: [.minutes, .seconds])),
                    systemImage: "clock"
                )
            }
            Spacer()
            #if os(macOS)
            Label("macOS", systemImage: "desktopcomputer")
            #else
            Label("iOS", systemImage: "iphone")
            #endif
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
    }

    // MARK: - Helpers

    private var isComplete: Bool {
        if case .complete = activity.phase { return true }
        return false
    }

    private var isReading: Bool {
        if case .reading = activity.phase { return true }
        if case .scanning = activity.phase { return true }
        return false
    }

    private func toggleButton(icon: String, isOn: Binding<Bool>, badge: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isOn.wrappedValue ? .accentNavi : .secondary)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isOn.wrappedValue ? Color.accentNavi.opacity(0.15) : .clear)
                    )

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(3)
                        .background(Circle().fill(Color.accentNavi))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phase completion check helper

extension AgentPhase {
    var isTerminal: Bool {
        if case .complete = self { return true }
        if case .error = self { return true }
        return false
    }
}

// MARK: - Preview

#Preview("Agent Activity") {
    let activity = AgentActivityState()

    AgentActivityView(activity: activity)
        .padding()
        .background(Color.black)
        .onAppear {
            activity.begin()
            activity.setPhase(.writing(file: "LoginView.swift", added: 42, removed: 8))
            activity.setTodoItems([
                ("Läs och förstå projektet", nil),
                ("Skapa LoginView.swift", nil),
                ("Implementera autentisering", nil),
                ("Uppdatera navigationen", nil),
                ("Testa", nil)
            ])
            activity.todoItems[0].status = .done
            activity.todoItems[1].status = .active
            activity.progress = 0.35
            activity.tokensUsed = 12450
            activity.currentCostSEK = 0.42
            activity.recordNewFile(file: "LoginView.swift", content: """
            import SwiftUI

            struct LoginView: View {
                @State private var email = ""
                @State private var password = ""

                var body: some View {
                    VStack {
                        TextField("E-post", text: $email)
                        SecureField("Lösenord", text: $password)
                        Button("Logga in") { }
                    }
                }
            }
            """)
        }
}
