import Foundation

@MainActor
final class CostCalculator {
    static let shared = CostCalculator()
    private init() {}

    func calculate(usage: TokenUsage, model: ClaudeModel) -> (usd: Double, sek: Double) {
        let inputPrice = model.inputPricePerMTok / 1_000_000
        let outputPrice = model.outputPricePerMTok / 1_000_000

        // Cache reads: 10% of normal input price
        let cacheReadTokens = Double(usage.cacheReadInputTokens ?? 0)
        // Cache writes: 125% of normal input price (Anthropic pricing)
        let cacheWriteTokens = Double(usage.cacheCreationInputTokens ?? 0)
        // Normal input = total input minus cache-read and cache-write tokens
        let normalInputTokens = Double(usage.inputTokens) - cacheReadTokens - cacheWriteTokens
        let outputTokens = Double(usage.outputTokens)

        let usd = (normalInputTokens * inputPrice)
                + (cacheReadTokens * inputPrice * 0.1)
                + (cacheWriteTokens * inputPrice * 1.25)
                + (outputTokens * outputPrice)

        let sek = usd * ExchangeRateService.shared.usdToSEK
        return (usd, sek)
    }

    func formatSEK(_ amount: Double) -> String {
        if amount < 0.01 { return "< 0.01 SEK" }
        return String(format: "%.2f SEK", amount)
    }

    func formatUSD(_ amount: Double) -> String {
        if amount < 0.001 { return "< $0.001" }
        return String(format: "$%.4f", amount)
    }

    func costDescription(usage: TokenUsage, model: ClaudeModel) -> String {
        let (usd, sek) = calculate(usage: usage, model: model)
        return "\(formatSEK(sek)) · \(usage.inputTokens)→\(usage.outputTokens) tok"
    }
}

// MARK: - Response cleaner — strips internal XML/system data from agent output

enum ResponseCleaner {
    /// All XML/internal tags that should never be shown to the user.
    private static let strippedTags = [
        "function_calls", "invoke", "parameter",
        "system-reminder", "task-notification",
        "antml_thinking", "antml:thinking", "thinking",
        "antml_invoke", "antml:invoke",
        "antml_function_calls", "antml:function_calls",
        "artifact", "result", "tool_call",
        "search_quality_reflection", "search_quality_score",
    ]

    /// Strips raw function_calls XML, invoke blocks, thinking blocks, system echoes, and other internal artifacts from response text.
    static func clean(_ text: String) -> String {
        var result = text

        // Strip all known internal tags
        for tag in strippedTags {
            result = removeXMLBlocks(from: result, tag: tag)
        }

        // Remove orphaned self-closing tags like <thinking/>
        if let regex = try? NSRegularExpression(pattern: "<[a-zA-Z_:]+\\s*/\\s*>") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove lines that are just XML-like tags (e.g. standalone <thinking> without close)
        if let regex = try? NSRegularExpression(pattern: "^\\s*</?[a-zA-Z_:]+[^>]*>\\s*$", options: .anchorsMatchLines) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Strip system prompt echoes from MiniMax/OpenRouter models
        // These models sometimes repeat the system prompt at the start of the response
        result = stripSystemEchoes(result)

        // Clean up excessive blank lines left after removal
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip system prompt echoes that MiniMax and other OpenRouter models sometimes include
    private static func stripSystemEchoes(_ text: String) -> String {
        var result = text

        // Common patterns where models echo back system instructions
        let systemEchoPatterns = [
            // Models echoing "Du är Navi" system prompt
            "^\\s*(?:System:|\\[System\\]|<system>).*?(?:\n\n|\n(?=[A-ZÅÄÖ]))",
            // Models echoing role assignments
            "^\\s*(?:As an AI assistant|I am Navi|Jag är Navi —).*?(?:\n\n)",
            // Navi Code system prompt echo
            "^\\s*Du är Navi Code — senior arkitekt.*?(?:\\n\\n|$)",
            // Models echoing ## Identitet, ## Modellregler etc.
            "^\\s*## (?:Identitet|Modellregler|Ditt arbetsflöde|Kodkvalitet|Projektkontext|Vad du ALDRIG).*?(?=\\n## |\\n\\n[^#]|$)",
        ]

        for pattern in systemEchoPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(result.startIndex..., in: result)
                // Only strip from the beginning (first 500 chars) to avoid removing legitimate content
                let limitedRange = NSRange(location: 0, length: min(500, range.length))
                result = regex.stringByReplacingMatches(in: result, range: limitedRange, withTemplate: "")
            }
        }

