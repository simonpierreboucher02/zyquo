import Foundation
import Logging

// MARK: - Local Model Provider

/// LLM provider for locally-running models.
///
/// Conforms to the same `LLMProvider` protocol as cloud providers, enabling
/// seamless swapping between local and remote inference. Delegates actual
/// inference to a `LocalInferenceEngine` implementation.
///
/// V2 Phase 8: ships with `MockLocalEngine` for testing.
/// Future: `LlamaCppEngine` (Metal-accelerated GGUF) and
///         `FoundationModelEngine` (Apple Foundation Models).
///
/// Reference: CLAUDE.md §25, V2 Phase 8
public final class LocalProvider: LLMProvider, @unchecked Sendable {
    public let id = "local"
    public let displayName = "Local"

    private let lock = NSLock()
    private var _engines: [String: any LocalInferenceEngine] = [:]
    private var _supportedModels: [ModelDescriptor] = []

    public var supportedModels: [ModelDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return _supportedModels
    }

    public init() {}

    // MARK: - Engine Registration

    /// Register a local inference engine for a specific model.
    ///
    /// - Parameters:
    ///   - engine: The inference engine implementation.
    ///   - descriptor: Model descriptor for catalog integration.
    public func registerEngine(
        _ engine: any LocalInferenceEngine,
        descriptor: ModelDescriptor
    ) {
        lock.lock()
        defer { lock.unlock() }
        _engines[engine.modelId] = engine
        if !_supportedModels.contains(where: { $0.id == descriptor.id }) {
            _supportedModels.append(descriptor)
        }
    }

    /// Remove a registered engine.
    public func removeEngine(modelId: String) {
        lock.lock()
        defer { lock.unlock() }
        _engines.removeValue(forKey: modelId)
        _supportedModels.removeAll { $0.id == modelId }
    }

    /// Check if a specific model engine is available.
    public func hasEngine(for modelId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _engines[modelId]?.isAvailable ?? false
    }

    /// List all registered engine model IDs.
    public func registeredModelIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(_engines.keys)
    }

    // MARK: - LLMProvider Conformance

    public func send(
        request: LLMRequest,
        cancellation: Task<Void, Never>?
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        let modelId = request.model
        let engine: (any LocalInferenceEngine)?
        lock.lock()
        engine = _engines[modelId]
        lock.unlock()

        guard let engine else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ZyquoError.provider(ProviderError(
                    code: "provider.local.model_not_found",
                    description: "Local model '\(modelId)' is not loaded",
                    remediation: "Register a local model with `zyquo models register <path>` or check `zyquo models local`"
                )))
            }
        }

        guard engine.isAvailable else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: ZyquoError.provider(ProviderError(
                    code: "provider.local.model_unavailable",
                    description: "Local model '\(modelId)' is not available",
                    remediation: "Check model status with `zyquo models info \(modelId)`"
                )))
            }
        }

        let maxTokens = request.maxTokens
        let temperature = Float(request.temperature ?? 0.7)

        // Build prompt from messages
        let prompt = assemblePrompt(from: request)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Emit message start
                    let messageId = "local-\(UUID().uuidString.prefix(8))"
                    continuation.yield(.messageStart(MessageMeta(
                        id: messageId,
                        model: modelId
                    )))

                    // Stream inference tokens
                    var totalOutputTokens = 0
                    let stream = engine.generate(
                        prompt: prompt,
                        maxTokens: maxTokens,
                        temperature: temperature
                    )

                    for try await chunk in stream {
                        if Task.isCancelled { throw CancellationError() }
                        continuation.yield(.textDelta(chunk))
                        totalOutputTokens += engine.tokenCount(for: chunk)
                    }

                    // Emit usage
                    let inputTokens = engine.tokenCount(for: prompt)
                    continuation.yield(.usage(TokenUsage(
                        inputTokens: inputTokens,
                        outputTokens: totalOutputTokens
                    )))

                    // Emit stop
                    continuation.yield(.messageStop(.endTurn))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ZyquoError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Wire up cancellation
            if let cancellation {
                Task {
                    await cancellation.value
                    task.cancel()
                }
            }

            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Prompt Assembly

    /// Assemble a flat prompt string from the LLMRequest messages.
    ///
    /// Local models do not use the structured Messages API, so we flatten
    /// system prompt + messages into a single text prompt using a simple
    /// chat template format.
    private func assemblePrompt(from request: LLMRequest) -> String {
        var parts: [String] = []

        if let system = request.systemPrompt {
            parts.append("<system>\(system)</system>")
        }

        for message in request.messages {
            let role = message.role.rawValue
            let content = message.content.compactMap { block -> String? in
                switch block {
                case .text(let text): return text
                case .toolResult(_, let content, _): return content
                default: return nil
                }
            }.joined(separator: "\n")

            parts.append("<\(role)>\(content)</\(role)>")
        }

        return parts.joined(separator: "\n\n")
    }
}
