import Foundation

// MARK: - CleanupResult

/// The outcome of a stale data cleanup operation.
public struct CleanupResult: Sendable {
    /// Number of items (files, entries) removed.
    public let itemsRemoved: Int
    /// Approximate bytes freed on disk.
    public let bytesFreed: UInt64
    /// Human-readable summary of what was cleaned.
    public let description: String

    public init(itemsRemoved: Int, bytesFreed: UInt64, description: String) {
        self.itemsRemoved = itemsRemoved
        self.bytesFreed = bytesFreed
        self.description = description
    }

    /// A result indicating nothing was cleaned.
    public static let empty = CleanupResult(
        itemsRemoved: 0,
        bytesFreed: 0,
        description: "No stale data found"
    )
}

// MARK: - StaleDataCleaner

/// Cleans up stale snapshots, sessions, and orphaned vector entries.
///
/// Used by `DaemonService.refreshMemory()` and `zyquo daemon clean`
/// to reclaim disk space and keep the `.zyquo/` directory tidy.
///
/// All operations are safe: they only remove data older than the
/// specified retention period and never touch user-edited files
/// like `project.md`.
///
/// Reference: CLAUDE.md V2 Phase 4 - Background Intelligence Runtime
public struct StaleDataCleaner: Sendable {

    public init() {}

    // MARK: - Snapshots

    /// Clean snapshot files older than the specified number of days.
    ///
    /// Snapshots are content-addressed gzip files under `.zyquo/snapshots/`.
    ///
    /// - Parameters:
    ///   - days: Retention period in days. Files older than this are removed.
    ///   - snapshotsDir: The directory containing snapshot files.
    /// - Returns: A summary of what was cleaned.
    /// - Throws: If the directory cannot be read.
    public func cleanSnapshots(olderThan days: Int, at snapshotsDir: URL) throws -> CleanupResult {
        try cleanFiles(olderThan: days, at: snapshotsDir, label: "snapshots")
    }

    // MARK: - Sessions

    /// Clean session files older than the specified number of days.
    ///
    /// Sessions are JSONL files under `.zyquo/memory/sessions/`.
    ///
    /// - Parameters:
    ///   - days: Retention period in days. Files older than this are removed.
    ///   - sessionsDir: The directory containing session files.
    /// - Returns: A summary of what was cleaned.
    /// - Throws: If the directory cannot be read.
    public func cleanSessions(olderThan days: Int, at sessionsDir: URL) throws -> CleanupResult {
        try cleanFiles(olderThan: days, at: sessionsDir, label: "sessions")
    }

    // MARK: - Orphaned Vectors

    /// Remove vector entries for files that no longer exist on disk.
    ///
    /// Compares the set of file paths stored in the vector store against
    /// the set of existing files. Any vectors referencing files not in
    /// `existingFiles` are removed.
    ///
    /// - Parameters:
    ///   - vectorStore: The vector store to clean.
    ///   - existingFiles: The set of file paths that currently exist.
    /// - Returns: A summary of what was cleaned.
    public func cleanOrphanedVectors(
        vectorStore: VectorStore,
        existingFiles: Set<String>
    ) async -> CleanupResult {
        let indexedFiles = await vectorStore.indexedFiles

        // Find files in the vector store that are not in the existing files set
        let orphaned = indexedFiles.subtracting(existingFiles)

        guard !orphaned.isEmpty else {
            return CleanupResult(
                itemsRemoved: 0,
                bytesFreed: 0,
                description: "No orphaned vectors found"
            )
        }

        for filePath in orphaned {
            await vectorStore.remove(filePath: filePath)
        }

        return CleanupResult(
            itemsRemoved: orphaned.count,
            bytesFreed: 0, // Vector memory freed, not disk until save
            description: "Removed vectors for \(orphaned.count) orphaned file(s)"
        )
    }

    // MARK: - Internal

    /// Generic cleanup of files older than a threshold in a directory.
    private func cleanFiles(
        olderThan days: Int,
        at directory: URL,
        label: String
    ) throws -> CleanupResult {
        let fm = FileManager.default

        guard fm.fileExists(atPath: directory.path) else {
            return .empty
        }

        let cutoff = Date().addingTimeInterval(-TimeInterval(days * 86400))
        var removedCount = 0
        var freedBytes: UInt64 = 0

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return .empty
        }

        for fileURL in contents {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { continue }

            guard let modDate = values.contentModificationDate else { continue }

            if modDate < cutoff {
                let size = UInt64(values.fileSize ?? 0)
                do {
                    try fm.removeItem(at: fileURL)
                    removedCount += 1
                    freedBytes += size
                } catch {
                    // Skip files that can't be removed
                    continue
                }
            }
        }

        if removedCount == 0 {
            return CleanupResult(
                itemsRemoved: 0,
                bytesFreed: 0,
                description: "No stale \(label) found"
            )
        }

        return CleanupResult(
            itemsRemoved: removedCount,
            bytesFreed: freedBytes,
            description: "Removed \(removedCount) stale \(label), freed \(formatBytes(freedBytes))"
        )
    }

    /// Format bytes into a human-readable string.
    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
