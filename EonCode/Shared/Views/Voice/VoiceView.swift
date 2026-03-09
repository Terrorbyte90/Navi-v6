import SwiftUI
import AVFoundation

// MARK: - VoiceView
// Three tabs: Text till tal · Ljud (sound effects) · Röstdesign
// All features powered by ElevenLabs API.

struct VoiceView: View {
    @StateObject private var eleven = ElevenLabsClient.shared

    enum VoiceTab: String, CaseIterable, Identifiable {
        case tts    = "Text till tal"
        case sound  = "Ljud"
        case design = "Röstdesign"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .tts:    return "waveform"
            case .sound:  return "music.note"
            case .design: return "person.wave.2"
            }
        }
    }

    @State private var selectedTab: VoiceTab = .tts

    var body: some View {
        VStack(spacing: 0) {
            // ── Tab bar ──────────────────────────────────────────────────────
            tabBar

            Divider().opacity(0.12)

            // ── Content ──────────────────────────────────────────────────────
            Group {
                switch selectedTab {
                case .tts:    TTSTab()
                case .sound:  SoundTab()
                case .design: VoiceDesignTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.chatBackground)
        .onAppear {
            Task { await eleven.fetchVoices() }
        }
    }

    // MARK: - Tab bar

    var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(VoiceTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(selectedTab == tab ? Color.accentNavi : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentNavi : Color.clear)
                            .frame(height: 2),
                        alignment: .bottom
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .background(Color.chatBackground)
    }
}

// MARK: - TTS Tab

private struct TTSTab: View {
    @StateObject private var eleven = ElevenLabsClient.shared

    @State private var inputText = ""
    @State private var selectedVoiceID = ""
    @State private var isGenerating = false
    @State private var audioData: Data? = nil
    @State private var player = AudioPlayer()
    @State private var isPlaying = false
    @State private var error: String? = nil
    @State private var savedURL: URL? = nil

    var selectedVoice: ElevenLabsVoice? {
        eleven.availableVoices.first(where: { $0.voice_id == selectedVoiceID })
            ?? eleven.availableVoices.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Voice picker ─────────────────────────────────────────────
                voiceSection

                // ── Text input ───────────────────────────────────────────────
                textSection

                // ── Controls ─────────────────────────────────────────────────
                controlsSection

                // ── Result ───────────────────────────────────────────────────
                if let _ = audioData {
                    resultSection
                }

                if let e = error {
                    Text(e)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                }

                Spacer(minLength: 40)
            }
            .padding(20)
        }
        .onAppear {
            if selectedVoiceID.isEmpty {
                selectedVoiceID = SettingsStore.shared.selectedVoiceID.isEmpty
                    ? (eleven.availableVoices.first?.voice_id ?? "")
                    : SettingsStore.shared.selectedVoiceID
            }
        }
    }

    var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Röst", icon: "person.wave.2.fill")

            if eleven.availableVoices.isEmpty {
                Text("Hämtar röster… (kräver API-nyckel i Inställningar)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(eleven.availableVoices) { voice in
                            voiceChip(voice)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    func voiceChip(_ voice: ElevenLabsVoice) -> some View {
        let isSelected = selectedVoiceID == voice.voice_id
        return Button {
            selectedVoiceID = voice.voice_id
        } label: {
            Text(voice.name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? Color.accentNavi : Color.userBubble)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Text", icon: "text.alignleft")
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.userBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                TextEditor(text: $inputText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 120, maxHeight: 200)
                if inputText.isEmpty {
                    Text("Skriv text att omvandla till tal…")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    var controlsSection: some View {
        HStack(spacing: 12) {
            Button {
                Task { await generate() }
            } label: {
                Label(isGenerating ? "Genererar…" : "Generera tal",
                      systemImage: isGenerating ? "hourglass" : "waveform.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(inputText.isBlank || isGenerating ? Color.secondary.opacity(0.3) : Color.accentNavi)
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.isBlank || isGenerating)

            if audioData != nil {
                Button {
                    Task { await playAudio() }
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentNavi)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.accentNavi.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Resultat", icon: "checkmark.circle.fill")
            HStack(spacing: 12) {
                if let url = savedURL {
                    Label(url.lastPathComponent, systemImage: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        Task { await saveToiCloud() }
                    } label: {
                        Label("Sparat!", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("Ljud genererat", systemImage: "waveform")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task { await saveToiCloud() }
                    } label: {
                        Label("Spara till iCloud", systemImage: "icloud.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentNavi)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.userBubble))
        }
    }

    // MARK: - Actions

    func generate() async {
        guard !inputText.isBlank else { return }
        let voiceID = selectedVoiceID.isEmpty ? (eleven.availableVoices.first?.voice_id ?? "21m00Tcm4TlvDq8ikWAM") : selectedVoiceID
        isGenerating = true
        error = nil
        audioData = nil
        savedURL = nil
        defer { isGenerating = false }
        do {
            audioData = try await eleven.textToSpeech(text: inputText, voiceID: voiceID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func playAudio() async {
        guard let data = audioData else { return }
        if isPlaying {
            player.stop()
            isPlaying = false
        } else {
            isPlaying = true
            await player.play(data: data)
            isPlaying = false
        }
    }

    func saveToiCloud() async {
        guard let data = audioData else { return }
        let voiceName = selectedVoice?.name ?? "roest"
        let ts = Int(Date().timeIntervalSince1970)
        let filename = "tts-\(voiceName.lowercased().replacingOccurrences(of: " ", with: "-"))-\(ts).mp3"
        savedURL = await eleven.saveAudioToiCloud(data, filename: filename)
    }
}

// MARK: - Sound Effects Tab

private struct SoundTab: View {
    @StateObject private var eleven = ElevenLabsClient.shared

    @State private var prompt = ""
    @State private var duration: Double = 5
    @State private var isGenerating = false
    @State private var audioData: Data? = nil
    @State private var player = AudioPlayer()
    @State private var isPlaying = false
    @State private var error: String? = nil
    @State private var savedURL: URL? = nil

    let examplePrompts = [
        "Rain falling on leaves in a quiet forest",
        "Futuristic sci-fi ambient hum with subtle beeps",
        "Crackling campfire with distant crickets",
        "Ocean waves crashing on a rocky shore",
        "City street ambience with distant cars and birds"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Prompt ───────────────────────────────────────────────────
                promptSection

                // ── Duration ─────────────────────────────────────────────────
                durationSection

                // ── Examples ─────────────────────────────────────────────────
                examplesSection

                // ── Controls ─────────────────────────────────────────────────
                controlsSection

                // ── Result ───────────────────────────────────────────────────
                if let _ = audioData {
                    resultSection
                }

                if let e = error {
                    Text(e)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                }

                Spacer(minLength: 40)
            }
            .padding(20)
        }
    }

    var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Beskriv ljudet", icon: "music.note.list")
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.userBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                TextEditor(text: $prompt)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 100, maxHeight: 160)
                if prompt.isEmpty {
                    Text("T.ex. 'Rain falling on leaves in a quiet forest'…")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Längd: \(String(format: "%.0f", duration))s", icon: "timer")
            Slider(value: $duration, in: 1...22, step: 1)
                .accentColor(Color.accentNavi)
            HStack {
                Text("1s").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Text("22s").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }

    var examplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Exempel", icon: "lightbulb")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(examplePrompts, id: \.self) { ex in
                        Button {
                            prompt = ex
                        } label: {
                            Text(ex)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: 160, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.userBubble)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var controlsSection: some View {
        HStack(spacing: 12) {
            Button {
                Task { await generate() }
            } label: {
                Label(isGenerating ? "Genererar…" : "Generera ljud",
                      systemImage: isGenerating ? "hourglass" : "music.note.badge.plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(prompt.isBlank || isGenerating ? Color.secondary.opacity(0.3) : Color.accentNavi)
                    )
            }
            .buttonStyle(.plain)
            .disabled(prompt.isBlank || isGenerating)

            if audioData != nil {
                Button {
                    Task { await playAudio() }
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentNavi)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.accentNavi.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Resultat", icon: "checkmark.circle.fill")
            HStack(spacing: 12) {
                if let url = savedURL {
                    Label(url.lastPathComponent, systemImage: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Label("Sparat!", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                } else {
                    Label("Ljud genererat", systemImage: "waveform")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task { await saveToiCloud() }
                    } label: {
                        Label("Spara MP3 till iCloud", systemImage: "icloud.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentNavi)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.userBubble))
        }
    }

    // MARK: - Actions

    func generate() async {
        guard !prompt.isBlank else { return }
        isGenerating = true
        error = nil
        audioData = nil
        savedURL = nil
        defer { isGenerating = false }
        do {
            audioData = try await eleven.generateSoundEffect(
                prompt: prompt,
                durationSeconds: duration
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func playAudio() async {
        guard let data = audioData else { return }
        if isPlaying {
            player.stop()
            isPlaying = false
        } else {
            isPlaying = true
            await player.play(data: data)
            isPlaying = false
        }
    }

    func saveToiCloud() async {
        guard let data = audioData else { return }
        let ts = Int(Date().timeIntervalSince1970)
        let filename = "ljud-\(ts).mp3"
        savedURL = await eleven.saveAudioToiCloud(data, filename: filename)
    }
}

// MARK: - Voice Design Tab

private struct VoiceDesignTab: View {
    @StateObject private var eleven = ElevenLabsClient.shared

    @State private var voiceDescription = ""
    @State private var previewText = "Hej! Det här är en förhandsvisning av min röst."
    @State private var isGenerating = false
    @State private var previews: [ElevenLabsVoicePreview] = []
    @State private var playingIndex: Int? = nil
    @State private var player = AudioPlayer()
    @State private var savingIndex: Int? = nil
    @State private var savedNames: [UUID: String] = [:]
    @State private var voiceSaveName = ""
    @State private var showNameAlert = false
    @State private var pendingPreview: ElevenLabsVoicePreview? = nil
    @State private var error: String? = nil

    let descriptionExamples = [
        "En lugn, varm svensk mansröst med tydligt uttal",
        "En energisk ung kvinna med lätt skånsk dialekt",
        "En mjuk, professionell berättarröst på svenska",
        "En äldre, kunnig mans röst med auktoritet"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Voice description ────────────────────────────────────────
                descriptionSection

                // ── Preview text ─────────────────────────────────────────────
                previewTextSection

                // ── Generate button ──────────────────────────────────────────
                generateSection

                // ── Previews ─────────────────────────────────────────────────
                if !previews.isEmpty {
                    previewsSection
                }

                if let e = error {
                    Text(e)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                }

                Spacer(minLength: 40)
            }
            .padding(20)
        }
        .alert("Namnge rösten", isPresented: $showNameAlert) {
            TextField("Röstnamn", text: $voiceSaveName)
            Button("Spara") {
                if let preview = pendingPreview {
                    Task { await saveVoice(preview) }
                }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Välj ett namn för att spara rösten till ditt ElevenLabs-bibliotek.")
        }
    }

    var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Beskriv rösten", icon: "person.wave.2.fill")
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.userBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                TextEditor(text: $voiceDescription)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 100, maxHeight: 160)
                if voiceDescription.isEmpty {
                    Text("T.ex. 'En lugn, varm mansröst med tydligt uttal'…")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }

            // Examples
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(descriptionExamples, id: \.self) { ex in
                        Button { voiceDescription = ex } label: {
                            Text(ex)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: 160, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.userBubble)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var previewTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Exempeltext (för förhandslyssning)", icon: "text.bubble")
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.userBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                    )
                TextEditor(text: $previewText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 80, maxHeight: 140)
            }
        }
    }

    var generateSection: some View {
        Button {
            Task { await generate() }
        } label: {
            Label(isGenerating ? "Genererar röster…" : "Generera röstförhandsvisningar",
                  systemImage: isGenerating ? "hourglass" : "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(voiceDescription.isBlank || previewText.isBlank || isGenerating
                              ? Color.secondary.opacity(0.3) : Color.accentNavi)
                )
        }
        .buttonStyle(.plain)
        .disabled(voiceDescription.isBlank || previewText.isBlank || isGenerating)
    }

    var previewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Röstförhandsvisningar", icon: "ear")
            ForEach(previews.indices, id: \.self) { i in
                let preview = previews[i]
                HStack(spacing: 14) {
                    // Play button
                    Button {
                        Task { await playPreview(i) }
                    } label: {
                        Image(systemName: playingIndex == i ? "stop.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.accentNavi)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.accentNavi.opacity(0.1)))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Röst \(i + 1)")
                            .font(.system(size: 14, weight: .medium))
                        if let savedName = savedNames[preview.id] {
                            Label("Sparad: \(savedName)", systemImage: "checkmark")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        } else {
                            Text("Tryck ▶ för att lyssna")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Save to voice library button
                    if savedNames[preview.id] == nil {
                        Button {
                            voiceSaveName = "Min röst \(i + 1)"
                            pendingPreview = preview
                            showNameAlert = true
                        } label: {
                            Label("Spara röst", systemImage: "person.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accentNavi)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentNavi.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(Color.accentNavi.opacity(0.3), lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.userBubble))
            }
        }
    }

    // MARK: - Actions

    func generate() async {
        guard !voiceDescription.isBlank, !previewText.isBlank else { return }
        isGenerating = true
        error = nil
        previews = []
        defer { isGenerating = false }
        do {
            previews = try await eleven.designVoicePreviews(
                voiceDescription: voiceDescription,
                previewText: previewText
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func playPreview(_ index: Int) async {
        let preview = previews[index]
        if playingIndex == index {
            player.stop()
            playingIndex = nil
        } else {
            if playingIndex != nil { player.stop() }
            playingIndex = index
            await player.play(data: preview.audioData)
            playingIndex = nil
        }
    }

    func saveVoice(_ preview: ElevenLabsVoicePreview) async {
        let name = voiceSaveName.isEmpty ? "Min röst" : voiceSaveName
        do {
            _ = try await eleven.saveDesignedVoice(
                generatedVoiceId: preview.generatedVoiceId,
                name: name
            )
            savedNames[preview.id] = name
            await eleven.fetchVoices()   // Refresh voice list
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Shared helper

private func sectionLabel(_ title: String, icon: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}
