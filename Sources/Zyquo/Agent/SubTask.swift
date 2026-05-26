import Foundation

// MARK: - SubTask

/// A unit of work delegated to a specialized sub-agent.
///
/// SubTasks are created by the Orchestrator when decomposing a complex
/// intent. Each subtask tracks its lifecycle from pending through completion.
///
/// Reference: CLAUDE.md §24
public struct SubTask: Sendable, Identifiable {
    /// Unique subtask identifier.
    public let id: String
    /// Parent subtask identifier (nil for top-level tasks).
    public let parentId: String?
    /// The agent type identifier that should handle this task.
    public let agentType: String
    /// What this subtask aims to accomplish.
    public let goal: String
    /// How to verify the subtask succeeded.
    public let successCriteria: String
    /// Current lifecycle status.
    public var status: SubTaskStatus
    /// The result after completion (nil while running).
    public var result: SubTaskResult?
    /// Messages exchanged about this subtask.
    public var messages: [AgentMessage]
    /// When the subtask began execution.
    public var startedAt: Date?
    /// When the subtask finished execution.
    public var finishedAt: Date?
    /// Ordering hint for sequential execution.
    public let priority: Int

    public init(
        id: String = UUID().uuidString,
        parentId: String? = nil,
        agentType: String,
        goal: String,
        successCriteria: String,
        status: SubTaskStatus = .pending,
        result: SubTaskResult? = nil,
        messages: [AgentMessage] = [],
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.parentId = parentId
        self.agentType = agentType
        self.goal = goal
        self.successCriteria = successCriteria
        self.status = status
        self.result = result
        self.messages = messages
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.priority = priority
    }

    /// Whether the subtask has reached a terminal state.
    public var isTerminal: Bool {
        switch status {
        case .completed, .failed, .cancelled:
            return true
        case .pending, .assigned, .running:
            return false
        }
    }

    /// Wall-clock duration in seconds, or nil if not started/finished.
    public var durationSeconds: TimeInterval? {
        guard let start = startedAt, let end = finishedAt else { return nil }
        return end.timeIntervalSince(start)
    }
}

// MARK: - SubTaskStatus

/// Lifecycle states for a subtask.
public enum SubTaskStatus: String, Sendable, Codable, CaseIterable {
    /// Created but not yet assigned to an agent.
    case pending
    /// Assigned to an agent but not yet started.
    case assigned
    /// Currently being executed by an agent.
    case running
    /// Successfully completed.
    case completed
    /// Failed after attempted execution.
    case failed
    /// Cancelled before or during execution.
    case cancelled
}

// MARK: - SubTaskResult

/// The outcome of a completed subtask.
public struct SubTaskResult: Sendable {
    /// Human-readable summary of what the agent accomplished.
    public let summary: String
    /// Files that were modified during this subtask.
    public let filesModified: [String]
    /// Shell commands that were executed.
    public let commandsRun: [String]
    /// Raw observations from the agent's tool calls.
    public let observations: [Observation]

    public init(
        summary: String,
        filesModified: [String] = [],
        commandsRun: [String] = [],
        observations: [Observation] = []
    ) {
        self.summary = summary
        self.filesModified = filesModified
        self.commandsRun = commandsRun
        self.observations = observations
    }
}
