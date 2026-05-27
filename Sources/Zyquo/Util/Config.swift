import Foundation
import TOMLKit

public struct Config: Sendable {
    public let ui: UIConfig
    public let agent: AgentConfig
    public let providers: ProvidersConfig
    public let shell: ShellConfig
    public let memory: MemoryConfig

    public init(
        flags: CommandFlags = .init(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workspaceConfigPath: URL? = nil,
        userConfigPath: URL? = nil
    ) {
        let workspaceConfig = Self.loadWorkspaceConfig(at: workspaceConfigPath)
        let userConfig = Self.loadUserConfig(at: userConfigPath ?? Self.defaultUserConfigPath)

        self.ui = UIConfig(flags: flags, env: environment, workspace: workspaceConfig, user: userConfig)
        self.agent = AgentConfig(flags: flags, env: environment, workspace: workspaceConfig, user: userConfig)
        self.providers = ProvidersConfig(flags: flags, env: environment, workspace: workspaceConfig, user: userConfig)
        self.shell = ShellConfig(flags: flags, env: environment, workspace: workspaceConfig, user: userConfig)
        self.memory = MemoryConfig(flags: flags, env: environment, workspace: workspaceConfig, user: userConfig)
    }

    static let defaultUserConfigPath: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("config.toml")
    }()

    static func loadWorkspaceConfig(at path: URL?) -> [String: Any] {
        guard let path, let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    static func loadUserConfig(at path: URL) -> [String: Any] {
        guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [:] }
        guard let table = try? TOMLTable(string: content) else { return [:] }
        return Self.tomlToDict(table)
    }

    private static func tomlToDict(_ table: TOMLTable) -> [String: Any] {
        var dict: [String: Any] = [:]
        for (key, value) in table {
            switch value {
            case let s as String: dict[key] = s
            case let i as Int: dict[key] = i
            case let d as Double: dict[key] = d
            case let b as Bool: dict[key] = b
            case let t as TOMLTable: dict[key] = tomlToDict(t)
            default: dict[key] = String(describing: value)
            }
        }
        return dict
    }
}

public struct CommandFlags: Sendable {
    public var workspace: String?
    public var noColor: Bool
    public var json: Bool
    public var yes: Bool
    public var dryRun: Bool
    public var model: String?
    public var provider: String?
    public var maxSteps: Int?
    public var maxCost: Double?
    public var verbose: Bool
    public var quiet: Bool
    public var logFile: String?

    public init(
        workspace: String? = nil,
        noColor: Bool = false,
        json: Bool = false,
        yes: Bool = false,
        dryRun: Bool = false,
        model: String? = nil,
        provider: String? = nil,
        maxSteps: Int? = nil,
        maxCost: Double? = nil,
        verbose: Bool = false,
        quiet: Bool = false,
        logFile: String? = nil
    ) {
        self.workspace = workspace
        self.noColor = noColor
        self.json = json
        self.yes = yes
        self.dryRun = dryRun
        self.model = model
        self.provider = provider
        self.maxSteps = maxSteps
        self.maxCost = maxCost
        self.verbose = verbose
        self.quiet = quiet
        self.logFile = logFile
    }
}

public struct UIConfig: Sendable {
    public let theme: String
    public let animations: Bool
    public let unicodeBorders: Bool
    public let noColor: Bool

    init(flags: CommandFlags, env: [String: String], workspace: [String: Any], user: [String: Any]) {
        let uiSection = user["ui"] as? [String: Any] ?? [:]
        self.noColor = flags.noColor || env["NO_COLOR"] != nil
        self.theme = uiSection["theme"] as? String ?? "zyquo-dark"
        self.animations = uiSection["animations"] as? Bool ?? true
        self.unicodeBorders = uiSection["unicode_borders"] as? Bool ?? true
    }
}

public struct AgentConfig: Sendable {
    public let maxSteps: Int
    public let maxCostUSD: Double
    public let autoApproveSafe: Bool

    init(flags: CommandFlags, env: [String: String], workspace: [String: Any], user: [String: Any]) {
        let agentSection = user["agent"] as? [String: Any] ?? [:]
        self.maxSteps = flags.maxSteps
            ?? (env["ZYQUO_MAX_STEPS"].flatMap(Int.init))
            ?? agentSection["max_steps"] as? Int
            ?? 40
        self.maxCostUSD = flags.maxCost
            ?? (env["ZYQUO_MAX_COST"].flatMap(Double.init))
            ?? agentSection["max_cost_usd"] as? Double
            ?? 5.0
        self.autoApproveSafe = flags.yes || (agentSection["auto_approve_safe"] as? Bool ?? true)
    }
}

public struct ProvidersConfig: Sendable {
    public let defaultProvider: String
    public let defaultModel: String
    public let overrideProvider: String?
    public let overrideModel: String?

    init(flags: CommandFlags, env: [String: String], workspace: [String: Any], user: [String: Any]) {
        let provSection = user["providers"] as? [String: Any] ?? [:]
        let anthSection = provSection["anthropic"] as? [String: Any] ?? [:]

        self.overrideProvider = flags.provider
        self.overrideModel = flags.model
        self.defaultProvider = workspace["provider"] as? String
            ?? provSection["default"] as? String
            ?? "anthropic"
        self.defaultModel = workspace["model"] as? String
            ?? anthSection["default_model"] as? String
            ?? "claude-sonnet-4-6"
    }

    public var resolvedProvider: String { overrideProvider ?? defaultProvider }
    public var resolvedModel: String { overrideModel ?? defaultModel }
}

public struct ShellConfig: Sendable {
    public let defaultShell: String
    public let loadProfile: Bool
    public let timeoutSeconds: Int

    init(flags: CommandFlags, env: [String: String], workspace: [String: Any], user: [String: Any]) {
        let shellSection = user["shell"] as? [String: Any] ?? [:]
        self.defaultShell = shellSection["default"] as? String ?? "/bin/zsh"
        self.loadProfile = shellSection["load_profile"] as? Bool ?? false
        self.timeoutSeconds = shellSection["timeout_s"] as? Int ?? 120
    }
}

public struct MemoryConfig: Sendable {
    public let compressThresholdPct: Int
    public let keepDecisionsVerbatim: Bool

    init(flags: CommandFlags, env: [String: String], workspace: [String: Any], user: [String: Any]) {
        let memSection = user["memory"] as? [String: Any] ?? [:]
        self.compressThresholdPct = memSection["compress_threshold_pct"] as? Int ?? 70
        self.keepDecisionsVerbatim = memSection["keep_decisions_verbatim"] as? Bool ?? true
    }
}
