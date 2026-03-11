import Foundation

// MARK: - ModelRouter
// Provider-agnostic streaming. Routes to Anthropic, xAI, or OpenRouter.
// Special behaviour for Qwen3-Coder: 15s timeout → auto-fallback to MiniMax M2.5.
// Tools are Anthropic-only — non-Anthropic models fall back to .sonnet46 when tools are provided.

@MainActor
final class ModelRouter {

    // MARK: - Primary entry

    /// Stream a completion, routing to the correct provider.
    /// - `tools`: Anthropic-only. Non-Anthropic models auto-fall-back to `.sonnet46` when tools are provided.
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

        // Tools: Anthropic supports native tool use.
        // xAI/OpenRouter: fall back to Anthropic Sonnet only for tool calls.
        // Exception: Qwen and MiniMax do NOT get fallback — they just run without tools.
        if let tools, !tools.isEmpty, model.provider != .anthropic {
            // For xAI models, fall back to Anthropic for tool use
            if model.provider == .xai {
                try validateAPIKey(for: .sonnet46)
                try await ClaudeAPIClient.shared.streamMessage(
                    messages: messages,
                    model: .sonnet46,
                    systemPrompt: systemPrompt,
                    tools: tools,
                    maxTokens: maxTokens,
                    usePromptCaching: false,
                    onEvent: onEvent
                )
                return .sonnet46
            }
            // OpenRouter models: run without tools (they handle instructions inline)
            try await routeStream(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                tools: nil,
                onEvent: onEvent
            )
            return model
        }

        // Qwen3-Coder: 15-second timeout + fallback to MiniMax M2.5
        if model == .qwen3CoderFree {
            return try await streamWithQwenFallback(
                messages: messages,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                onEvent: onEvent
            )
        }

        // All other models: direct routing, no timeout
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

    // MARK: - Qwen fallback

    private static func streamWithQwenFallback(
        messages: [ChatMessage],
        systemPrompt: String?,
        maxTokens: Int,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws -> ClaudeModel {

        // Try Qwen with 15-second timeout
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    try await routeStream(
                        messages: messages,
                        model: .qwen3CoderFree,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        tools: nil,
                        onEvent: onEvent
                    )
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                    throw ModelRouterError.qwenTimeout
                }

                // Wait for first task to complete
                do {
                    try await group.next()
                    group.cancelAll()
                } catch is CancellationError {
                    throw CancellationError()
                } catch ModelRouterError.qwenTimeout {
                    group.cancelAll()
                    throw ModelRouterError.qwenTimeout
                } catch {
                    // Qwen failed with a real error — propagate, don't timeout
                    group.cancelAll()
                    throw error
                }
            }
            return .qwen3CoderFree
        } catch ModelRouterError.qwenTimeout {
            // Emit fallback notice
            onEvent(.contentBlockDelta(
                index: 0,
                delta: .text("\n\n⚡ *Qwen3-Coder timeout — testar MiniMax M2.5*\n\n")
            ))

            // Try MiniMax M2.5
            do {
                try await routeStream(
                    messages: messages,
                    model: .minimaxM25,
                    systemPrompt: systemPrompt,
                    maxTokens: maxTokens,
                    tools: nil,
                    onEvent: onEvent
                )
                return .minimaxM25
            } catch {
                // MiniMax failed — try Sonnet as final fallback
                onEvent(.contentBlockDelta(
                    index: 0,
                    delta: .text("\n\n⚡ *MiniMax misslyckades — byter till Sonnet*\n\n")
                ))

                try validateAPIKey(for: .sonnet45)
                try await routeStream(
                    messages: messages,
                    model: .sonnet45,
                    systemPrompt: systemPrompt,
                    maxTokens: maxTokens,
                    tools: nil,
                    onEvent: onEvent
                )
                return .sonnet45
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
                onEvent: onEvent
            )
        case .openRouter:
            try await OpenRouterClient.shared.streamChatCompletion(
                messages: messages,
                model: model,
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
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

    var errorDescription: String? {
        switch self {
        case .qwenTimeout:
            return "Qwen3-Coder timeout (15s) — byter till MiniMax M2.5"
        case .noAPIKey(let provider):
            return "Ingen \(provider) API-nyckel. Gå till Inställningar."
        }
    }
}
