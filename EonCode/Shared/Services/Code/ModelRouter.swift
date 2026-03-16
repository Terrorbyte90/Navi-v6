import Foundation

// MARK: - ModelRouter
// Provider-agnostic streaming. Routes to Anthropic, xAI, or OpenRouter.
// ALL providers now support native tool calling.
// Free OpenRouter models: linear fallback chain through all 9 free models.

@MainActor
final class ModelRouter {

    // MARK: - Free model fallback chain
    // When a free model is rate-limited or times out, the next model in the chain is tried.
    // .freeModels is the virtual UI entry point that starts from the first model in the chain.

    private static let freeModelChain: [ClaudeModel] = ClaudeModel.freeModelChain

    private static func isFreeModel(_ model: ClaudeModel) -> Bool {
        model == .freeModels || freeModelChain.contains(model)
    }

    /// Detects rate-limit errors from OpenRouter (429) or similar quota errors.
    private static func isRateLimitOrTimeoutError(_ error: Error) -> Bool {
        if let routerErr = error as? ModelRouterError {
            switch routerErr {
            case .qwenTimeout, .allFreeModelsRateLimited: return true
            case .noAPIKey: return false
            }
        }
        let nsError = error as NSError
        if nsError.code == 429 { return true }
        let desc = error.localizedDescription.lowercased()
        return desc.contains("rate limit") || desc.contains("429") ||
               desc.contains("too many") || desc.contains("quota") ||
               desc.contains("timeout") || desc.contains("overloaded")
    }

    // MARK: - Primary entry

    /// Stream a completion, routing to the correct provider.
    /// - `tools`: Supported by ALL providers (Anthropic native, xAI/OpenRouter via OpenAI function calling format).
    /// - Returns: The model that was actually used (may differ from `model` if fallback triggered).
    @discardableResult
    static func stream(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String? = nil,
        maxTokens: Int = Constants.Agent.maxTokensDefault,
        tools: [ClaudeTool]? = nil,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws -> ClaudeModel {

        // Validate API key before doing anything
        try validateAPIKey(for: model)

        // Free OpenRouter models: fallback chain through all 9 free models
        if isFreeModel(model) {
            let startModel = (model == .freeModels) ? freeModelChain[0] : model
            return try await streamWithFreeModelFallback(
                startModel: startModel,
                messages: messages,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                tools: tools,
                onEvent: onEvent
            )
        }

        // All other models: direct routing with tools
        try await routeStream(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            tools: tools,
            onEvent: onEvent
        )
        return model
    }

    // MARK: - API key validation

    private static func validateAPIKey(for model: ClaudeModel) throws {
        switch model.provider {
        case .anthropic:
            guard KeychainManager.shared.anthropicAPIKey?.isEmpty == false else {
                throw ModelRouterError.noAPIKey("Anthropic")
            }
        case .xai:
            guard KeychainManager.shared.xaiAPIKey?.isEmpty == false else {
                throw ModelRouterError.noAPIKey("xAI")
            }
        case .openRouter:
            guard KeychainManager.shared.openRouterAPIKey?.isEmpty == false else {
                throw ModelRouterError.noAPIKey("OpenRouter")
            }
        }
    }

    // MARK: - Free model circular fallback

    /// Tries each free model in a circular chain starting from `startModel`.
    /// On rate-limit (429), timeout, or quota error → rotates to next model seamlessly.
    /// Context carries over because `messages` is passed unchanged to each attempt.
    private static func streamWithFreeModelFallback(
        startModel: ClaudeModel,
        messages: [ChatMessage],
        systemPrompt: String?,
        maxTokens: Int,
        tools: [ClaudeTool]?,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws -> ClaudeModel {

        let startIndex = freeModelChain.firstIndex(of: startModel) ?? 0
        let count = freeModelChain.count

        for i in 0..<count {
            let modelIdx = (startIndex + i) % count
            let model = freeModelChain[modelIdx]

            // Emit switch notice for fallback attempts (not for the first try)
            if i > 0 {
                onEvent(.contentBlockDelta(
                    index: 0,
                    delta: .text("\n\n⚡ *Rate limit — byter till \(model.displayName)…*\n\n")
                ))
            }

            do {
                // Apply timeout for models that are often slow to start
                if model == .qwen3CoderFree || model == .gemini25Flash || model == .nvidianemotron {
                    try await streamWithTimeout(
                        model: model,
                        messages: messages,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        tools: tools,
                        timeout: 20,
                        onEvent: onEvent
                    )
                } else {
                    try await routeStream(
                        messages: messages,
                        model: model,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        tools: tools,
                        onEvent: onEvent
                    )
                }
                return model  // Success
            } catch {
                NaviLog.info("ModelRouter: \(model.displayName) failed (\(error.localizedDescription)) — trying next free model")
                if isRateLimitOrTimeoutError(error) {
                    continue  // Rotate to next free model
                }
                throw error  // Non-rate-limit error: propagate
            }
        }

        // All free models exhausted
        throw ModelRouterError.allFreeModelsRateLimited
    }

    /// Streams with a strict first-response timeout. Throws `ModelRouterError.qwenTimeout` if no response within `timeout` seconds.
    private static func streamWithTimeout(
        model: ClaudeModel,
        messages: [ChatMessage],
        systemPrompt: String?,
        maxTokens: Int,
        tools: [ClaudeTool]?,
        timeout: UInt64,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await routeStream(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt,
                    maxTokens: maxTokens,
                    tools: tools,
                    onEvent: onEvent
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                throw ModelRouterError.qwenTimeout
            }
            do {
                try await group.next()
                group.cancelAll()
            } catch is CancellationError {
                throw CancellationError()
            } catch ModelRouterError.qwenTimeout {
                group.cancelAll()
                throw ModelRouterError.qwenTimeout
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    // MARK: - Provider routing

    @discardableResult
    private static func routeStream(
        messages: [ChatMessage],
        model: ClaudeModel,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [ClaudeTool]?,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws -> ClaudeModel {
        switch model.provider {
        case .anthropic:
            try await ClaudeAPIClient.shared.streamMessage(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                tools: tools,
                maxTokens: maxTokens,
                usePromptCaching: false,
                onEvent: onEvent
            )
        case .xai:
            try await XAIClient.shared.streamChatCompletion(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                tools: tools,
                onEvent: onEvent
            )
        case .openRouter:
            try await OpenRouterClient.shared.streamChatCompletion(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                tools: tools,
                onEvent: onEvent
            )
        }
        return model
    }
}

// MARK: - ModelRouterError

enum ModelRouterError: LocalizedError {
    case qwenTimeout
    case noAPIKey(String)
    case allFreeModelsRateLimited

    var errorDescription: String? {
        switch self {
        case .qwenTimeout:
            return "Timeout (20s) — byter modell"
        case .noAPIKey(let provider):
            return "Ingen \(provider) API-nyckel. Gå till Inställningar."
        case .allFreeModelsRateLimited:
            return "Alla 9 gratismodeller är just nu rate-limitade. Vänta 1 minut och försök igen, eller välj en betald modell."
        }
    }
}
