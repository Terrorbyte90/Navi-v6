import Foundation

// MARK: - MemoryManager
// Extracts, stores, and injects memories across conversations.

@MainActor
final class MemoryManager: ObservableObject {
    static let shared = MemoryManager()

    @Published var memories: [Memory] = []

    private let store = iCloudMemoryStore.shared
    private let api = ClaudeAPIClient.shared

    private init() {
        Task { await reload() }
    }

    // MARK: - Load

    func reload() async {
        memories = (try? await store.loadAll()) ?? []
    }

    // MARK: - Memory context for system prompt

    func memoryContext() -> String {
        guard !memories.isEmpty else { return "" }
        let lines = memories.map { "- \($0.fact)" }.joined(separator: "\n")
        return """

        Saker du vet om användaren (från tidigare konversationer):
        \(lines)

        Använd denna information naturligt. Referera inte till att du "minns" — agera som om du bara vet det.
        """
    }

    // MARK: - Extract memories from messages

    func extractMemories(from messages: [PureChatMessage], conversationId: UUID) async {
        guard SettingsStore.shared.autoExtractMemories else { return }
        guard messages.count >= 2 else { return }

        let transcript = messages.map { "[\($0.role == .user ? "Användare" : "AI")] \($0.content.prefix(500))" }
            .joined(separator: "\n")

        let existingFacts = memories.map { "- \($0.fact)" }.joined(separator: "\n")

        let prompt = """
        Analysera denna konversation och extrahera viktig information om användaren som kan vara nyttig i framtida konversationer.

        Returnera BARA ett JSON-objekt med en array "memories":
        {"memories": [{"fact": "...", "category": "personal|preference|project|technical|other"}]}

        Regler:
        - Bara fakta relevanta för framtida samtal
        - Korta, koncisa formuleringar (max 15 ord per fakta)
        - Inga upprepningar av redan kända fakta nedan
        - Inga känsliga uppgifter (lösenord, personnummer, bankuppgifter)
        - Max 5 nya minnen
        - Om inget väsentligt nytt: returnera {"memories": []}

        Redan kända fakta (duplicera inte):
        \(existingFacts.isEmpty ? "(inga)" : existingFacts)

        Konversation:
        \(transcript)
        """

        let requestMessages = [ChatMessage(
            role: .user,
            content: [.text(prompt)]
        )]

        guard KeychainManager.shared.anthropicAPIKey?.isEmpty == false else { return }

        do {
            let (response, _) = try await api.sendMessage(
                messages: requestMessages,
                model: .haiku,
                systemPrompt: nil
            )

            if let parsed = parseMemoriesJSON(response) {
                for entry in parsed {
                    let memory = Memory(
                        fact: entry.fact,
                        category: entry.category,
                        source: .extracted(conversationId: conversationId)
                    )
                    try? await store.save(memory)
                    memories.append(memory)
                }
            }
        } catch {
            // Silent fail — memory extraction is best-effort
        }
    }

    // Also accept raw ChatMessages (from agent conversations)
    func extractMemoriesFromAgent(messages: [ChatMessage], conversationId: UUID) async {
        let purified = messages.compactMap { msg -> PureChatMessage? in
            let text = msg.content.compactMap {
                if case .text(let t) = $0 { return t }
                return nil
            }.joined(separator: " ")
            guard !text.isEmpty else { return nil }
            return PureChatMessage(role: msg.role, content: text)
        }
        await extractMemories(from: purified, conversationId: conversationId)
    }

    // MARK: - CRUD

    func addMemory(fact: String, category: MemoryCategory) async {
        let memory = Memory(fact: fact, category: category, source: .manual)
        try? await store.save(memory)
        memories.append(memory)
    }

    func deleteMemory(id: UUID) async {
        try? await store.delete(id: id)
        memories.removeAll { $0.id == id }
    }

    func updateMemory(id: UUID, newFact: String) async {
        try? await store.update(id: id, fact: newFact)
        if let idx = memories.firstIndex(where: { $0.id == id }) {
            var updated = memories[idx]
            updated.fact = newFact
            memories[idx] = updated  // Reassign to trigger @Published change detection
        }
    }

    // MARK: - Parse JSON

    private struct MemoryEntry: Decodable {
        let fact: String
        let category: MemoryCategory
    }

    private struct MemoriesResponse: Decodable {
        let memories: [MemoryEntry]
    }

    private func parseMemoriesJSON(_ text: String) -> [MemoryEntry]? {
        // Extract JSON from response (may have surrounding text)
        guard let start = text.range(of: "{"),
              let end = text.range(of: "}", options: .backwards) else { return nil }
        let jsonStr = String(text[start.lowerBound...end.upperBound])
        guard let data = jsonStr.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(MemoriesResponse.self, from: data) else { return nil }
        return parsed.memories
    }
}

// MARK: - SettingsStore memory toggle

extension SettingsStore {
    var autoExtractMemories: Bool {
        get { UserDefaults.standard.bool(forKey: "autoExtractMemories") }
        set { UserDefaults.standard.set(newValue, forKey: "autoExtractMemories") }
    }
}
