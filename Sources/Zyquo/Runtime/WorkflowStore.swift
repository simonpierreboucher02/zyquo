import Foundation

// MARK: - WorkflowStore

/// Actor-isolated store for scheduled workflows and their run history.
///
/// Workflows are stored as individual JSON files under `.zyquo/workflows/`.
/// Run history is stored as JSONL sidecar files alongside each workflow.
///
/// Reference: CLAUDE.md §30 Phase 10
public actor WorkflowStore {
    /// Base directory for workflow storage.
    private let baseDir: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public init(path: URL) {
        self.baseDir = path
    }

    // MARK: - Save

    /// Save a workflow to disk. Overwrites any existing workflow with the same ID.
    ///
    /// - Parameter workflow: The workflow to persist.
    /// - Throws: If the file cannot be written.
    public func save(_ workflow: ScheduledWorkflow) throws {
        try ensureDir()
        let data = try encoder.encode(workflow)
        let path = workflowPath(for: workflow.id)
        try data.write(to: path, options: .atomic)
    }

    // MARK: - Load

    /// Load a workflow by its ID.
    ///
    /// - Parameter id: The workflow ID to load.
    /// - Returns: The workflow, or nil if not found.
    public func load(id: String) -> ScheduledWorkflow? {
        let path = workflowPath(for: id)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let workflow = try? decoder.decode(ScheduledWorkflow.self, from: data) else {
            return nil
        }
        return workflow
    }

    // MARK: - List

    /// List all workflows sorted by creation date (newest first).
    ///
    /// - Returns: Array of all persisted workflows.
    public func list() -> [ScheduledWorkflow] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
            return []
        }

        let jsonFiles = files.filter {
            $0.pathExtension == "json" && !$0.lastPathComponent.contains(".history.")
        }

        var workflows: [ScheduledWorkflow] = []
        for file in jsonFiles {
            guard let data = try? Data(contentsOf: file),
                  let workflow = try? decoder.decode(ScheduledWorkflow.self, from: data) else {
                continue
            }
            workflows.append(workflow)
        }

        workflows.sort { $0.createdAt > $1.createdAt }
        return workflows
    }

    // MARK: - Delete

    /// Delete a workflow and its run history.
    ///
    /// - Parameter id: The workflow ID to delete.
    /// - Throws: If the files cannot be removed.
    public func delete(id: String) throws {
        let fm = FileManager.default
        let workflowFile = workflowPath(for: id)
        let historyFile = historyPath(for: id)

        if fm.fileExists(atPath: workflowFile.path) {
            try fm.removeItem(at: workflowFile)
        }
        if fm.fileExists(atPath: historyFile.path) {
            try fm.removeItem(at: historyFile)
        }
    }

    // MARK: - Run History

    /// Record a workflow run result.
    ///
    /// Appends the result to the workflow's JSONL history file
    /// and updates the workflow's lastRunAt and lastResult fields.
    ///
    /// - Parameter result: The run result to record.
    /// - Throws: If the result cannot be written.
    public func recordRun(_ result: WorkflowRunResult) throws {
        try ensureDir()

        // Append to history JSONL
        let path = historyPath(for: result.workflowId)
        let data = try lineEncoder.encode(result)
        guard var line = String(data: data, encoding: .utf8) else {
            throw PersistenceError(
                code: "workflow.encode_error",
                description: "Failed to encode workflow run result as UTF-8",
                remediation: "Check run result data for encoding issues"
            )
        }
        line += "\n"

        if FileManager.default.fileExists(atPath: path.path) {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let lineData = line.data(using: .utf8) {
                handle.write(lineData)
            }
        } else {
            try line.write(to: path, atomically: true, encoding: .utf8)
        }

        // Update the workflow record with latest run info
        if var workflow = load(id: result.workflowId) {
            workflow.lastRunAt = result.finishedAt
            workflow.lastResult = result
            try save(workflow)
        }
    }

    // MARK: - History Query

    /// Load run history for a workflow.
    ///
    /// - Parameters:
    ///   - workflowId: The workflow ID to query.
    ///   - limit: Maximum number of results (most recent first).
    /// - Returns: Array of run results, newest first.
    public func history(workflowId: String, limit: Int = 50) -> [WorkflowRunResult] {
        let path = historyPath(for: workflowId)
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var results: [WorkflowRunResult] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let result = try? decoder.decode(WorkflowRunResult.self, from: data) else {
                continue
            }
            results.append(result)
        }

        // Sort newest first, then limit
        results.sort { $0.startedAt > $1.startedAt }
        return Array(results.prefix(limit))
    }

    // MARK: - Paths

    private func workflowPath(for id: String) -> URL {
        baseDir.appendingPathComponent("\(id).json")
    }

    private func historyPath(for id: String) -> URL {
        baseDir.appendingPathComponent("\(id).history.jsonl")
    }

    private func ensureDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDir.path) {
            try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
    }
}
