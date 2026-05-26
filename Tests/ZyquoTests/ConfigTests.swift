import XCTest
@testable import Zyquo

final class ConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = Config()
        XCTAssertEqual(config.ui.theme, "zyquo-dark")
        XCTAssertEqual(config.agent.maxSteps, 40)
        XCTAssertEqual(config.agent.maxCostUSD, 5.0)
        XCTAssertEqual(config.providers.defaultProvider, "anthropic")
        XCTAssertEqual(config.providers.defaultModel, "claude-sonnet-4-6")
        XCTAssertEqual(config.shell.defaultShell, "/bin/zsh")
        XCTAssertEqual(config.shell.timeoutSeconds, 120)
        XCTAssertFalse(config.shell.loadProfile)
        XCTAssertEqual(config.memory.compressThresholdPct, 70)
        XCTAssertTrue(config.memory.keepDecisionsVerbatim)
    }

    func testFlagOverrides() {
        let flags = CommandFlags(
            noColor: true,
            yes: true,
            model: "claude-opus-4-7",
            provider: "openrouter",
            maxSteps: 100,
            maxCost: 10.0,
            verbose: true
        )
        let config = Config(flags: flags)

        XCTAssertTrue(config.ui.noColor)
        XCTAssertTrue(config.agent.autoApproveSafe)
        XCTAssertEqual(config.agent.maxSteps, 100)
        XCTAssertEqual(config.agent.maxCostUSD, 10.0)
        XCTAssertEqual(config.providers.resolvedProvider, "openrouter")
        XCTAssertEqual(config.providers.resolvedModel, "claude-opus-4-7")
    }

    func testNoColorFromEnvironment() {
        let config = Config(
            flags: .init(),
            environment: ["NO_COLOR": "1"]
        )
        XCTAssertTrue(config.ui.noColor)
    }

    func testEnvironmentMaxSteps() {
        let config = Config(
            flags: .init(),
            environment: ["ZYQUO_MAX_STEPS": "25"]
        )
        XCTAssertEqual(config.agent.maxSteps, 25)
    }
}
