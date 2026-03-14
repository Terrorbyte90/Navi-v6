import SwiftUI
import Combine

// MARK: - VisualsTest
// Preview-only file: 10 distinct AI activity indicator designs
// Navigate with arrows, pick your favorite, then apply across the app.

struct VisualsTest: View {
    @State private var currentVisual = 1
    private let totalVisuals = 10

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text("Visual Test")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Visual \(currentVisual) / \(totalVisuals)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.1)

            // Chat area
            ScrollView {
                VStack(spacing: 0) {
                    fakeConversation

                    // Active visual — sits naturally in the chat flow
                    HStack(alignment: .top, spacing: 10) {
                        assistantAvatar
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 0) {
                            visualForIndex(currentVisual)
                        }

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .id(currentVisual)
                }
                .padding(.vertical, 16)
            }
            .background(Color.chatBackground)

            Divider().opacity(0.1)

            // Navigation arrows
            HStack(spacing: 24) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentVisual = currentVisual > 1 ? currentVisual - 1 : totalVisuals
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentNavi)
                        .frame(width: 48, height: 48)
                        .background(Color.accentNavi.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text(visualTitle(currentVisual))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(visualSubtitle(currentVisual))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 140)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentVisual = currentVisual < totalVisuals ? currentVisual + 1 : 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentNavi)
                        .frame(width: 48, height: 48)
                        .background(Color.accentNavi.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 14)
            .background(Color.chatBackground)
        }
        .background(Color.chatBackground)
    }

    // MARK: - Fake conversation

    var fakeConversation: some View {
        VStack(spacing: 0) {
            // User message 1
            HStack {
                Spacer(minLength: 60)
                Text("Kan du bygga en inloggningssida med OAuth?")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.userBubble)
                    .cornerRadius(20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            // Assistant message 1
            HStack(alignment: .top, spacing: 10) {
                assistantAvatar
                    .padding(.top, 2)
                Text("Absolut! Jag skapar en inloggningsvy med Google och Apple OAuth. Låt mig börja med att sätta upp strukturen.")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // User message 2
            HStack {
                Spacer(minLength: 60)
                Text("Perfekt, kör på!")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.userBubble)
                    .cornerRadius(20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    var assistantAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentNavi.opacity(0.15), Color.accentNavi.opacity(0.02)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 14
                    )
                )
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.accentNavi.opacity(0.5))
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Visual router

    @ViewBuilder
    func visualForIndex(_ index: Int) -> some View {
        switch index {
        case 1:  Visual1_TerminalPulse()
        case 2:  Visual2_StreamingCode()
        case 3:  Visual3_GlassOrb()
        case 4:  Visual4_WaveformBar()
        case 5:  Visual5_ScanningLines()
        case 6:  Visual6_ParticleSwarm()
        case 7:  Visual7_NeonRing()
        case 8:  Visual8_MatrixRain()
        case 9:  Visual9_BreathingDot()
        case 10: Visual10_GlitchRetry()
        default: EmptyView()
        }
    }

    func visualTitle(_ index: Int) -> String {
        switch index {
        case 1:  return "Terminal Pulse"
        case 2:  return "Streaming Code"
        case 3:  return "Glass Orb"
        case 4:  return "Waveform"
        case 5:  return "Scanner"
        case 6:  return "Particle Swarm"
        case 7:  return "Neon Ring"
        case 8:  return "Matrix Rain"
        case 9:  return "Breathing Dot"
        case 10: return "Glitch Retry"
        default: return ""
        }
    }

    func visualSubtitle(_ index: Int) -> String {
        switch index {
        case 1:  return "Tänker / resonerar"
        case 2:  return "Skriver kod"
        case 3:  return "Söker"
        case 4:  return "Bygger / kompilerar"
        case 5:  return "Läser / skannar filer"
        case 6:  return "Flera verktyg samtidigt"
        case 7:  return "Hämtar data"
        case 8:  return "Analyserar resultat"
        case 9:  return "Väntar / idle"
        case 10: return "Fel / försöker igen"
        default: return ""
        }
    }
}

// ============================================================
// MARK: - Visual 1: Terminal Pulse — "Tänker…"
// Minimal terminal cursor blinking beside a pulsing accent line.
// ============================================================

struct Visual1_TerminalPulse: View {
    @State private var cursorVisible = true
    @State private var lineWidth: CGFloat = 0
    @State private var dotScale: CGFloat = 0.6
    @State private var phase: Double = 0
    @State private var phaseTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status label
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentNavi)
                    .frame(width: 5, height: 5)
                    .scaleEffect(dotScale)
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.7))
                Text("Tänker…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.75))
                Spacer()
                // Three pulsing dots
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.accentNavi.opacity(0.3 + 0.5 * (sin(phase + Double(i) * 0.8) + 1) / 2))
                            .frame(width: 4, height: 4)
                    }
                }
            }

            // Animated accent bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentNavi.opacity(0.1))
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentNavi.opacity(0.8), Color.accentNavi.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: lineWidth, height: 3)
            }

            // Terminal line with blinking cursor
            HStack(spacing: 2) {
                Text(">")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentNavi.opacity(0.5))
                Text("resonerar")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                Rectangle()
                    .fill(Color.accentNavi.opacity(cursorVisible ? 0.8 : 0))
                    .frame(width: 7, height: 14)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentNavi.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentNavi.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                dotScale = 1.3
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                lineWidth = 200
            }
            startPhaseTimer()
        }
        .onDisappear {
            phaseTimer?.invalidate()
            phaseTimer = nil
        }
    }

    private func startPhaseTimer() {
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            Task { @MainActor in phase += 0.08 }
        }
    }
}

