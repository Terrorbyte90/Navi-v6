import Foundation
import AVFoundation

struct ElevenLabsVoice: Identifiable, Codable {
    let voice_id: String
    let name: String
    var id: String { voice_id }
}

@MainActor
final class ElevenLabsClient: ObservableObject {
    static let shared = ElevenLabsClient()

    @Published var isSpeaking = false
    @Published var isEnabled = false
    @Published var availableVoices: [ElevenLabsVoice] = []

    private let player = AudioPlayer()

    private var apiKey: String? { KeychainManager.shared.elevenLabsAPIKey }

    private var activeVoiceID: String {
        let stored = SettingsStore.shared.selectedVoiceID
        return stored.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : stored
    }

    private init() {}

    func speak(_ text: String) async {
        guard isEnabled, let key = apiKey, !key.isEmpty else { return }
        guard !text.isBlank else { return }

        isSpeaking = true
        defer { isSpeaking = false }

        do {
            let data = try await fetchAudio(text: text, apiKey: key, voiceID: activeVoiceID)
            await player.play(data: data)
        } catch {
            // TTS is optional
        }
    }

    func speakForVoiceMode(_ text: String) async {
        guard let key = apiKey, !key.isEmpty else { return }
        guard !text.isBlank else { return }

        isSpeaking = true
        defer { isSpeaking = false }

        do {
            let data = try await fetchAudio(text: text, apiKey: key, voiceID: activeVoiceID)
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            await player.play(data: data)
        } catch {
            // TTS failed silently
        }
    }

    func stop() {
        player.stop()
        isSpeaking = false
    }

    func fetchVoices() async {
        guard let key = apiKey, !key.isEmpty else { return }
        do {
            let url = URL(string: "\(Constants.API.elevenLabsBaseURL)/voices")!
            var request = URLRequest(url: url)
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            struct VoicesResponse: Codable { let voices: [ElevenLabsVoice] }
            let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
            availableVoices = decoded.voices
        } catch {
            // Silently fail
        }
    }

    private func fetchAudio(text: String, apiKey: String, voiceID: String) async throws -> Data {
        let url = URL(string: "\(Constants.API.elevenLabsBaseURL)/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ElevenLabsError.requestFailed
        }
        return data
    }
}

enum ElevenLabsError: Error {
    case requestFailed
}

@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    func play(data: Data) async {
        await withCheckedContinuation { [weak self] continuation in
            self?.continuation = continuation
            do {
                #if os(iOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                player.play()
                self?.audioPlayer = player
            } catch {
                continuation.resume()
            }
        }
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        continuation?.resume()
        continuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
