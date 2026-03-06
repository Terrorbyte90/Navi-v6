import Foundation

// MARK: - BrowserAction

enum BrowserAction {
    case navigate(url: String)
    case click(selector: String)
    case type(selector: String, text: String)
    case scroll(direction: String)
    case screenshot
    case waitForLoad
    case askUser(question: String)
    case goalComplete(summary: String)
    case goalFailed(reason: String)

    var logDescription: String {
        switch self {
        case .navigate(let url):         return "🌐 Navigerar till \(url)"
        case .click(let sel):            return "👆 Klickar på \(sel)"
        case .type(let sel, let text):   return "⌨️ Skriver '\(text.prefix(40))' i \(sel)"
        case .scroll(let dir):           return "📜 Scrollar \(dir)"
        case .screenshot:                return "📸 Tar skärmbild (vision-läge)"
        case .waitForLoad:               return "⏳ Väntar på att sidan laddas…"
        case .askUser(let q):            return "❓ Frågar användaren: \(q)"
        case .goalComplete(let sum):     return "✅ Klart! \(sum)"
        case .goalFailed(let r):         return "❌ Misslyckades: \(r)"
        }
    }
}

// MARK: - BrowserActionDecider

struct BrowserActionDecider {

    static let systemPrompt = """
    Du är en autonom webbläsaragent. Du surfar på webben för att uppnå användarens mål.

    Du får sidans innehåll som strukturerad text (titel, synlig text, länkar, input-fält, knappar).

    Svara ALLTID med exakt ett JSON-objekt och inget annat:

    {"action": "navigate", "url": "https://..."}
    {"action": "click", "selector": "CSS-selector eller länkindex [N]"}
    {"action": "type", "selector": "CSS-selector", "text": "text att skriva"}
    {"action": "scroll", "direction": "down"}
    {"action": "scroll", "direction": "up"}
    {"action": "screenshot"}
    {"action": "wait"}
    {"action": "ask_user", "question": "Fråga till användaren"}
    {"action": "goal_complete", "summary": "Sammanfattning av resultatet"}
    {"action": "goal_failed", "reason": "Varför det misslyckades"}

    Regler:
    - Tänk steg för steg — välj den mest logiska nästa actionen.
    - Om sidan har cookie-consent, klicka bort den direkt.
    - Om du ser CAPTCHA, använd ask_user.
    - Om sidan kräver inloggning och du inte har credentials, använd ask_user.
    - Prova text-extraktion först — använd 'screenshot' bara när text inte räcker.
    - Ge aldrig upp direkt. Försök minst 3 alternativa strategier innan goal_failed.
    - Klicka på rätt element med CSS-selector. Länkindex [N] fungerar med navigate.
    - Max 50 steg per uppgift.
    """

    static func decide(
        goal: String,
        pageContent: PageContent,
        history: [BrowserLogEntry],
        apiClient: ClaudeAPIClient
    ) async throws -> BrowserAction {
        let historyText = history.suffix(20)
            .map { $0.displayText }
            .joined(separator: "\n")

        let userMessage = """
        Mål: \(goal)

        Historik (senaste stegen):
        \(historyText.isEmpty ? "(inga steg ännu)" : historyText)

        Aktuell sida:
        \(pageContent.summary)

        Vad ska nästa steg vara?
        """

        let messages = [ChatMessage(role: .user, content: [.text(userMessage)])]
        let (response, _) = try await apiClient.sendMessage(
            messages: messages,
            model: .haiku,
            systemPrompt: systemPrompt,
            maxTokens: 256
        )

        return parseAction(from: response)
    }

    // MARK: - Parse JSON response

    static func parseAction(from text: String) -> BrowserAction {
        // Find matching braces to extract JSON properly
        guard let jsonStr = extractJSON(from: text),
              let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = obj["action"] as? String else {
            print("⚠️ BrowserActionDecider: kunde inte tolka JSON från svar: \(text.prefix(200))")
            return .waitForLoad
        }

        switch action {
        case "navigate":
            guard let url = obj["url"] as? String, !url.isEmpty else {
                print("⚠️ BrowserActionDecider: navigate saknar giltig URL")
                return .waitForLoad
            }
            return .navigate(url: url)
        case "click":
            guard let selector = obj["selector"] as? String, !selector.isEmpty else {
                print("⚠️ BrowserActionDecider: click saknar giltig selector")
                return .waitForLoad
            }
            return .click(selector: selector)
        case "type":
            guard let selector = obj["selector"] as? String, !selector.isEmpty,
                  let text = obj["text"] as? String else {
                print("⚠️ BrowserActionDecider: type saknar selector eller text")
                return .waitForLoad
            }
            return .type(selector: selector, text: text)
        case "scroll":
            return .scroll(direction: (obj["direction"] as? String) ?? "down")
        case "screenshot":
            return .screenshot
        case "wait":
            return .waitForLoad
        case "ask_user":
            return .askUser(question: (obj["question"] as? String) ?? "Behöver din hjälp")
        case "goal_complete":
            return .goalComplete(summary: (obj["summary"] as? String) ?? "Uppgiften är klar")
        case "goal_failed":
            return .goalFailed(reason: (obj["reason"] as? String) ?? "Okänd anledning")
        default:
            print("⚠️ BrowserActionDecider: okänd action '\(action)'")
            return .waitForLoad
        }
    }

    /// Extract the outermost JSON object by matching braces properly
    private static func extractJSON(from text: String) -> String? {
        guard let startIdx = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var endIdx: String.Index?

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
