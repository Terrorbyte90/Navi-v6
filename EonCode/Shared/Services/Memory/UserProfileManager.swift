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
    private let synthesisInterval = 5      // Synthesize every N new memories
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
        Baserat på dessa minnesfakta om en person, skapa en djupgående, personlig användarprofil på svenska.

        Returnera BARA ett giltigt JSON-objekt med exakt dessa nycklar (inga andra nycklar, inga kommentarer):
        {
          "summary": "...",
          "interests": [...],
          "projects": [...],
          "personalFacts": [...],
          "technicalSkills": [...],
          "patterns": [...],
          "goals": [...]
        }

        Detaljerade riktlinjer för varje fält:

        summary (sträng, 5–8 meningar):
          - En levande, personlig berättelse om vem personen är — inte en punktlista
          - Fläta ihop bakgrund, drivkrafter, personlighet, relationer och vad som gör dem unika
          - Nämn konkreta detaljer: vart de bor, vad de bygger, vad de brinner för, livssituation
          - Skriv i tredjeperson, varmt och respektfullt — som en välskriven bio

        interests (lista med strängar, max 10 poster, sorterade efter intensitet):
          - Mycket specifika och kontextualiserade formuleringar
          - Inte "programmering" utan "AI-assisterad iOS-apputveckling med SwiftUI"
          - Inte "säkerhet" utan "Offensiv säkerhet och etisk hacking i gråzoner"
          - Fånga nyanser och djup: vad exakt fascinerar dem, inte bara ämnesområde

        projects (lista med strängar, max 8 poster):
          - Varje post: "Projektnamn — kort beskrivning av vad det är och status"
          - T.ex. "Navi v2 — personlig AI-assistent för iOS/macOS, byggt med SwiftUI + Claude API"
          - Inkludera hobbybyggen, professionella projekt, och pågående experiment

        personalFacts (lista med strängar, max 10 poster):
          - Konkreta, faktabaserade meningar om livet
          - T.ex. "Bor i Kvänum, Västergötland", "Har en dotter på 2 år som heter Vera"
          - Inkludera hälsa, familj, geografi, livsstil — det som skapar kontext

        technicalSkills (lista med strängar, max 12 poster):
          - Specifika teknologier, frameworks, verktyg och kompetensområden
          - T.ex. "SwiftUI / Combine — avancerad nivå", "Python för AI-scripting och automation"
          - Inkludera API-integrationer, databaser, och DevOps om det finns i minnena

        patterns (lista med strängar, max 8 poster):
          - Återkommande beteendemönster och karaktärsdrag som framkommer i minnena
          - T.ex. "Tenderar att bygga verktyg från grunden snarare än använda färdiga lösningar"
          - T.ex. "Fokuserar djupt på ett projekt i taget — hög intensitet i kortare spurter"
          - T.ex. "Kombinerar kreativitet och teknisk precision — bryr sig om design och funktion lika mycket"

        goals (lista med strängar, max 8 poster, blandad tidshorisont):
          - Konkreta mål och ambitioner som framgår av minnena
          - Blanda kortsiktiga (veckor/månader) och långsiktiga (år)
          - T.ex. "Lansera Navi i App Store innan sommaren 2025"
          - T.ex. "Bygga ekonomisk frihet genom egna produkter och appar"

        Minnesfakta att analysera:
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
                    patterns: parsed.patterns,
                    goals: parsed.goals,
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
        let patterns: [String]
        let goals: [String]
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
