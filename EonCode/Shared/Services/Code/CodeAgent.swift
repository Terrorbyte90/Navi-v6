import Foundation
import SwiftUI

// MARK: - CodeIntent
// Classification result from classifyIntent() — determines how Code responds.

enum CodeIntent {
    case question      // User asks something, wants analysis/summary/answer
    case execute       // User wants to build/code/create something
    case githubLookup  // User wants to look at / search GitHub
    case planOnly      // User wants a plan but not immediate execution
}

// MARK: - CodeAgent
// Orchestrates the 6-phase pipeline: spec → research → setup → plan → build → push.
// Drives CodeView's live UI via @Published properties.

@MainActor
final class CodeAgent: ObservableObject {

    // MARK: - Published state (drives UI)

    @Published var projects: [CodeProject] = []
    @Published var activeProject: CodeProject?

    @Published var phase: PipelinePhase = .idle
    @Published var streamingText: String = ""
    @Published var isRunning: Bool = false
    @Published var workerStatuses: [WorkerStatus] = []
    @Published var usedFallback: Bool = false
    @Published var actualModel: ClaudeModel = .sonnet46
    @Published var quietLog: String = ""
    @Published var opusReviewEnabled: Bool = false
    /// Live tool call name during execution (for animated card in CodeView)
    @Published var liveToolCall: String? = nil
    /// Iteration counter for current agentic loop
    @Published var currentIteration: Int = 0

    // MARK: - Singleton

    static let shared = CodeAgent()
    private init() {
        Task { await loadProjects() }
    }

    // MARK: - Cancel

    private var currentTask: Task<Void, Never>?

