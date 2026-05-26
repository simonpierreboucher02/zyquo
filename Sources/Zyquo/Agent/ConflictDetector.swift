import Foundation

// MARK: - ParallelConflict

/// A conflict detected when multiple parallel tasks modify the same file.
///
/// Unlike `FileConflict` (which tracks agent-level conflicts in the
/// `ChangeSetMerger`), `ParallelConflict` is task-oriented and may
/// involve more than two tasks touching the same file.
public struct ParallelConflict: Sendable {
    /// The file path where the conflict occurred.
    public let filePath: String
    /// The IDs of all tasks that modified this file.
    public let taskIds: [String]
    /// The agent types of the tasks involved.
    public let agentTypes: [String]
    /// Human-readable description of the conflict.
    public let description: String

    public init(
        filePath: String,
        taskIds: [String],
        agentTypes: [String],
        description: String
    ) {
        self.filePath = filePath
        self.taskIds = taskIds
        self.agentTypes = agentTypes
        self.description = description
    }
}

// MARK: - ConflictDetector

/// Detects file-level conflicts among parallel task results.
///
/// When multiple tasks running in parallel modify the same file, this
/// detector identifies those overlaps so the scheduler or orchestrator
/// can surface them to the user.
///
/// Reference: CLAUDE.md §30 Phase 7
public struct ConflictDetector: Sendable {

    /// Detect conflicts among a set of task results.
    ///
    /// A conflict exists when two or more tasks modify the same file path.
    ///
    /// - Parameter results: Tuples of (taskId, agentType, filesModified).
    /// - Returns: An array of detected conflicts, one per conflicted file.
    public static func detect(
        results: [(taskId: String, agentType: String, filesModified: [String])]
    ) -> [ParallelConflict] {
        // Build a map of file -> [(taskId, agentType)]
        var fileOwners: [String: [(taskId: String, agentType: String)]] = [:]

        for entry in results {
            for file in entry.filesModified {
                fileOwners[file, default: []].append(
                    (taskId: entry.taskId, agentType: entry.agentType)
                )
            }
        }

        // Collect conflicts (files touched by 2+ tasks)
        var conflicts: [ParallelConflict] = []

        for (filePath, owners) in fileOwners.sorted(by: { $0.key < $1.key }) {
            guard owners.count >= 2 else { continue }

            let taskIds = owners.map(\.taskId)
            let agentTypes = owners.map(\.agentType)
            let uniqueAgents = Array(Set(agentTypes)).sorted()

            let description: String
            if uniqueAgents.count == 1 {
                description = "File '\(filePath)' was modified by \(owners.count) tasks of type '\(uniqueAgents[0])'"
            } else {
                description = "File '\(filePath)' was modified by \(owners.count) tasks (\(uniqueAgents.joined(separator: ", ")))"
            }

            conflicts.append(ParallelConflict(
                filePath: filePath,
                taskIds: taskIds,
                agentTypes: agentTypes,
                description: description
            ))
        }

        return conflicts
    }
}
