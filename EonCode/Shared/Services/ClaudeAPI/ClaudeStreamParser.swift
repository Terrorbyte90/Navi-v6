import Foundation

final class ClaudeStreamParser {
    private var buffer = ""
    private var inputTokensFromStart: Int = 0
    private var cacheCreationTokens: Int? = nil
    private var cacheReadTokens: Int? = nil

    func parse(line: String) -> StreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty { return nil }

        if trimmed.hasPrefix("data: ") {
            let json = String(trimmed.dropFirst(6))
            if json == "[DONE]" { return .messageStop }
            return parseData(json)
        }

        if trimmed.hasPrefix("event: ") {
            // event type is carried in data JSON
            return nil
        }

        return nil
    }

    private func parseData(_ json: String) -> StreamEvent? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let type = obj["type"] as? String ?? ""

        switch type {
        case "message_start":
            let msg = obj["message"] as? [String: Any]
            let id = msg?["id"] as? String ?? ""
            let model = msg?["model"] as? String ?? ""
            // Capture input tokens from message_start usage
            if let usage = msg?["usage"] as? [String: Any] {
                inputTokensFromStart = usage["input_tokens"] as? Int ?? 0
                cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int
                cacheReadTokens = usage["cache_read_input_tokens"] as? Int
            }
            return .messageStart(id: id, model: model)

        case "content_block_start":
            let index = obj["index"] as? Int ?? 0
            let block = obj["content_block"] as? [String: Any]
            let blockType = block?["type"] as? String ?? "text"
            let blockID = block?["id"] as? String
            let blockName = block?["name"] as? String
            return .contentBlockStart(index: index, type: blockType, id: blockID, name: blockName)

        case "content_block_delta":
            let index = obj["index"] as? Int ?? 0
            let delta = obj["delta"] as? [String: Any]
            let deltaType = delta?["type"] as? String ?? ""
            if deltaType == "text_delta" {
                let text = delta?["text"] as? String ?? ""
                return .contentBlockDelta(index: index, delta: .text(text))
            } else if deltaType == "input_json_delta" {
                let partial = delta?["partial_json"] as? String ?? ""
                return .contentBlockDelta(index: index, delta: .inputJSON(partial))
            }
            return nil

        case "content_block_stop":
            let index = obj["index"] as? Int ?? 0
            return .contentBlockStop(index: index)

        case "message_delta":
            let delta = obj["delta"] as? [String: Any]
            let stopReason = delta?["stop_reason"] as? String
            let usageObj = obj["usage"] as? [String: Any]
            var usage: TokenUsage? = nil
            if let usageObj = usageObj {
                let output = usageObj["output_tokens"] as? Int ?? 0
                usage = TokenUsage(
                    inputTokens: inputTokensFromStart,
                    outputTokens: output,
                    cacheCreationInputTokens: cacheCreationTokens,
                    cacheReadInputTokens: cacheReadTokens
                )
            }
            return .messageDelta(stopReason: stopReason, usage: usage)

        case "message_stop":
            return .messageStop

        case "ping":
            return .ping

        case "error":
            let error = obj["error"] as? [String: Any]
            let msg = error?["message"] as? String ?? "Unknown streaming error"
            return .error(msg)

        default:
            return nil
        }
    }
}
