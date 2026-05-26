import Foundation

public final class SSEDecoder: @unchecked Sendable {
    private var buffer = ""

    public init() {}

    public func decode(_ chunk: Data) -> [SSEEvent] {
        guard let text = String(data: chunk, encoding: .utf8) else { return [] }
        buffer += text

        var events: [SSEEvent] = []
        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            if let event = parseBlock(block) {
                events.append(event)
            }
        }
        return events
    }

    private func parseBlock(_ block: String) -> SSEEvent? {
        var eventType: String?
        var dataLines: [String] = []

        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("event: ") {
                eventType = String(s.dropFirst(7))
            } else if s.hasPrefix("data: ") {
                dataLines.append(String(s.dropFirst(6)))
            } else if s == "data:" {
                dataLines.append("")
            }
        }

        guard !dataLines.isEmpty else { return nil }
        let data = dataLines.joined(separator: "\n")
        if data == "[DONE]" { return SSEEvent(type: eventType ?? "done", data: data) }
        return SSEEvent(type: eventType ?? "message", data: data)
    }

    public func reset() {
        buffer = ""
    }
}

public struct SSEEvent: Sendable {
    public let type: String
    public let data: String

    public var jsonData: Data? { data.data(using: .utf8) }
}

// MARK: - Anthropic Event Parsing

public enum AnthropicEventParser {
    public static func parse(event: SSEEvent) -> LLMEvent? {
        guard let jsonData = event.jsonData else { return nil }

        switch event.type {
        case "message_start":
            return parseMessageStart(jsonData)
        case "content_block_start":
            return parseContentBlockStart(jsonData)
        case "content_block_delta":
            return parseContentBlockDelta(jsonData)
        case "content_block_stop":
            return nil
        case "message_delta":
            return parseMessageDelta(jsonData)
        case "message_stop":
            return nil
        case "ping":
            return nil
        case "error":
            return parseError(jsonData)
        default:
            return nil
        }
    }

    private static func parseMessageStart(_ data: Data) -> LLMEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let id = message["id"] as? String,
              let model = message["model"] as? String else { return nil }

        let event = LLMEvent.messageStart(MessageMeta(id: id, model: model))

        if let usageDict = message["usage"] as? [String: Any] {
            let usage = parseUsage(usageDict)
            return event // usage comes in message_delta at end
        }
        return event
    }

    private static func parseContentBlockStart(_ data: Data) -> LLMEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let block = json["content_block"] as? [String: Any],
              let type = block["type"] as? String else { return nil }

        if type == "tool_use" {
            let id = block["id"] as? String ?? ""
            let name = block["name"] as? String ?? ""
            return .toolUseStart(ToolUseMeta(id: id, name: name))
        }
        return nil
    }

    private static func parseContentBlockDelta(_ data: Data) -> LLMEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delta = json["delta"] as? [String: Any],
              let type = delta["type"] as? String else { return nil }

        switch type {
        case "text_delta":
            if let text = delta["text"] as? String {
                return .textDelta(text)
            }
        case "input_json_delta":
            if let partial = delta["partial_json"] as? String {
                return .toolUseInputDelta(partial)
            }
        default:
            break
        }
        return nil
    }

    private static func parseMessageDelta(_ data: Data) -> LLMEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let usageDict = json["usage"] as? [String: Any] {
            let usage = parseUsage(usageDict)
            if usage.outputTokens > 0 || usage.inputTokens > 0 {
                return .usage(usage)
            }
        }

        if let delta = json["delta"] as? [String: Any],
           let stopStr = delta["stop_reason"] as? String {
            let reason = StopReason(rawValue: stopStr) ?? .endTurn
            return .messageStop(reason)
        }
        return nil
    }

    private static func parseError(_ data: Data) -> LLMEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        let message = error["message"] as? String ?? "Unknown provider error"
        let type = error["type"] as? String ?? "api_error"
        return .error(ProviderError(
            code: "provider.api_error",
            description: "\(type): \(message)",
            remediation: "Check the Anthropic API status page"
        ))
    }

    static func parseUsage(_ dict: [String: Any]) -> TokenUsage {
        TokenUsage(
            inputTokens: dict["input_tokens"] as? Int ?? 0,
            outputTokens: dict["output_tokens"] as? Int ?? 0,
            cacheReadTokens: dict["cache_read_input_tokens"] as? Int ?? 0,
            cacheWriteTokens: dict["cache_creation_input_tokens"] as? Int ?? 0
        )
    }
}

// MARK: - OpenAI/OpenRouter Event Parsing

public enum OpenAIEventParser {
    public static func parse(event: SSEEvent) -> LLMEvent? {
        if event.data == "[DONE]" { return nil }
        guard let jsonData = event.jsonData,
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }

        if let id = json["id"] as? String, let model = json["model"] as? String {
            if let choices = json["choices"] as? [[String: Any]], let choice = choices.first {
                if let delta = choice["delta"] as? [String: Any] {
                    if let content = delta["content"] as? String {
                        return .textDelta(content)
                    }
                    if let toolCalls = delta["tool_calls"] as? [[String: Any]],
                       let tc = toolCalls.first {
                        if let function = tc["function"] as? [String: Any] {
                            if let name = function["name"] as? String {
                                let tcId = tc["id"] as? String ?? ""
                                return .toolUseStart(ToolUseMeta(id: tcId, name: name))
                            }
                            if let args = function["arguments"] as? String, !args.isEmpty {
                                return .toolUseInputDelta(args)
                            }
                        }
                    }
                }
                if let finishReason = choice["finish_reason"] as? String, finishReason != "" {
                    let reason: StopReason
                    switch finishReason {
                    case "stop": reason = .endTurn
                    case "tool_calls": reason = .toolUse
                    case "length": reason = .maxTokens
                    default: reason = .endTurn
                    }
                    return .messageStop(reason)
                }
            }

            if let usage = json["usage"] as? [String: Any] {
                return .usage(TokenUsage(
                    inputTokens: usage["prompt_tokens"] as? Int ?? 0,
                    outputTokens: usage["completion_tokens"] as? Int ?? 0
                ))
            }
        }

        return nil
    }
}
