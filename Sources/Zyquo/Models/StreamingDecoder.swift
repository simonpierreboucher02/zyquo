import Foundation
import os

public final class SSEDecoder: @unchecked Sendable {
    private var eventType: String?
    private var dataLines: [String] = []

    public init() {}

    /// Feed a single line from the SSE stream. Returns events when a blank line
    /// (event boundary) is encountered. Use with `bytes.lines`.
    public func feedLine(_ line: String) -> [SSEEvent] {
        // SSE spec: blank line = end of event
        if line.isEmpty {
            return flushEvent()
        }

        // SSE comment (keep-alive)
        if line.hasPrefix(":") {
            return []
        }

        if line.hasPrefix("event: ") {
            eventType = String(line.dropFirst(7))
        } else if line.hasPrefix("data: ") {
            dataLines.append(String(line.dropFirst(6)))
        } else if line == "data:" {
            dataLines.append("")
        }

        return []
    }

    private func flushEvent() -> [SSEEvent] {
        guard !dataLines.isEmpty else {
            eventType = nil
            return []
        }

        let data = dataLines.joined(separator: "\n")
        let type: String
        if data == "[DONE]" {
            type = eventType ?? "done"
        } else {
            type = eventType ?? "message"
        }

        let event = SSEEvent(type: type, data: data)

        eventType = nil
        dataLines.removeAll()

        return [event]
    }

    /// Decode raw Data chunk (byte-by-byte safe). Buffers bytes until valid
    /// UTF-8 is available, then buffers text until complete lines are formed.
    private var rawBuffer = Data()
    private var lineBuffer = ""

    public func decode(_ chunk: Data) -> [SSEEvent] {
        rawBuffer.append(chunk)

        guard let text = String(data: rawBuffer, encoding: .utf8) else {
            if rawBuffer.count > 16384 { rawBuffer.removeAll() }
            return []
        }
        rawBuffer.removeAll()

        lineBuffer += text

        var events: [SSEEvent] = []

        while let nlRange = lineBuffer.range(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<nlRange.lowerBound])
            lineBuffer = String(lineBuffer[nlRange.upperBound...])
            events.append(contentsOf: feedLine(line))
        }

        return events
    }

    public func reset() {
        eventType = nil
        dataLines.removeAll()
        rawBuffer.removeAll()
        lineBuffer = ""
    }
}

public struct SSEEvent: Sendable {
    public let type: String
    public let data: String

    public var jsonData: Data? { data.data(using: .utf8) }
}

// MARK: - Anthropic Event Parsing

public enum AnthropicEventParser {

    /// Track whether the current content block is a tool_use (vs text/thinking).
    private static let _currentBlockIsToolUse = OSAllocatedUnfairLock(initialState: false)

    /// Parse an SSE event, returning zero or more LLMEvents.
    /// A single SSE event (e.g. message_delta) may produce both usage and stop events.
    public static func parseAll(event: SSEEvent) -> [LLMEvent] {
        guard let jsonData = event.jsonData else { return [] }

        switch event.type {
        case "message_start":
            return parseMessageStartAll(jsonData)
        case "content_block_start":
            if let e = parseContentBlockStart(jsonData) { return [e] }
            return []
        case "content_block_delta":
            if let e = parseContentBlockDelta(jsonData) { return [e] }
            return []
        case "content_block_stop":
            return parseContentBlockStop(jsonData)
        case "message_delta":
            return parseMessageDeltaAll(jsonData)
        case "message_stop":
            return []
        case "ping":
            return []
        case "error":
            if let e = parseError(jsonData) { return [e] }
            return []
        default:
            return []
        }
    }

    /// Legacy single-event parse (kept for backward compatibility).
    public static func parse(event: SSEEvent) -> LLMEvent? {
        parseAll(event: event).first
    }

    // MARK: - message_start

    private static func parseMessageStartAll(_ data: Data) -> [LLMEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let id = message["id"] as? String,
              let model = message["model"] as? String else { return [] }

        var events: [LLMEvent] = [.messageStart(MessageMeta(id: id, model: model))]

        if let usageDict = message["usage"] as? [String: Any] {
            let usage = parseUsage(usageDict)
            if usage.inputTokens > 0 || usage.cacheReadTokens > 0 || usage.cacheWriteTokens > 0 {
                events.append(.usage(usage))
            }
        }
        return events
    }

    // MARK: - content_block_start

    private static func parseContentBlockStart(_ data: Data) -> LLMEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let block = json["content_block"] as? [String: Any],
              let type = block["type"] as? String else {
            _currentBlockIsToolUse.withLock { $0 = false }
            return nil
        }

