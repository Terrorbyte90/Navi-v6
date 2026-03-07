import Foundation

// MARK: - BrowserAction

enum BrowserAction {
    case navigate(url: String)
    case click(selector: String)
    case type(selector: String, text: String)
    case submitForm(selector: String)
    case scroll(direction: String)
    case screenshot
    case waitForLoad
    case askUser(question: String)
    case goBack
    case goalComplete(summary: String)
    case goalFailed(reason: String)

    var logDescription: String {
        switch self {
        case .navigate(let url):         return "Navigerar → \(url.prefix(60))"
        case .click(let sel):            return "Klickar: \(sel.prefix(50))"
        case .type(let sel, let text):   return "Skriver '\(text.prefix(30))' i \(sel.prefix(30))"
        case .submitForm(let sel):       return "Skickar formulär: \(sel.prefix(40))"
        case .scroll(let dir):           return "Scrollar \(dir)"
        case .screenshot:                return "Tar skärmbild (vision)"
        case .waitForLoad:               return "Väntar på sidan…"
        case .askUser(let q):            return "Fråga: \(q)"
        case .goBack:                    return "Går tillbaka"
        case .goalComplete(let sum):     return "Klart: \(sum)"
        case .goalFailed(let r):         return "Misslyckades: \(r)"
        }
    }

    var shortDescription: String {
        switch self {
        case .navigate(let url):
            let host = URL(string: url)?.host ?? url.prefix(30).description
            return "Navigerar till \(host)"
        case .click:            return "Klickar…"
        case .type(_, let text): return "Skriver '\(text.prefix(20))'…"
        case .submitForm:       return "Skickar formulär…"
        case .scroll(let dir):  return "Scrollar \(dir)…"
        case .screenshot:       return "Vision-analys…"
        case .waitForLoad:      return "Väntar…"
        case .askUser:          return "Behöver hjälp…"
        case .goBack:           return "Går tillbaka…"
        case .goalComplete:     return "Klart!"
        case .goalFailed:       return "Misslyckades"
        }
    }

    var logType: BrowserLogEntry.LogType {
        switch self {
        case .navigate:     return .navigate
        case .click:        return .click
        case .type:         return .typeText
        case .submitForm:   return .click
        case .scroll:       return .scroll
        case .screenshot:   return .screenshot
        case .waitForLoad:  return .thinking
        case .askUser:      return .question
        case .goBack:       return .navigate
        case .goalComplete: return .success
        case .goalFailed:   return .failure
        }
    }
}

// MARK: - Decision result

struct BrowserDecisionResult {
    let action: BrowserAction
    let usage: TokenUsage
}

// MARK: - BrowserActionDecider

struct BrowserActionDecider {

    // MARK: - DOM-first decision

    static func decide(
        goal: String,
        subGoal: String?,
        pageContent: PageContent,
        history: ArraySlice<BrowserLogEntry>,
        strategy: BrowserAgent.BrowsingStrategy,
        apiClient: ClaudeAPIClient
    ) async throws -> BrowserDecisionResult {
        let historyText = history.map(\.displayText).joined(separator: "\n")
        let activeGoal = subGoal ?? goal

        let userMessage = """
        MÅL: \(goal)\(subGoal != nil ? "\nDELMÅL: \(activeGoal)" : "")

        HISTORIK:
        \(historyText.isEmpty ? "(start)" : historyText)

        SIDA:
        \(pageContent.summary)

        Nästa steg?
        """

        let messages = [ChatMessage(role: .user, content: [.text(userMessage)])]
        let (response, usage) = try await apiClient.sendMessage(
            messages: messages, model: .haiku,
            systemPrompt: domSystemPrompt, maxTokens: 150
        )
        return BrowserDecisionResult(action: parseAction(from: response), usage: usage)
    }

    // MARK: - Vision-based decision

    static func decideWithVision(
        goal: String,
        subGoal: String?,
        screenshotData: Data,
        basicDOM: PageContent?,
        history: ArraySlice<BrowserLogEntry>,
        apiClient: ClaudeAPIClient
    ) async throws -> BrowserDecisionResult {
        let historyText = history.map(\.displayText).joined(separator: "\n")
        let domContext = basicDOM.map { "URL: \($0.url)\nTitel: \($0.title)" } ?? ""

        let messages = [ChatMessage(
            role: .user,
            content: [
                .image(screenshotData, mimeType: "image/jpeg"),
                .text("""
                MÅL: \(goal)\(subGoal != nil ? "\nDELMÅL: \(subGoal!)" : "")
                \(domContext)
                HISTORIK:
                \(historyText.isEmpty ? "(start)" : historyText)
                Analysera skärmbilden. Svara med JSON-action.
                """)
            ]
        )]

        let (response, usage) = try await apiClient.sendMessage(
            messages: messages, model: .haiku,
            systemPrompt: visionSystemPrompt, maxTokens: 400
        )
        return BrowserDecisionResult(action: parseAction(from: response), usage: usage)
    }

