import Foundation
import Logging

public final class OpenRouterProvider: LLMProvider, @unchecked Sendable {
    public let id = "openrouter"
    public let displayName = "OpenRouter"
    public let supportedModels: [ModelDescriptor] = ModelCatalog.allModels

    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let maxRetries = 3
    private let requestTimeout: TimeInterval = 120
    private let logger = ZyquoLogger.shared

    public init() {}

    public func send(
        request: LLMRequest,
        cancellation: Task<Void, Never>?
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await executeWithRetry(request: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func executeWithRetry(
        request: LLMRequest,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) async throws {
        var lastError: Error?
        var retryAfterOverride: TimeInterval?

        for attempt in 0..<maxRetries {
            if Task.isCancelled { throw ZyquoError.cancelled }

            do {
                try await executeStream(request: request, continuation: continuation)
                return
            } catch let error as ProviderError where error.code == "provider.rate_limited" || error.code == "provider.server_error" || error.code == "provider.service_unavailable" {
                lastError = error
                let delay: TimeInterval
                if let override = retryAfterOverride {
                    delay = override
                    retryAfterOverride = nil
                } else {
                    delay = retryDelay(attempt: attempt)
                }
                logger.warning("OpenRouter retry \(attempt + 1)/\(maxRetries) after \(String(format: "%.1f", delay))s")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch let error as OpenRouterRetryableError {
                lastError = error.underlying
                retryAfterOverride = error.retryAfter
                let delay = error.retryAfter ?? retryDelay(attempt: attempt)
                logger.warning("OpenRouter retry \(attempt + 1)/\(maxRetries) after \(String(format: "%.1f", delay))s (Retry-After)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                throw error
            }
        }
        throw ZyquoError.provider(lastError as? ProviderError ?? .networkError(lastError ?? CancellationError()))
    }

    private func executeStream(
        request: LLMRequest,
        continuation: AsyncThrowingStream<LLMEvent, Error>.Continuation
    ) async throws {
        guard let apiKey = KeychainHelper.read(service: ProviderKeychain.service, account: "openrouter") else {
            throw ZyquoError.provider(.authMissing(provider: "openrouter"))
        }

        let body = buildRequestBody(request)
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = bodyData
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        urlRequest.setValue("https://zyquo.dev", forHTTPHeaderField: "http-referer")
        urlRequest.setValue("Zyquo CLI", forHTTPHeaderField: "x-title")
        urlRequest.timeoutInterval = requestTimeout

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let modelId = mapModelToOpenRouter(request.model)
        logger.debug("OpenRouter request: model=\(modelId) maxTokens=\(request.maxTokens)")

        let (bytes, response) = try await session.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZyquoError.provider(.networkError(URLError(.badServerResponse)))
        }

        if httpResponse.statusCode != 200 {
            let errorBody = try await collectErrorBody(bytes: bytes)
            let retryAfter = parseRetryAfter(httpResponse)
            let error = buildHTTPError(status: httpResponse.statusCode, body: errorBody)

            if retryAfter != nil, case .provider(let pe) = error,
               pe.code == "provider.rate_limited" || pe.code == "provider.service_unavailable" {
                throw OpenRouterRetryableError(underlying: pe, retryAfter: retryAfter)
            }
            throw error
        }

        let decoder = SSEDecoder()
        var sentStart = false

        for try await byte in bytes {
            if Task.isCancelled { throw ZyquoError.cancelled }

            let events = decoder.decode(Data([byte]))
            for sseEvent in events {
                if !sentStart {
                    continuation.yield(.messageStart(MessageMeta(id: "or-\(UUID().uuidString.prefix(8))", model: modelId)))
                    sentStart = true
                }

                let llmEvents = OpenAIEventParser.parseAll(event: sseEvent)
                for llmEvent in llmEvents {
                    continuation.yield(llmEvent)
                }
            }
        }

        continuation.finish()
    }

    // MARK: - Request Body

    private func buildRequestBody(_ request: LLMRequest) -> [String: Any] {
        let modelId = mapModelToOpenRouter(request.model)

        var body: [String: Any] = [
            "model": modelId,
            "max_tokens": request.maxTokens,
            "stream": true,
            "stream_options": ["include_usage": true],
        ]

        if let temp = request.temperature {
            body["temperature"] = temp
        }

        var messages: [[String: Any]] = []

        if let system = request.systemPrompt {
            messages.append(["role": "system", "content": system])
        }

        for msg in request.messages {
            messages.append(encodeMessage(msg))
        }
        body["messages"] = messages

        if !request.tools.isEmpty {
            body["tools"] = request.tools.map { encodeTool($0) }
            switch request.toolChoice {
            case .auto: body["tool_choice"] = "auto"
            case .any: body["tool_choice"] = "required"
            case .none: body["tool_choice"] = "none"
            case .specific(let name): body["tool_choice"] = ["type": "function", "function": ["name": name]]
            }
        }

        if request.enableCaching && modelId.hasPrefix("anthropic/") {
            body["cache_control"] = ["type": "auto"]
        }

        switch request.thinking {
        case .disabled:
            break
        case .adaptive:
            body["reasoning"] = ["type": "adaptive"] as [String: Any]
        case .enabled(let budget):
            body["reasoning"] = [
                "type": "enabled",
                "budget_tokens": budget,
            ] as [String: Any]
        }

        return body
    }

    private func encodeMessage(_ message: LLMMessage) -> [String: Any] {
        var dict: [String: Any] = ["role": message.role == .tool ? "tool" : message.role.rawValue]

        if message.content.count == 1 {
            switch message.content[0] {
            case .text(let text):
                dict["content"] = text
            case .toolResult(let toolUseId, let content, _):
                dict["tool_call_id"] = toolUseId
                dict["content"] = content
            default:
                break
            }
        } else {
            var parts: [[String: Any]] = []
            var toolCalls: [[String: Any]] = []

            for block in message.content {
                switch block {
                case .text(let text):
                    parts.append(["type": "text", "text": text])
                case .thinking:
                    break
                case .toolUse(let id, let name, let input):
                    toolCalls.append([
                        "id": id,
                        "type": "function",
                        "function": [
                            "name": name,
                            "arguments": jsonEncode(input),
                        ] as [String: Any],
                    ])
                case .toolResult(let toolUseId, let content, _):
                    dict["tool_call_id"] = toolUseId
                    dict["content"] = content
                case .image(let mediaType, let data):
                    parts.append([
                        "type": "image_url",
                        "image_url": [
                            "url": "data:\(mediaType);base64,\(data.base64EncodedString())",
                        ],
                    ])
                }
            }

            if !toolCalls.isEmpty {
                dict["tool_calls"] = toolCalls
                if parts.isEmpty {
                    dict["content"] = NSNull()
                } else if parts.count == 1, let text = parts[0]["text"] as? String {
                    dict["content"] = text
                } else {
                    dict["content"] = parts
                }
            } else if !parts.isEmpty {
                dict["content"] = parts
            }
        }
        return dict
    }

    private func encodeTool(_ tool: ToolSchema) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": jsonValueToAny(tool.inputSchema),
            ] as [String: Any],
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

    private func jsonEncode(_ dict: [String: JSONValue]) -> String {
        let any = jsonValueToAny(dict)
        guard let data = try? JSONSerialization.data(withJSONObject: any),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func mapModelToOpenRouter(_ model: String) -> String {
        if model.hasPrefix("anthropic/") || model.hasPrefix("openai/") { return model }
        if model.contains("claude") { return "anthropic/\(model)" }
        return model
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

    private func parseRetryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = Double(value) {
            return seconds
        }
        return nil
    }

    private func buildHTTPError(status: Int, body: String) -> ZyquoError {
        let parsed = parseErrorBody(body)

        switch status {
        case 400:
            return .provider(ProviderError(
                code: "provider.bad_request",
                description: parsed ?? "Bad request to OpenRouter",
                remediation: "Check request parameters — model ID, messages format, and tool definitions"
            ))
        case 401:
            return .provider(ProviderError(
                code: "provider.auth_invalid",
                description: parsed ?? "Invalid OpenRouter API key",
                remediation: "Run `zyquo provider login openrouter` to update your API key"
            ))
        case 402:
            return .provider(ProviderError(
                code: "provider.payment_required",
                description: parsed ?? "Insufficient OpenRouter credits",
                remediation: "Add credits at openrouter.ai/settings/credits"
            ))
        case 403:
            return .provider(ProviderError(
                code: "provider.forbidden",
                description: parsed ?? "Access denied by OpenRouter",
                remediation: "Check your API key permissions or content moderation flags"
            ))
        case 408:
            return .provider(ProviderError(
                code: "provider.timeout",
                description: parsed ?? "Request timed out on OpenRouter",
                remediation: "Retry with a shorter prompt or different model"
            ))
        case 429:
            return .provider(ProviderError(
                code: "provider.rate_limited",
                description: parsed ?? "Rate limited by OpenRouter",
                remediation: "Wait and retry, or check rate limits at openrouter.ai/docs/limits"
            ))
        case 502:
            return .provider(ProviderError(
                code: "provider.bad_gateway",
                description: parsed ?? "Model unavailable on OpenRouter (502)",
                remediation: "The upstream model provider is unavailable — try a different model or retry later"
            ))
        case 503:
            return .provider(ProviderError(
                code: "provider.service_unavailable",
                description: parsed ?? "No provider available on OpenRouter (503)",
                remediation: "No provider matches your routing criteria — try without provider preferences"
            ))
        case 500...599:
            return .provider(ProviderError(
                code: "provider.server_error",
                description: parsed ?? "OpenRouter server error (\(status))",
                remediation: "Wait and retry"
            ))
        default:
            return .provider(ProviderError(
                code: "provider.http_\(status)",
                description: parsed ?? "Unexpected HTTP status \(status) from OpenRouter",
                remediation: "Check the OpenRouter documentation"
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
        if let code = error["code"] {
            return "[\(code)] \(message)"
        }
        return message
    }

    private func retryDelay(attempt: Int) -> TimeInterval {
        let base = pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.5)
        return min(base + jitter, 30.0)
    }
}

// MARK: - Internal Retry Error

private struct OpenRouterRetryableError: Error {
    let underlying: ProviderError
    let retryAfter: TimeInterval?
}
