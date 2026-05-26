import Foundation

public enum ZyquoError: Error, Sendable, CustomStringConvertible {
    case config(ConfigError)
    case provider(ProviderError)
    case tool(ToolError)
    case shell(ShellError)
    case workspace(WorkspaceError)
    case persistence(PersistenceError)
    case approval(ApprovalError)
    case risk(RiskError)
    case plugin(PluginError)
    case cancelled
    case userExit

    public var description: String {
        switch self {
        case .config(let e): return e.description
        case .provider(let e): return e.description
        case .tool(let e): return e.description
        case .shell(let e): return e.description
        case .workspace(let e): return e.description
        case .persistence(let e): return e.description
        case .approval(let e): return e.description
        case .risk(let e): return e.description
        case .plugin(let e): return e.description
        case .cancelled: return "Operation cancelled"
        case .userExit: return "User exit"
        }
    }

    public var exitCode: Int32 {
        switch self {
        case .config: return 3
        case .provider: return 4
        case .tool: return 5
        case .shell: return 5
        case .workspace: return 8
        case .persistence: return 9
        case .approval: return 6
        case .risk: return 7
        case .plugin: return 10
        case .cancelled: return 130
        case .userExit: return 0
        }
    }
}

public struct ConfigError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }

    public static func missing(key: String) -> ConfigError {
        ConfigError(
            code: "config.missing_key",
            description: "Configuration key '\(key)' is not set",
            remediation: "Run `zyquo config set \(key) <value>` or set the corresponding environment variable"
        )
    }

    public static func invalid(key: String, value: String) -> ConfigError {
        ConfigError(
            code: "config.invalid_value",
            description: "Invalid value '\(value)' for configuration key '\(key)'",
            remediation: "Check `zyquo config get \(key)` for accepted values"
        )
    }
}

public struct ProviderError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }

    public static func authMissing(provider: String) -> ProviderError {
        ProviderError(
            code: "provider.auth_missing",
            description: "No API key found for provider '\(provider)'",
            remediation: "Run `zyquo provider login \(provider)` to store your API key in Keychain"
        )
    }

    public static func rateLimited(provider: String, retryAfter: Int?) -> ProviderError {
        let retry = retryAfter.map { " Retry after \($0)s." } ?? ""
        return ProviderError(
            code: "provider.rate_limited",
            description: "Rate limited by \(provider).\(retry)",
            remediation: "Wait and retry, or switch provider with `--provider openrouter`"
        )
    }

    public static func networkError(_ error: any Error) -> ProviderError {
        ProviderError(
            code: "provider.network",
            description: "Network error: \(error.localizedDescription)",
            remediation: "Check your internet connection and try again",
            underlying: error
        )
    }
}

public struct ToolError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }

    public static func unknownTool(_ name: String) -> ToolError {
        ToolError(
            code: "tool.unknown",
            description: "Unknown tool '\(name)'",
            remediation: "Run `zyquo tools list` to see available tools"
        )
    }

    public static func missingDependency(_ binary: String, installHint: String) -> ToolError {
        ToolError(
            code: "tool.missing_dep",
            description: "Required binary '\(binary)' not found",
            remediation: installHint
        )
    }
}

public struct ShellError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }

    public static func timeout(command: String, seconds: Int) -> ShellError {
        ShellError(
            code: "shell.timeout",
            description: "Command timed out after \(seconds)s: \(command.prefix(80))",
            remediation: "Increase timeout or simplify the command"
        )
    }

    public static func nonZeroExit(command: String, code: Int32) -> ShellError {
        ShellError(
            code: "shell.exit_\(code)",
            description: "Command exited with code \(code): \(command.prefix(80))",
            remediation: "Check the command output for error details"
        )
    }
}

public struct WorkspaceError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }

    public static func boundaryViolation(path: String) -> WorkspaceError {
        WorkspaceError(
            code: "workspace.boundary",
            description: "Path '\(path)' is outside workspace boundary",
            remediation: "Only operate on files within the workspace root"
        )
    }
}

public struct PersistenceError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }
}

public struct ApprovalError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }

    public static let denied = ApprovalError(
        code: "approval.denied",
        description: "User denied the proposed action",
        remediation: "Modify the approach or grant trust via /trust"
    )
}

public struct RiskError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }

    public static func budgetExceeded(cost: Double, limit: Double) -> RiskError {
        RiskError(
            code: "risk.budget_exceeded",
            description: "Session cost $\(String(format: "%.2f", cost)) exceeds limit $\(String(format: "%.2f", limit))",
            remediation: "Increase --max-cost or start a new session"
        )
    }
}

public struct PluginError: Error, Sendable, CustomStringConvertible {
    public let code: String
    public let description: String
    public let remediation: String
    public let underlying: (any Error)?

    public init(code: String, description: String, remediation: String, underlying: (any Error)? = nil) {
        self.code = code
        self.description = description
        self.remediation = remediation
        self.underlying = underlying
    }
}