    // MARK: - System prompts

    private static let domSystemPrompt = """
    Du är en autonom webbläsaragent. Analysera sidans DOM och välj nästa action.

    Svara med exakt ETT JSON-objekt, inget annat:
    {"action": "navigate", "url": "https://..."}
    {"action": "click", "selector": "CSS-selector eller [N] för länkindex"}
    {"action": "type", "selector": "CSS-selector", "text": "text"}
    {"action": "submit", "selector": "CSS-selector"}
    {"action": "scroll", "direction": "down|up"}
    {"action": "screenshot"}
    {"action": "wait"}
    {"action": "ask_user", "question": "..."}
    {"action": "go_back"}
    {"action": "goal_complete", "summary": "Fullständigt resultat/svar"}
    {"action": "goal_failed", "reason": "Varför"}

    STRATEGI:
    1. Cookie/GDPR/consent-banners: ALLTID klicka "acceptera"/"godkänn"/"allow" OMEDELBART. Prioritera detta före allt annat.
    2. SNABBVÄGAR: Om sidan har ett sökfält och målet handlar om att söka — skriv direkt i fältet utan extra steg.
    3. Om sidan har en specifik navigeringslänk till rätt sektion — klicka den direkt.
    4. CAPTCHA/inloggning: ask_user.
    5. Vid jämförelser: besök FLERA sidor, sammanställ i goal_complete.
    6. Om du scrollat 3+ gånger utan resultat: sök annorlunda, go_back, eller prova en annan URL.
    7. Om du fastnat (upprepar samma action): BYT strategi — prova screenshot, annan URL, eller go_back.
    8. Testa minst 3 alternativ innan goal_failed.
    9. goal_complete MÅSTE innehålla hela svaret/resultatet — aldrig bara "klart".
    10. Var SNABB: välj direkt rätt action, slösa inte steg.

    VIKTIGT: Svara BARA med JSON. Ingen annan text.
    """

    private static let visionSystemPrompt = """
    Du är en webbläsaragent med synförmåga. Du ser en skärmbild.
    Svara med ETT JSON-objekt, inget annat.
    Actions: navigate, click, type, submit, scroll, wait, ask_user, go_back, goal_complete, goal_failed.
    Cookie/consent-banners: klicka acceptera OMEDELBART — leta efter knappar med "Accept"/"Godkänn"/"OK".
    Click: använd CSS-selector baserad på vad du ser (t.ex. '#accept-btn', 'button.accept', '[aria-label=Accept]').
    Trasiga sidor: go_back.
    goal_complete: inkludera hela resultatet.
    """

    // MARK: - Parse JSON

    static func parseAction(from text: String) -> BrowserAction {
        guard let jsonStr = extractJSON(from: text),
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else {
            return .waitForLoad
        }

        switch action {
        case "navigate":
            guard let url = obj["url"] as? String, !url.isEmpty else { return .waitForLoad }
            return .navigate(url: url)
        case "click":
            guard let sel = obj["selector"] as? String, !sel.isEmpty else { return .waitForLoad }
            return .click(selector: sel)
        case "type":
            guard let sel = obj["selector"] as? String, !sel.isEmpty,
                  let text = obj["text"] as? String else { return .waitForLoad }
            return .type(selector: sel, text: text)
        case "submit":
            return .submitForm(selector: (obj["selector"] as? String) ?? "form")
        case "scroll":
            return .scroll(direction: (obj["direction"] as? String) ?? "down")
        case "screenshot": return .screenshot
        case "wait": return .waitForLoad
        case "ask_user":
            return .askUser(question: (obj["question"] as? String) ?? "Behöver din hjälp")
        case "go_back": return .goBack
        case "goal_complete":
            return .goalComplete(summary: (obj["summary"] as? String) ?? "Uppgiften klar")
        case "goal_failed":
            return .goalFailed(reason: (obj["reason"] as? String) ?? "Okänd anledning")
        default: return .waitForLoad
        }
    }

    private static func extractJSON(from text: String) -> String? {
        guard let startIdx = text.firstIndex(of: "{") else { return nil }
        var depth = 0; var inString = false; var escape = false; var endIdx: String.Index?
        for i in text[startIdx...].indices {
            let ch = text[i]
            if escape { escape = false; continue }
            if ch == "\\" && inString { escape = true; continue }
            if ch == "\"" { inString = !inString; continue }
            if inString { continue }
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1; if depth == 0 { endIdx = i; break } }
        }
        guard let end = endIdx else { return nil }
        return String(text[startIdx...end])
    }
}
