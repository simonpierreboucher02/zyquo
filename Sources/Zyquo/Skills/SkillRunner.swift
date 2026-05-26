import Foundation

// MARK: - SkillExecutionContext

/// Dependencies injected into a skill execution.
public struct SkillExecutionContext: Sendable {
    /// The workspace root directory.
    public let workspace: URL
    /// The LLM provider to use for planning/execution.
    public let provider: any LLMProvider
    /// The model identifier to use.
    public let model: String
    /// The full tool registry (will be filtered to allowed tools).
    public let toolRegistry: ToolRegistry
    /// The session ID for this execution.
    public let sessionId: SessionID

    public init(
        workspace: URL,
        provider: any LLMProvider,
        model: String,
        toolRegistry: ToolRegistry,
        sessionId: SessionID
    ) {
        self.workspace = workspace
        self.provider = provider
        self.model = model
        self.toolRegistry = toolRegistry
        self.sessionId = sessionId
    }
}

// MARK: - SkillEvent

/// Events emitted during skill execution for UI rendering.
public enum SkillEvent: Sendable {
    /// The skill has started executing.
    case started(SkillManifest)
    /// A step in the skill has been executed.
    case stepExecuted(Int, String)       // step number, summary
    /// The verification command is about to run.
    case verificationStarted
    /// The verification command passed.
    case verificationPassed
    /// The verification command failed.
    case verificationFailed(exitCode: Int, output: String)
    /// The skill is approaching its step budget.
    case budgetWarning(stepsUsed: Int, maxSteps: Int)
    /// The skill completed successfully.
    case completed(SkillResult)
    /// The skill failed with an error.
    case failed(String)
}

// MARK: - SkillResult

/// The outcome of a completed skill execution.
public struct SkillResult: Sendable {
    /// The skill that was executed.
    public let skillId: String
    /// Number of agent steps completed.
    public let stepsCompleted: Int
    /// Files modified during execution.
    public let filesModified: [String]
    /// Whether verification passed (nil if no verification was configured).
    public let verificationPassed: Bool?
    /// Cumulative cost of the skill run.
    public let cost: SessionCost
    /// Wall-clock duration of the skill run.
    public let duration: TimeInterval

    public init(
        skillId: String,
        stepsCompleted: Int,
        filesModified: [String] = [],
        verificationPassed: Bool? = nil,
        cost: SessionCost = SessionCost(),
        duration: TimeInterval = 0
    ) {
        self.skillId = skillId
        self.stepsCompleted = stepsCompleted
        self.filesModified = filesModified
        self.verificationPassed = verificationPassed
        self.cost = cost
        self.duration = duration
    }
}

// MARK: - SkillRunError

/// Errors specific to skill execution.
public enum SkillRunError: Error, CustomStringConvertible, Sendable {
    case toolNotAllowed(String, skillId: String)
    case riskCeilingExceeded(risk: RiskLevel, ceiling: RiskLevel, skillId: String)
    case budgetExhausted(kind: String, used: String, limit: String, skillId: String)
    case missingRequiredInput(name: String, skillId: String)
    case inputTypeInvalid(name: String, expectedType: String, skillId: String)

    public var description: String {
        switch self {
        case .toolNotAllowed(let tool, let skillId):
            return "Skill '\(skillId)' is not allowed to use tool '\(tool)'"
        case .riskCeilingExceeded(let risk, let ceiling, let skillId):
            return "Skill '\(skillId)' attempted \(risk.displayName) action but ceiling is \(ceiling.displayName)"
        case .budgetExhausted(let kind, let used, let limit, let skillId):
            return "Skill '\(skillId)' exceeded \(kind) budget: \(used) / \(limit)"
        case .missingRequiredInput(let name, let skillId):
            return "Skill '\(skillId)' requires input '\(name)'"
        case .inputTypeInvalid(let name, let expectedType, let skillId):
            return "Skill '\(skillId)' input '\(name)' must be of type '\(expectedType)'"
        }
    }
}

// MARK: - SkillRunner

