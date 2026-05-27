import ArgumentParser
import Foundation
import TOMLKit

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Read or write configuration",
        subcommands: [ConfigGet.self, ConfigSet.self, ConfigList.self]
    )
}

// MARK: - config get

struct ConfigGet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Read a configuration value"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    @Argument(help: "Configuration key (e.g. ui.theme)")
    var key: String

    func run() async throws {
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let wsConfigPath = root
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("config.json")
        let config = Config(
            flags: globals.flags,
            workspaceConfigPath: FileManager.default.fileExists(atPath: wsConfigPath.path) ? wsConfigPath : nil
        )
        guard let value = ConfigKeys.resolve(key, config: config) else {
            print("Unknown key: \(key)")
            print("Run \u{1B}[1mzyquo config list\u{1B}[0m to see all available keys.")
            throw ExitCode(rawValue: 3)
        }
        print(value)
    }
}

// MARK: - config set

struct ConfigSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Write a configuration value"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    @Flag(name: .long, help: "Write to workspace config (.zyquo/config.json) instead of user config")
    var workspace: Bool = false

    @Argument(help: "Configuration key (e.g. ui.theme)")
    var key: String

    @Argument(help: "Value to set")
    var value: String

    func run() async throws {
        // Validate the key is known
        guard ConfigKeys.allKeys.contains(key) else {
            print("Unknown key: \(key)")
            print("Run \u{1B}[1mzyquo config list\u{1B}[0m to see all available keys.")
            throw ExitCode(rawValue: 3)
        }

        // Validate and coerce the value
        guard let coerced = ConfigKeys.coerce(value, forKey: key) else {
            let expected = ConfigKeys.expectedType(forKey: key)
            print("Invalid value \"\(value)\" for key \"\(key)\" (expected \(expected))")
            throw ExitCode(rawValue: 3)
        }

        if workspace {
            try setWorkspaceConfig(key: key, value: coerced)
        } else {
            try setUserConfig(key: key, value: coerced)
        }
    }

    // MARK: - User config (TOML)

    private func setUserConfig(key: String, value: ConfigValue) throws {
        let fm = FileManager.default
        let zyquoDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
        let configPath = zyquoDir.appendingPathComponent("config.toml")

        // Ensure directory exists
        if !fm.fileExists(atPath: zyquoDir.path) {
            try fm.createDirectory(at: zyquoDir, withIntermediateDirectories: true)
        }

        // Load existing TOML or create empty table
        let table: TOMLTable
        if let content = try? String(contentsOf: configPath, encoding: .utf8),
           let parsed = try? TOMLTable(string: content) {
            table = parsed
        } else {
            table = TOMLTable()
        }

        // Parse key into section.field (e.g. "ui.theme" -> "ui", "theme")
        // Nested sections like "providers.anthropic.default_model" -> "providers", "anthropic", "default_model"
        let parts = key.split(separator: ".").map(String.init)
        guard parts.count >= 2 else {
            print("Key must be in section.field format (e.g. ui.theme)")
            throw ExitCode(rawValue: 3)
        }

        // Navigate/create nested tables and set the value
        setTOMLValue(table: table, keyParts: parts, value: value)

        // Write back
        let output = table.convert(to: .toml)
        try output.write(to: configPath, atomically: true, encoding: .utf8)

        print("  Set \(key) = \(value.displayString) in \(configPath.path)")
    }

    private func setTOMLValue(table: TOMLTable, keyParts: [String], value: ConfigValue) {
        var current = table
        // Navigate/create intermediate tables
        for i in 0 ..< keyParts.count - 1 {
            let section = keyParts[i]
            if let existing = current[section]?.table {
                current = existing
            } else {
                let newTable = TOMLTable()
                current[section] = newTable
                current = newTable
            }
        }
        // Set the leaf value using TOMLValueConvertible conformances
        let field = keyParts[keyParts.count - 1]
        switch value {
        case .string(let s): current[field] = s
        case .int(let n):    current[field] = n
        case .double(let d): current[field] = d
        case .bool(let b):   current[field] = b
        }
    }

    // MARK: - Workspace config (JSON)

    private func setWorkspaceConfig(key: String, value: ConfigValue) throws {
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let zyquoDir = root.appendingPathComponent(".zyquo")
        let configPath = zyquoDir.appendingPathComponent("config.json")
        let fm = FileManager.default

        // Ensure directory exists
        if !fm.fileExists(atPath: zyquoDir.path) {
            try fm.createDirectory(at: zyquoDir, withIntermediateDirectories: true)
        }

        // Load existing JSON or create empty dict
        var dict: [String: Any]
        if let data = try? Data(contentsOf: configPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = existing
        } else {
            dict = ["version": 1]
        }

        // Parse key into parts and set nested value
        let parts = key.split(separator: ".").map(String.init)
        guard parts.count >= 2 else {
            print("Key must be in section.field format (e.g. ui.theme)")
            throw ExitCode(rawValue: 3)
        }

        setJSONValue(dict: &dict, keyParts: parts, value: value)

        // Write back
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configPath, options: .atomic)

        print("  Set \(key) = \(value.displayString) in \(configPath.path)")
    }

    private func setJSONValue(dict: inout [String: Any], keyParts: [String], value: ConfigValue) {
        if keyParts.count == 1 {
            dict[keyParts[0]] = value.jsonValue
            return
        }

        let section = keyParts[0]
        var sub = dict[section] as? [String: Any] ?? [:]
        let remaining = Array(keyParts.dropFirst())
        setJSONValue(dict: &sub, keyParts: remaining, value: value)
        dict[section] = sub
    }
}