// ============================================================
// MARK: - Visual 2: Streaming Code — "Skriver kod…"
// Larger card with typewriter code streaming + syntax colors.
// ============================================================

struct Visual2_StreamingCode: View {
    @State private var displayedLines: [CodeLine] = []
    @State private var currentCharIndex = 0
    @State private var currentLineIndex = 0
    @State private var cursorBlink = true
    @State private var pulse = false

    struct CodeLine: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
        let indent: Int
    }

    private let codeLines: [(String, Color, Int)] = [
        ("struct", .pink, 0),
        (" LoginView", .cyan, 0),
        (": View {", .secondary, 0),
        ("    @State", .pink, 1),
        (" private var", .secondary, 1),
        (" email = \"\"", .green, 1),
        ("    @State", .pink, 1),
        (" private var", .secondary, 1),
        (" password = \"\"", .green, 1),
        ("", .clear, 0),
        ("    var", .pink, 1),
        (" body:", .secondary, 1),
        (" some View", .cyan, 1),
        (" {", .secondary, 1),
        ("        VStack", .cyan, 2),
        ("(spacing: 24)", .secondary, 2),
        (" {", .secondary, 2),
        ("            TextField", .yellow, 3),
        ("(\"E-post\",", .green, 3),
        (" text: $email)", .secondary, 3),
        ("            SecureField", .yellow, 3),
        ("(\"Lösenord\",", .green, 3),
        (" text: $password)", .secondary, 3),
        ("            Button", .yellow, 3),
        ("(\"Logga in\")", .green, 3),
        (" {", .secondary, 3),
        ("                authenticate()", .cyan, 4),
        ("            }", .secondary, 3),
    ]

    private var flatCode: String {
        codeLines.map { $0.0 }.joined()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header pill
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.7))
                Circle()
                    .fill(Color.accentNavi)
                    .frame(width: 5, height: 5)
                    .scaleEffect(pulse ? 1.3 : 0.8)
                    .opacity(pulse ? 1.0 : 0.5)
                Text("Skriver kod…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.75))
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.accentNavi.opacity(pulse ? 0.8 : 0.3))
                            .frame(width: 4, height: 4)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.15),
                                value: pulse
                            )
                    }
                }
                Spacer()
                Text("LoginView.swift")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentNavi.opacity(0.04))
            .overlay(alignment: .bottom) {
                Divider().opacity(0.08)
            }

            // Code area — taller than other visuals
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayedLines.enumerated()), id: \.element.id) { idx, line in
                        HStack(spacing: 0) {
                            // Line number gutter
                            Text("\(idx + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.25))
                                .frame(width: 22, alignment: .trailing)
                                .padding(.trailing, 8)

                            Text(line.text)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundColor(line.color == .secondary
                                    ? .secondary.opacity(0.8)
                                    : line.color.opacity(0.9))
                        }
                        .padding(.leading, 4)
                    }

                    // Blinking cursor on current line
                    HStack(spacing: 0) {
                        Spacer().frame(width: 34)
                        Rectangle()
                            .fill(Color.accentNavi.opacity(cursorBlink ? 0.9 : 0))
                            .frame(width: 2, height: 15)
                    }
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .frame(height: 180)
            .background(NaviTheme.codeBG)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentNavi.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(12)
        .onAppear {
            pulse = true
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                cursorBlink = false
            }
            startTyping()
        }
    }

    private func startTyping() {
        // Build lines one at a time from the raw tuples
        var lineBuffer = ""
        var lineColor: Color = .secondary
        var lineIndent = 0
        var tupleIdx = 0
        var charIdx = 0

        Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { timer in
            guard tupleIdx < codeLines.count else {
                // Loop
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    displayedLines.removeAll()
                    startTyping()
                }
                timer.invalidate()
                return
            }

            let (text, color, indent) = codeLines[tupleIdx]
            lineColor = color
            lineIndent = indent

            if text.isEmpty {
                displayedLines.append(CodeLine(text: "", color: .clear, indent: 0))
                tupleIdx += 1
                return
            }

            if charIdx < text.count {
                let idx = text.index(text.startIndex, offsetBy: charIdx)
                lineBuffer.append(text[idx])
                charIdx += 1

                // Update or add line
                if let lastIdx = displayedLines.indices.last,
                   displayedLines[lastIdx].color == lineColor {
                    displayedLines[lastIdx] = CodeLine(
                        text: lineBuffer,
                        color: lineColor,
                        indent: lineIndent
                    )
                } else {
                    displayedLines.append(CodeLine(
                        text: lineBuffer,
                        color: lineColor,
                        indent: lineIndent
                    ))
                }
            } else {
                tupleIdx += 1
                charIdx = 0
                lineBuffer = ""
            }
        }
    }
}

