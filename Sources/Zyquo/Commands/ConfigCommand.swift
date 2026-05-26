import ArgumentParser
import Foundation

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Read or write configuration",
        subcommands: [ConfigGet.self, ConfigSet.self]
    )
}

struct ConfigGet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Read a configuration value"
    )

    @Argument(help: "Configuration key (e.g. ui.theme)")
    var key: String

    func run() async throws {
        let config = Config()
        guard let value = resolveKey(key, config: config) else {
            print("Unknown key: \(key)")
            throw ExitCode(rawValue: 3)
        }
        print(value)
    }

    private func resolveKey(_ key: String, config: Config) -> String? {
        switch key {
        case "ui.theme": return config.ui.theme
        case "ui.animations": return String(config.ui.animations)
        case "ui.unicode_borders": return String(config.ui.unicodeBorders)
        case "agent.max_steps": return String(config.agent.maxSteps)
        case "agent.max_cost_usd": return String(config.agent.maxCostUSD)
        case "agent.auto_approve_safe": return String(config.agent.autoApproveSafe)
        case "providers.default": return config.providers.defaultProvider
        case "providers.default_model": return config.providers.defaultModel
        case "shell.default": return config.shell.defaultShell
        case "shell.load_profile": return String(config.shell.loadProfile)
        case "shell.timeout_s": return String(config.shell.timeoutSeconds)
        case "memory.compress_threshold_pct": return String(config.memory.compressThresholdPct)
        default: return nil
        }
    }
}

struct ConfigSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Write a configuration value"
    )

    @Argument(help: "Configuration key")
    var key: String

    @Argument(help: "Value to set")
    var value: String

    func run() async throws {
        print("Config persistence is not yet implemented.")
        print("Would set \(key) = \(value)")
    }
}