// MARK: - config list

struct ConfigList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Show all configuration values with their source"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    func run() async throws {
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let config = Config(flags: globals.flags)
        let noColor = config.ui.noColor

        // Load raw sources for attribution
        let userConfigPath = Config.defaultUserConfigPath
        let userDict = Config.loadUserConfig(at: userConfigPath)
        let workspaceConfigPath = root
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("config.json")
        let workspaceDict = Config.loadWorkspaceConfig(
            at: FileManager.default.fileExists(atPath: workspaceConfigPath.path)
                ? workspaceConfigPath : nil
        )
        let env = ProcessInfo.processInfo.environment
        let flags = globals.flags

        let bold = noColor ? "" : "\u{1B}[1m"
        let dim = noColor ? "" : "\u{1B}[2m"
        let cyan = noColor ? "" : "\u{1B}[36m"
        let green = noColor ? "" : "\u{1B}[32m"
        let yellow = noColor ? "" : "\u{1B}[33m"
        let blue = noColor ? "" : "\u{1B}[34m"
        let magenta = noColor ? "" : "\u{1B}[35m"
        let reset = noColor ? "" : "\u{1B}[0m"

        print()
        print("  \(bold)Zyquo Configuration\(reset)")
        print("  \(dim)Precedence: flag > env > workspace > user > default\(reset)")
        print()

        let sections: [(title: String, keys: [(key: String, value: String, source: String)])] = [
            ("ui", [
                configEntry("ui.theme", config.ui.theme,
                            flagValue: nil,
                            envKey: nil, env: env,
                            workspacePath: ["ui", "theme"], workspace: workspaceDict,
                            userPath: ["ui", "theme"], user: userDict),
                configEntry("ui.animations", String(config.ui.animations),
                            flagValue: nil,
                            envKey: nil, env: env,
                            workspacePath: ["ui", "animations"], workspace: workspaceDict,
                            userPath: ["ui", "animations"], user: userDict),
                configEntry("ui.unicode_borders", String(config.ui.unicodeBorders),
                            flagValue: nil,
                            envKey: nil, env: env,
                            workspacePath: ["ui", "unicode_borders"], workspace: workspaceDict,
                            userPath: ["ui", "unicode_borders"], user: userDict),
            ]),
            ("agent", [
                configEntry("agent.max_steps", String(config.agent.maxSteps),
                            flagValue: flags.maxSteps.map { String($0) },
                            envKey: "ZYQUO_MAX_STEPS", env: env,
                            workspacePath: ["agent", "max_steps"], workspace: workspaceDict,
                            userPath: ["agent", "max_steps"], user: userDict),
                configEntry("agent.max_cost_usd", String(config.agent.maxCostUSD),
                            flagValue: flags.maxCost.map { String($0) },
                            envKey: "ZYQUO_MAX_COST", env: env,
                            workspacePath: ["agent", "max_cost_usd"], workspace: workspaceDict,
                            userPath: ["agent", "max_cost_usd"], user: userDict),
                configEntry("agent.auto_approve_safe", String(config.agent.autoApproveSafe),
                            flagValue: flags.yes ? "true" : nil,
                            envKey: nil, env: env,
                            workspacePath: ["agent", "auto_approve_safe"], workspace: workspaceDict,
                            userPath: ["agent", "auto_approve_safe"], user: userDict),
            ]),
            ("providers", [
                configEntry("providers.default", config.providers.defaultProvider,
                            flagValue: flags.provider,
                            envKey: nil, env: env,
                            workspacePath: ["provider"], workspace: workspaceDict,
                            userPath: ["providers", "default"], user: userDict),
                configEntry("providers.anthropic.default_model", config.providers.defaultModel,
                            flagValue: flags.model,
                            envKey: nil, env: env,
                            workspacePath: ["model"], workspace: workspaceDict,
                            userPath: ["providers", "anthropic", "default_model"], user: userDict),
            ]),
            ("shell", [
                configEntry("shell.default", config.shell.defaultShell,
                            flagValue: nil,
                            envKey: nil, env: env,
                            workspacePath: ["shell", "default"], workspace: workspaceDict,
                            userPath: ["shell", "default"], user: userDict),
                configEntry("shell.load_profile", String(config.shell.loadProfile),
                            flagValue: nil,
                            envKey: nil, env: env,
                            workspacePath: ["shell", "load_profile"], workspace: workspaceDict,
                            userPath: ["shell", "load_profile"], user: userDict),
                configEntry("shell.timeout_s", String(config.shell.timeoutSeconds),
                            flagValue: nil,
                            envKey: nil, env: env,
                            workspacePath: ["shell", "timeout_s"], workspace: workspaceDict,
                            userPath: ["shell", "timeout_s"], user: userDict),
            ]),
            ("memory", [
                configEntry("memory.compress_threshold_pct", String(config.memory.compressThresholdPct),
                            flagValue: nil,
                            envKey: nil, env: env,
                            workspacePath: ["memory", "compress_threshold_pct"], workspace: workspaceDict,
                            userPath: ["memory", "compress_threshold_pct"], user: userDict),
                configEntry("memory.keep_decisions_verbatim", String(config.memory.keepDecisionsVerbatim),
                            flagValue: nil,
                            envKey: nil, env: env,
                            workspacePath: ["memory", "keep_decisions_verbatim"], workspace: workspaceDict,
                            userPath: ["memory", "keep_decisions_verbatim"], user: userDict),
            ]),
        ]

        for section in sections {
            print("  \(bold)[\(section.title)]\(reset)")
            for entry in section.keys {
                let sourceTag: String
                switch entry.source {
                case "flag":      sourceTag = "\(green)flag\(reset)"
                case "env":       sourceTag = "\(yellow)env\(reset)"
                case "workspace": sourceTag = "\(blue)workspace\(reset)"
                case "user":      sourceTag = "\(magenta)user\(reset)"
                default:          sourceTag = "\(dim)default\(reset)"
                }
                let padding = String(repeating: " ", count: max(1, 40 - entry.key.count))
                print("    \(cyan)\(entry.key)\(reset)\(padding)= \(entry.value)  \(dim)(\(sourceTag)\(dim))\(reset)")
            }
            print()
        }

        // Show file paths
        print("  \(dim)Config files:\(reset)")
        print("    \(dim)User:      \(userConfigPath.path)\(reset)")
        print("    \(dim)Workspace: \(workspaceConfigPath.path)\(reset)")
        print()
    }

    private func configEntry(
        _ key: String,
        _ resolvedValue: String,
        flagValue: String?,
        envKey: String?,
        env: [String: String],
        workspacePath: [String],
        workspace: [String: Any],
        userPath: [String],
        user: [String: Any]
    ) -> (key: String, value: String, source: String) {
        // Determine the source that provided the resolved value
        let source: String
        if flagValue != nil {
            source = "flag"
        } else if let envKey, env[envKey] != nil {
            source = "env"
        } else if lookupNested(workspace, path: workspacePath) != nil {
            source = "workspace"
        } else if lookupNested(user, path: userPath) != nil {
            source = "user"
        } else {
            source = "default"
        }
        return (key: key, value: resolvedValue, source: source)
    }

    private func lookupNested(_ dict: [String: Any], path: [String]) -> Any? {
        guard !path.isEmpty else { return nil }
        if path.count == 1 {
            return dict[path[0]]
        }
        guard let sub = dict[path[0]] as? [String: Any] else { return nil }
        return lookupNested(sub, path: Array(path.dropFirst()))
    }
}

