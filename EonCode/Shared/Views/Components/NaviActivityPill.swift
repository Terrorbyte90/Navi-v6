import SwiftUI

// MARK: - NaviActivityPill
// The single, unified visual for ALL model activity states.
// Compact terminal-style pill with expand/collapse. Replaces all
// ThinkingPhaseCard, LiveToolCallCard, CodeThinkingCard etc.

struct NaviActivityPill: View {
    let statusText: String          // "Tänker", "Letar", "Skriver kod" …
    var items: [String] = []        // Expandable item list (tool names, files)
    var isLive: Bool = true         // Pulsing dot when actively running
    var accentColor: Color = .accentNavi

    @State private var expanded = false
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row
            Button {
                guard !items.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.7))

                    if isLive {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 5, height: 5)
                            .scaleEffect(pulse ? 1.3 : 0.8)
                            .opacity(pulse ? 1.0 : 0.5)
                    }

                    Text(statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.75))

                    Spacer(minLength: 0)

                    // Three animated dots — visible when live
                    if isLive {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(accentColor.opacity(pulse ? 0.8 : 0.3))
                                    .frame(width: 4, height: 4)
                                    .animation(
                                        .easeInOut(duration: 0.5)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(i) * 0.15),
                                        value: pulse
                                    )
                            }
                        }
                    }

                    if !items.isEmpty {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(accentColor.opacity(0.4))
                    }
                }
            }
            .buttonStyle(.plain)

            // Expanded item list
            if expanded && !items.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items.prefix(8), id: \.self) { item in
                        HStack(spacing: 5) {
                            Image(systemName: NaviActivityPill.toolIcon(item))
                                .font(.system(size: 8))
                                .foregroundColor(accentColor.opacity(0.5))
                            Text(item)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(accentColor.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    if items.count > 8 {
                        Text("+ \(items.count - 8) till…")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accentColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(10)
        .onAppear {
            guard isLive else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: isLive) { _, live in
            if live {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation { pulse = false }
            }
        }
    }

    // Shared tool icon lookup (used in expanded list)
    static func toolIcon(_ tool: String) -> String {
        let t = tool.lowercased()
        if t.hasPrefix("bash") || t.hasPrefix("run_command") || t.hasPrefix("execute") { return "terminal" }
        if t.hasPrefix("read_file") || t.hasPrefix("get_file") { return "doc.text" }
        if t.hasPrefix("write_file") || t.hasPrefix("create_file") { return "square.and.pencil" }
        if t.hasPrefix("list_files") || t.hasPrefix("list_dir") { return "folder" }
        if t.hasPrefix("github_create_pull") { return "arrow.triangle.pull" }
        if t.hasPrefix("github_create") { return "plus.circle" }
        if t.hasPrefix("github") { return "arrow.triangle.branch" }
        if t.hasPrefix("web_search") { return "globe" }
        if t.hasPrefix("server_exec") { return "server.rack" }
        if t.hasPrefix("server_ask") { return "brain" }
        if t.hasPrefix("server") { return "server.rack" }
        if t.hasPrefix("search") { return "magnifyingglass" }
        if t.hasPrefix("memory") { return "brain.head.profile" }
        if t.hasPrefix("image") { return "photo" }
        return "wrench.and.screwdriver"
    }
}

// MARK: - NaviCodeLiveCard
// Larger variant shown when the model is actively writing code.
// Displays filename + streaming code in real-time with blinking cursor.

struct NaviCodeLiveCard: View {
    let fileName: String
    let liveCode: String
    var isActive: Bool = true
    var accentColor: Color = .accentNavi

    @State private var expanded = true
    @State private var pulse = false

    private var codePreview: String {
        let lines = liveCode.components(separatedBy: "\n")
        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return meaningful.suffix(5).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — same pill style as NaviActivityPill
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.7))

                    if isActive {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 5, height: 5)
                            .scaleEffect(pulse ? 1.3 : 0.8)
                            .opacity(pulse ? 1.0 : 0.5)
                    }

                    Text("Skriver kod")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.75))

                    // Three animated dots
                    if isActive {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(accentColor.opacity(pulse ? 0.8 : 0.3))
                                    .frame(width: 4, height: 4)
                                    .animation(
                                        .easeInOut(duration: 0.5)
                                            .repeatForever(autoreverses: true)
                                            .delay(Double(i) * 0.15),
                                        value: pulse
                                    )
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Text(fileName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(accentColor.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accentColor.opacity(0.4))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            // Live code view
            if expanded && !liveCode.isEmpty {
                Rectangle()
                    .fill(accentColor.opacity(0.08))
                    .frame(height: 0.5)

                HStack(alignment: .bottom, spacing: 0) {
                    Text(codePreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(accentColor.opacity(0.6))
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isActive {
                        BlinkingCursor()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .animation(.easeOut(duration: 0.08), value: liveCode)
            }
        }
        .background(accentColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(accentColor.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(10)
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Status text helpers — ChatManager.ThinkingPhase

extension ChatManager.ThinkingPhase {
    var pillText: String {
        switch self {
        case .idle:           return ""
        case .preparing:      return "Förbereder"
        case .connecting:     return "Ansluter"
        case .thinking:       return "Tänker"
        case .responding:     return "Skriver"
        case .executingTools: return "Kör verktyg"
        case .finishing:      return "Slutför"
        }
    }
}

// MARK: - Status text helpers — PipelinePhase

extension PipelinePhase {
    var pillText: String {
        switch self {
        case .idle:     return "Väntar"
        case .spec:     return "Planerar"
        case .research: return "Undersöker"
        case .setup:    return "Konfigurerar"
        case .plan:     return "Planerar"
        case .build:    return "Skriver kod"
        case .push:     return "Pushar"
        case .done:     return "Klart"
        }
    }
}

// MARK: - Status text helpers — String (tool names)

extension String {
    /// Maps a raw tool name → a human-readable Swedish pill label.
    var liveToolPillText: String {
        let t = self.lowercased()
        if t.hasPrefix("web_search") { return "Letar" }
        if t.hasPrefix("server_ask") { return "Frågar Brain" }
        if t.hasPrefix("server_exec") { return "Kör kommando" }
        if t.hasPrefix("server_status") { return "Serverstatus" }
        if t.hasPrefix("server_repos") { return "Listar repos" }
        if t.hasPrefix("github_list") { return "Hämtar från GitHub" }
        if t.hasPrefix("github_get") { return "Läser GitHub" }
        if t.hasPrefix("github_create_pull") { return "Öppnar PR" }
        if t.hasPrefix("github_create") { return "Skapar på GitHub" }
        if t.hasPrefix("github") { return "GitHub" }
        if t.hasPrefix("read_file") { return "Letar" }
        if t.hasPrefix("write_file") || t.hasPrefix("create_file") { return "Skriver kod" }
        if t.hasPrefix("list_files") || t.hasPrefix("list_dir") { return "Letar" }
        if t.hasPrefix("bash") || t.hasPrefix("run_command") || t.hasPrefix("execute") { return "Kör kommando" }
        if t.hasPrefix("search") { return "Letar" }
        if t.hasPrefix("memory") { return "Minnet" }
        if t.hasPrefix("image") { return "Genererar bild" }
        return self
    }

    /// True if this tool name corresponds to a write/code operation.
    var isCodeWritingTool: Bool {
        let t = self.lowercased()
        return t.hasPrefix("write_file") || t.hasPrefix("create_file")
    }
}

// MARK: - ActivityState
// Maps the current model state to one of the 10 visual designs from VisualsTest.
// Each case corresponds precisely to a Visual1–Visual10 struct.

enum ActivityState {
    case thinking           // Visual 1: Terminal Pulse  — Tänker / resonerar
    case writingCode        // Visual 2: Streaming Code  — Skriver kod
    case searching          // Visual 3: Glass Orb       — Söker
    case building           // Visual 4: Waveform Bar    — Bygger / kompilerar
    case scanningFiles      // Visual 5: Scanning Lines  — Läser / skannar filer
    case multipleTools      // Visual 6: Particle Swarm  — Flera verktyg
    case fetchingData       // Visual 7: Neon Ring       — Hämtar data
    case analyzing          // Visual 8: Matrix Rain     — Analyserar resultat
    case waiting            // Visual 9: Breathing Dot   — Väntar / idle
    case error              // Visual 10: Glitch Retry   — Fel / försöker igen

    // MARK: Derive from raw tool name

    static func fromTool(_ toolName: String, toolCount: Int = 1) -> ActivityState {
        if toolCount > 2 { return .multipleTools }
        let t = toolName.lowercased()
        if t.hasPrefix("write_file") || t.hasPrefix("create_file") { return .writingCode }
        if t.hasPrefix("read_file")                                 { return .scanningFiles }
        if t.hasPrefix("list_files") || t.hasPrefix("list_dir")    { return .searching }
        if t.hasPrefix("web_search") || t.hasPrefix("search")      { return .searching }
        if t.hasPrefix("bash") || t.hasPrefix("run_command") || t.hasPrefix("execute") { return .building }
        if t.hasPrefix("github_list") || t.hasPrefix("github_get") { return .fetchingData }
        if t.hasPrefix("github_create_pull")                       { return .fetchingData }
        if t.hasPrefix("github")                                    { return .fetchingData }
        if t.hasPrefix("server_exec")                               { return .building }
        if t.hasPrefix("server_ask")                                { return .fetchingData }
        if t.hasPrefix("server")                                    { return .fetchingData }
        if t.hasPrefix("image")                                     { return .analyzing }
        if t.hasPrefix("memory")                                    { return .analyzing }
        return .thinking
    }

    // MARK: Derive from Swedish/English status text

    static func fromStatus(_ text: String) -> ActivityState {
        let s = text.lowercased()
        if s.contains("skriver kod") || s.contains("write") || s.contains("skapar fil") { return .writingCode }
        if s.contains("kör verktyg") || s.contains("flera verktyg")                     { return .multipleTools }
        if s.contains("letar") || s.contains("söker") || s.contains("search")          { return .searching }
        if s.contains("läser") || s.contains("skannar")                                 { return .scanningFiles }
        if s.contains("bygger") || s.contains("kompilerar") || s.contains("kör kommando") ||
           s.contains("pushar") || s.contains("konfigurerar")                           { return .building }
        if s.contains("hämtar") || s.contains("github") || s.contains("brain") ||
           s.contains("frågar") || s.contains("ansluter")                               { return .fetchingData }
        if s.contains("analyserar")                                                      { return .analyzing }
        if s.contains("väntar") || s.contains("förbereder")                             { return .waiting }
        if s.contains("fel") || s.contains("error") || s.contains("retry")             { return .error }
        // covers "Tänker", "Planerar", "Undersöker", "Slutför",
        // "Opus tänker", "Qwen tänker", "Minimax tänker" …
        return .thinking
    }
}

// MARK: - PipelinePhase → ActivityState

extension PipelinePhase {
    var activityState: ActivityState {
        switch self {
        case .idle:     return .waiting
        case .spec:     return .thinking
        case .research: return .searching
        case .setup:    return .building
        case .plan:     return .thinking
        case .build:    return .writingCode
        case .push:     return .building
        case .done:     return .waiting
        }
    }
}

// MARK: - ChatManager.ThinkingPhase → ActivityState

extension ChatManager.ThinkingPhase {
    var activityState: ActivityState {
        switch self {
        case .idle:           return .waiting
        case .preparing:      return .waiting
        case .connecting:     return .fetchingData
        case .thinking:       return .thinking
        case .responding:     return .thinking
        case .executingTools: return .multipleTools
        case .finishing:      return .thinking
        }
    }
}

// MARK: - NaviVisualActivity
// The single entry-point for live model-activity visuals.
// Simplified: ONLY Visual1 (with dynamic label) and Visual2 (code writing).
// Visual1 label changes based on what the model is actually doing.

struct NaviVisualActivity: View {
    let state: ActivityState

    // MARK: Label + terminal text for Visual1

    private var visual1Label: String {
        switch state {
        case .thinking:      return "Tänker…"
        case .writingCode:   return "Skriver kod…"
        case .searching:     return "Söker…"
        case .building:      return "Bygger…"
        case .scanningFiles: return "Läser…"
        case .multipleTools: return "Kör verktyg…"
        case .fetchingData:  return "Hämtar data…"
        case .analyzing:     return "Analyserar…"
        case .waiting:       return "Förbereder…"
        case .error:         return "Försöker igen…"
        }
    }

    private var visual1Terminal: String {
        switch state {
        case .thinking:      return "resonerar"
        case .writingCode:   return "skriver"
        case .searching:     return "söker"
        case .building:      return "kompilerar"
        case .scanningFiles: return "skannar filer"
        case .multipleTools: return "kör verktyg"
        case .fetchingData:  return "hämtar"
        case .analyzing:     return "analyserar"
        case .waiting:       return "förbereder"
        case .error:         return "retry"
        }
    }

    var body: some View {
        if state == .writingCode {
            Visual2_StreamingCode()
        } else {
            Visual1_TerminalPulse(label: visual1Label, terminalText: visual1Terminal)
        }
    }

    // MARK: Convenience constructors

    static func forTool(_ toolName: String, count: Int = 1) -> NaviVisualActivity {
        NaviVisualActivity(state: .fromTool(toolName, toolCount: count))
    }

    static func forStatus(_ statusText: String) -> NaviVisualActivity {
        NaviVisualActivity(state: .fromStatus(statusText))
    }

    static func forPhase(_ phase: PipelinePhase) -> NaviVisualActivity {
        NaviVisualActivity(state: phase.activityState)
    }
}

// MARK: - Previews

#Preview("NaviActivityPill") {
    VStack(spacing: 12) {
        NaviActivityPill(statusText: "Tänker")
        NaviActivityPill(statusText: "Letar", items: ["web_search"])
        NaviActivityPill(
            statusText: "3 verktyg kördes",
            items: ["github_get_repo", "github_list_branches", "github_list_commits"],
            isLive: false
        )
        NaviActivityPill(statusText: "Skriver kod", items: ["write_file"])
    }
    .padding()
    .background(Color.chatBackground)
}

#Preview("NaviCodeLiveCard") {
    NaviCodeLiveCard(
        fileName: "HomeView.swift",
        liveCode: """
        struct HomeView: View {
            var body: some View {
                VStack {
                    Text("Hello, World!")
                        .font(.title)
                }
            }
        }
        """
    )
    .padding()
    .background(Color.chatBackground)
}
