import Foundation

// MARK: - StepID

/// Unique identifier for an agent step within a session.
public struct StepID: Sendable, Hashable, CustomStringConvertible, Codable {
    public let value: String

    public init() {
        let random = UInt32.random(in: 0...0xFFFFFF)
        self.value = "zs_\(String(random, radix: 16, uppercase: false))"
    }

    public init(value: String) {
        self.value = value
    }

    public var description: String { value }
}

// MARK: - ToolCall

/// A proposed or executed tool invocation from the agent.
public struct ToolCall: Sendable {
    /// The stable tool name, e.g. "shell.run", "file.read".
    public let toolName: String
    /// Structured input keyed by the tool's input schema fields.
    public let input: [String: JSONValue]
    /// Unique identifier for this tool use (matches LLM tool_use id).
    public let id: String

    public init(toolName: String, input: [String: JSONValue], id: String) {
        self.toolName = toolName
        self.input = input
        self.id = id
    }

    /// A deterministic hash for loop detection. Based on tool name + sorted input keys/values.
    public var contentHash: String {
        var hasher = Hasher()
        hasher.combine(toolName)
        for key in input.keys.sorted() {
            hasher.combine(key)
            hasher.combine(String(describing: input[key]!))
        }
        let hash = hasher.finalize()
        return String(format: "%08x", abs(hash))
    }
}

// MARK: - Observation

/// The result of executing a tool call.
public struct Observation: Sendable {
    /// Short summary (1-3 lines) for UI and LLM context.
    public let summary: String
    /// Structured payload from the tool.
    public let payload: JSONValue?
    /// Wall-clock duration of execution in milliseconds.
    public let durationMs: Int
    /// Estimated token count if the observation were echoed to the LLM.
    public let tokenHint: Int
    /// Whether the observation represents an error.
    public let isError: Bool

    public init(
        summary: String,
        payload: JSONValue? = nil,
        durationMs: Int = 0,
        tokenHint: Int = 0,
        isError: Bool = false
    ) {
        self.summary = summary
        self.payload = payload
        self.durationMs = durationMs
        self.tokenHint = tokenHint
        self.isError = isError
    }
}

// MARK: - Verdict

/// The result of verifying whether a step achieved its goal.
public enum Verdict: String, Sendable, Codable {
    case pass
    case fail
    case unclear
}

// MARK: - Plan

/// A sequence of steps the agent intends to execute.
public struct Plan: Sendable {
    /// The ordered steps in this plan.
    public var steps: [PlanStep]
    /// Whether all steps have been addressed (completed or skipped).
    public var isComplete: Bool

    public init(steps: [PlanStep] = [], isComplete: Bool = false) {
        self.steps = steps
        self.isComplete = isComplete
    }

    /// An empty plan (no steps, marked complete).
    public static let empty = Plan(steps: [], isComplete: true)
}

// MARK: - PlanStep

/// A single planned step with a goal and success criteria.
public struct PlanStep: Sendable {
    /// What this step aims to accomplish.
    public let goal: String
    /// How to verify the step succeeded.
    public let successCriteria: String

    public init(goal: String, successCriteria: String) {
        self.goal = goal
        self.successCriteria = successCriteria
    }
}

// MARK: - AgentStep

/// A step in the agent's execution, tracking proposal through verification.
public struct AgentStep: Sendable, Identifiable {
    /// Unique step identifier.
    public let id: StepID
    /// Zero-based index within the session.
    public let index: Int
    /// The goal this step is trying to achieve.
    public let goal: String
    /// The success criteria for verification.
    public let successCriteria: String
    /// The proposed tool call (set after planning).
    public var toolCall: ToolCall?
    /// The observation from executing the tool call.
    public var observation: Observation?
    /// The verification verdict.
    public var verdict: Verdict?
    /// Risk classification of the tool call.
    public var risk: RiskLevel?
    /// How the tool call was approved.
    public var approvedBy: ApprovalSource?
    /// When execution of this step started.
    public var startedAt: Date?
    /// When execution of this step finished.
    public var finishedAt: Date?

    public init(
        id: StepID = StepID(),
        index: Int,
        goal: String,
        successCriteria: String
    ) {
        self.id = id
        self.index = index
        self.goal = goal
        self.successCriteria = successCriteria
    }

    /// Duration of this step in milliseconds, or nil if not started/finished.
    public var durationMs: Int? {
        guard let start = startedAt, let end = finishedAt else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }

    /// Whether this step has completed execution (regardless of verdict).
    public var isComplete: Bool {
        finishedAt != nil
    }
}
