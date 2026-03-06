import Foundation

// MARK: - ProjectPlan model

struct ProjectPlan: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var summary: String            // One-line description extracted from conversation
    var messages: [PureChatMessage]
    var model: ClaudeModel
    var createdAt: Date
    var updatedAt: Date
    var totalCostSEK: Double
    var status: PlanStatus
    var extractedPlan: ExtractedPlan?  // Structured plan extracted from conversation

    init(model: ClaudeModel = .sonnet45) {
        self.id = UUID()
        self.title = "Ny plan"
        self.summary = ""
        self.messages = []
        self.model = model
        self.createdAt = Date()
        self.updatedAt = Date()
        self.totalCostSEK = 0
        self.status = .draft
        self.extractedPlan = nil
    }

    static func == (lhs: ProjectPlan, rhs: ProjectPlan) -> Bool { lhs.id == rhs.id }
}

enum PlanStatus: String, Codable, CaseIterable {
    case draft      = "Utkast"
    case active     = "Aktiv"
    case completed  = "Klar"
    case archived   = "Arkiverad"

    var icon: String {
        switch self {
        case .draft:    return "doc.badge.ellipsis"
        case .active:   return "bolt.fill"
        case .completed: return "checkmark.seal.fill"
        case .archived: return "archivebox"
        }
    }

    var color: String {
        switch self {
        case .draft:    return "secondary"
        case .active:   return "blue"
        case .completed: return "green"
        case .archived: return "gray"
        }
    }
}

// MARK: - Structured plan extracted from conversation

struct ExtractedPlan: Codable, Equatable {
    var projectName: String
    var description: String
    var techStack: [String]
    var phases: [PlanPhase]
    var estimatedTime: String
    var keyFeatures: [String]
    var risks: [String]
    var nextStep: String
}

struct PlanPhase: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var tasks: [String]
    var estimatedDays: Int?

    init(name: String, description: String, tasks: [String], estimatedDays: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.tasks = tasks
        self.estimatedDays = estimatedDays
    }
}

// MARK: - PlanManager

@MainActor
final class PlanManager: ObservableObject {
    static let shared = PlanManager()

    @Published var plans: [ProjectPlan] = []
    @Published var activePlan: ProjectPlan?
    @Published var isStreaming = false
    @Published var streamingText = ""

    private let api = ClaudeAPIClient.shared
    private let storageKey = "navi.plans"

    private init() {
        load()
    }

    // MARK: - New plan

    func newPlan(model: ClaudeModel = .sonnet45) -> ProjectPlan {
        let plan = ProjectPlan(model: model)
        plans.insert(plan, at: 0)
        activePlan = plan
        persist()
        return plan
    }

    // MARK: - Send message

    func send(
        text: String,
        images: [Data] = [],
        in plan: inout ProjectPlan,
        onToken: @escaping (String) -> Void
    ) async throws {
        let userMsg = PureChatMessage(role: .user, content: text, imageData: images.isEmpty ? nil : images)
        plan.messages.append(userMsg)
        plan.updatedAt = Date()

        let apiMessages = plan.messages.map { msg in
            ChatMessage(role: msg.role, content: msg.apiContent)
        }

        isStreaming = true
        streamingText = ""
        defer { isStreaming = false }

        var fullText = ""
        var finalUsage: TokenUsage?

        try await api.streamMessage(
            messages: apiMessages,
            model: plan.model,
            systemPrompt: planningSystemPrompt,
            tools: nil,
            usePromptCaching: true
        ) { [weak self] event in
            switch event {
            case .contentBlockDelta(_, let delta):
                if case .text(let chunk) = delta {
                    fullText += chunk
                    self?.streamingText = fullText
                    onToken(chunk)
                }
            case .messageDelta(_, let usage):
                finalUsage = usage
            default:
                break
            }
        }

        let costSEK: Double
        if let usage = finalUsage {
            let (_, sek) = CostCalculator.shared.calculate(usage: usage, model: plan.model)
            costSEK = sek
            plan.totalCostSEK += sek
            CostTracker.shared.record(usage: usage, model: plan.model)
        } else {
            costSEK = 0
        }

        let assistantMsg = PureChatMessage(
            role: .assistant,
            content: fullText,
            costSEK: costSEK,
            model: plan.model,
            tokenUsage: finalUsage
        )
        plan.messages.append(assistantMsg)
        plan.updatedAt = Date()

        // Auto-title from first exchange
        if plan.title == "Ny plan" && plan.messages.count >= 2 {
            plan.title = generateTitle(from: plan)
            plan.summary = generateSummary(from: plan)
        }

        // Try to extract structured plan after enough context (capture by value)
        if plan.messages.count >= 4 && plan.extractedPlan == nil {
            let planSnapshot = plan
            Task {
                if let extracted = try? await extractStructuredPlan(from: planSnapshot) {
                    if let idx = plans.firstIndex(where: { $0.id == planSnapshot.id }) {
                        plans[idx].extractedPlan = extracted
                    }
                    if activePlan?.id == planSnapshot.id {
                        activePlan?.extractedPlan = extracted
                    }
                    persist()
                }
            }
        }

        // Update published list
        if let idx = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[idx] = plan
        }

