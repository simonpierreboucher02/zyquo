import Foundation

public struct SessionCost: Sendable {
    public private(set) var totalInputTokens: Int = 0
    public private(set) var totalOutputTokens: Int = 0
    public private(set) var totalCacheReadTokens: Int = 0
    public private(set) var totalCacheWriteTokens: Int = 0
    public private(set) var totalCostUSD: Double = 0.0
    public private(set) var requests: Int = 0

    public init() {}

    public mutating func record(usage: TokenUsage, model: ModelDescriptor) {
        totalInputTokens += usage.inputTokens
        totalOutputTokens += usage.outputTokens
        totalCacheReadTokens += usage.cacheReadTokens
        totalCacheWriteTokens += usage.cacheWriteTokens
        requests += 1

        totalCostUSD += Self.computeCost(usage: usage, model: model)
    }

    public static func computeCost(usage: TokenUsage, model: ModelDescriptor) -> Double {
        let inputCost = Double(usage.inputTokens) * model.inputPricePerMToken / 1_000_000.0
        let outputCost = Double(usage.outputTokens) * model.outputPricePerMToken / 1_000_000.0
        let cacheReadCost = Double(usage.cacheReadTokens) * model.inputPricePerMToken * 0.1 / 1_000_000.0
        let cacheWriteCost = Double(usage.cacheWriteTokens) * model.inputPricePerMToken * 1.25 / 1_000_000.0
        return inputCost + outputCost + cacheReadCost + cacheWriteCost
    }

    public var formattedCost: String {
        String(format: "$%.4f", totalCostUSD)
    }

    public var summary: String {
        "Tokens: \(totalInputTokens) in / \(totalOutputTokens) out | Cost: \(formattedCost) | Requests: \(requests)"
    }
}
