import Foundation

@MainActor
final class CostCalculator {
    static let shared = CostCalculator()
    private init() {}

    func calculate(usage: TokenUsage, model: ClaudeModel) -> (usd: Double, sek: Double) {
        let inputPrice = model.inputPricePerMTok / 1_000_000
        let outputPrice = model.outputPricePerMTok / 1_000_000

        // Cache reads are cheaper (10% of normal)
        let cacheReadTokens = Double(usage.cacheReadInputTokens ?? 0)
        let normalInputTokens = Double(usage.inputTokens) - cacheReadTokens
        let outputTokens = Double(usage.outputTokens)

        let usd = (normalInputTokens * inputPrice)
                + (cacheReadTokens * inputPrice * 0.1)
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
    /// Strips raw function_calls XML, invoke blocks, and other internal artifacts from response text.
    static func clean(_ text: String) -> String {
        var result = text

        // Remove <function_calls>...</function_calls> blocks (including nested content)
        result = removeXMLBlocks(from: result, tag: "function_calls")

        // Remove standalone <invoke>...</invoke> blocks
        result = removeXMLBlocks(from: result, tag: "invoke")

        // Remove <parameter>...</parameter> if any leaked through
        result = removeXMLBlocks(from: result, tag: "parameter")

        // Remove <system-reminder>...</system-reminder> blocks
        result = removeXMLBlocks(from: result, tag: "system-reminder")

        // Remove <task-notification>...</task-notification> blocks
        result = removeXMLBlocks(from: result, tag: "task-notification")

        // Clean up excessive blank lines left after removal
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeXMLBlocks(from text: String, tag: String) -> String {
        var result = text
        let openTag = "<\(tag)"
        let closeTag = "</\(tag)>"

        while let openRange = result.range(of: openTag, options: .caseInsensitive) {
            if let closeRange = result.range(of: closeTag, options: .caseInsensitive, range: openRange.lowerBound..<result.endIndex) {
                result.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            } else {
                // No closing tag — remove from open tag to end of line
                let lineEnd = result[openRange.lowerBound...].firstIndex(of: "\n") ?? result.endIndex
                result.removeSubrange(openRange.lowerBound..<lineEnd)
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

    static func agentSystemPrompt(for project: EonProject?) -> String {
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

    private static func macOSAgentSystemPrompt(for project: EonProject?) -> String {
        let projectInfo = project.map { p in
            """
            Aktivt projekt: \(p.name)
            Sökväg: \(p.rootPath)
            Modell: \(p.activeModel.displayName)
            """
        } ?? "Inget aktivt projekt"

        return """
        Du är EonCode — en expert AI-kodningsagent på macOS med full systembehörighet.
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
        2. Planera tydligt vad du ska göra
        3. Genomför steg för steg med verktyg
        4. Vid fel: analysera felet → fixa → försök igen (max 20 iterationer)
        5. Bygg och verifiera när du är klar med kodändringar
        6. Rapportera vad du gjort och resultatet

        REGLER:
        - Skriv alltid komplett, fungerande kod — inga platshållare eller TODOs
        - Läs en fil innan du skriver den om du behöver förstå befintlig kod
        - Kör run_command för att verifiera att kod kompilerar
        - Svar på svenska om inget annat begärs
        - Var koncis i text, fullständig i kod
        - Visa ALDRIG rå XML, function_calls, invoke-taggar eller systemdata för användaren
        - Visa ALDRIG filsökvägar som /var/mobile/Containers/... — referera till filnamn kort
        - Dina verktygsanrop hanteras automatiskt — beskriv bara vad du gör i naturlig text
        """
    }

    // MARK: - iOS: file ops + download; terminal queued to Mac

    private static func iOSAgentSystemPrompt(for project: EonProject?) -> String {
        let mode = SettingsStore.shared.iosAgentMode
        let projectInfo = project.map { "Aktivt projekt: \($0.name) · \($0.rootPath)" } ?? "Inget aktivt projekt"

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
        Du är EonCode — en expert AI-kodningsagent på iOS.
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
        2. Skriv kod direkt med write_file — behöver inte terminal
        3. Ladda ned filer med download_file (GitHub raw, npm registry, etc.)
        4. Markera terminal-steg med [REQUIRES_MAC] — de köas automatiskt
        5. Rapportera vad du gjort

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