        return result
    }

    private static func removeXMLBlocks(from text: String, tag: String) -> String {
        var result = text
        // Escape colons for regex-safe matching but use literal string matching
        let openTag = "<\(tag)"
        let closeTag = "</\(tag)>"

        while let openRange = result.range(of: openTag, options: .caseInsensitive) {
            if let closeRange = result.range(of: closeTag, options: .caseInsensitive, range: openRange.lowerBound..<result.endIndex) {
                result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            } else {
                // No closing tag — remove from open tag to end (partial/streaming tag)
                result.removeSubrange(openRange.lowerBound..<result.endIndex)
            }
        }
        return result
    }
}

// MARK: - Message builder with context management

@MainActor
final class MessageBuilder {
    static func buildAPIMessages(
        from conversation: Conversation,
        projectContext: String? = nil,
        fileContents: [String: String] = [:]
    ) -> [ChatMessage] {
        var messages = conversation.messages

        // Inject file contents into context if available
        if !fileContents.isEmpty || projectContext != nil {
            var contextText = ""
            if let proj = projectContext {
                contextText += proj + "\n\n"
            }
            for (path, content) in fileContents {
                contextText += "=== \(path) ===\n\(content)\n\n"
            }
            if !contextText.isEmpty {
                // Prepend context to first user message or add system-like message
                if let firstIdx = messages.firstIndex(where: { $0.role == .user }) {
                    var first = messages[firstIdx]
                    var newContent = [MessageContent.text("[PROJEKT KONTEXT]\n\(contextText)\n[SLUT KONTEXT]\n\n")]
                    newContent.append(contentsOf: first.content)
                    first.content = newContent
                    messages[firstIdx] = first
                }
            }
        }

        return messages
    }

    /// Current active view context (set by UI before sending messages)
    static var currentViewContext: String = ""

    static func agentSystemPrompt(for project: NaviProject?) -> String {
        #if os(iOS)
        var prompt = iOSAgentSystemPrompt(for: project)
        #else
        var prompt = macOSAgentSystemPrompt(for: project)
        #endif

        // View context
        if !currentViewContext.isEmpty {
            prompt += "\n\nAKTIV VY: \(currentViewContext)"
        }

        let memCtx = MemoryManager.shared.memoryContext()
        if !memCtx.isEmpty { prompt += "\n\n---\nKONTEXT OM ANVÄNDAREN:\n\(memCtx)" }
        return prompt
    }

    // MARK: - macOS: full capabilities