        switch type {
        case "tool_use":
            _currentBlockIsToolUse.withLock { $0 = true }
            let id = block["id"] as? String ?? ""
            let name = block["name"] as? String ?? ""
            return .toolUseStart(ToolUseMeta(id: id, name: name))
        case "thinking":
            _currentBlockIsToolUse.withLock { $0 = false }
            return nil
        default:
            _currentBlockIsToolUse.withLock { $0 = false }
            return nil
        }
    }

    // MARK: - content_block_delta

    private static func parseContentBlockDelta(_ data: Data) -> LLMEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delta = json["delta"] as? [String: Any],
              let type = delta["type"] as? String else { return nil }

        switch type {
        case "text_delta":
            if let text = delta["text"] as? String {
                return .textDelta(text)
            }
        case "thinking_delta":
            if let thinking = delta["thinking"] as? String {
                return .thinkingDelta(thinking)
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

    // MARK: - content_block_stop

    private static func parseContentBlockStop(_ data: Data) -> [LLMEvent] {
        let wasToolUse = _currentBlockIsToolUse.withLock { val in
            let was = val
            val = false
            return was
        }
        return wasToolUse ? [.toolUseEnd] : []
    }

    // MARK: - message_delta

    private static func parseMessageDeltaAll(_ data: Data) -> [LLMEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        var events: [LLMEvent] = []

        if let usageDict = json["usage"] as? [String: Any] {
            let usage = parseUsage(usageDict)
            if usage.outputTokens > 0 || usage.inputTokens > 0 {
                events.append(.usage(usage))
            }
        }

        if let delta = json["delta"] as? [String: Any],
           let stopStr = delta["stop_reason"] as? String {
            let reason = StopReason(rawValue: stopStr) ?? .endTurn
            events.append(.messageStop(reason))
        }

        return events
    }

    // MARK: - error

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

    // MARK: - Usage

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

    /// Parse an SSE event into zero or more LLMEvents.
    /// A single SSE chunk can carry usage, finish_reason, and content simultaneously.
    public static func parseAll(event: SSEEvent) -> [LLMEvent] {
        if event.data == "[DONE]" { return [] }
        guard let jsonData = event.jsonData,
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return [] }

        var events: [LLMEvent] = []

        // Mid-stream error at top level
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown provider error"
            let code = error["code"]
            events.append(.error(ProviderError(
                code: "provider.stream_error",
                description: code.map { "[\($0)] \(message)" } ?? message,
                remediation: "Check model availability or retry"
            )))
            return events
        }

        if let choices = json["choices"] as? [[String: Any]], let choice = choices.first {
            // Mid-stream error in choice
            if let choiceError = choice["error"] as? [String: Any] {
                let message = choiceError["message"] as? String ?? "Unknown stream error"
                events.append(.error(ProviderError(
                    code: "provider.stream_error",
                    description: message,
                    remediation: "Retry the request"
                )))
            }

            if let delta = choice["delta"] as? [String: Any] {
                if let content = delta["content"] as? String {
                    events.append(.textDelta(content))
                }
                if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                    for tc in toolCalls {
                        if let function = tc["function"] as? [String: Any] {
                            if let name = function["name"] as? String {
                                let tcId = tc["id"] as? String ?? ""
                                events.append(.toolUseStart(ToolUseMeta(id: tcId, name: name)))
                            }
                            if let args = function["arguments"] as? String, !args.isEmpty {
                                events.append(.toolUseInputDelta(args))
                            }
                        }
                    }
                }
            }

            if let finishReason = choice["finish_reason"] as? String, !finishReason.isEmpty {
                let reason: StopReason
                switch finishReason {
                case "stop": reason = .endTurn
                case "tool_calls": reason = .toolUse
                case "length": reason = .maxTokens
                case "content_filter": reason = .endTurn
                case "error": reason = .endTurn
                default: reason = .endTurn
                }
                events.append(.messageStop(reason))
            }
        }

        if let usage = json["usage"] as? [String: Any] {
            let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
            let cacheRead = promptDetails?["cached_tokens"] as? Int ?? 0
            let cacheWrite = promptDetails?["cache_write_tokens"] as? Int ?? 0

            events.append(.usage(TokenUsage(
                inputTokens: usage["prompt_tokens"] as? Int ?? 0,
                outputTokens: usage["completion_tokens"] as? Int ?? 0,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite
            )))
        }

        return events
    }

    /// Legacy single-event parse (kept for backward compatibility).
    public static func parse(event: SSEEvent) -> LLMEvent? {
        parseAll(event: event).first
    }
}
