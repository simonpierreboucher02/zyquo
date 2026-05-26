import Foundation

// MARK: - SubAgentType Protocol

/// A specialized agent type with a constrained tool set and risk ceiling.
///
/// Each SubAgentType defines what tools the agent is allowed to use,
/// what risk level it cannot exceed, and how many steps it may take.
/// The Orchestrator selects the appropriate agent type for each subtask.
///
/// Reference: CLAUDE.md §24
public protocol SubAgentType: Sendable {
    /// Stable identifier, e.g. "architect", "coder".
    var id: String { get }
    /// Human-readable display name.
    var displayName: String { get }
    /// One-sentence description of the agent's role.
    var description: String { get }
    /// The set of tool names this agent is permitted to invoke.
    var allowedTools: Set<String> { get }
    /// The specialized system prompt for this agent type.
    var systemPrompt: String { get }
    /// Maximum number of steps this agent may execute per subtask.
    var maxSteps: Int { get }
    /// The highest risk tier this agent is allowed to reach.
    var riskCeiling: RiskLevel { get }
}

// MARK: - Tool Whitelist Enforcement

extension SubAgentType {
    /// Check whether a tool call is permitted by this agent's whitelist.
    ///
    /// Uses prefix matching so that "memory.*" allows "memory.read",
    /// "memory.write", etc.
    public func isToolAllowed(_ toolName: String) -> Bool {
        // Direct match
        if allowedTools.contains(toolName) {
            return true
        }
        // Wildcard match: "memory.*" allows "memory.read", "memory.write", etc.
        for pattern in allowedTools {
            if pattern.hasSuffix(".*") {
                let prefix = String(pattern.dropLast(2)) + "."
                if toolName.hasPrefix(prefix) {
                    return true
                }
            }
        }
        return false
    }

    /// Check whether a risk level is within this agent's ceiling.
    public func isRiskAllowed(_ risk: RiskLevel) -> Bool {
        risk <= riskCeiling
    }
}

// MARK: - ArchitectAgent

/// Long-horizon design, ADRs, structural analysis.
/// Read-only with planning capabilities; cannot modify files.
public struct ArchitectAgent: SubAgentType {
    public let id = "architect"
    public let displayName = "Architect Agent"
    public let description = "Long-horizon design, ADRs, structural refactors and analysis"
    public let allowedTools: Set<String> = [
        "file.read", "file.search", "file.list",
        "memory.*",
        "workspace.*",
        "task.plan",
    ]
    public let systemPrompt = AgentPrompts.architectSystem
    public let maxSteps = 20
    public let riskCeiling: RiskLevel = .safe

    public init() {}
}

// MARK: - CoderAgent

/// Per-task implementation agent with access to all V1 tools.
/// Can read, write, patch, and execute shell commands.
public struct CoderAgent: SubAgentType {
    public let id = "coder"
    public let displayName = "Coder Agent"
    public let description = "Per-task implementation, narrow scope, fast loop"
    public let allowedTools: Set<String> = [
        "shell.run", "shell.cancel", "shell.history", "shell.which",
        "file.read", "file.write", "file.patch", "file.list",
        "file.tree", "file.stat", "file.glob", "file.search",
        "file.checksum", "file.diff", "file.touch", "file.move",
        "file.copy", "file.delete",
        "git.*",
        "memory.*",
        "workspace.*",
        "task.*",
        "notify.user", "ask.user",
        "present.*",
        "code.format", "code.lint",
        "build.run", "test.run", "lint.run", "format.run",
        "package.install", "package.add", "package.remove",
        "log.*", "trace.*", "metrics.*", "cost.*",
    ]
    public let systemPrompt = AgentPrompts.coderSystem
    public let maxSteps = 30
    public let riskCeiling: RiskLevel = .moderate

    public init() {}
}

// MARK: - ShellAgent

/// Build, test, and CI orchestration specialist.
public struct ShellAgent: SubAgentType {
    public let id = "shell"
    public let displayName = "Shell Agent"
    public let description = "Build/test/CI orchestration and shell command execution"
    public let allowedTools: Set<String> = [
        "shell.run", "shell.cancel", "shell.history", "shell.which",
        "file.read",
        "git.*",
    ]
    public let systemPrompt = AgentPrompts.shellSystem
    public let maxSteps = 25
    public let riskCeiling: RiskLevel = .moderate

    public init() {}
}

// MARK: - ReviewerAgent

/// Code review agent. Read-only: inspects diffs and files.
public struct ReviewerAgent: SubAgentType {
    public let id = "reviewer"
    public let displayName = "Reviewer Agent"
    public let description = "Diff review, style, conventions, regression scanning"
    public let allowedTools: Set<String> = [
        "file.read", "file.search", "file.list",
        "git.diff",
    ]
    public let systemPrompt = AgentPrompts.reviewerSystem
    public let maxSteps = 15
    public let riskCeiling: RiskLevel = .safe

    public init() {}
}

// MARK: - ResearchAgent

/// Documentation and knowledge extraction. Read-only.
public struct ResearchAgent: SubAgentType {
    public let id = "research"
    public let displayName = "Research Agent"
    public let description = "Doc search, citation, knowledge extraction"
    public let allowedTools: Set<String> = [
        "file.read", "file.search", "file.list",
        "memory.*",
    ]
    public let systemPrompt = AgentPrompts.researchSystem
    public let maxSteps = 20
    public let riskCeiling: RiskLevel = .safe

    public init() {}
}

// MARK: - VerifierAgent

/// Test execution and verification. Can run shell commands to test.
public struct VerifierAgent: SubAgentType {
    public let id = "verifier"
    public let displayName = "Verifier Agent"
    public let description = "Test execution, output parsing, success/failure proof"
    public let allowedTools: Set<String> = [
        "shell.run",
        "file.read", "file.list",
    ]
    public let systemPrompt = AgentPrompts.verifierAgentSystem
    public let maxSteps = 15
    public let riskCeiling: RiskLevel = .moderate

    public init() {}
}

// MARK: - Agent Registry

/// Registry of all available sub-agent types.
public enum SubAgentRegistry {
    /// All built-in agent types.
    public static let allAgents: [any SubAgentType] = [
        ArchitectAgent(),
        CoderAgent(),
        ShellAgent(),
        ReviewerAgent(),
        ResearchAgent(),
        VerifierAgent(),
    ]

    /// Find an agent type by its identifier.
    public static func find(id: String) -> (any SubAgentType)? {
        allAgents.first { $0.id == id }
    }
}
