import Foundation

/// A single recorded command execution entry.
public struct CommandHistoryEntry: Sendable {
    /// The command string that was executed.
    public let command: String
    /// When the command was started.
    public let timestamp: Date
    /// The process exit code.
    public let exitCode: Int32
    /// Wall-clock duration in milliseconds.
    public let durationMs: Int
    /// The job identifier.
    public let jobId: JobID

    public init(
        command: String,
        timestamp: Date,
        exitCode: Int32,
        durationMs: Int,
        jobId: JobID
    ) {
        self.command = command
        self.timestamp = timestamp
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.jobId = jobId
    }
}

/// Per-session append-only command history.
///
/// Records every command executed during a session. Supports querying
/// recent entries and searching by command substring.
public final class CommandHistory: @unchecked Sendable {

    private let lock = NSLock()
    private var entries: [CommandHistoryEntry] = []

    /// Maximum number of entries to retain (oldest are dropped).
    public let maxEntries: Int

    public init(maxEntries: Int = 10_000) {
        self.maxEntries = maxEntries
    }

    /// Record a command execution.
    public func record(_ entry: CommandHistoryEntry) {
        lock.lock()
        defer { lock.unlock() }

        entries.append(entry)

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    /// Record from a CommandResult.
    public func record(from result: CommandResult, startedAt: Date) {
        let entry = CommandHistoryEntry(
            command: result.command,
            timestamp: startedAt,
            exitCode: result.exitCode,
            durationMs: result.durationMs,
            jobId: result.jobId
        )
        record(entry)
    }

    /// Get the last N entries (most recent last).
    public func last(_ count: Int) -> [CommandHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }

        let start = max(0, entries.count - count)
        return Array(entries[start...])
    }

    /// Get all entries.
    public var all: [CommandHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// Search entries by command substring (case-insensitive).
    public func search(_ query: String) -> [CommandHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }

        let lower = query.lowercased()
        return entries.filter { $0.command.lowercased().contains(lower) }
    }

    /// Number of recorded entries.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Remove all entries.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
