import Foundation

public actor ZyquoMetrics {
    public static let shared = ZyquoMetrics()

    private var counters: [String: Int] = [:]
    private var histograms: [String: [Double]] = [:]

    private init() {}

    public func increment(_ name: String, by amount: Int = 1) {
        counters[name, default: 0] += amount
    }

    public func record(_ name: String, value: Double) {
        histograms[name, default: []].append(value)
    }

    public func counter(_ name: String) -> Int {
        counters[name] ?? 0
    }

    public func histogram(_ name: String) -> HistogramSummary? {
        guard let values = histograms[name], !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        let sum = sorted.reduce(0, +)
        return HistogramSummary(
            count: count,
            sum: sum,
            min: sorted[0],
            max: sorted[count - 1],
            mean: sum / Double(count),
            p50: sorted[count / 2],
            p95: sorted[Int(Double(count) * 0.95)],
            p99: sorted[min(Int(Double(count) * 0.99), count - 1)]
        )
    }

    public func allCounters() -> [String: Int] {
        counters
    }

    public func reset() {
        counters.removeAll()
        histograms.removeAll()
    }

    // MARK: - Well-Known Metric Names

    public enum Name {
        public static let agentSteps = "zyquo.agent.steps"
        public static let agentStepDurationMs = "zyquo.agent.steps.duration_ms"
        public static let toolInvocations = "zyquo.tool.invocations"
        public static let toolErrors = "zyquo.tool.errors"
        public static let llmTokensIn = "zyquo.llm.tokens.in"
        public static let llmTokensOut = "zyquo.llm.tokens.out"
        public static let llmCostUSD = "zyquo.llm.cost_usd"
        public static let shellCommands = "zyquo.shell.commands"
        public static let approvals = "zyquo.approvals"
    }
}

public struct HistogramSummary: Sendable {
    public let count: Int
    public let sum: Double
    public let min: Double
    public let max: Double
    public let mean: Double
    public let p50: Double
    public let p95: Double
    public let p99: Double
}
