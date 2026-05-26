import Foundation

// MARK: - AgentMessage

/// A typed message exchanged between agents or between an agent and the orchestrator.
///
/// Messages are the coordination primitive for multi-agent workflows.
/// They are immutable, timestamped, and fully codable for persistence.
///
/// Reference: CLAUDE.md §24
public struct AgentMessage: Sendable, Codable, Identifiable {
    /// Unique message identifier.
    public let id: String
    /// The sending agent's identifier (or "orchestrator").
    public let from: String
    /// The receiving agent's identifier (or "orchestrator").
    public let to: String
    /// The semantic kind of message.
    public let kind: MessageKind
    /// The message content (natural language or structured text).
    public let content: String
    /// When the message was created.
    public let timestamp: Date
    /// Optional key-value metadata for extensibility.
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        from: String,
        to: String,
        kind: MessageKind,
        content: String,
        timestamp: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.kind = kind
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - MessageKind

/// The semantic type of an inter-agent message.
public enum MessageKind: String, Sendable, Codable, CaseIterable {
    /// The orchestrator is delegating a task to an agent.
    case taskDelegation
    /// An agent is returning the result of a completed task.
    case taskResult
    /// An agent is sharing context or findings with another agent.
    case contextShare
    /// An agent is reporting progress to the orchestrator.
    case progressUpdate
    /// An agent is reporting a conflict it detected.
    case conflictReport
    /// An agent has a question that requires user input.
    case question
}
