import XCTest
@testable import Zyquo

final class PricingTests: XCTestCase {

    func testComputeCostSonnet() {
        let usage = TokenUsage(inputTokens: 1000, outputTokens: 500)
        let cost = SessionCost.computeCost(usage: usage, model: ModelCatalog.claudeSonnet4_6)
        // input: 1000 * 3.0 / 1M = 0.003
        // output: 500 * 15.0 / 1M = 0.0075
        let expected = 0.003 + 0.0075
        XCTAssertEqual(cost, expected, accuracy: 0.000001)
    }

    func testComputeCostOpus() {
        let usage = TokenUsage(inputTokens: 10_000, outputTokens: 2_000)
        let cost = SessionCost.computeCost(usage: usage, model: ModelCatalog.claudeOpus4_7)
        // input: 10000 * 15.0 / 1M = 0.15
        // output: 2000 * 75.0 / 1M = 0.15
        let expected = 0.15 + 0.15
        XCTAssertEqual(cost, expected, accuracy: 0.000001)
    }

    func testComputeCostHaiku() {
        let usage = TokenUsage(inputTokens: 5000, outputTokens: 1000)
        let cost = SessionCost.computeCost(usage: usage, model: ModelCatalog.claudeHaiku4_5)
        // input: 5000 * 0.80 / 1M = 0.004
        // output: 1000 * 4.0 / 1M = 0.004
        let expected = 0.004 + 0.004
        XCTAssertEqual(cost, expected, accuracy: 0.000001)
    }

    func testCostWithCacheTokens() {
        let usage = TokenUsage(
            inputTokens: 1000,
            outputTokens: 500,
            cacheReadTokens: 2000,
            cacheWriteTokens: 500
        )
        let cost = SessionCost.computeCost(usage: usage, model: ModelCatalog.claudeSonnet4_6)
        // input: 1000 * 3.0 / 1M = 0.003
        // output: 500 * 15.0 / 1M = 0.0075
        // cache read: 2000 * 3.0 * 0.1 / 1M = 0.0006
        // cache write: 500 * 3.0 * 1.25 / 1M = 0.001875
        let expected = 0.003 + 0.0075 + 0.0006 + 0.001875
        XCTAssertEqual(cost, expected, accuracy: 0.000001)
    }

    func testSessionCostAccumulation() {
        var cost = SessionCost()
        XCTAssertEqual(cost.totalInputTokens, 0)
        XCTAssertEqual(cost.totalOutputTokens, 0)
        XCTAssertEqual(cost.totalCostUSD, 0.0)
        XCTAssertEqual(cost.requests, 0)

        cost.record(
            usage: TokenUsage(inputTokens: 1000, outputTokens: 500),
            model: ModelCatalog.claudeSonnet4_6
        )
        XCTAssertEqual(cost.totalInputTokens, 1000)
        XCTAssertEqual(cost.totalOutputTokens, 500)
        XCTAssertEqual(cost.requests, 1)

        cost.record(
            usage: TokenUsage(inputTokens: 2000, outputTokens: 1000),
            model: ModelCatalog.claudeSonnet4_6
        )
        XCTAssertEqual(cost.totalInputTokens, 3000)
        XCTAssertEqual(cost.totalOutputTokens, 1500)
        XCTAssertEqual(cost.requests, 2)
    }

    func testZeroCost() {
        let usage = TokenUsage(inputTokens: 0, outputTokens: 0)
        let cost = SessionCost.computeCost(usage: usage, model: ModelCatalog.claudeSonnet4_6)
        XCTAssertEqual(cost, 0.0)
    }

    func testFormattedCost() {
        var cost = SessionCost()
        cost.record(
            usage: TokenUsage(inputTokens: 1000, outputTokens: 500),
            model: ModelCatalog.claudeSonnet4_6
        )
        XCTAssertTrue(cost.formattedCost.hasPrefix("$"))
        XCTAssertTrue(cost.formattedCost.contains("."))
    }

    func testSummaryContainsAllParts() {
        var cost = SessionCost()
        cost.record(
            usage: TokenUsage(inputTokens: 100, outputTokens: 50),
            model: ModelCatalog.claudeSonnet4_6
        )
        let summary = cost.summary
        XCTAssertTrue(summary.contains("100 in"))
        XCTAssertTrue(summary.contains("50 out"))
        XCTAssertTrue(summary.contains("$"))
        XCTAssertTrue(summary.contains("Requests: 1"))
    }
}
