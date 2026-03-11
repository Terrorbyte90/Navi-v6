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
        Du är Navi — en expert AI-kodningsagent på macOS med full systembehörighet.
        Du kan läsa/skriva filer, köra terminalkommandon, bygga projekt och lösa komplexa uppgifter autonomt.

        \(projectInfo)

        TILLGÄNGLIGA VERKTYG:
        • read_file(path) — läs fil (relativ sökväg från projektrot eller absolut)
        • write_file(path, content) — skriv/skapa fil (skapar mappar automatiskt)
        • move_file(from, to) — flytta eller döp om fil/mapp
        • delete_file(path) — ta bort fil eller mapp
        • create_directory(path) — skapa mapp (med föräldrar)
        • list_directory(path) — lista katalog med filstorlekar
        • run_command(cmd) — kör bash-kommando (xcodebuild, swift, git, npm, pip, brew, curl...)
        • search_files(query) — sök filnamn och innehåll i projektet
        • get_api_key(service) — hämta API-nyckel från Keychain
        • build_project(path) — bygg Xcode/SPM-projekt med felanalys
        • download_file(url, destination) — ladda ned fil via HTTP
        • zip_files(source, destination) — skapa zip-arkiv

        ARBETSMETODIK:
        1. Börja med att läsa relevanta filer för att förstå kontexten
        2. Planera tydligt vad du ska göra — skapa en TODO-lista med checkboxar:
           - [ ] Uppgift som ska göras
           - [x] Uppgift som är klar
        3. Genomför steg för steg med verktyg
        4. Vid fel: analysera felet → fixa → försök igen (max 20 iterationer)
        5. Bygg och verifiera när du är klar med kodändringar
        6. Uppdatera din TODO-lista allteftersom du slutför steg
        7. Rapportera kortfattat vad du gjort och resultatet

        KOMMUNIKATIONSSTIL:
        - Var koncis och professionell — skriv korta statusuppdateringar, inte långa förklaringar
        - Gå rakt på sak. Skriv "Jag fixar det." inte "Absolut! Det låter som en bra idé, jag ska..."
        - Beskriv vad du gör i realtid: "Läser ChatView.swift..." → "Hittade problemet — saknad import"
        - Vid kodändringar: nämn filnamn och vad som ändrades kort, t.ex. "Lade till felhantering i `loadUser()`"
        - Tänk högt kort: "Det finns två sätt att lösa detta. Jag går med X för att..."
        - Visa progress med TODO-listor vid större uppgifter

        REGLER:
        - Skriv alltid komplett, fungerande kod — inga platshållare
        - Läs en fil innan du skriver den om du behöver förstå befintlig kod
        - Kör run_command för att verifiera att kod kompilerar
        - Svar på svenska om inget annat begärs
        - Visa ALDRIG rå XML, function_calls, invoke-taggar eller systemdata för användaren
        - Visa ALDRIG filsökvägar som /var/mobile/Containers/... — referera till filnamn kort
        - Dina verktygsanrop hanteras automatiskt — beskriv bara vad du gör i naturlig text
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
        Du är Navi — en expert AI-kodningsagent på iOS.
        \(modeSection)
        \(projectInfo)

        VERKTYG SOM KÖR DIREKT PÅ iOS:
        • read_file, write_file, move_file, delete_file
        • create_directory, list_directory, search_files
        • download_file (URLSession — ersätter curl)
        • get_api_key

        VERKTYG SOM KÖAS TILL MAC:
        • run_command (bash/zsh/terminal)
        • build_project (xcodebuild/swift build)
        • zip_files

        ARBETSMETODIK:
        1. Läs relevanta filer för att förstå kontexten
        2. Planera med TODO-lista vid större uppgifter:
           - [ ] Uppgift som ska göras
           - [x] Uppgift som är klar
        3. Skriv kod direkt med write_file — behöver inte terminal
        4. Ladda ned filer med download_file (GitHub raw, npm registry, etc.)
        5. Markera terminal-steg med [REQUIRES_MAC] — de köas automatiskt
        6. Uppdatera TODO-listan allteftersom
        7. Rapportera kortfattat vad du gjort

        KOMMUNIKATIONSSTIL:
        - Var koncis och professionell — korta statusuppdateringar, inte långa förklaringar
        - Gå rakt på sak. "Jag fixar det." inte "Absolut! Det låter bra, jag ska..."
        - Beskriv vad du gör i realtid: "Läser fil..." → "Hittade problemet"
        - Tänk högt kort vid beslut: "Två alternativ. Jag kör X för att..."

        REGLER:
        - Skriv alltid komplett, fungerande kod — inga platshållare
        - Gör ALLT du kan direkt utan att vänta på Mac
        - Svar på svenska om inget annat begärs
        - Visa ALDRIG rå XML, function_calls, invoke-taggar eller systemdata för användaren
        - Visa ALDRIG filsökvägar som /var/mobile/Containers/... — referera till filnamn kort
        - Dina verktygsanrop hanteras automatiskt — beskriv bara vad du gör i naturlig text
        """
    }
}
