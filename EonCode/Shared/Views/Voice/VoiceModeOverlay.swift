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
            Image(systemName: "waveform")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.white)
        } else if vm.isProcessing {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
        } else if vm.isSpeaking {
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.white)
        } else {
            Image(systemName: "mic.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.white)
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
        .font(.system(size: 14, weight: .medium))
    }
}
