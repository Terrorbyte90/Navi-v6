import WidgetKit
import SwiftUI

// MARK: - Widget data model (shared via UserDefaults App Group)

struct NaviWidgetSession: Codable, Identifiable {
    var id: String
    var task: String
    var status: String      // running | done | error | stopped
    var model: String
    var todosDone: Int
    var todosTotal: Int
    var updatedAt: Date

    var isRunning: Bool { status == "running" }
    var progress: Double {
        guard todosTotal > 0 else { return isRunning ? 0.5 : 1.0 }
        return Double(todosDone) / Double(todosTotal)
    }
    var statusLabel: String {
        switch status {
        case "running": return "Kör…"
        case "done":    return "Klar"
        case "error":   return "Fel"
        case "stopped": return "Stoppad"
        default:        return "Väntar"
        }
    }
    var taskPreview: String { String(task.prefix(60)) }
}

// MARK: - App Group key

enum NaviWidgetShared {
    static let suiteName = "group.com.tedsvard.navi"
    static let sessionsKey = "naviWidgetSessions"

    static func saveSessions(_ sessions: [NaviWidgetSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: sessionsKey)
    }

    static func loadSessions() -> [NaviWidgetSession] {
        guard
            let data = UserDefaults(suiteName: suiteName)?.data(forKey: sessionsKey),
            let sessions = try? JSONDecoder().decode([NaviWidgetSession].self, from: data)
        else { return [] }
        return sessions
    }
}

// MARK: - Timeline Entry

struct NaviWidgetEntry: TimelineEntry {
    let date: Date
    let sessions: [NaviWidgetSession]

    var activeSession: NaviWidgetSession? { sessions.first { $0.isRunning } }
    var latestSession: NaviWidgetSession? { sessions.first }
}

// MARK: - Provider

struct NaviWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> NaviWidgetEntry {
        NaviWidgetEntry(date: Date(), sessions: [
            NaviWidgetSession(id: "demo", task: "Bygg ett React dashboard", status: "running",
                              model: "MiniMax", todosDone: 3, todosTotal: 7, updatedAt: Date())
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (NaviWidgetEntry) -> Void) {
        let sessions = NaviWidgetShared.loadSessions()
        completion(NaviWidgetEntry(date: Date(), sessions: sessions))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NaviWidgetEntry>) -> Void) {
        let sessions = NaviWidgetShared.loadSessions()
        let entry = NaviWidgetEntry(date: Date(), sessions: sessions)
        // Refresh every 60 seconds while sessions are active, 5 min otherwise
        let hasActive = sessions.contains { $0.isRunning }
        let next = Calendar.current.date(byAdding: .second, value: hasActive ? 60 : 300, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(next))
        completion(timeline)
    }
}

// MARK: - Small Widget View

struct NaviWidgetSmallView: View {
    let entry: NaviWidgetEntry

    var body: some View {
        if let session = entry.activeSession ?? entry.latestSession {
            sessionView(session)
        } else {
            emptyView
        }
    }

    private func sessionView(_ session: NaviWidgetSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(session.isRunning ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text("NAVI")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "C4825A"))
                Spacer()
                Text(timeString(session.updatedAt))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(session.taskPreview)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                Text(session.statusLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(session.isRunning ? .orange : .green)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(session.isRunning ? Color.orange : Color.green)
                            .frame(width: geo.size.width * session.progress, height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(12)
        .background(Color(UIColor.systemBackground))
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Text("NAVI")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "C4825A"))
            Text("Ingen aktiv agent")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Medium Widget View

struct NaviWidgetMediumView: View {
    let entry: NaviWidgetEntry

    var body: some View {
        HStack(spacing: 0) {
            // Left: active or latest session
            if let session = entry.activeSession ?? entry.latestSession {
                mainSessionPanel(session)
            } else {
                emptyPanel
            }

            Divider().opacity(0.15)

            // Right: list of other sessions
            sessionList
        }
        .background(Color(UIColor.systemBackground))
    }

    private func mainSessionPanel(_ session: NaviWidgetSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(session.isRunning ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text("NAVI")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "C4825A"))
                Spacer()
            }

            Text(session.taskPreview)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(3)

