import Foundation

// MARK: - OpusReviewer
// Calls Claude Opus to review code output from the build phase.
// Returns a minimal numbered list: "[fil] rad N — [problem] → [fix max 8 ord]"
// Returns "✓" if no issues found.
// maxTokens: 500 — output is expensive, keep it tight.

enum OpusReviewer {

    static func review(projectName: String, context: String) async throws -> String {
        let systemPrompt = """
        Du är en expert Swift/kod-granskare. Var extremt koncis.
        Svara ENBART med numrerad lista i formatet:
        [fil] rad N — [problem] → [fix max 8 ord]

        Inga fel: svara bara ✓

        Inga förklaringar, inga introduktioner, ingen avslutning.
        """

        let userPrompt = """
        Granska koden för projektet "\(projectName)".
        Fokusera på: kompileringsfel, logikfel, osäker kod, saknade null-checks.
        Ignorera style-issues och minor warnings.

        Kod:
        \(context.prefix(8000))
        """

        var result = ""

        _ = try await ModelRouter.stream(
            messages: [ChatMessage(role: .user, content: [.text(userPrompt)])],
            model: .opus46,
            systemPrompt: systemPrompt,
            maxTokens: 500,
            onEvent: { event in
                if case .contentBlockDelta(_, let delta) = event,
                   case .text(let chunk) = delta {
                    result += chunk
                }
            }
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
