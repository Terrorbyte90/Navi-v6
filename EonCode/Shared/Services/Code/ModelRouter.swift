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

        // Tools are Anthropic-only — fall back to sonnet46 for non-Anthropic models with tools
        if let tools, !tools.isEmpty, model.provider != .anthropic {
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

    // MARK: - Qwen fallback

    private static func streamWithQwenFallback(
        messages: [ChatMessage],
        systemPrompt: String?,
        maxTokens: Int,
        onEvent: @escaping (StreamEvent) -> Void
    ) async throws -> ClaudeModel {

        // Race: Qwen stream vs 15-second timer
        let timeoutSeconds: UInt64 = 15

        return try await withThrowingTaskGroup(of: ClaudeModel.self) { group in
            // Task 1: Qwen streaming
            group.addTask {
                try await routeStream(
                    messages: messages,
                    model: .qwen3CoderFree,
                    systemPrompt: systemPrompt,
                    maxTokens: maxTokens,
                    tools: nil,
                    onEvent: onEvent
                )
                return .qwen3CoderFree
            }

            // Task 2: Timeout sentinel (throws after 15s)
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw ModelRouterError.qwenTimeout
            }

            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch ModelRouterError.qwenTimeout {
                group.cancelAll()

                // Emit fallback notice so UI can display it
                onEvent(.contentBlockDelta(
                    index: 0,
                    delta: .text("\n\n⚡ *Qwen3-Coder timeout (15s) — trying MiniMax M2.5*\n\n")
                ))

                // Try MiniMax M2.5
                do {
                    let result = try await routeStream(
                        messages: messages,
                        model: .minimaxM25,
                        systemPrompt: systemPrompt,
                        maxTokens: maxTokens,
                        tools: nil,
                        onEvent: onEvent
                    )
                    return result
                } catch {
                    // MiniMax also failed - try Sonnet as final fallback
                    onEvent(.contentBlockDelta(
                        index: 0,
                        delta: .text("\n\n⚡ *MiniMax failed — trying Claude Sonnet*\n\n")
                    ))
                    
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

    var errorDescription: String? {
        switch self {
        case .qwenTimeout:
            return "Qwen3-Coder timeout (15s) — byter till MiniMax M2.5"
        }
    }
}