    private static func macOSAgentSystemPrompt(for project: NaviProject?) -> String {
        let projectInfo: String
        if let p = project {
            var info = """
            Aktivt projekt: \(p.name)
            Sökväg: \(p.rootPath)
            Modell: \(p.activeModel.displayName)
            """
            if let repo = p.githubRepoFullName {
                info += "\nGitHub-repo: \(repo)"
                if let branch = p.githubBranch {
                    info += " (branch: \(branch))"
                }
                if let localPath = GitHubManager.shared.clonedRepos[repo] {
                    info += "\nKlonad till: \(localPath)"
                }
            }
            projectInfo = info
        } else {
            projectInfo = "Inget aktivt projekt"
        }

        return """
        Du är Navi — en autonom, premiumkvalitativ AI-utvecklingsagent skapad av Ted Svärd.
        Full systembehörighet på macOS. Löser komplexa uppgifter autonomt.

        \(projectInfo)

        ─── ARBETSSÄTT (ReAct-loop) ───────────────────────────

        THINK → PLAN → ACT (verktyg) → OBSERVE → REPEAT tills löst.
        Läs filer innan du ändrar. Verifiera med verktyg — anta ingenting.

        ─── VERKTYG ───────────────────────────────────────────

        • Filer: read_file, write_file, move_file, delete_file, create_directory, list_directory, search_files
        • Terminal: run_command (bash, xcodebuild, swift, git, npm, pip, brew, curl)
        • Bygg: build_project (Xcode/SPM med felanalys)
        • GitHub: github_list_repos, github_get_repo, github_list_branches, github_list_commits,
                  github_list_pull_requests, github_create_pull_request, github_get_file_content,
                  github_search_repos, github_get_user
        • Webb: web_search
        • Server: server_ask, server_status, server_exec, server_repos
        • Övrigt: download_file, zip_files, get_api_key

        ─── KOMMUNIKATION ─────────────────────────────────────

        💭 Tänker  📋 Planerar  🔍 Söker  📁 Filer  📝 Kodar
        🐙 GitHub  🖥️ Server  🌐 Webb  ✅ Klart  ❌ Fel

        - Koncis och professionell. Gå rakt på sak.
        - TODO-listor vid större uppgifter: [ ] pågår, [x] klart
        - Beskriv i realtid: "Läser ChatView.swift..." → "Hittade problemet"

        ─── REGLER ────────────────────────────────────────────

        - Komplett, fungerande kod — inga platshållare
        - Verifiera med run_command/build_project
        - Svar på svenska om inget annat begärs
        - Visa ALDRIG rå XML, systemdata eller interna sökvägar
        - Om någon frågar: "Jag är Navi, skapad av Ted Svärd."

        ─── SLUTLEVERANS ──────────────────────────────────────

        Avsluta med: vad som gjordes, ändrade filer, beslut, nästa steg.
        """
    }

    // MARK: - iOS: file ops + download; terminal queued to Mac

    private static func iOSAgentSystemPrompt(for project: NaviProject?) -> String {
        let mode = SettingsStore.shared.iosAgentMode
        let projectInfo: String
        if let p = project {
            var info = "Aktivt projekt: \(p.name) · \(p.rootPath)"
            if let repo = p.githubRepoFullName {
                info += "\nGitHub-repo: \(repo)"
                if let branch = p.githubBranch { info += " (branch: \(branch))" }
            }
            projectInfo = info
        } else {
            projectInfo = "Inget aktivt projekt"
        }

        let modeSection: String
        if mode == .autonomous {
            modeSection = """
            LÄGE: Autonom
            Du kör fil-operationer direkt på iOS. Terminal-kommandon köas automatiskt till Mac.
            """
        } else {
            modeSection = """
            LÄGE: Remote
            Alla operationer köas till Mac för exekvering.
            """
        }

        return """
        Du är Navi — en autonom AI-utvecklingsagent skapad av Ted Svärd, optimerad för iOS.
        \(modeSection)
        \(projectInfo)

        ─── ARBETSSÄTT (ReAct-loop) ───────────────────────────

        THINK → PLAN → ACT (verktyg) → OBSERVE → REPEAT tills löst.

        ─── VERKTYG (direkt på iOS) ───────────────────────────

        • read_file, write_file, move_file, delete_file
        • create_directory, list_directory, search_files
        • download_file (URLSession), get_api_key
        • github_*, web_search, server_*

        Terminal-kommandon (run_command, build_project, zip_files) köas till Mac.

        ─── KOMMUNIKATION ─────────────────────────────────────

        - Koncis och professionell. Gå rakt på sak.
        - TODO-listor vid större uppgifter
        - Beskriv i realtid: "Läser fil..." → "Hittade problemet"

        ─── REGLER ────────────────────────────────────────────

        - Komplett kod — inga platshållare. Gör ALLT direkt utan Mac.
        - Svar på svenska. Visa ALDRIG rå XML eller interna sökvägar.
        - Om någon frågar: "Jag är Navi, skapad av Ted Svärd."
        """
    }
}
