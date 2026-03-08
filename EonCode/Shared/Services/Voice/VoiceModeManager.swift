import Foundation
import Speech
import AVFoundation

@MainActor
final class VoiceModeManager: ObservableObject {
    static let shared = VoiceModeManager()

    @Published var isActive = false
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var isProcessing = false
    @Published var userTranscript = ""
    @Published var assistantTranscript = ""
    @Published var audioLevel: CGFloat = 0
    @Published var errorMessage: String?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var consecutiveRecognitionErrors = 0
    private let maxRecognitionRetries = 3
    private let silenceThreshold: TimeInterval = 1.8

    private init() {
        // Prefer Swedish speech recognition
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "sv-SE"))
            ?? SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        userTranscript = ""
        assistantTranscript = ""
        errorMessage = nil
        consecutiveRecognitionErrors = 0

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.configureAudioSessionForRecording()
                    self.startListening()
                default:
                    self.errorMessage = "Mikrofonåtkomst nekad"
                    self.isActive = false
                }
            }
        }
    }

    func stop() {
        isActive = false
        stopListening()
        ElevenLabsClient.shared.stop()
        SystemTTSFallback.shared.stop()
        isListening = false
        isSpeaking = false
        isProcessing = false
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - Audio session management

    private func configureAudioSessionForRecording() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            NaviLog.error("VoiceMode: kunde inte konfigurera audio session för inspelning", error: error)
            errorMessage = "Kunde inte starta mikrofon"
            isActive = false
        }
        #endif
    }

    private func configureAudioSessionForPlayback() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            NaviLog.error("VoiceMode: kunde inte konfigurera audio session för uppspelning", error: error)
        }
        #endif
    }

    // MARK: - Speech recognition

    private func startListening() {
        guard !isListening else { return }  // Prevent double-start
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Taligenkänning ej tillgänglig"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            let level = Self.calculateLevel(buffer: buffer)
            Task { @MainActor [weak self] in
                self?.audioLevel = CGFloat(level)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            errorMessage = nil
        } catch {
            // Clean up and retry once
            NaviLog.warning("VoiceMode: första start misslyckades, försöker igen…")
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.prepare()
            do {
                try audioEngine.start()
                isListening = true
                errorMessage = nil
            } catch {
                NaviLog.error("VoiceMode: kunde inte starta ljudinspelning", error: error)
                errorMessage = "Kunde inte starta ljudinspelning"
                return
            }
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, self.isListening else { return }

                if let result {
                    self.consecutiveRecognitionErrors = 0
                    self.userTranscript = result.bestTranscription.formattedString
                    self.silenceTimer?.invalidate()
                    if result.isFinal {
                        self.handleUserFinishedSpeaking()
                    } else {
                        self.silenceTimer = Timer.scheduledTimer(
                            withTimeInterval: self.silenceThreshold, repeats: false
                        ) { _ in
                            Task { @MainActor [weak self] in
                                self?.handleUserFinishedSpeaking()
                            }
                        }
                    }
                }

                if let error {
                    self.consecutiveRecognitionErrors += 1
                    NaviLog.warning("VoiceMode: igenkänningsfel (\(self.consecutiveRecognitionErrors)): \(error.localizedDescription)")

                    if !self.userTranscript.isEmpty {
                        self.handleUserFinishedSpeaking()
                    } else if self.consecutiveRecognitionErrors < self.maxRecognitionRetries {
                        self.stopListening()
                        try? await Task.sleep(for: .milliseconds(500))
                        if self.isActive {
                            self.configureAudioSessionForRecording()
                            self.startListening()
                        }
                    } else {
                        self.errorMessage = "Taligenkänning misslyckades upprepade gånger"
                    }
                }
            }
        }
    }

    private func stopListening() {
        isListening = false  // Set early to prevent re-entry from timer callback
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioLevel = 0
    }

    private func handleUserFinishedSpeaking() {
        let text = userTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isListening else { return }

        stopListening()
        isListening = false
        isProcessing = true

        Task { await sendToClaudeAndSpeak() }
    }

    // MARK: - Claude + TTS

    private func sendToClaudeAndSpeak() async {
        let text = userTranscript
        let voiceInstruction = "Svara ALLTID på svenska. Kort och koncist, max 2-3 meningar. Ingen markdown, kod eller formatering."

        do {
            let fullResponse: String

            // Route to project agent if an active project exists, otherwise use pure chat
            if let project = ProjectStore.shared.activeProject {
                fullResponse = try await sendViaProjectAgent(text: text, project: project, voiceInstruction: voiceInstruction)
            } else {
                fullResponse = try await sendViaChatManager(text: text, voiceInstruction: voiceInstruction)
            }

            let clean = Self.stripMarkdown(fullResponse)
            assistantTranscript = clean
            isProcessing = false
            isSpeaking = true

            configureAudioSessionForPlayback()
            await speakWithFallback(clean)

            isSpeaking = false

            if isActive {
                userTranscript = ""
                configureAudioSessionForRecording()
                startListening()
            }
        } catch {
            isProcessing = false
            NaviLog.error("VoiceMode: fel vid kommunikation", error: error)
            errorMessage = "Fel vid kommunikation med Claude"
            if isActive { resumeListening() }
        }
    }

    /// Send via pure chat (no project context)
    private func sendViaChatManager(text: String, voiceInstruction: String) async throws -> String {
        let manager = ChatManager.shared

        if manager.activeConversation == nil {
            _ = manager.newConversation()
        }
        guard var conv = manager.conversations.first(where: { $0.id == manager.activeConversation?.id })
                ?? manager.activeConversation else {
            return ""
        }

        // Use Haiku for voice — responses are short and conversational
        let originalModel = conv.model
        conv.model = .haiku

        var fullResponse = ""
        do {
            try await manager.send(text: text, images: [], in: &conv, voiceInstruction: voiceInstruction) { chunk in
                fullResponse += chunk
            }
        } catch {
            conv.model = originalModel
            if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
                manager.conversations[idx] = conv
            }
            throw error
        }

        // Restore model so subsequent non-voice messages use the user's chosen model
        conv.model = originalModel

        manager.activeConversation = conv
        if let idx = manager.conversations.firstIndex(where: { $0.id == conv.id }) {
            manager.conversations[idx] = conv
        }

        return fullResponse
    }

    /// Send via project agent (coding context)
    private func sendViaProjectAgent(text: String, project: NaviProject, voiceInstruction: String) async throws -> String {
        let agent = AgentPool.shared.agent(for: project)

        // Send the message and wait for completion
        return await withCheckedContinuation { continuation in
            agent.sendMessage("[RÖSTLÄGE: \(voiceInstruction)] \(text)", images: []) {
                // Get the last assistant message from the agent's conversation
                let lastMsg = agent.conversation.messages.last(where: { $0.role == .assistant })
                let response = lastMsg?.textContent ?? "Uppgiften utförd."
                continuation.resume(returning: response)
            }
        }
    }

    private func speakWithFallback(_ text: String) async {
        let elevenlabs = ElevenLabsClient.shared
        let hasElevenLabsKey = KeychainManager.shared.elevenLabsAPIKey?.isEmpty == false

        if hasElevenLabsKey {
            await elevenlabs.speakForVoiceMode(text)
        } else {
            await SystemTTSFallback.shared.speak(text)
        }
    }

    private func resumeListening() {
        isProcessing = false
        userTranscript = ""
        configureAudioSessionForRecording()
        startListening()
    }

    // MARK: - Helpers

    private static func calculateLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frames { sum += abs(channelData[0][i]) }
        return min(sum / Float(frames) * 10.0, 1.0)
    }

    static func stripMarkdown(_ text: String) -> String {
        var r = text
        r = r.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: "(?m)^#+\\s+", with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: "[*_]{1,3}", with: "", options: .regularExpression)
        r = r.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        r = r.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return r.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - System TTS fallback (no ElevenLabs key required)

@MainActor
final class SystemTTSFallback: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SystemTTSFallback()

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async {
        guard !text.isEmpty else { return }

        await withCheckedContinuation { [weak self] cont in
            guard let self else { cont.resume(); return }
            self.continuation = cont

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "sv-SE")
                ?? AVSpeechSynthesisVoice(language: "sv")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
            utterance.pitchMultiplier = 1.0

            self.synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        continuation?.resume()
        continuation = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
