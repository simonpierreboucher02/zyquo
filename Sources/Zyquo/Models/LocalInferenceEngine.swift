import Foundation

// MARK: - Local Inference Engine Protocol

/// Abstraction over local model inference backends.
///
/// Implementations include:
/// - `MockLocalEngine` — echoes structured responses for testing
/// - Future: `LlamaCppEngine` — llama.cpp via Swift wrapper
/// - Future: `FoundationModelEngine` — Apple Foundation Models
///
/// Reference: CLAUDE.md §25, V2 Phase 8
public protocol LocalInferenceEngine: Sendable {
    /// Whether the engine is ready to accept inference requests.
    var isAvailable: Bool { get }

    /// The model identifier this engine is loaded with.
    var modelId: String { get }

    /// Maximum context window in tokens.
    var contextWindow: Int { get }

    /// Generate a streaming completion from a prompt.
    ///
    /// - Parameters:
    ///   - prompt: The assembled prompt text.
    ///   - maxTokens: Maximum tokens to generate.
    ///   - temperature: Sampling temperature (0.0 = deterministic, higher = more random).
    /// - Returns: An async stream of generated text chunks (word or sub-word level).
    func generate(
        prompt: String,
        maxTokens: Int,
        temperature: Float
    ) -> AsyncThrowingStream<String, Error>

    /// Estimate the token count for a given text.
    ///
    /// Local models use different tokenizers, so this is an approximation.
    /// The default heuristic is ~4 characters per token for English text.
    func tokenCount(for text: String) -> Int
}

// MARK: - Mock Local Engine

/// A mock inference engine that produces deterministic responses for testing.
///
/// Generates a structured echo of the prompt, emitted word by word to simulate
/// streaming inference. Fully functional for testing the local model pipeline
/// without requiring any actual ML runtime.
public final class MockLocalEngine: LocalInferenceEngine, @unchecked Sendable {
    public let modelId: String
    public let contextWindow: Int
    public let isAvailable: Bool

    /// Simulated delay per token in nanoseconds. Set to 0 for fast tests.
    private let tokenDelayNs: UInt64

    public init(
        modelId: String = "mock-local-7b-q4",
        contextWindow: Int = 4096,
        isAvailable: Bool = true,
        tokenDelayNs: UInt64 = 0
    ) {
        self.modelId = modelId
        self.contextWindow = contextWindow
        self.isAvailable = isAvailable
        self.tokenDelayNs = tokenDelayNs
    }

    public func generate(
        prompt: String,
        maxTokens: Int,
        temperature: Float
    ) -> AsyncThrowingStream<String, Error> {
        let words = buildResponse(for: prompt, maxTokens: maxTokens)
        let delay = tokenDelayNs

        return AsyncThrowingStream { continuation in
            let task = Task {
                for (index, word) in words.enumerated() {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    let prefix = index == 0 ? "" : " "
                    continuation.yield(prefix + word)

                    if delay > 0 {
                        try await Task.sleep(nanoseconds: delay)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func tokenCount(for text: String) -> Int {
        // Approximate: ~4 characters per token for English text
        max(1, text.count / 4)
    }

    // MARK: - Response Generation

    private func buildResponse(for prompt: String, maxTokens: Int) -> [String] {
        let promptPreview = String(prompt.prefix(80))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        var response = [
            "[Local",
            "model",
            "response]",
            "Processed",
            "prompt:",
            "\"\(promptPreview)\".",
            "This",
            "is",
            "a",
            "mock",
            "inference",
            "output",
            "from",
            modelId + ".",
            "The",
            "local",
            "model",
            "runtime",
            "is",
            "operational.",
        ]

        // Respect maxTokens by capping the word count
        // Rough estimate: 1 token ~= 0.75 words for English
        let maxWords = max(1, Int(Double(maxTokens) * 0.75))
        if response.count > maxWords {
            response = Array(response.prefix(maxWords))
        }

        return response
    }
}