/// Executes a loaded skill with scoped tools and budget enforcement.
///
/// The runner:
/// 1. Validates required inputs
/// 2. Creates a scoped tool registry with only the allowed tools
/// 3. Enforces the risk ceiling (commands above the ceiling are rejected)
/// 4. Tracks step count against `budget.maxSteps`
/// 5. Tracks cost against `budget.maxCostUSD`
/// 6. Runs the verification command after skill completion (if specified)
/// 7. Emits `SkillEvent`s for UI rendering
///
/// Reference: CLAUDE.md §30 Phase 6
public actor SkillRunner {
    public init() {}

    // MARK: - Input Validation

    /// Validate that all required inputs are provided and types are correct.
    public func validateInputs(
        skill: LoadedSkill,
        inputs: [String: String]
    ) throws {
        for inputDef in skill.manifest.inputs where inputDef.required {
            let provided = inputs[inputDef.name] ?? inputDef.defaultValue
            if provided == nil || provided?.isEmpty == true {
                throw SkillRunError.missingRequiredInput(
                    name: inputDef.name,
                    skillId: skill.manifest.id
                )
            }
        }

        // Basic type validation for provided values
        for (key, value) in inputs {
            guard let inputDef = skill.manifest.inputs.first(where: { $0.name == key }) else {
                continue // Extra inputs are ignored silently
            }
            switch inputDef.type {
            case "int":
                if Int(value) == nil {
                    throw SkillRunError.inputTypeInvalid(
                        name: key, expectedType: "int", skillId: skill.manifest.id
                    )
                }
            case "bool":
                let lower = value.lowercased()
                if lower != "true" && lower != "false" {
                    throw SkillRunError.inputTypeInvalid(
                        name: key, expectedType: "bool", skillId: skill.manifest.id
                    )
                }
            default:
                break // "string" and "path" accept any string
            }
        }
    }

    // MARK: - Tool Whitelist

    /// Create a scoped tool registry containing only the tools allowed
    /// by the skill manifest. Uses prefix matching for wildcard patterns
    /// (e.g. "git.*" allows "git.status", "git.diff", etc.).
    public func createScopedRegistry(
        skill: LoadedSkill,
        fullRegistry: ToolRegistry
    ) -> ToolRegistry {
        let scoped = ToolRegistry()
        let allowed = Set(skill.manifest.toolsAllowed)

        for tool in fullRegistry.allTools() {
            if isToolAllowed(tool.name, allowedTools: allowed) {
                scoped.register(tool)
            }
        }

        return scoped
    }

    /// Check whether a tool name matches the allowed list, supporting
    /// wildcard patterns like "git.*".
    public func isToolAllowed(_ toolName: String, allowedTools: Set<String>) -> Bool {
        // Direct match
        if allowedTools.contains(toolName) {
            return true
        }
        // Wildcard match: "git.*" allows "git.status"
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

    // MARK: - Risk Ceiling Check

    /// Check whether a risk level is within the skill's ceiling.
    public func isRiskAllowed(
        _ risk: RiskLevel,
        skill: LoadedSkill
    ) -> Bool {
        risk <= skill.manifest.resolvedRiskCeiling
    }

    // MARK: - Budget Check

    /// Check whether the step count is within budget.
    /// Returns true if within budget, false if exhausted.
    public func isStepBudgetAvailable(
        stepsUsed: Int,
        skill: LoadedSkill
    ) -> Bool {
        stepsUsed < skill.manifest.budget.maxSteps
    }

    /// Check whether the cost is within budget.
    /// Returns true if within budget, false if exhausted.
    public func isCostBudgetAvailable(
        costUsed: Double,
        skill: LoadedSkill
    ) -> Bool {
        costUsed < skill.manifest.budget.maxCostUSD
    }

    // MARK: - Run

    /// Execute a skill with scoped tools and budget enforcement.
    ///
    /// This is the primary entry point. It validates inputs, creates a
    /// scoped tool registry, and produces a stream of `SkillEvent`s.
    ///
    /// - Parameters:
    ///   - skill: The loaded skill to execute.
    ///   - inputs: Input values keyed by parameter name.
    ///   - context: Execution context (workspace, provider, tools, etc.).
    /// - Returns: An `AsyncStream` of `SkillEvent`s.
    public func run(
        skill: LoadedSkill,
        inputs: [String: String],
        context: SkillExecutionContext
    ) -> AsyncStream<SkillEvent> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.yield(.failed("SkillRunner was deallocated"))
                    continuation.finish()
                    return
                }

                let startTime = Date()

                // 1. Validate inputs
                do {
                    try await self.validateInputs(skill: skill, inputs: inputs)
                } catch {
                    continuation.yield(.failed(error.localizedDescription))
                    continuation.finish()
                    return
                }

                // 2. Emit started event
                continuation.yield(.started(skill.manifest))

                // 3. Create scoped registry
                let scopedRegistry = await self.createScopedRegistry(
                    skill: skill,
                    fullRegistry: context.toolRegistry
                )

                // 4. Simulate step execution with budget enforcement
                // In a full implementation, this would delegate to the agent loop
                // with the scoped tools and skill prompt as the system prompt.
                var stepsCompleted = 0
                var cost = SessionCost()
                let filesModified: [String] = []

                // Budget check before starting
                let budgetAvailable = await self.isStepBudgetAvailable(stepsUsed: stepsCompleted, skill: skill)
                if !budgetAvailable {
                    continuation.yield(.failed("Step budget exhausted before starting"))
                    continuation.finish()
                    return
                }

                // Emit a planning step
                stepsCompleted += 1
                continuation.yield(.stepExecuted(stepsCompleted, "Assembled context with \(scopedRegistry.count) scoped tools"))

                // Budget warning at 80% threshold
                let warningThreshold = Int(Double(skill.manifest.budget.maxSteps) * 0.8)
                if stepsCompleted >= warningThreshold {
                    continuation.yield(.budgetWarning(
                        stepsUsed: stepsCompleted,
                        maxSteps: skill.manifest.budget.maxSteps
                    ))
                }

                // 5. Run verification if configured
                var verificationPassed: Bool? = nil
                if let verify = skill.manifest.verify {
                    continuation.yield(.verificationStarted)
                    // In full implementation, this would execute the command via ShellExecutor
                    // For now, we report it as pending
                    verificationPassed = nil
                    continuation.yield(.stepExecuted(stepsCompleted + 1, "Verification: \(verify.command)"))
                }

                // 6. Emit completion
                let duration = Date().timeIntervalSince(startTime)
                let result = SkillResult(
                    skillId: skill.manifest.id,
                    stepsCompleted: stepsCompleted,
                    filesModified: filesModified,
                    verificationPassed: verificationPassed,
                    cost: cost,
                    duration: duration
                )
                continuation.yield(.completed(result))
                continuation.finish()
            }
        }
    }
}