// MARK: - Config Key Registry

private enum ConfigKeys {

    /// All known config keys.
    static let allKeys: Set<String> = [
        "ui.theme",
        "ui.animations",
        "ui.unicode_borders",
        "agent.max_steps",
        "agent.max_cost_usd",
        "agent.auto_approve_safe",
        "providers.default",
        "providers.anthropic.default_model",
        "shell.default",
        "shell.load_profile",
        "shell.timeout_s",
        "memory.compress_threshold_pct",
        "memory.keep_decisions_verbatim",
    ]

    /// Resolve a config key to its current value from the resolved Config.
    static func resolve(_ key: String, config: Config) -> String? {
        switch key {
        case "ui.theme":                        return config.ui.theme
        case "ui.animations":                   return String(config.ui.animations)
        case "ui.unicode_borders":              return String(config.ui.unicodeBorders)
        case "agent.max_steps":                 return String(config.agent.maxSteps)
        case "agent.max_cost_usd":              return String(config.agent.maxCostUSD)
        case "agent.auto_approve_safe":         return String(config.agent.autoApproveSafe)
        case "providers.default":               return config.providers.defaultProvider
        case "providers.anthropic.default_model": return config.providers.defaultModel
        case "shell.default":                   return config.shell.defaultShell
        case "shell.load_profile":              return String(config.shell.loadProfile)
        case "shell.timeout_s":                 return String(config.shell.timeoutSeconds)
        case "memory.compress_threshold_pct":   return String(config.memory.compressThresholdPct)
        case "memory.keep_decisions_verbatim":  return String(config.memory.keepDecisionsVerbatim)
        default:                                return nil
        }
    }

