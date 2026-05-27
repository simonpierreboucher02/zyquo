import Foundation
import Logging

public final class AnthropicProvider: LLMProvider, @unchecked Sendable {
    public let id = "anthropic"
    public let displayName = "Anthropic"
    public let supportedModels: [ModelDescriptor] = ModelCatalog.allModels

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let maxRetries = 3
    private let requestTimeout: TimeInterval = 120
    private let streamIdleTimeout: TimeInterval = 30
    private let logger = ZyquoLogger.shared

    public init() {}

    public func send(
        request: LLMRequest,
        cancellation: Task<Void, Never>?
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await executeWithRetry(request: request, continuation: continuation, cancellation: cancellation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func executeWithRetry(
        request: LLMRequest,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation,
        cancellation: Task<Void, Never>?
    ) async throws {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            if Task.isCancelled { throw ZyquoError.cancelled }

            do {
                try await executeStream(request: request, continuation: continuation, cancellation: cancellation)
                return
            } catch let error as ProviderError where error.code == "provider.rate_limited" || error.code == "provider.server_error" {
                lastError = error
                let delay = retryDelay(attempt: attempt)
                logger.warning("Anthropic retry \(attempt + 1)/\(maxRetries) after \(String(format: "%.1f", delay))s: \(error.description)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                throw error
            }
        }
        throw ZyquoError.provider(lastError as? ProviderError ?? .networkError(lastError ?? CancellationError()))
    }

    private func executeStream(
        request: LLMRequest,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation,
        cancellation: Task<Void, Never>?
    ) async throws {
        guard let apiKey = KeychainHelper.read(service: ProviderKeychain.service, account: "anthropic") else {
            throw ZyquoError.provider(.authMissing(provider: "anthropic"))
        }

        let body = buildRequestBody(request)
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = bodyData
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "accept")
        urlRequest.timeoutInterval = requestTimeout

        let betaFeatures = buildBetaFeatures(request)
        if !betaFeatures.isEmpty {
            urlRequest.setValue(betaFeatures.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout * 2
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        logger.debug("Anthropic request: model=\(request.model) maxTokens=\(request.maxTokens) thinking=\(String(describing: request.thinking))")

        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZyquoError.provider(.networkError(URLError(.badServerResponse)))
        }

        if httpResponse.statusCode != 200 {
            let errorBody = try await collectErrorBody(bytes: bytes)
            throw buildHTTPError(status: httpResponse.statusCode, body: errorBody)
        }

        let decoder = SSEDecoder()
        var hasEmittedMessageStart = false

        for try await byte in bytes {
            if Task.isCancelled { throw ZyquoError.cancelled }

            let events = decoder.decode(Data([byte]))
            for sseEvent in events {
                let llmEvents = AnthropicEventParser.parseAll(event: sseEvent)
                for llmEvent in llmEvents {
                    if case .messageStart = llmEvent { hasEmittedMessageStart = true }
                    continuation.yield(llmEvent)
                }
            }
        }

        if !hasEmittedMessageStart {
            continuation.yield(.messageStop(.endTurn))
        }

        continuation.finish()
    }

    // MARK: - Beta Features

    private func buildBetaFeatures(_ request: LLMRequest) -> [String] {
        var features: [String] = []
        if request.enableCaching {
            features.append("prompt-caching-2024-07-31")
        }
        return features
    }

    // MARK: - Request Body

    private func buildRequestBody(_ request: LLMRequest) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "stream": true,
        ]

        if let system = request.systemPrompt {
            if request.enableCaching {
                body["system"] = [
                    [
                        "type": "text",
                        "text": system,
                        "cache_control": ["type": "ephemeral"],
                    ] as [String: Any]
                ]
            } else {
                body["system"] = system
            }
        }

        switch request.thinking {
        case .disabled:
            if let temp = request.temperature {
                body["temperature"] = temp
            }
        case .adaptive:
            body["thinking"] = ["type": "adaptive"] as [String: Any]
        case .enabled(let budget):
            body["thinking"] = [
                "type": "enabled",
                "budget_tokens": budget,
            ] as [String: Any]
        }

        body["messages"] = request.messages.map { encodeMessage($0) }

        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { encodeTool($0) }
            switch request.toolChoice {
            case .auto: body["tool_choice"] = ["type": "auto"]
            case .any: body["tool_choice"] = ["type": "any"]
            case .none: break
            case .specific(let name): body["tool_choice"] = ["type": "tool", "name": name]
            }
        }

