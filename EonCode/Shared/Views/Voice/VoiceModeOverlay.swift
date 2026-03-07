import SwiftUI

struct VoiceModeOverlay: View {
    @StateObject private var vm = VoiceModeManager.shared
    @Binding var isPresented: Bool

    @State private var outerPulse = false
    @State private var innerPulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 0) {
                closeBar
                Spacer()
                transcriptArea
                Spacer()
                pulsingCircle
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
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
                    .background(Color.white.opacity(0.1), in: Circle())
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

    private var pulsingCircle: some View {
        let baseSize: CGFloat = 120
        let levelBoost = vm.audioLevel * 40

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [circleColor.opacity(0.15), circleColor.opacity(0.02)],
                        center: .center, startRadius: 40, endRadius: baseSize
                    )
                )
                .frame(width: baseSize + 80 + levelBoost, height: baseSize + 80 + levelBoost)
                .scaleEffect(outerPulse ? 1.12 : 0.95)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [circleColor.opacity(0.3), circleColor.opacity(0.08)],
                        center: .center, startRadius: 20, endRadius: 60
                    )
                )
                .frame(width: baseSize + 30 + levelBoost * 0.5, height: baseSize + 30 + levelBoost * 0.5)
                .scaleEffect(innerPulse ? 1.08 : 0.96)

            Circle()
                .fill(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: baseSize, height: baseSize)
                .shadow(color: circleColor.opacity(0.5), radius: 20)

            circleIcon
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
    private var circleIcon: some View {
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

    private var circleColor: Color {
        if vm.isListening { return Color(red: 0.3, green: 0.7, blue: 0.5) }
        if vm.isProcessing { return Color(red: 0.4, green: 0.5, blue: 0.8) }
        if vm.isSpeaking { return Color(red: 0.6, green: 0.4, blue: 0.8) }
        return Color(red: 0.45, green: 0.65, blue: 0.6)
    }

    private var gradientColors: [Color] {
        if vm.isListening {
            return [Color(red: 0.3, green: 0.75, blue: 0.55), Color(red: 0.2, green: 0.55, blue: 0.45)]
        }
        if vm.isProcessing {
            return [Color(red: 0.4, green: 0.5, blue: 0.85), Color(red: 0.3, green: 0.4, blue: 0.7)]
        }
        if vm.isSpeaking {
            return [Color(red: 0.65, green: 0.4, blue: 0.85), Color(red: 0.5, green: 0.3, blue: 0.7)]
        }
        return [Color(red: 0.45, green: 0.67, blue: 0.61), Color(red: 0.3, green: 0.55, blue: 0.5)]
    }

    private var statusLabel: some View {
        Group {
            if let error = vm.errorMessage {
                Text(error)
                    .foregroundColor(.red.opacity(0.8))
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