// ============================================================
// MARK: - Visual 3: Glass Orb — "Söker…"
// Glassmorphic breathing orb with ripple rings.
// ============================================================

struct Visual3_GlassOrb: View {
    @State private var breathe = false
    @State private var ripple1 = false
    @State private var ripple2 = false
    @State private var ringRotation: Double = 0
    @State private var textOpacity: Double = 0.5

    var body: some View {
        HStack(spacing: 14) {
            // Orb area
            ZStack {
                // Outer ripple 1
                Circle()
                    .stroke(Color.accentNavi.opacity(0.15), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                    .scaleEffect(ripple1 ? 1.8 : 1.0)
                    .opacity(ripple1 ? 0.0 : 0.6)

                // Outer ripple 2
                Circle()
                    .stroke(Color.accentNavi.opacity(0.1), lineWidth: 1)
                    .frame(width: 44, height: 44)
                    .scaleEffect(ripple2 ? 2.2 : 1.0)
                    .opacity(ripple2 ? 0.0 : 0.4)

                // Glass orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentNavi.opacity(0.3),
                                Color.accentNavi.opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 22
                        )
                    )
                    .frame(width: 44, height: 44)
                    .scaleEffect(breathe ? 1.08 : 0.92)
                    .overlay(
                        Circle()
                            .stroke(Color.accentNavi.opacity(0.25), lineWidth: 1.5)
                    )

                // Inner glow
                Circle()
                    .fill(Color.accentNavi.opacity(breathe ? 0.6 : 0.3))
                    .frame(width: 14, height: 14)
                    .blur(radius: 3)

                // Rotating ring
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentNavi.opacity(0.4), lineWidth: 2)
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(ringRotation))
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("Söker…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.8))

                Text("Genomsöker projekt och filer")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(textOpacity))

                // Search progress dots
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.accentNavi.opacity(
                                breathe && i < 3 ? 0.7 : 0.15
                            ))
                            .frame(width: 16, height: 3)
                            .animation(
                                .easeInOut(duration: 0.4)
                                    .delay(Double(i) * 0.1),
                                value: breathe
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentNavi.opacity(0.12), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                ripple1 = true
            }
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false).delay(0.7)) {
                ripple2 = true
            }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                textOpacity = 0.8
            }
        }
    }
}

// ============================================================
// MARK: - Visual 4: Waveform Bar — "Bygger…"
// Audio-waveform-style bars pulsing rhythmically.
// ============================================================

struct Visual4_WaveformBar: View {
    @State private var phase: Double = 0
    @State private var progress: CGFloat = 0