            Spacer()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(session.isRunning ? .orange : .green)
                    Spacer()
                    if session.todosTotal > 0 {
                        Text("\(session.todosDone)/\(session.todosTotal)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(session.isRunning ? Color.orange : Color.green)
                            .frame(width: geo.size.width * session.progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            let others = entry.sessions.prefix(3)
            ForEach(Array(others.enumerated()), id: \.element.id) { idx, sess in
                if idx > 0 { Divider().opacity(0.08) }
                HStack(spacing: 6) {
                    Circle()
                        .fill(sess.isRunning ? Color.orange : (sess.status == "done" ? Color.green : Color.secondary))
                        .frame(width: 6, height: 6)
                    Text(String(sess.task.prefix(28)))
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            Spacer()
        }
        .frame(maxWidth: 130)
    }

    private var emptyPanel: some View {
        VStack(spacing: 8) {
            Text("NAVI")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "C4825A"))
            Text("Ingen aktiv agent")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Widget entry point

struct NaviWidget: Widget {
    let kind = "NaviWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NaviWidgetProvider()) { entry in
            NaviWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Navi")
        .description("Håll koll på agentens arbete — direkt på hemskärmen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NaviWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NaviWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:  NaviWidgetSmallView(entry: entry)
        case .systemMedium: NaviWidgetMediumView(entry: entry)
        default:            NaviWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Hex color helper (widget-local)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Live Activity Attributes

import ActivityKit

@available(iOS 16.2, *)
struct NaviLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String           // "thinking" | "tools" | "done" | "error"
        var phaseLabel: String      // "Tänker…" | "Kör 3 verktyg…"
        var iteration: Int
        var maxIteration: Int
        var todosDone: Int
        var todosTotal: Int
        var currentTool: String?    // e.g. "write_file"
    }
    var task: String                // Original task (static)
    var model: String               // "MiniMax" | "Claude" etc.
}

// MARK: - Live Activity Lock Screen View

@available(iOS 16.2, *)
struct NaviLockScreenLiveView: View {
    let context: ActivityViewContext<NaviLiveActivityAttributes>

    private var phaseColor: Color {
        switch context.state.phase {
        case "done":  return .green
        case "error": return .red
        default:      return .orange
        }
    }

    private var progress: Double {
        let total = context.state.todosTotal
        guard total > 0 else { return context.state.phase == "done" ? 1.0 : 0.3 }
        return Double(context.state.todosDone) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(phaseColor).frame(width: 8, height: 8)
                    Text("NAVI").font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "C4825A"))
                    Text("·").foregroundColor(.secondary)
                    Text(context.attributes.model)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("steg \(context.state.iteration)/\(context.state.maxIteration)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Task
            Text(String(context.attributes.task.prefix(80)))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)

            // Progress bar + todo count
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.15))
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3).fill(phaseColor)
                            .frame(width: geo.size.width * progress, height: 5)
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 5)

                HStack {
                    Text(context.state.phaseLabel.isEmpty ? phaseText : context.state.phaseLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(phaseColor)
                    Spacer()
                    if context.state.todosTotal > 0 {
                        Text("\(context.state.todosDone)/\(context.state.todosTotal) uppgifter")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if let tool = context.state.currentTool {
                        Text(tool)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(14)
    }

    private var phaseText: String {
        switch context.state.phase {
        case "thinking": return "Tänker…"
        case "tools":    return "Kör verktyg…"
        case "done":     return "Klar ✓"
        case "error":    return "Fel"
        default:         return "Arbetar…"
        }
    }
}

// MARK: - Live Activity Widget

@available(iOS 16.2, *)
struct NaviLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NaviLiveActivityAttributes.self) { context in
            NaviLockScreenLiveView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — shows when user long-presses or swipes down
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(context.state.phase == "done" ? Color.green :
                                  context.state.phase == "error" ? Color.red : Color.orange)
                            .frame(width: 9, height: 9)
                        Text("NAVI")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(Color(hex: "C4825A"))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.iteration)/\(context.state.maxIteration)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(context.attributes.task.prefix(55)))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            // Progress bar
                            GeometryReader { geo in
                                let p = context.state.todosTotal > 0
                                    ? Double(context.state.todosDone) / Double(context.state.todosTotal)
                                    : (context.state.phase == "done" ? 1.0 : 0.3)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.12))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(context.state.phase == "done" ? Color.green : Color.orange)
                                        .frame(width: geo.size.width * p)
                                }
                            }
                            .frame(height: 4)
                            if let tool = context.state.currentTool {
                                Text(tool)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 90)
                            }
                        }
                    }
                }
            } compactLeading: {
                Circle()
                    .fill(context.state.phase == "done" ? Color.green :
                          context.state.phase == "error" ? Color.red : Color.orange)
                    .frame(width: 9, height: 9)
            } compactTrailing: {
                Text("\(context.state.iteration)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .monospacedDigit()
            } minimal: {
                Circle()
                    .fill(context.state.phase == "done" ? Color.green :
                          context.state.phase == "error" ? Color.red : Color.orange)
                    .frame(width: 11, height: 11)
            }
            .keylineTint(Color(hex: "C4825A"))
        }
    }
}