        persist()
    }

    // MARK: - Delete

    func delete(_ plan: ProjectPlan) {
        plans.removeAll { $0.id == plan.id }
        if activePlan?.id == plan.id {
            activePlan = plans.first
        }
        persist()
    }

    // MARK: - Update status

    func updateStatus(_ plan: ProjectPlan, status: PlanStatus) {
        if let idx = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[idx].status = status
            if activePlan?.id == plan.id { activePlan?.status = status }
            persist()
        }
    }

    // MARK: - Extract structured plan via Claude

    private func extractStructuredPlan(from plan: ProjectPlan) async throws -> ExtractedPlan? {
        let conversation = plan.messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n\n")

        let prompt = """
        Analysera denna planeringskonversation och extrahera en strukturerad projektplan.

        KONVERSATION:
        \(conversation.prefix(8000))

        Returnera ENBART giltig JSON (inga markdown-block):
        {
          "projectName": "Projektnamn",
          "description": "Kort beskrivning (1-2 meningar)",
          "techStack": ["Swift", "SwiftUI", "..."],
          "phases": [
            {
              "name": "Fas 1: Grundstruktur",
              "description": "Vad som ska göras",
              "tasks": ["Uppgift 1", "Uppgift 2"],
              "estimatedDays": 3
            }
          ],
          "estimatedTime": "2-3 veckor",
          "keyFeatures": ["Feature 1", "Feature 2"],
          "risks": ["Risk 1"],
          "nextStep": "Konkret nästa steg att ta"
        }
        """

        let (text, _) = try await api.sendMessage(
            messages: [ChatMessage(role: .user, content: [.text(prompt)])],
            model: .haiku,
            systemPrompt: "Du är en projektplanerare. Returnera alltid giltig JSON och inget annat.",
            maxTokens: 2048
        )

        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode(ExtractedPlan.self, from: data)
    }

    // MARK: - Helpers

    private func generateTitle(from plan: ProjectPlan) -> String {
        guard let first = plan.messages.first(where: { $0.role == .user }) else { return "Ny plan" }
        return String(first.content.prefix(50))
    }

    private func generateSummary(from plan: ProjectPlan) -> String {
        guard let first = plan.messages.first(where: { $0.role == .assistant }) else { return "" }
        return String(first.content.prefix(120))
    }

    // MARK: - Planning system prompt

    private var planningSystemPrompt: String {
        """
        Du är Navis projektplanerare — en expert på att hjälpa utvecklare planera nya appar och projekt.

        Din roll:
        - Ställ klargörande frågor för att förstå projektets syfte, målgrupp och krav
        - Föreslå lämplig teknisk stack baserat på plattform och krav
        - Bryt ner projektet i tydliga faser med konkreta uppgifter
        - Identifiera risker och utmaningar tidigt
        - Ge realistiska tidsuppskattningar
        - Föreslå MVP (Minimum Viable Product) och iterationer

        Format för planer:
        - Använd tydliga rubriker med ## för faser
        - Lista uppgifter med - för varje fas
        - Markera kritiska beslut med **fetstil**
        - Inkludera tidsuppskattningar i dagar/veckor
        - Avsluta alltid med ett konkret "Nästa steg"

        Exempel på struktur:
        ## Fas 1: Grundstruktur (3-5 dagar)
        - Sätt upp Xcode-projekt
        - Definiera datamodeller
        - Implementera grundläggande navigation

        **Nästa steg:** Skapa Xcode-projektet och definiera datamodellerna

        Svar på svenska om inget annat begärs. Var konkret och handlingsorienterad.
        """
    }

    // MARK: - Persistence (UserDefaults — plans are small enough)

    private func persist() {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ProjectPlan].self, from: data)
        else { return }
        plans = decoded
        activePlan = plans.first(where: { $0.status == .active }) ?? plans.first
    }
}