    private let barCount = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.7))
                Text("Bygger…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.75))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.accentNavi.opacity(0.5))
            }

            // Waveform
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let normalized = Double(i) / Double(barCount)
                    let height = 6 + 18 * abs(sin(phase + normalized * .pi * 3))

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentNavi.opacity(0.9),
                                    Color.accentNavi.opacity(0.3)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4, height: CGFloat(height))
                }
            }
            .frame(height: 28, alignment: .center)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentNavi.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentNavi.opacity(0.6))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)

            HStack(spacing: 8) {
                Text("Kompilerar 12 filer")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.5))
                Spacer()
                Text("swift build")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.35))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentNavi.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentNavi.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(12)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
                phase += 0.06
            }
            withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
                progress = 1.0
            }
        }
    }
}

// ============================================================
// MARK: - Visual 5: Scanning Lines — "Läser filer…"
// Horizontal scan lines sweep across file names.
// ============================================================

struct Visual5_ScanningLines: View {
    @State private var scanOffset: CGFloat = -1
    @State private var currentFileIndex = 0
    @State private var fileOpacity: Double = 1.0

    private let files = [
        "ContentView.swift",
        "AppDelegate.swift",
        "NetworkManager.swift",
        "UserModel.swift",
        "AuthService.swift"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.7))
                Text("Läser filer…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.75))
                Spacer()
                Text("\(currentFileIndex + 1)/\(files.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.4))
            }

            // File being scanned
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(NaviTheme.codeBG)
                    .frame(height: 48)

                // Scan line
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentNavi.opacity(0),
                                    Color.accentNavi.opacity(0.3),
                                    Color.accentNavi.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 60, height: 48)
                        .offset(x: scanOffset * geo.size.width)
                }
                .clipped()

                // File name
                HStack(spacing: 6) {
                    Image(systemName: "swift")
                        .font(.system(size: 11))
                        .foregroundColor(.orange.opacity(0.7))
                    Text(files[currentFileIndex])
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(NaviTheme.codeText)
                        .opacity(fileOpacity)
                }
            }
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NaviTheme.codeBorder, lineWidth: 0.5)
            )

            // Scanned files list
            HStack(spacing: 3) {
                ForEach(0..<files.count, id: \.self) { i in
                    Circle()
                        .fill(i <= currentFileIndex
                              ? Color.accentNavi.opacity(0.6)
                              : Color.secondary.opacity(0.15))
                        .frame(width: 5, height: 5)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentNavi.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentNavi.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(12)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                scanOffset = 1.1
            }
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                withAnimation(.easeOut(duration: 0.2)) { fileOpacity = 0.3 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    currentFileIndex = (currentFileIndex + 1) % files.count
                    withAnimation(.easeIn(duration: 0.3)) { fileOpacity = 1.0 }
                }
            }
        }
    }
}

// ============================================================
// MARK: - Visual 6: Particle Swarm — "Flera verktyg…"
// Canvas-rendered particles orbiting a center, each representing a tool.
// ============================================================

struct Visual6_ParticleSwarm: View {
    @State private var phase: Double = 0

    private let tools = [
        ("terminal", "Kör kommando"),
        ("magnifyingglass", "Söker"),
        ("square.and.pencil", "Skriver"),
        ("folder", "Listar filer"),
    ]

    private func particleOffset(index i: Int) -> CGSize {
        let angle = phase + Double(i) * (.pi * 2 / Double(tools.count))
        let radius: CGFloat = 32
        return CGSize(width: cos(angle) * Double(radius), height: sin(angle) * Double(radius) * 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.7))
                Text("Kör verktyg…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.75))
                Spacer()
                Text("\(tools.count) aktiva")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.accentNavi.opacity(0.4))
            }

            // Particle canvas
            ZStack {
                // Orbital paths
                ForEach(0..<tools.count, id: \.self) { i in
                    VStack(spacing: 2) {
                        Image(systemName: tools[i].0)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentNavi)
                        Text(tools[i].1)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.accentNavi.opacity(0.08))
                            .frame(width: 38, height: 38)
                    )
                    .offset(particleOffset(index: i))
                }

                // Center dot
                Circle()
                    .fill(Color.accentNavi.opacity(0.4))
                    .frame(width: 8, height: 8)

                // Orbit ring
                Ellipse()
                    .stroke(Color.accentNavi.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: 68, height: 34)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentNavi.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentNavi.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(12)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
                phase += 0.015
            }
        }
    }
}

// ============================================================
// MARK: - Visual 7: Neon Ring — "Hämtar data…"
// Glowing ring with rotating gradient and data transfer indicators.
// ============================================================

