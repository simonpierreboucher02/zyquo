import Foundation

// MARK: - MergedResult

/// The unified outcome of merging results from multiple sub-agent subtasks.
///
/// The Orchestrator produces a MergedResult after all subtasks complete,
/// including any file conflicts detected between agents.
///
/// Reference: CLAUDE.md §24
public struct MergedResult: Sendable {
    /// All subtasks that contributed to this result.
    public let subtasks: [SubTask]
    /// Deduplicated list of all files modified across subtasks.
    public let filesModified: [String]
    /// Conflicts detected when multiple agents touched the same file.
    public let conflicts: [FileConflict]
    /// Human-readable summary of the merged outcome.
    public let summary: String

    public init(
        subtasks: [SubTask],
        filesModified: [String],
        conflicts: [FileConflict],
        summary: String
    ) {
        self.subtasks = subtasks
        self.filesModified = filesModified
        self.conflicts = conflicts
        self.summary = summary
    }

    /// Whether the merge is clean (no conflicts).
    public var isClean: Bool {
        conflicts.isEmpty
    }

    /// Count of subtasks that completed successfully.
    public var completedCount: Int {
        subtasks.filter { $0.status == .completed }.count
    }

    /// Count of subtasks that failed.
    public var failedCount: Int {
        subtasks.filter { $0.status == .failed }.count
    }
}

// MARK: - FileConflict

/// A conflict between two agents that both modified the same file.
public struct FileConflict: Sendable {
    /// The file path where the conflict occurred.
    public let path: String
    /// Identifier of the first agent that touched the file.
    public let agentA: String
    /// Identifier of the second agent that touched the file.
    public let agentB: String
    /// Human-readable description of the conflict.
    public let description: String

    public init(
        path: String,
        agentA: String,
        agentB: String,
        description: String
    ) {
        self.path = path
        self.agentA = agentA
        self.agentB = agentB
        self.description = description
    }
}

// MARK: - ChangeSetMerger

/// Merges results from multiple subtasks, detecting file conflicts.
public struct ChangeSetMerger: Sendable {

    public init() {}

    /// Merge a list of completed subtasks into a single MergedResult.
    ///
    /// Detects conflicts when two different agents modify the same file.
    /// The conflict detection is based on the `filesModified` lists in each
    /// subtask's result.
    ///
    /// - Parameter subtasks: The completed subtasks to merge.
    /// - Returns: A MergedResult with conflict information.
    public func merge(subtasks: [SubTask]) -> MergedResult {
        var allFiles: [String] = []
        var conflicts: [FileConflict] = []

        // Track which agent modified which files
        var fileOwners: [String: String] = [:] // path -> first agent that modified it

        for task in subtasks {
            guard let result = task.result else { continue }
            for file in result.filesModified {
                if let existingOwner = fileOwners[file], existingOwner != task.agentType {
                    // Conflict: two different agents modified the same file
                    conflicts.append(FileConflict(
                        path: file,
                        agentA: existingOwner,
                        agentB: task.agentType,
                        description: "File '\(file)' was modified by both '\(existingOwner)' and '\(task.agentType)' agents"
                    ))
                } else {
                    fileOwners[file] = task.agentType
                }
            }
            allFiles.append(contentsOf: result.filesModified)
        }

        let uniqueFiles = Array(Set(allFiles)).sorted()

        let completedCount = subtasks.filter { $0.status == .completed }.count
        let failedCount = subtasks.filter { $0.status == .failed }.count
        let conflictCount = conflicts.count

        var summaryParts: [String] = []
        summaryParts.append("\(completedCount)/\(subtasks.count) subtasks completed")
        if failedCount > 0 {
            summaryParts.append("\(failedCount) failed")
        }
        summaryParts.append("\(uniqueFiles.count) files modified")
        if conflictCount > 0 {
            summaryParts.append("\(conflictCount) conflict(s) detected")
        }

        return MergedResult(
            subtasks: subtasks,
            filesModified: uniqueFiles,
            conflicts: conflicts,
            summary: summaryParts.joined(separator: " · ")
        )
    }
}
