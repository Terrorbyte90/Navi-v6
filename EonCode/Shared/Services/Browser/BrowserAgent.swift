import Foundation
import WebKit

// MARK: - Browser Status & Models

enum BrowserStatus: Equatable {
    case idle
    case planning
    case working(step: Int, of: Int)
    case waitingForUser
    case complete
    case failed
}

struct BrowserLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let displayText: String
    let isError: Bool
    let type: LogType

    enum LogType {
        case goal, subGoal, navigate, click, typeText, scroll, screenshot
        case vision, thinking, question, answer, success, failure, warning, retry, info, cost
    }

    init(_ text: String, type: LogType = .info, isError: Bool = false) {
        self.timestamp = Date()
        self.displayText = text
        self.type = type
        self.isError = isError
    }
}

struct BrowserSubGoal: Identifiable {
    let id = UUID()
    let description: String
    var status: SubGoalStatus = .pending
    var result: String?

    enum SubGoalStatus { case pending, active, completed, failed }
}

// MARK: - Session cost tracking

struct BrowserSessionCost {
    var totalInputTokens: Int = 0
    var totalOutputTokens: Int = 0
    var apiCalls: Int = 0
    var costUSD: Double = 0
    var costSEK: Double = 0

    mutating func add(usage: TokenUsage, model: ClaudeModel) {
        totalInputTokens += usage.inputTokens
        totalOutputTokens += usage.outputTokens
        apiCalls += 1
        let (usd, sek) = CostCalculator.shared.calculate(usage: usage, model: model)
        costUSD += usd
        costSEK += sek
    }

    var formatted: String {
        if costSEK < 0.01 { return "< 0.01 SEK" }
        return String(format: "%.2f SEK", costSEK)
    }

    var detail: String {
        "\(apiCalls) anrop · \(totalInputTokens + totalOutputTokens) tok · \(formatted)"
    }
}

// MARK: - BrowserAgent