struct Visual7_NeonRing: View {
    @State private var rotation: Double = 0
    @State private var dataFlash = false
    @State private var bytesReceived = 0

    var body: some View {
        HStack(spacing: 14) {
            // Neon ring
            ZStack {
                // Glow background
                Circle()
                    .fill(Color.accentNavi.opacity(0.06))
                    .frame(width: 52, height: 52)

                // Base ring
                Circle()
                    .stroke(Color.accentNavi.opacity(0.1), lineWidth: 3)
                    .frame(width: 40, height: 40)

                // Animated gradient ring
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.accentNavi.opacity(0.0),
                                Color.accentNavi.opacity(0.4),
                                Color.accentNavi.opacity(0.9),
                                Color.accentNavi
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(rotation))

                // Center icon
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentNavi.opacity(dataFlash ? 1.0 : 0.5))
                    .scaleEffect(dataFlash ? 1.1 : 0.95)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Hämtar data…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.8))

                HStack(spacing: 6) {
                    // Data transfer animation
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            Rectangle()
                                .fill(Color.accentNavi.opacity(dataFlash && i < 3 ? 0.7 : 0.15))
                                .frame(width: 3, height: 8 - CGFloat(i))
                                .animation(
                                    .easeInOut(duration: 0.3).delay(Double(i) * 0.08),
                                    value: dataFlash
                                )
                        }
                    }

                    Text("\(bytesReceived) KB")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Text("api.anthropic.com")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.35))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.accentNavi.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentNavi.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(12)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                dataFlash = true
            }
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                bytesReceived += Int.random(in: 2...18)
                if bytesReceived > 9999 { bytesReceived = 0 }
            }
        }
    }
}

// ============================================================
// MARK: - Visual 8: Matrix Rain — "Analyserar…"
// Vertical character streams falling like The Matrix.
// ============================================================

struct Visual8_MatrixRain: View {
    @State private var columns: [[MatrixChar]] = []
    @State private var tick = 0

    struct MatrixChar: Identifiable {
        let id = UUID()
        var char: String
        var opacity: Double
    }

    private let columnCount = 14
    private let rowCount = 6
    private let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789{}[]();:=><+-*/"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.7))
                Text("Analyserar…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentNavi.opacity(0.75))
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Color.accentNavi.opacity(tick % 3 == i ? 0.8 : 0.2))
                            .frame(width: 4, height: 4)
                    }
                }
            }

            // Matrix rain area
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<min(columns.count, columnCount), id: \.self) { col in
                    VStack(spacing: 1) {
                        ForEach(columns[col]) { mc in
                            Text(mc.char)
                                .font(.system(size: 10, weight: .light, design: .monospaced))
                                .foregroundColor(Color.accentNavi.opacity(mc.opacity))
                        }
                    }
                }
            }
            .frame(height: CGFloat(rowCount) * 14)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
            )
            .cornerRadius(8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentNavi.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentNavi.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(12)
        .onAppear {
            initColumns()
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                tick += 1
                updateRain()
            }
        }
    }

    private func initColumns() {
        columns = (0..<columnCount).map { _ in
            (0..<rowCount).map { row in
                MatrixChar(
                    char: randomChar(),
                    opacity: Double(rowCount - row) / Double(rowCount) * 0.6
                )
            }
        }
    }

    private func updateRain() {
        for col in 0..<columns.count {
            // Shift down
            for row in stride(from: columns[col].count - 1, through: 1, by: -1) {
                columns[col][row] = MatrixChar(
                    char: columns[col][row - 1].char,
                    opacity: columns[col][row - 1].opacity * 0.75
                )
            }
            // New char at top
            columns[col][0] = MatrixChar(
                char: randomChar(),
                opacity: Double.random(in: 0.5...1.0)
            )
        }
    }

    private func randomChar() -> String {
        String(chars.randomElement()!)
    }
}

// ============================================================
// MARK: - Visual 9: Breathing Dot — "Väntar…"
// Minimal single dot breathing with concentric rings fading out.
// ============================================================

struct Visual9_BreathingDot: View {
    @State private var breathe = false
    @State private var ring1 = false
    @State private var ring2 = false
    @State private var ring3 = false
    @State private var textShimmer = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                // Concentric rings
                Circle()
                    .stroke(Color.accentNavi.opacity(0.05), lineWidth: 1)
                    .frame(width: 48, height: 48)
                    .scaleEffect(ring3 ? 1.3 : 1.0)
                    .opacity(ring3 ? 0.0 : 0.3)