    /// Expected type description for a key (used in error messages).
    static func expectedType(forKey key: String) -> String {
        switch key {
        case "ui.theme", "providers.default", "providers.anthropic.default_model",
             "shell.default":
            return "string"
        case "ui.animations", "ui.unicode_borders", "agent.auto_approve_safe",
             "shell.load_profile", "memory.keep_decisions_verbatim":
            return "bool (true/false)"
        case "agent.max_steps", "shell.timeout_s", "memory.compress_threshold_pct":
            return "integer"
        case "agent.max_cost_usd":
            return "number"
        default:
            return "string"
        }
    }

    /// Coerce a string value into the appropriate typed ConfigValue for the given key.
    /// Returns nil if the value cannot be coerced to the expected type.
    static func coerce(_ value: String, forKey key: String) -> ConfigValue? {
        switch key {
        // String keys
        case "ui.theme", "providers.default", "providers.anthropic.default_model",
             "shell.default":
            return .string(value)

        // Bool keys
        case "ui.animations", "ui.unicode_borders", "agent.auto_approve_safe",
             "shell.load_profile", "memory.keep_decisions_verbatim":
            switch value.lowercased() {
            case "true", "1", "yes":  return .bool(true)
            case "false", "0", "no":  return .bool(false)
            default: return nil
            }

        // Int keys
        case "agent.max_steps", "shell.timeout_s", "memory.compress_threshold_pct":
            guard let n = Int(value) else { return nil }
            return .int(n)

        // Double keys
        case "agent.max_cost_usd":
            guard let d = Double(value) else { return nil }
            return .double(d)

        default:
            return .string(value)
        }
    }
}

// MARK: - ConfigValue

/// A typed configuration value used for writing to TOML/JSON.
private enum ConfigValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    var displayString: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .int(let n):    return String(n)
        case .double(let d): return String(d)
        case .bool(let b):   return String(b)
        }
    }

    var jsonValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let n):    return n
        case .double(let d): return d
        case .bool(let b):   return b
        }
    }
}