        return body
    }

    private func encodeMessage(_ message: LLMMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": message.role.rawValue]
        if message.content.count == 1, case .text(let text) = message.content[0] {
            dict["content"] = text
        } else {
            dict["content"] = message.content.map { encodeContentBlock($0) }
        }
        return dict
    }

    private func encodeContentBlock(_ block: ContentBlock) -> [String: Any] {
        switch block {
        case .text(let text):
            return ["type": "text", "text": text]
        case .thinking(let text):
            return ["type": "thinking", "thinking": text]
        case .toolUse(let id, let name, let input):
            var encoded: [String: Any] = ["type": "tool_use", "id": id, "name": name]
            encoded["input"] = jsonValueToAny(input)
            return encoded
        case .toolResult(let toolUseId, let content, let isError):
            var dict: [String: Any] = ["type": "tool_result", "tool_use_id": toolUseId, "content": content]
            if isError { dict["is_error"] = true }
            return dict
        case .image(let mediaType, let data):
            return [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": data.base64EncodedString(),
                ] as [String: Any],
            ]
        }
    }

    private func encodeTool(_ tool: ToolSchema) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "input_schema": jsonValueToAny(tool.inputSchema),
        ]
    }

    private func jsonValueToAny(_ dict: [String: JSONValue]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (k, v) in dict {
            result[k] = jsonValueSingleToAny(v)
        }
        return result
    }

    private func jsonValueSingleToAny(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map { jsonValueSingleToAny($0) }
        case .object(let o): return jsonValueToAny(o)
        }
    }

    // MARK: - Error Handling

    private func collectErrorBody(bytes: URLSession.AsyncBytes) async throws -> String {
        var collected = Data()
        let limit = 4096
        for try await byte in bytes {
            collected.append(byte)
            if collected.count >= limit { break }
        }
        return String(data: collected, encoding: .utf8) ?? ""
    }

    private func buildHTTPError(status: Int, body: String) -> ZyquoError {
        let parsed = parseErrorBody(body)

        switch status {
        case 401:
            return .provider(ProviderError(
                code: "provider.auth_invalid",
                description: parsed ?? "Invalid Anthropic API key",
                remediation: "Run `zyquo provider login anthropic` to update your API key"
            ))
        case 400:
            return .provider(ProviderError(
                code: "provider.bad_request",
                description: parsed ?? "Bad request to Anthropic API",
                remediation: "Check request parameters — model, max_tokens, and message format"
            ))
        case 403:
            return .provider(ProviderError(
                code: "provider.forbidden",
                description: parsed ?? "Access denied by Anthropic",
                remediation: "Check your API key permissions and organization settings"
            ))
        case 429:
            return .provider(ProviderError(
                code: "provider.rate_limited",
                description: parsed ?? "Rate limited by Anthropic",
                remediation: "Wait and retry, or switch provider with `--provider openrouter`"
            ))
        case 529:
            return .provider(ProviderError(
                code: "provider.server_error",
                description: parsed ?? "Anthropic API overloaded (529)",
                remediation: "Wait and retry"
            ))
        case 500...599:
            return .provider(ProviderError(
                code: "provider.server_error",
                description: parsed ?? "Anthropic server error (\(status))",
                remediation: "Wait and retry"
            ))
        default:
            return .provider(ProviderError(
                code: "provider.http_\(status)",
                description: parsed ?? "Unexpected HTTP status \(status) from Anthropic",
                remediation: "Check the Anthropic API documentation"
            ))
        }
    }

    private func parseErrorBody(_ body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        let type = error["type"] as? String ?? "api_error"
        return "\(type): \(message)"
    }

    private func retryDelay(attempt: Int) -> TimeInterval {
        let base = pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.5)
        return min(base + jitter, 30.0)
    }
}