                Circle()
                    .stroke(Color.accentNavi.opacity(0.08), lineWidth: 1)
                    .frame(width: 36, height: 36)
                    .scaleEffect(ring2 ? 1.4 : 1.0)
                    .opacity(ring2 ? 0.0 : 0.4)

                Circle()
                    .stroke(Color.accentNavi.opacity(0.12), lineWidth: 1)
                    .frame(width: 24, height: 24)
                    .scaleEffect(ring1 ? 1.5 : 1.0)
                    .opacity(ring1 ? 0.0 : 0.5)

                // Core dot
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentNavi.opacity(breathe ? 0.7 : 0.3),
                                Color.accentNavi.opacity(breathe ? 0.2 : 0.05)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 10
                        )
                    )
                    .frame(width: 16, height: 16)
                    .scaleEffect(breathe ? 1.15 : 0.85)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text("Väntar…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary.opacity(textShimmer ? 0.7 : 0.4))

                Text("Redo att fortsätta")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.35))

                // Idle pulse line
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(Color.accentNavi.opacity(breathe && i == 1 ? 0.3 : 0.08))
                            .frame(width: i == 1 ? 24 : 12, height: 3)
                            .animation(
                                .easeInOut(duration: 1.5).delay(Double(i) * 0.2),
                                value: breathe
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.02))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(14)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                ring1 = true
            }
            withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false).delay(0.5)) {
                ring2 = true
            }
            withAnimation(.easeOut(duration: 3.0).repeatForever(autoreverses: false).delay(1.0)) {
                ring3 = true
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                textShimmer = true
            }
        }
    }
}

// ============================================================
// MARK: - Visual 10: Glitch Retry — "Fel — försöker igen…"
// Error state with glitch effect and countdown retry.
// ============================================================

struct Visual10_GlitchRetry: View {
    @State private var glitchOffset: CGFloat = 0
    @State private var retryCountdown = 5
    @State private var flash = false
    @State private var shake = false
    @State private var barProgress: CGFloat = 0

    private let errorColor = Color(naviHex: "E53935")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Error header with glitch
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(errorColor.opacity(flash ? 1.0 : 0.7))

                ZStack {
                    Text("Fel — försöker igen…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(errorColor.opacity(0.85))
                        .offset(x: glitchOffset)

                    // Glitch shadow
                    Text("Fel — försöker igen…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.cyan.opacity(0.15))
                        .offset(x: -glitchOffset, y: glitchOffset * 0.5)
                }

                Spacer()

                Text("om \(retryCountdown)s")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(errorColor.opacity(0.5))
            }
            .offset(x: shake ? -3 : 0)

            // Error details
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(errorColor.opacity(0.5))
                    .frame(width: 2, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("429 Too Many Requests")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(errorColor.opacity(0.7))
                    Text("Rate limit — väntar på slot")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }

            // Retry progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(errorColor.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [errorColor.opacity(0.6), errorColor.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * barProgress)
                }
            }
            .frame(height: 3)

            // Retry attempts
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    HStack(spacing: 3) {
                        Circle()
                            .fill(i < 2 ? errorColor.opacity(0.5) : Color.secondary.opacity(0.2))
                            .frame(width: 4, height: 4)
                        Text("Försök \(i + 1)")
                            .font(.system(size: 9))
                            .foregroundColor(i < 2 ? errorColor.opacity(0.5) : .secondary.opacity(0.3))
                    }
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(errorColor.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(errorColor.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(12)
        .onAppear {
            // Glitch effect
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if Bool.random() && Int.random(in: 0...5) == 0 {
                    glitchOffset = CGFloat.random(in: -3...3)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        glitchOffset = 0
                    }
                }
            }

            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                flash = true
            }

            // Shake
            withAnimation(.interpolatingSpring(stiffness: 800, damping: 4).repeatForever(autoreverses: true)) {
                shake = true
            }

            // Progress bar
            withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                barProgress = 1.0
            }

            // Countdown
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if retryCountdown > 0 {
                    retryCountdown -= 1
                } else {
                    retryCountdown = 5
                    barProgress = 0
                    withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
                        barProgress = 1.0
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Visuals Test") {
    VisualsTest()
        .frame(width: 400, height: 700)
}

#Preview("Visual 2 — Code Streaming") {
    Visual2_StreamingCode()
        .padding(20)
        .background(Color.chatBackground)
        .frame(width: 360)
}