@MainActor
final class BrowserAgent: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = BrowserAgent()

    // Published state
    @Published var status: BrowserStatus = .idle
    @Published var currentURL: URL?
    @Published var log: [BrowserLogEntry] = []
    @Published var pageTitle: String = ""
    @Published var userQuestion: String = ""
    @Published var loadingProgress: Double = 0
    @Published var currentGoal: String = ""
    @Published var subGoals: [BrowserSubGoal] = []
    @Published var currentThought: String = ""
    @Published var sessionCost = BrowserSessionCost()
    @Published var canTakeControl: Bool = false

    // WebView
    let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        config.mediaTypesRequiringUserActionForPlayback = .all

        let wv = WKWebView(frame: .zero, configuration: config)
        #if os(macOS)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        #else
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        #endif
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }()

    // Private state
    private let api = ClaudeAPIClient.shared
    private var userInputContinuation: CheckedContinuation<String, Never>?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var navigationID: UUID?
    private var progressObservation: NSKeyValueObservation?
    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var currentExecutionTask: Task<Void, Never>?
    private var strategy: BrowsingStrategy = .domFirst
    private var consecutiveVisionFallbacks: Int = 0

    enum BrowsingStrategy { case domFirst, visionFirst }

    private override init() {
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        setupObservers()
    }

    // MARK: - KVO Observers

    private func setupObservers() {
        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.loadingProgress = wv.estimatedProgress }
        }
        titleObservation = webView.observe(\.title, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.pageTitle = wv.title ?? "" }
        }
        urlObservation = webView.observe(\.url, options: .new) { [weak self] wv, _ in
            Task { @MainActor [weak self] in self?.currentURL = wv.url }
        }
    }

    // MARK: - Main execute

    func execute(goal: String) async {
        guard status == .idle || status == .complete || status == .failed else { return }

        currentExecutionTask?.cancel()

        status = .planning
        currentGoal = goal
        sessionCost = BrowserSessionCost()
        log = [BrowserLogEntry("Mål: \(goal)", type: .goal)]
        subGoals = []
        currentThought = "Analyserar mål…"
        strategy = .domFirst
        consecutiveVisionFallbacks = 0
        canTakeControl = true

        // Decompose
        let decomposed = await decomposeGoal(goal)
        if decomposed.count > 1 {
            subGoals = decomposed
            appendLog("Uppdelat i \(decomposed.count) delmål", type: .thinking)
            for (i, sg) in decomposed.enumerated() {
                appendLog("  \(i + 1). \(sg.description)", type: .subGoal)
            }
        }

        // Execute
        let goalsToExecute = subGoals.isEmpty ? [BrowserSubGoal(description: goal)] : subGoals

        for (goalIdx, _) in goalsToExecute.enumerated() {
            guard !Task.isCancelled else { break }

            if !subGoals.isEmpty {
                subGoals[goalIdx].status = .active
                appendLog("Delmål \(goalIdx + 1): \(goalsToExecute[goalIdx].description)", type: .subGoal)
            }

            currentThought = goalsToExecute[goalIdx].description
            let success = await executeSubGoal(
                goalsToExecute[goalIdx].description,
                fullGoal: goal,
                stepOffset: goalIdx
            )

            if !subGoals.isEmpty {
                subGoals[goalIdx].status = success ? .completed : .failed
                subGoals[goalIdx].result = success ? "Klart" : "Misslyckades"
            }

            if !success && strategy == .domFirst {
                appendLog("Byter till vision-strategi…", type: .retry)
                strategy = .visionFirst
                let _ = await executeSubGoal(
                    goalsToExecute[goalIdx].description,
                    fullGoal: goal,
                    stepOffset: goalIdx
                )
                strategy = .domFirst
            }
        }

        // Final status
        if status != .idle {
            let allDone = subGoals.isEmpty || subGoals.allSatisfy { $0.status == .completed }
            if allDone {
                status = .complete
                currentThought = "Klart!"
            } else if subGoals.contains(where: { $0.status == .completed }) {
                status = .complete
                currentThought = "Delvis klart"
            } else {
                status = .failed
                currentThought = "Misslyckades"
            }
            appendLog("Session: \(sessionCost.detail)", type: .cost)
        }
        canTakeControl = false
    }

    // MARK: - Goal decomposition

    private func decomposeGoal(_ goal: String) async -> [BrowserSubGoal] {
        let wordCount = goal.split(separator: " ").count
        guard wordCount > 5 else { return [] }

        do {
            let prompt = """
            Analysera detta webbmål och avgör om det behöver delmål.
            Mål: \(goal)
            Om enkelt, svara: SIMPLE
            Om komplext, svara med numrerad lista (2-5 steg). Bara stegen, inget annat.
            """
            let (response, usage) = try await api.sendMessage(
                messages: [ChatMessage(role: .user, content: [.text(prompt)])],
                model: .haiku,
                systemPrompt: "Du bryter ner webbmål i steg. Svara koncist.",
                maxTokens: 200
            )
            sessionCost.add(usage: usage, model: .haiku)

            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().contains("SIMPLE") { return [] }

            var goals: [BrowserSubGoal] = []
            for line in trimmed.components(separatedBy: .newlines) {
                let cleaned = line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "^\\d+\\.?\\s*", with: "", options: .regularExpression)
                if !cleaned.isEmpty { goals.append(BrowserSubGoal(description: cleaned)) }
            }
            return goals.count >= 2 ? goals : []
        } catch {
            return []
        }
    }

    // MARK: - Execute sub-goal

    private func executeSubGoal(_ subGoalText: String, fullGoal: String, stepOffset: Int) async -> Bool {
        var attempt = 0
        let maxAttempts = 30
        var extractionFailStreak = 0
        var actionFailStreak = 0

        while attempt < maxAttempts {
            attempt += 1
            status = .working(step: attempt, of: maxAttempts)
            guard !Task.isCancelled else {
                status = .idle
                return false
            }

            if strategy == .visionFirst || consecutiveVisionFallbacks >= 2 {
                return await executeVisionStrategy(subGoalText: subGoalText, fullGoal: fullGoal, maxAttempts: maxAttempts - attempt)
            }

            // 1. Extract
            let pageContent: PageContent
            do {
                currentThought = "Läser sidan…"
                pageContent = try await withTimeout(seconds: 10) {
                    try await PageExtractor.extract(from: self.webView)
                }
                extractionFailStreak = 0
            } catch {
                extractionFailStreak += 1
                appendLog("Extraktion misslyckades (\(extractionFailStreak)/3)", type: .warning, isError: true)
                if extractionFailStreak >= 3 {
                    consecutiveVisionFallbacks += 1
                    return await executeVisionStrategy(subGoalText: subGoalText, fullGoal: fullGoal, maxAttempts: maxAttempts - attempt)
                }
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            // 2. Dismiss popups
            let dismissed = await handlePopupsAndOverlays()
            if dismissed {
                appendLog("Stängde popup/overlay", type: .click)
                try? await Task.sleep(for: .seconds(0.5))
                continue
            }

            // 3. Decide
            let action: BrowserAction
            do {
                currentThought = "Tänker…"
                let result = try await BrowserActionDecider.decide(
                    goal: fullGoal, subGoal: subGoalText, pageContent: pageContent,
                    history: log.suffix(15), strategy: .domFirst, apiClient: api
                )
                action = result.action
                sessionCost.add(usage: result.usage, model: .haiku)
            } catch {
                actionFailStreak += 1
                appendLog("Beslutsfel (\(actionFailStreak)/3)", type: .warning, isError: true)
                if actionFailStreak >= 3 { return false }
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            actionFailStreak = 0

            // 4. Execute
            currentThought = action.shortDescription
            appendLog(action.logDescription, type: action.logType)

            do {
                let shouldContinue = try await executeAction(action, pageContent: pageContent, goal: fullGoal, subGoal: subGoalText)
                consecutiveVisionFallbacks = 0
                if !shouldContinue { return true }
            } catch {
                appendLog("Fel: \(error.localizedDescription)", type: .failure, isError: true)
                actionFailStreak += 1
                if actionFailStreak > 5 { return false }
            }

            if case .working = status {
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        return false
    }

    // MARK: - Vision strategy (fallback)

    private func executeVisionStrategy(subGoalText: String, fullGoal: String, maxAttempts: Int) async -> Bool {
        appendLog("Vision-strategi aktiv", type: .vision)

        for attempt in 0..<min(maxAttempts, 15) {
            guard !Task.isCancelled else { return false }
            status = .working(step: attempt + 1, of: min(maxAttempts, 15))

            do {
                currentThought = "Tar skärmbild…"
                let screenshotData = try await ScreenshotAnalyzer.takeScreenshot(from: webView)
                let basicDOM = try? await PageExtractor.extract(from: webView)

                currentThought = "Analyserar med vision…"
                let result = try await BrowserActionDecider.decideWithVision(
                    goal: fullGoal, subGoal: subGoalText, screenshotData: screenshotData,
                    basicDOM: basicDOM, history: log.suffix(10), apiClient: api
                )
                sessionCost.add(usage: result.usage, model: .sonnet45)

                currentThought = result.action.shortDescription
                appendLog(result.action.logDescription, type: result.action.logType)

                let shouldContinue = try await executeAction(result.action, pageContent: basicDOM, goal: fullGoal, subGoal: subGoalText)
                if !shouldContinue { return true }
            } catch {
                appendLog("Vision-fel: \(error.localizedDescription)", type: .failure, isError: true)
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    // MARK: - Execute action

    private func executeAction(
        _ action: BrowserAction, pageContent: PageContent?,
        goal: String, subGoal: String
    ) async throws -> Bool {
        switch action {
        case .navigate(let url):
            try await navigate(to: url)
            try? await Task.sleep(for: .seconds(1))
        case .click(let selector):
            if let idx = linkIndex(from: selector), let links = pageContent?.links, idx < links.count {
                try await navigate(to: links[idx].href)
            } else {
                try await PageExtractor.clickElement(selector: selector, in: webView)
                try? await Task.sleep(for: .seconds(1))
            }
        case .type(let selector, let text):
            try await PageExtractor.typeInField(selector: selector, text: text, in: webView)
        case .submitForm(let selector):
            try await PageExtractor.submitForm(selector: selector, in: webView)
            try? await Task.sleep(for: .seconds(1.5))
        case .scroll(let direction):
            try await PageExtractor.scroll(direction, in: webView)
            try? await Task.sleep(for: .seconds(0.5))
        case .screenshot:
            let data = try await ScreenshotAnalyzer.takeScreenshot(from: webView)
            let analysis = try await ScreenshotAnalyzer.analyze(
                screenshotData: data, goal: goal,
                context: log.suffix(5).map(\.displayText).joined(separator: "\n"), apiClient: api
            )
            appendLog("Vision: \(analysis)", type: .vision)
        case .waitForLoad:
            currentThought = "Väntar…"
            try? await Task.sleep(for: .seconds(2))
        case .askUser(let question):
            status = .waitingForUser
            userQuestion = question
            currentThought = "Väntar på svar…"
            appendLog("Frågar: \(question)", type: .question)
            let answer = await waitForUserInput()
            if answer.isEmpty { status = .idle; return false }
            appendLog("Svar: \(answer)", type: .answer)
            status = .working(step: 0, of: 30)
        case .goBack:
            if webView.canGoBack { webView.goBack(); try? await Task.sleep(for: .seconds(1.5)) }
        case .goalComplete(let summary):
            appendLog("Klart: \(summary)", type: .success)
            return false
        case .goalFailed(let reason):
            appendLog("Misslyckades: \(reason)", type: .failure, isError: true)
            return false
        }
        return true
    }

    // MARK: - Popup handling

    private func handlePopupsAndOverlays() async -> Bool {
        (try? await PageExtractor.detectAndDismissOverlays(in: webView)) ?? false
    }

    // MARK: - Navigation

    func navigate(to urlString: String) async throws {
        let urlStr = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
        guard let url = URL(string: urlStr) else { throw BrowserError.navigationFailed(urlString) }

        navigationContinuation?.resume(throwing: BrowserError.navigationFailed("Cancelled"))
        navigationContinuation = nil
        let navID = UUID()
        navigationID = navID

        try await withTimeout(seconds: 30) {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                guard self.navigationID == navID else {
                    cont.resume(throwing: BrowserError.navigationFailed("Superseded"))
                    return
                }
                self.navigationContinuation = cont
                self.webView.load(URLRequest(url: url))
            }
        }
    }

    // MARK: - User input

    func provideUserInput(_ input: String) {
        userInputContinuation?.resume(returning: input)
        userInputContinuation = nil
        userQuestion = ""
    }

    private func waitForUserInput() async -> String {
        await withCheckedContinuation { cont in userInputContinuation = cont }
    }

    func updateGoal(_ newGoal: String) {
        currentGoal = newGoal
        appendLog("Mål uppdaterat: \(newGoal)", type: .goal)
    }

    // MARK: - Cancel

    func cancel() {
        webView.stopLoading()
        currentExecutionTask?.cancel()
        currentExecutionTask = nil
        status = .idle
        currentGoal = ""
        currentThought = ""
        canTakeControl = false
        userInputContinuation?.resume(returning: "")
        userInputContinuation = nil
        navigationContinuation?.resume(throwing: BrowserError.navigationFailed("Cancelled"))
        navigationContinuation = nil
        navigationID = nil
        userQuestion = ""
    }

    // MARK: - Helpers

    func appendLog(_ text: String, type: BrowserLogEntry.LogType = .info, isError: Bool = false) {
        log.append(BrowserLogEntry(text, type: type, isError: isError))
        if log.count > 500 { log = Array(log.suffix(400)) }
    }

    private func linkIndex(from selector: String) -> Int? {
        guard selector.hasPrefix("["), selector.hasSuffix("]") else { return nil }
        return Int(selector.dropFirst().dropLast())
    }

    func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: .seconds(seconds)); throw BrowserError.extractionFailed }
            guard let result = try await group.next() else { throw BrowserError.extractionFailed }
            group.cancelAll()
            return result
        }
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard self.navigationContinuation != nil else { return }
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
            self.navigationID = nil
            self.currentURL = webView.url
            self.pageTitle = webView.title ?? ""
            self.loadingProgress = 1.0
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            if (error as NSError).code == NSURLErrorCancelled { return }
            guard self.navigationContinuation != nil else { return }
            self.navigationContinuation?.resume(throwing: error)
            self.navigationContinuation = nil
            self.navigationID = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            if (error as NSError).code == NSURLErrorCancelled { return }
            guard self.navigationContinuation != nil else { return }
            self.navigationContinuation?.resume(throwing: error)
            self.navigationContinuation = nil
            self.navigationID = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in self.loadingProgress = 0.1 }
    }

    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            Task { @MainActor in webView.load(navigationAction.request) }
        }
        return nil
    }

    nonisolated func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.appendLog("JS Alert: \(message.prefix(200))", type: .info) }
        completionHandler()
    }

    nonisolated func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in self.appendLog("JS Confirm (auto-OK): \(message.prefix(200))", type: .info) }
        completionHandler(true)
    }
}
