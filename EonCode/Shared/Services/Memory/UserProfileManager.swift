import Foundation

// MARK: - UserProfileManager
// Synthesizes and persists a rich user profile from memories using Claude Haiku.
// Auto-triggers when memory count crosses a threshold (every 10 new memories).
// Saves to iCloud → syncs between Mac and iOS automatically.

@MainActor
final class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()

    @Published var profile: UserProfile?
    @Published var isSynthesizing = false

    private let api = ClaudeAPIClient.shared
    private let synthesisInterval = 10     // Synthesize every N new memories
    private var lastSynthesisCount = 0

    private init() {
        Task { await loadProfile() }
    }

    // MARK: - iCloud file URL

    private var fileURL: URL? {
        guard let base = iCloudSyncEngine.shared.containerURL else { return nil }
        let dir = base.appendingPathComponent("Memories", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_profile.json")
    }

    // MARK: - Load from iCloud

    func loadProfile() async {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path) else { return }

        let result: UserProfile? = try? await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { u in
                    blockRan = true
                    do {
                        let data = try Data(contentsOf: u)
                        let profile = try JSONDecoder().decode(UserProfile.self, from: data)
                        cont.resume(returning: profile)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan, let err = coordError { cont.resume(throwing: err) }
            }
        }
        profile = result
        lastSynthesisCount = result?.memoryCountAtGeneration ?? 0
    }

    // MARK: - Save to iCloud

    private func saveProfile(_ p: UserProfile) async {
        guard let url = fileURL else { return }
        guard let data = try? JSONEncoder().encode(p) else { return }

        try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                var blockRan = false
                coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
                    blockRan = true
                    do {
                        try data.write(to: u, options: .atomic)
                        cont.resume()
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
                if !blockRan, let err = coordError { cont.resume(throwing: err) }
            }
        }
    }

    // MARK: - Auto-trigger check

    /// Call this after memories are saved. Synthesizes if threshold crossed.
    func checkAndSynthesize(currentMemoryCount: Int, memories: [Memory]) async {
        let newSinceLastSynthesis = currentMemoryCount - lastSynthesisCount
        guard newSinceLastSynthesis >= synthesisInterval || (profile == nil && currentMemoryCount >= 3) else { return }
        await synthesize(memories: memories)
    }

    // MARK: - Synthesize profile from memories

    func synthesize(memories: [Memory]) async {
        guard !isSynthesizing else { return }
        guard !memories.isEmpty else { return }
        guard KeychainManager.shared.anthropicAPIKey?.isEmpty == false else { return }

        isSynthesizing = true
        defer { isSynthesizing = false }

        let memoryLines = memories.map { "- [\($0.category.rawValue)] \($0.fact)" }.joined(separator: "\n")

        let prompt = """
        Baserat på dessa minnesfakta om en person, skapa en detaljerad användarprofil på svenska.

        Returnera BARA ett JSON-objekt med exakt dessa nycklar:
        {
          "summary": "3-5 meningar som beskriver vem personen är, deras bakgrund och passion",
          "interests": ["intresse1", "intresse2", "intresse3", ...],
          "projects": ["projekt1", "projekt2", ...],
          "personalFacts": ["fakta1", "fakta2", ...],
          "technicalSkills": ["färdighet1", "färdighet2", ...]
        }

        Riktlinjer:
        - summary: Skriv som en levande, personlig beskrivning (inte punktlista). Nämn personliga detaljer, drömmar, relationer
        - interests: Max 8 intressen, sorterade efter intensitet/tydlighet i minnena. Konkreta formuleringar som "Gråzoner inom hacking", "AI-assisterad programmering"
        - projects: Specifika projekt med kort beskrivning, t.ex. "Navi — eget AI-assistentssystem byggt med SwiftUI"
        - personalFacts: Konkreta personliga fakta, t.ex. "Bor i Kvänum", "Har en dotter på 2 år", "Behandlas för MS"
        - technicalSkills: Specifika tekniska kompetenser, t.ex. "SwiftUI / iOS-utveckling", "Python AI-scripting"

        Minnesfakta:
        \(memoryLines)
        """

        let requestMessages = [ChatMessage(
            role: .user,
            content: [.text(prompt)]
        )]

        do {
            let (response, _) = try await api.sendMessage(
                messages: requestMessages,
                model: .haiku,
                systemPrompt: "Du är en assistent som skapar strukturerade JSON-profiler. Returnera BARA giltig JSON, ingen förklaring."
            )

            if let parsed = parseProfileJSON(response) {
                let newProfile = UserProfile(
                    summary: parsed.summary,
                    interests: parsed.interests,
                    projects: parsed.projects,
                    personalFacts: parsed.personalFacts,
                    technicalSkills: parsed.technicalSkills,
                    createdAt: profile?.createdAt ?? Date(),
                    updatedAt: Date(),
                    memoryCountAtGeneration: memories.count
                )
                profile = newProfile
                lastSynthesisCount = memories.count
                await saveProfile(newProfile)
                NaviLog.info("UserProfileManager: profil syntetiserad från \(memories.count) minnen")
            }
        } catch {
            NaviLog.error("UserProfileManager: syntetisering misslyckades", error: error)
        }
    }

    // MARK: - JSON parsing

    private struct ProfileJSON: Decodable {
        let summary: String
        let interests: [String]
        let projects: [String]
        let personalFacts: [String]
        let technicalSkills: [String]
    }

    private func parseProfileJSON(_ text: String) -> ProfileJSON? {
        guard let startIdx = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var endIdx: String.Index?
        for i in text.indices[startIdx...] {
            if text[i] == "{" { depth += 1 }
            else if text[i] == "}" { depth -= 1 }
            if depth == 0 { endIdx = i; break }
        }
        guard let end = endIdx else { return nil }
        let jsonStr = String(text[startIdx...end])
        guard let data = jsonStr.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ProfileJSON.self, from: data) else { return nil }
        return parsed
    }
}