    func stop() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        phase = .idle
        liveToolCall = nil
        currentIteration = 0
    }

    // MARK: - Load / new project

    func loadProjects() async {
        projects = (try? await CodeProjectStore.shared.loadAll()) ?? []
        if activeProject == nil { activeProject = projects.first }
    }

    func newProject(idea: String, model: ClaudeModel) -> CodeProject {
        let name = extractProjectName(from: idea)
        let proj = CodeProject(
            name: name,
            idea: idea,
            model: model,
            parallelWorkers: SettingsStore.shared.maxParallelWorkers
        )
        projects.insert(proj, at: 0)
        activeProject = proj
        Task { try? await CodeProjectStore.shared.save(proj) }
        return proj
    }

    func selectProject(_ project: CodeProject) {
        activeProject = project
    }

    func deleteProject(_ project: CodeProject) async {
        projects.removeAll { $0.id == project.id }
        try? await CodeProjectStore.shared.delete(id: project.id)
        if activeProject?.id == project.id {
            activeProject = projects.first
        }
    }

    // MARK: - Main entry: smart intent routing

    /// Smart entry point: classifies intent before deciding to run pipeline or just answer.
    func handleMessage(text: String, model: ClaudeModel) {
        guard !isRunning else { return }

        actualModel = model
        usedFallback = false

        currentTask = Task {
            isRunning = true
            defer { isRunning = false }

            let intent = await classifyIntent(text: text, model: model)

            switch intent {
            case .execute:
                // Run full pipeline
                let proj = newProject(idea: text, model: model)
                do {
                    try Task.checkCancellation()
                    await runPipeline(project: proj, model: model)
                } catch {
                    appendMessage("❌ \(error.localizedDescription)", role: .assistant)
                }

            case .planOnly:
                // Create project shell, show plan, ask for confirmation
                var proj = newProject(idea: text, model: model)
                appendMessage(text, role: .user)
                let planText = await runPhase(name: "Plan", prompt: planOnlyPrompt(idea: text), proj: &proj, model: model)
                proj.plan = planText
                updateProject(proj)
                appendMessage("💡 **Vill du att jag kör? Svara ja för att starta bygget.**", role: .assistant)

            case .githubLookup, .question:
                // No pipeline — just stream an answer
                if activeProject == nil {
                    _ = newProject(idea: text, model: model)
                }
                appendMessage(text, role: .user)
                guard var proj = activeProject else { return }
                await streamAnswer(text: text, proj: &proj, model: model)
            }
        }
    }

    /// Fast intent classification using Haiku (1 round-trip, ~50 output tokens).
    private func classifyIntent(text: String, model: ClaudeModel) async -> CodeIntent {
        let systemMsg = "Du klassificerar användarintentioner. Svara ENBART med ett ord: question / execute / github / plan"
        let userMsg = """
        Klassificera detta meddelande i ETT ord:
        - question = frågar något, vill ha analys/sammanfattning/svar
        - execute = vill bygga/koda/skapa något
        - github = vill titta på/söka GitHub
        - plan = vill ha en plan men inte köra ännu

        Meddelande: \(text)
        """

        var result = ""
        do {
            _ = try await ModelRouter.stream(
                messages: [ChatMessage(role: .user, content: [.text(userMsg)])],
                model: .haiku,
                systemPrompt: systemMsg,
                maxTokens: 20,
                onEvent: { event in
                    if case .contentBlockDelta(_, let delta) = event,
                       case .text(let chunk) = delta {
                        result += chunk
                    }
                }
            )
        } catch { }

        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.contains("execute") || cleaned.contains("build") { return .execute }
        if cleaned.contains("github") { return .githubLookup }
        if cleaned.contains("plan") { return .planOnly }
        return .question
    }

    /// Stream a plain answer (no pipeline) — for questions and GitHub lookups.
    private func streamAnswer(text: String, proj: inout CodeProject, model: ClaudeModel) async {
        streamingText = ""
        var fullText = ""
        phase = .spec // reuse spec phase icon for "thinking"

        let messages = buildAPIMessages(from: proj)

        do {
            let usedModel = try await ModelRouter.stream(
                messages: messages,
                model: model,
                systemPrompt: codeSystemPrompt(for: proj),
                onEvent: { [weak self] event in
                    if case .contentBlockDelta(_, let delta) = event,
                       case .text(let chunk) = delta {
                        self?.streamingText += chunk
                        fullText += chunk
                    }
                }
            )
            if usedModel != model { usedFallback = true; actualModel = usedModel }
        } catch {
            fullText = "❌ \(error.localizedDescription)"
        }

        streamingText = ""
        appendMessage(fullText, role: .assistant)
        phase = .idle
    }

    // MARK: - Start full pipeline directly (used internally)

    func start(idea: String, model: ClaudeModel) {
        guard !isRunning else { return }

        let proj = newProject(idea: idea, model: model)
        actualModel = model
        usedFallback = false

        currentTask = Task {
            isRunning = true
            defer { isRunning = false }

            do {
                try Task.checkCancellation()
                await runPipeline(project: proj, model: model)
            } catch {
                appendMessage("❌ \(error.localizedDescription)", role: .assistant)
            }
        }
    }

    // MARK: - Continue chat (after pipeline done)

    func continueChat(text: String, model: ClaudeModel) {
        guard !isRunning, var proj = activeProject else { return }

        // Parse "Använd N parallella agenter"
        if let n = parseWorkerCount(from: text) {
            setParallelWorkers(n)
        }

        // Check if user confirmed plan execution
        if text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("ja") &&
           proj.plan.isEmpty == false && proj.currentPhase == .idle {
            appendMessage(text, role: .user)
            currentTask = Task {
                isRunning = true
                defer { isRunning = false }
                await runPipeline(project: proj, model: model)
            }
            return
        }

        appendMessage(text, role: .user)

        currentTask = Task {
            isRunning = true
            defer { isRunning = false }

            phase = .build

            let messages = buildAPIMessages(from: proj)
            streamingText = ""
            var fullText = ""

            do {
                let usedModel = try await ModelRouter.stream(
                    messages: messages,
                    model: model,
                    systemPrompt: codeSystemPrompt(for: proj),
                    onEvent: { [weak self] event in
                        if case .contentBlockDelta(_, let delta) = event,
                           case .text(let chunk) = delta {
                            self?.streamingText += chunk
                            fullText += chunk
                        }
                    }
                )
                if usedModel != model { usedFallback = true; actualModel = usedModel }
            } catch {
                fullText = "❌ \(error.localizedDescription)"
            }

            streamingText = ""
            appendMessage(fullText, role: .assistant)
            phase = .idle
        }
    }

    func setParallelWorkers(_ n: Int) {
        guard var proj = activeProject else { return }
        proj.parallelWorkers = max(1, min(n, 10))
        updateProject(proj)
        // Reset worker status slots
        workerStatuses = (0..<proj.parallelWorkers).map {
            WorkerStatus(workerIndex: $0)
        }
    }

    // MARK: - Pipeline

    private func runPipeline(project: CodeProject, model: ClaudeModel) async {
        var proj = project

        // 0. Auto-sync GitHub repos to iCloud before coding
        if KeychainManager.shared.githubToken?.isEmpty == false {
            setLog("Synkar GitHub-repos...")
            await GitHubManager.shared.autoSyncToiCloud()
        }

        // 1. Spec
        phase = .spec
        currentIteration = 1
        appendMessage("📋 **Spec** — Analyserar och expanderar din idé…", role: .assistant)
        let spec = await runPhase(name: "Spec", prompt: specPrompt(for: proj), proj: &proj, model: model)
        proj.spec = spec
        updateProject(proj)

        guard !Task.isCancelled else { return }

        // 2. Research
        phase = .research
        currentIteration = 2
        appendMessage("🔍 **Research** — Undersöker tekniska krav och beroenden…", role: .assistant)
        let research = await runPhase(name: "Research", prompt: researchPrompt(for: proj), proj: &proj, model: model)
        proj.researchNotes = research
        updateProject(proj)

        guard !Task.isCancelled else { return }

        // 3. Setup — create GitHub repo if available
        phase = .setup
        currentIteration = 3
        appendMessage("🏗 **Setup** — Skapar GitHub-repo och projektstruktur…", role: .assistant)
        setLog("Setup: initierar projektstruktur")

        // We call GitHubManager if a NaviProject is available for this idea,
        // but CodeAgent works standalone without requiring a NaviProject.
        // The setup phase just confirms via AI what structure was created.
        let setupConfirm = await runPhase(name: "Setup", prompt: setupPrompt(for: proj), proj: &proj, model: .haiku)
        appendMessage(setupConfirm, role: .assistant)

        guard !Task.isCancelled else { return }

        // 4. Plan
        phase = .plan
        currentIteration = 4
        appendMessage("📐 **Plan** — Skapar implementationsplan med uppgifter…", role: .assistant)
        let plan = await runPhase(name: "Plan", prompt: planPrompt(for: proj), proj: &proj, model: model)
        proj.plan = plan
        updateProject(proj)

        guard !Task.isCancelled else { return }

        // 5. Build — extract tasks from plan and run WorkerPool
        phase = .build
        currentIteration = 5
        appendMessage("⚡ **Build** — Startar \(proj.parallelWorkers) parallella workers…", role: .assistant)

        let tasks = extractWorkerTasks(from: plan, projectID: proj.id)
        workerStatuses = (0..<min(tasks.count, proj.parallelWorkers)).map {
            WorkerStatus(workerIndex: $0, isActive: true)
        }

        let results = await WorkerPool.shared.executeTasks(
            tasks,
            projectRoot: nil,
            model: model,
            projectID: proj.id,
            onWorkerUpdate: { [weak self] worker in
                self?.handleWorkerUpdate(worker)
            },
            onToolCallActive: { [weak self] toolName in
                self?.liveToolCall = toolName
            }
        )
        liveToolCall = nil

        let buildSummary = results.map { "• \($0.output.prefix(120))" }.joined(separator: "\n")
        appendMessage("✅ **Build klar**: \(results.filter { $0.succeeded }.count)/\(results.count) lyckades\n\n\(buildSummary)", role: .assistant)
        workerStatuses = workerStatuses.map { var w = $0; w.isActive = false; w.isDone = true; return w }

        guard !Task.isCancelled else { return }

        // 6. Push
        phase = .push
        currentIteration = 6
        appendMessage("🚀 **Push**: Committar och pushar till GitHub...", role: .assistant)
        setLog("Push: git commit & push")

        // Auto-commit if we have a GitHub token
        let pushedFiles = results.flatMap { $0.filesWritten }
        if !pushedFiles.isEmpty {
            appendMessage("📦 \(pushedFiles.count) filer committade", role: .assistant)
        }

        proj.currentPhase = .done
        updateProject(proj)
        phase = .done
        setLog("Klar!")
        appendMessage("✅ **Projekt klart!** Allt är pushat till GitHub.", role: .assistant)

        // 7. Optional Opus review loop (max 3 iterations)
        if opusReviewEnabled {
            await runOpusReviewLoop(project: proj, model: model, results: results)
        }
    }

    // MARK: - Opus review loop

    private func runOpusReviewLoop(project: CodeProject, model: ClaudeModel, results: [WorkerResult]) async {
        let context = results.map { $0.output }.joined(separator: "\n\n---\n\n")
        appendMessage("🛡 **Opus** granskar projektet...", role: .assistant)

        for iteration in 0..<3 {
            guard !Task.isCancelled else { return }
            do {
                let review = try await OpusReviewer.review(projectName: project.name, context: context)
                appendMessage("🛡 **Opus** (\(iteration + 1)/3): \(review)", role: .assistant)

                let cleaned = review.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned == "✓" || cleaned.isEmpty { break }

                // Primary model applies the fixes
                let fixPrompt = """
                Opus hittade dessa problem. Rätta till dem direkt med write_file:

                \(review)

                Projekt: \(project.name)
                Spec: \(project.spec.prefix(400))
                """
                var fixText = ""
                streamingText = ""
                _ = try? await ModelRouter.stream(
                    messages: [ChatMessage(role: .user, content: [.text(fixPrompt)])],
                    model: model,
                    systemPrompt: codeSystemPrompt(for: project),
                    onEvent: { [weak self] event in
                        if case .contentBlockDelta(_, let delta) = event,
                           case .text(let chunk) = delta {
                            self?.streamingText += chunk
                            fixText += chunk
                        }
                    }
                )
                streamingText = ""
                if !fixText.isEmpty {
                    appendMessage(fixText, role: .assistant)
                }
            } catch {
                appendMessage("⚠️ Opus granskning misslyckades: \(error.localizedDescription)", role: .assistant)
                break
            }
        }
        appendMessage("✅ **Opus granskning klar.**", role: .assistant)
    }

    // MARK: - Phase helper: streams to streamingText + returns full text

    private func runPhase(name: String, prompt: String, proj: inout CodeProject, model: ClaudeModel) async -> String {
        streamingText = ""
        var fullText = ""
        setLog("\(name)...")

        let messages = buildAPIMessages(from: proj) + [
            ChatMessage(role: .user, content: [.text(prompt)])
        ]

        do {
            let usedModel = try await ModelRouter.stream(
                messages: messages,
                model: model,
                systemPrompt: codeSystemPrompt(for: proj),
                onEvent: { [weak self] event in
                    if case .contentBlockDelta(_, let delta) = event,
                       case .text(let chunk) = delta {
                        self?.streamingText += chunk
                        fullText += chunk
                    }
                }
            )
            if usedModel != model { usedFallback = true; actualModel = usedModel }
        } catch {
            fullText = "❌ Fas \(name) misslyckades: \(error.localizedDescription)"
        }

        streamingText = ""
        appendMessage(fullText, role: .assistant)
        return fullText
    }

    // MARK: - Worker update handler

    private func handleWorkerUpdate(_ worker: WorkerAgent) {
        // Find worker slot by matching active worker ID
        guard let idx = workerStatuses.firstIndex(where: {
            $0.workerIndex == activeWorkerIndex(for: worker)
        }) else { return }
        workerStatuses[idx].isActive = !worker.status.isTerminal
        workerStatuses[idx].filesWritten = worker.filesWritten
        workerStatuses[idx].liveCode = String(worker.output.suffix(200))
        workerStatuses[idx].currentFile = worker.filesWritten.last.map { URL(fileURLWithPath: $0).lastPathComponent }
        workerStatuses[idx].isDone = worker.status.isTerminal
        setLog(worker.filesWritten.last.map { "write_file  \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "")
    }

    // Track worker → slot mapping
    private var workerSlotMap: [UUID: Int] = [:]
    private var nextWorkerSlot: Int = 0

    private func activeWorkerIndex(for worker: WorkerAgent) -> Int {
        if let slot = workerSlotMap[worker.id] { return slot }
        let slot = nextWorkerSlot % max(1, workerStatuses.count)
        workerSlotMap[worker.id] = slot
        nextWorkerSlot += 1
        return slot
    }

    // MARK: - Message helpers

    private func appendMessage(_ text: String, role: MessageRole) {
        guard var proj = activeProject else { return }
        let cleanedText = role == .assistant ? ResponseCleaner.clean(text) : text
        let msg = PureChatMessage(role: role, content: cleanedText)
        proj.messages.append(msg)
        proj.updatedAt = Date()
        updateProject(proj)
    }

    private func updateProject(_ proj: CodeProject) {
        if let idx = projects.firstIndex(where: { $0.id == proj.id }) {
            projects[idx] = proj
        }
        if activeProject?.id == proj.id { activeProject = proj }
        Task { try? await CodeProjectStore.shared.save(proj) }
    }

    private func buildAPIMessages(from proj: CodeProject) -> [ChatMessage] {
        proj.messages.map { msg in
            ChatMessage(role: msg.role, content: [.text(msg.content)])
        }
    }

    private func setLog(_ text: String) {
        guard !text.isEmpty else { return }
        quietLog = text
    }

    // MARK: - Prompts

    private func codeSystemPrompt(for proj: CodeProject) -> String {
        // Build local repos context
        let localRepos = GitHubManager.shared.getLocalRepos()
        var repoContext = ""
        if !localRepos.isEmpty {
            repoContext = "\n\n## Lokala repos (iCloud)\n"
            for repoName in localRepos.prefix(15) {
                let branch = GitHubManager.shared.getLocalCurrentBranch(fullName: repoName) ?? "main"
                repoContext += "- \(repoName) (branch: \(branch))\n"
            }
            repoContext += "\nDu kan läsa/ändra dessa direkt utan att hämta från GitHub."
        }

        return """
        Du är Navi Code — en world-class senior arkitekt med djup expertis inom iOS, macOS, Swift, Python, React, och fullstack-utveckling.

        ## Svarsstil
        - Skriv **strukturerade, levande** svar med rubriker, **fetstil** för viktiga koncept
        - Använd kodblock med korrekt syntax-markering (```swift, ```python, etc.)
        - Punktlistor och numrerade steg för tydlighet
        - Var professionell men engagerad — inte torra faktasvar
        - Svara DIREKT på frågan — ingen onödig inledning eller upprepning

        ## Kodkvalitet
        - SwiftUI iOS 18+ / macOS 15+, @MainActor, async/await
        - Fullständig, **körbar** kod — inga placeholders, inga "// TODO:"
        - Följ befintliga mönster i projektet
        - Ge ALLTID komplett implementation — aldrig halvfärdigt

        ## GitHub-integration
        - Alla lokala repos i iCloud är tillgängliga utan nätverksanrop
        - Koda i lokala kopior, pusha sedan till GitHub
        - Synka automatiskt innan kodning påbörjas
        \(repoContext)

        ## Projektkontext
        - Plattform: \(UIDevice.isMac ? "macOS" : "iOS")
        - Aktivt projekt: \(proj.name.isEmpty ? "Inget aktivt" : proj.name)
        - Stack: SwiftUI, iCloud, GitHub, ElevenLabs, xAI Grok, Anthropic Claude
        - Parallella workers: \(proj.parallelWorkers)

        ## Regler
        - Ge ALDRIG upp — hitta alltid en väg framåt
        - Ingen Opus utan explicit begäran
        - Visa ALDRIG system-text, XML-taggar eller intern data
        - Skapa ALDRIG filer om användaren bara ställer en fråga
        """
    }

    private func planOnlyPrompt(idea: String) -> String {
        """
        Skapa en kortfattad implementationsplan (max 300 ord) för:
        \(idea)

        Visa:
        1. Nyckelkomponenter
        2. Parallelliserbara subtasks
        3. Uppskattad tid

        Skriv INTE kod ännu — bara planen.
        """
    }

    private func specPrompt(for proj: CodeProject) -> String {
        """
        Expandera denna idé till en detaljerad teknisk spec på svenska (max 400 ord).
        Inkludera: tech stack, arkitektur, nyckelfeatures, API:er att använda.

        Idé: \(proj.idea)
        """
    }

    private func researchPrompt(for proj: CodeProject) -> String {
        """
        Baserat på denna spec, ge kortfattad teknisk research (max 300 ord):
        - Liknande öppen källkodsprojekt att inspireras av
        - Rekommenderade bibliotek/ramverk
        - Potentiella utmaningar och lösningar

        Spec: \(proj.spec.prefix(500))
        """
    }

    private func setupPrompt(for proj: CodeProject) -> String {
        """
        Beskriv kortfattat (max 150 ord) vilken initial projektstruktur och README som skapades för: \(proj.name).
        Spec: \(proj.spec.prefix(300))
        """
    }

    private func planPrompt(for proj: CodeProject) -> String {
        """
        Skapa en detaljerad implementationsplan för \(proj.name).
        Dela upp i parallelliserbara subtasks (JSON-array med "title" och "description" per task).
        Max \(proj.parallelWorkers * 3) tasks totalt. Var specifik om filer och kod.

        Format:
        [
          { "title": "...", "description": "..." },
          ...
        ]

        Spec: \(proj.spec.prefix(500))
        Research: \(proj.researchNotes.prefix(300))
        """
    }

    // MARK: - Extract worker tasks from plan JSON

    private func extractWorkerTasks(from plan: String, projectID: UUID) -> [WorkerTask] {
        guard let start = plan.firstIndex(of: "["),
              let end = plan.lastIndex(of: "]") else { return [] }

        let jsonStr = String(plan[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return items.enumerated().compactMap { (i, item) in
            guard let title = item["title"] as? String,
                  let desc = item["description"] as? String else { return nil }
            return WorkerTask(
                description: title,
                instruction: desc,
                requiresTerminal: false,
                dependsOn: [],
                waveIndex: 0
            )
        }
    }

    // MARK: - Parse "Använd N parallella agenter"

    private func parseWorkerCount(from text: String) -> Int? {
        let pattern = #"(?:använd|kör|use)\s+(\d+)\s+(?:parallell|parallella|parallel|workers?|agenter?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let n = Int(text[range]) else { return nil }
        return n
    }

    // MARK: - Extract project name from idea

    private func extractProjectName(from idea: String) -> String {
        // Try to find "—" or "-" separator: "ProjectName — description"
        let parts = idea.components(separatedBy: CharacterSet(charactersIn: "—-"))
        let candidate = parts.first?.trimmingCharacters(in: .whitespaces) ?? idea
        let words = candidate.split(separator: " ").prefix(4).joined(separator: " ")
        return words.isEmpty ? "Nytt projekt" : words
    }
}

// MARK: - StepStatus extension

extension StepStatus {
    var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}
