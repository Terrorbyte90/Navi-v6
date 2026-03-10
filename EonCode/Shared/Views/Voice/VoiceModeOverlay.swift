import SwiftUI

struct VoiceModeOverlay: View {
    @StateObject private var vm = VoiceModeManager.shared
    @Binding var isPresented: Bool

    @State private var outerPulse = false
    @State private var innerPulse = false

    var body: some View {
        ZStack {
            // Dark glass background
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 0) {
                closeBar
                Spacer()
                transcriptArea
                Spacer()
                glassOrb
                Spacer()
                statusLabel
                    .padding(.bottom, 60)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .onChange(of: vm.isActive) { active in
            if !active { isPresented = false }
        }
    }

    private var closeBar: some View {
        HStack {
            Spacer()
            Button {
                vm.stop()
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.top, 16)
        }
    }

    private var transcriptArea: some View {
        VStack(spacing: 20) {
            if !vm.assistantTranscript.isEmpty {
                Text(vm.assistantTranscript)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !vm.userTranscript.isEmpty {
                Text(vm.userTranscript)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vm.userTranscript)
        .animation(.easeInOut(duration: 0.3), value: vm.assistantTranscript)
    }

    // MARK: - Glass orb (replaces flat colored circles)

    private var glassOrb: some View {
        let baseSize: CGFloat = 120
        let levelBoost = vm.audioLevel * 40

        return ZStack {
            // Outer glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColor.opacity(0.12), orbColor.opacity(0.01)],
                        center: .center, startRadius: 40, endRadius: baseSize
                    )
                )
                .frame(width: baseSize + 80 + levelBoost, height: baseSize + 80 + levelBoost)
                .scaleEffect(outerPulse ? 1.12 : 0.95)

            // Middle glass layer
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [orbColor.opacity(0.2), orbColor.opacity(0.05)],
                                center: .center, startRadius: 20, endRadius: 60
                            )
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .white.opacity(0.05)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .frame(width: baseSize + 30 + levelBoost * 0.5, height: baseSize + 30 + levelBoost * 0.5)
                .scaleEffect(innerPulse ? 1.08 : 0.96)

            // Inner glass orb
            Circle()
                .fill(
                    LinearGradient(
                        colors: orbGradient,
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Glass highlight reflection
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .topLeading, endPoint: .center
                            )
                        )
                        .frame(width: baseSize * 0.6, height: baseSize * 0.6)
                        .offset(x: -baseSize * 0.08, y: -baseSize * 0.08)
                )
                .frame(width: baseSize, height: baseSize)
                .shadow(color: orbColor.opacity(0.4), radius: 20)

            orbIcon
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                outerPulse = true
            }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                innerPulse = true
            }
        }
        .animation(.spring(response: 0.3), value: vm.audioLevel)
    }

    @ViewBuilder
    private var orbIcon: some View {
        if vm.isListening {
            // Dynamic sound bars that react to audio level
            VoiceWaveBars(audioLevel: vm.audioLevel)
                .frame(width: 50, height: 36)
        } else if vm.isProcessing {
            // Orbiting dots
            OrbitingDots()
                .frame(width: 44, height: 44)
        } else if vm.isSpeaking {
            // Pulsating speech rings
            SpeechRings(audioLevel: vm.audioLevel)
                .frame(width: 48, height: 48)
        } else {
            // Breathing mic glow
            BreathingMic()
                .frame(width: 40, height: 40)
        }
    }

    private var orbColor: Color {
        if vm.isListening  { return Color(naviHex: "4CAF50") }  // Green
        if vm.isProcessing { return Color.accentNavi }           // Terra cotta
        if vm.isSpeaking   { return Color(naviHex: "7C5CBF") }  // Purple
        return Color.accentNavi.opacity(0.7)
    }

    private var orbGradient: [Color] {
        if vm.isListening {
            return [Color(naviHex: "4CAF50").opacity(0.7), Color(naviHex: "388E3C").opacity(0.5)]
        }
        if vm.isProcessing {
            return [Color.accentNavi.opacity(0.7), Color(naviHex: "c85a3a").opacity(0.5)]
        }
        if vm.isSpeaking {
            return [Color(naviHex: "7C5CBF").opacity(0.7), Color(naviHex: "5E35B1").opacity(0.5)]
        }
        return [Color.accentNavi.opacity(0.5), Color(naviHex: "c85a3a").opacity(0.3)]
    }

    private var statusLabel: some View {
        Group {
            if let error = vm.errorMessage {
                Text(error)
                    .foregroundColor(NaviTheme.error.opacity(0.8))
            } else if vm.isListening {
                Text("Lyssnar…")
                    .foregroundColor(.white.opacity(0.5))
            } else if vm.isProcessing {
                Text("Tänker…")
                    .foregroundColor(.white.opacity(0.5))
            } else if vm.isSpeaking {
                Text("Talar…")
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text("Röstläge")
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
    }
}

// MARK: - VoiceWaveBars — reactive audio level bars

struct VoiceWaveBars: View {
    let audioLevel: CGFloat
    @State private var phases: [CGFloat] = [0, 0.3, 0.6, 0.1, 0.4]

    private let barCount = 5
    private let barWidth: CGFloat = 4
    private let spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(.white)
                    .frame(width: barWidth, height: barHeight(for: i))
                    .animation(.spring(response: 0.15, dampingFraction: 0.5), value: audioLevel)
            }
        }
        .drawingGroup()
        .onAppear { startAnimating() }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 8
        let maxAdd: CGFloat = 28
        let phase = phases[index % phases.count]
        let level = max(0, audioLevel + phase * 0.3 - 0.1)
        return base + maxAdd * min(1, level)
    }

    private func startAnimating() {
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            phases = (0..<barCount).map { _ in CGFloat.random(in: 0...1) }
        }
    }
}

// MARK: - OrbitingDots — thinking/processing animation

struct OrbitingDots: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(0.8 - Double(i) * 0.2))
                    .frame(width: 7, height: 7)
                    .offset(x: 16)
                    .rotationEffect(.degrees(rotation + Double(i) * 120))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - SpeechRings — pulsating rings that follow speech

struct SpeechRings: View {
    let audioLevel: CGFloat
    @State private var ring1 = false
    @State private var ring2 = false
    @State private var ring3 = false

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 1.5)
                .scaleEffect(1.0 + audioLevel * 0.4 + (ring1 ? 0.15 : 0))
                .opacity(ring1 ? 0.3 : 0.8)

            // Middle ring
            Circle()
                .stroke(.white.opacity(0.25), lineWidth: 2)
                .scaleEffect(0.7 + audioLevel * 0.3 + (ring2 ? 0.1 : 0))
                .opacity(ring2 ? 0.4 : 0.9)

            // Inner ring
            Circle()
                .stroke(.white.opacity(0.4), lineWidth: 2.5)
                .scaleEffect(0.4 + audioLevel * 0.2 + (ring3 ? 0.05 : 0))

            // Center dot
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .scaleEffect(1 + audioLevel * 0.5)
        }
        .drawingGroup()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { ring1 = true }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.2)) { ring2 = true }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(0.3)) { ring3 = true }
        }
        .animation(.spring(response: 0.2), value: audioLevel)
    }
}

// MARK: - BreathingMic — subtle idle animation

struct BreathingMic: View {
    @State private var breathe = false
    @State private var glow = false

    var body: some View {
        ZStack {
            // Glow ring
            Circle()
                .fill(.white.opacity(0.06))
                .scaleEffect(glow ? 1.3 : 1.0)

            // Mic icon with breathing
            Image(systemName: "mic.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .scaleEffect(breathe ? 1.08 : 0.95)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}
