import Foundation
import AVFoundation

// MARK: - ElevenLabs Voice model

struct ElevenLabsVoice: Identifiable, Codable {
    let voice_id: String
    let name: String
    var id: String { voice_id }
}

// MARK: - Voice Design preview

struct ElevenLabsVoicePreview: Identifiable {
    let id = UUID()
    let voiceId: String
    let audioData: Data
    let generatedVoiceId: String
}

// MARK: - ElevenLabsClient

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

    // MARK: - TTS (Voice Mode / Chat)

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

    // MARK: - Fetch voices

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

    // MARK: - Core TTS fetch (low-latency turbo model)

    func fetchAudio(text: String, apiKey: String, voiceID: String) async throws -> Data {
        let url = URL(string: "\(Constants.API.elevenLabsBaseURL)/text-to-speech/\(voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_turbo_v2_5",   // Low-latency multilingual model
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ElevenLabsError.requestFailed
        }
        return data
    }

    // MARK: - Public TTS (for VoiceView)

    func textToSpeech(text: String, voiceID: String) async throws -> Data {
        guard let key = apiKey, !key.isEmpty else { throw ElevenLabsError.noAPIKey }
        return try await fetchAudio(text: text, apiKey: key, voiceID: voiceID)
    }

    // MARK: - Sound Effect Generation

    /// Generate a sound effect from a text description.
    /// Returns raw MP3/audio data ready to save or play.
    func generateSoundEffect(
        prompt: String,
        durationSeconds: Double? = nil,
        promptInfluence: Double = 0.3
    ) async throws -> Data {
        guard let key = apiKey, !key.isEmpty else { throw ElevenLabsError.noAPIKey }

        let url = URL(string: "\(Constants.API.elevenLabsBaseURL)/sound-generation")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "text": prompt,
            "prompt_influence": promptInfluence
        ]
        if let dur = durationSeconds {
            body["duration_seconds"] = dur
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw ElevenLabsError.apiError(body)
        }
        return data
    }

    // MARK: - Voice Design

    /// Generate voice previews from a text description + sample text.
    /// Returns previews with base64 audio you can play before saving.
    func designVoicePreviews(
        voiceDescription: String,
        previewText: String
    ) async throws -> [ElevenLabsVoicePreview] {
        guard let key = apiKey, !key.isEmpty else { throw ElevenLabsError.noAPIKey }

        let url = URL(string: "\(Constants.API.elevenLabsBaseURL)/text-to-voice/create-previews")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "voice_description": voiceDescription,
            "text": previewText
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "unknown error"
            throw ElevenLabsError.apiError(errBody)
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let previews = obj["previews"] as? [[String: Any]] else {
            throw ElevenLabsError.invalidResponse
        }

        return previews.compactMap { preview -> ElevenLabsVoicePreview? in
            guard let b64 = preview["audio_base_64"] as? String,
                  let audioData = Data(base64Encoded: b64),
                  let generatedId = preview["generated_voice_id"] as? String else { return nil }
            return ElevenLabsVoicePreview(voiceId: generatedId, audioData: audioData, generatedVoiceId: generatedId)
        }
    }

    /// Save a previewed voice design to the user's ElevenLabs voice library.
    func saveDesignedVoice(generatedVoiceId: String, name: String) async throws -> String {
        guard let key = apiKey, !key.isEmpty else { throw ElevenLabsError.noAPIKey }

        let url = URL(string: "\(Constants.API.elevenLabsBaseURL)/text-to-voice/create-voice-from-preview")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "generated_voice_id": generatedVoiceId,
            "voice_name": name,
            "voice_description": ""
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let errBody = String(data: data, encoding: .utf8) ?? "unknown error"
            throw ElevenLabsError.apiError(errBody)
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voiceId = obj["voice_id"] as? String else {
            throw ElevenLabsError.invalidResponse
        }
        return voiceId
    }

    // MARK: - Save audio to iCloud

    /// Saves audio Data as an .mp3 file under iCloud/Documents/Navi/Media/Ljud/
    @discardableResult
    func saveAudioToiCloud(_ data: Data, filename: String) async -> URL? {
        guard let dir = iCloudSyncEngine.shared.mediaAudioRoot else { return nil }
        let fileURL = dir.appendingPathComponent(filename.hasSuffix(".mp3") ? filename : "\(filename).mp3")
        do {
            try await iCloudSyncEngine.shared.writeData(data, to: fileURL)
            NaviLog.info("ElevenLabsClient: Sparade ljud till \(fileURL.lastPathComponent)")
            return fileURL
        } catch {
            NaviLog.error("ElevenLabsClient: Kunde inte spara ljud", error: error)
            return nil
        }
    }
}

// MARK: - Errors

enum ElevenLabsError: LocalizedError {
    case noAPIKey
    case requestFailed
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:          return "Ingen ElevenLabs API-nyckel konfigurerad."
        case .requestFailed:     return "Förfrågan till ElevenLabs misslyckades."
        case .invalidResponse:   return "Ogiltigt svar från ElevenLabs."
        case .apiError(let msg): return "ElevenLabs API-fel: \(msg.prefix(200))"
        }
    }
}

// MARK: - AudioPlayer

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
