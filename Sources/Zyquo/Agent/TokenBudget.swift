import Foundation

/// Tracks token usage against a model's context window.
///
/// Used by ContextAssembler to decide when to truncate or compact context.
/// Reference: CLAUDE.md §16.1
public struct TokenBudget: Sendable {
    /// The model's total context window in tokens.
    public let modelContextWindow: Int
    /// Tokens currently used by the assembled context.
    public var tokensUsed: Int
    /// Tokens reserved for the model's output.
    public let reserveForOutput: Int

    public init(
        modelContextWindow: Int = 200_000,
        tokensUsed: Int = 0,
        reserveForOutput: Int = 8_192
    ) {
        self.modelContextWindow = modelContextWindow
        self.tokensUsed = tokensUsed
        self.reserveForOutput = reserveForOutput
    }

    /// Tokens remaining for input context before hitting the budget.
    public var remaining: Int {
        max(0, modelContextWindow - tokensUsed - reserveForOutput)
    }

    /// Current utilization as a percentage (0.0 to 1.0+).
    public var utilizationPercent: Float {
        guard modelContextWindow > 0 else { return 0 }
        return Float(tokensUsed) / Float(modelContextWindow - reserveForOutput)
    }

    /// Whether the context needs compaction (utilization > 70%).
    public var needsCompaction: Bool {
        utilizationPercent > 0.70
    }

    /// Record additional token usage.
    public mutating func record(tokens: Int) {
        tokensUsed += tokens
    }

    /// Reset usage (after compaction).
    public mutating func reset(to tokens: Int) {
        tokensUsed = tokens
    }
}
