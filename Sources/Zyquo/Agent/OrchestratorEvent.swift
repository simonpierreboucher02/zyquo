import Foundation

// MARK: - OrchestratorEvent

/// Events emitted by the Orchestrator during multi-agent task execution.
///
/// These are separate from AgentEvent to avoid breaking the existing
/// single-agent loop. The UI layer can observe both streams.
///
/// Reference: CLAUDE.md §24
public enum OrchestratorEvent: Sendable {
    /// The orchestrator decomposed the intent into subtasks.
    case decomposed(subtasks: [SubTask])
    /// An agent type was selected for a subtask.
    case agentSelected(subtask: SubTask, agent: String)
    /// A subtask began execution.
    case subtaskStarted(SubTask)
    /// A subtask completed successfully.
    case subtaskCompleted(SubTask, SubTaskResult)
    /// A subtask failed.
    case subtaskFailed(SubTask, ZyquoError)
    /// A file conflict was detected between two agents.
    case conflictDetected(FileConflict)
    /// All subtask results have been merged.
    case mergeCompleted(MergedResult)
    /// A message was sent between agents.
    case messageSent(AgentMessage)
}
