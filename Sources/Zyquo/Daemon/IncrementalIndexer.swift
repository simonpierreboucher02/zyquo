import Foundation

// MARK: - IndexerStats

/// Statistics from the incremental indexer.
public struct IndexerStats: Sendable {
    /// Total files processed during the indexer's lifetime.
    public let filesProcessed: Int
    /// Total symbols extracted across all indexing operations.
    public let symbolsExtracted: Int
    /// When the last full index was completed (nil if never).
    public let lastFullIndexTime: Date?
    /// When the last incremental index was completed (nil if never).
    public let lastIncrementalTime: Date?
    /// Average time in milliseconds to process a single file.
    public let averageFileTimeMs: Double

    public init(
        filesProcessed: Int = 0,
        symbolsExtracted: Int = 0,
        lastFullIndexTime: Date? = nil,
        lastIncrementalTime: Date? = nil,
        averageFileTimeMs: Double = 0.0
    ) {
        self.filesProcessed = filesProcessed
        self.symbolsExtracted = symbolsExtracted
        self.lastFullIndexTime = lastFullIndexTime
        self.lastIncrementalTime = lastIncrementalTime
        self.averageFileTimeMs = averageFileTimeMs
    }
}

// MARK: - IncrementalIndexer

/// Processes file changes incrementally to keep the symbol index current.
///
/// On file creation or modification, re-extracts symbols for the changed
/// file and updates the `SymbolIndex`. On deletion, removes the file's
/// symbols from the index. Tracks statistics for health reporting.
///
/// Thread-safe via actor isolation.
///
/// Reference: CLAUDE.md V2 Phase 4 - Background Intelligence Runtime
public actor IncrementalIndexer {

    // MARK: - State

    /// Total files processed during this indexer's lifetime.
    private var _filesProcessed: Int = 0

    /// Total symbols extracted across all operations.
    private var _symbolsExtracted: Int = 0

    /// When the last full index was completed.
    private var _lastFullIndexTime: Date?

    /// When the last incremental update was completed.
    private var _lastIncrementalTime: Date?

    /// Cumulative time spent processing files (seconds).
    private var _totalProcessingTime: TimeInterval = 0

    // MARK: - Init

    public init() {}

    // MARK: - Stats

    /// Current indexer statistics.
    public var stats: IndexerStats {
        let avgMs: Double
        if _filesProcessed > 0 {
            avgMs = (_totalProcessingTime / Double(_filesProcessed)) * 1000.0
        } else {
            avgMs = 0.0
        }

        return IndexerStats(
            filesProcessed: _filesProcessed,
            symbolsExtracted: _symbolsExtracted,
            lastFullIndexTime: _lastFullIndexTime,
            lastIncrementalTime: _lastIncrementalTime,
            averageFileTimeMs: avgMs
        )
    }

    // MARK: - Incremental Processing

    /// Process a batch of file changes, updating the symbol index.
    ///
    /// For each change:
    /// - `.created` / `.modified` / `.renamed`: re-index the file.
    /// - `.deleted`: remove the file from the index.
    ///
    /// - Parameters:
    ///   - changes: The file changes to process.
    ///   - symbolIndex: The symbol index to update.
    ///   - workspace: The workspace actor for boundary checks.
    public func processChanges(
        _ changes: [FSFileChange],
        symbolIndex: SymbolIndex,
        workspace: Workspace
    ) async {
        let startTime = CFAbsoluteTimeGetCurrent()

        for change in changes {
            switch change.kind {
            case .created, .modified, .renamed:
                await reindexFile(at: change.path, symbolIndex: symbolIndex)
            case .deleted:
                await symbolIndex.removeFile(change.path)
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        _totalProcessingTime += elapsed
        _filesProcessed += changes.count
        _symbolsExtracted = await symbolIndex.totalSymbols
        _lastIncrementalTime = Date()
    }

    /// Perform a full index of the entire workspace.
    ///
    /// Clears the existing symbol index and re-indexes all source files.
    ///
    /// - Parameters:
    ///   - workspace: The workspace to scan for files.
    ///   - symbolIndex: The symbol index to rebuild.
    public func fullIndex(
        workspace: Workspace,
        symbolIndex: SymbolIndex
    ) async {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Clear existing index
        await symbolIndex.clear()

        // Scan workspace for files
        let wsIndex = await workspace.scan()

        // Collect all source files by walking the workspace
        let root = workspace.root
        let files = collectSourceFiles(root: root)

        // Index each file
        for (filePath, language) in files {
            let fileURL = URL(fileURLWithPath: filePath)
            await symbolIndex.index(file: fileURL, language: language)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        _totalProcessingTime += elapsed
        _filesProcessed += files.count
        _symbolsExtracted = await symbolIndex.totalSymbols
        _lastFullIndexTime = Date()

        // Silence unused variable warning
        _ = wsIndex
    }

    // MARK: - Internal

    /// Re-index a single file by path.
    ///
    /// Determines the language from the file extension, reads the file,
    /// and updates the symbol index.
    private func reindexFile(at path: String, symbolIndex: SymbolIndex) async {
        let ext = (path as NSString).pathExtension
        guard let language = Language.from(extension: ext) else { return }

        let fileURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            // File was removed between detection and processing
            await symbolIndex.removeFile(path)
            return
        }

        await symbolIndex.index(file: fileURL, language: language)
    }

    /// Collect source files and their languages from a directory tree.
    ///
    /// Skips common non-source directories and returns only files for
    /// which a language can be determined from the extension.
    private func collectSourceFiles(root: URL) -> [(String, Language)] {
        let fm = FileManager.default
        var results: [(String, Language)] = []

        let skipDirs: Set<String> = [
            ".git", ".hg", ".svn", "node_modules", ".build", "build",
            "DerivedData", "Pods", ".venv", "venv", "__pycache__",
            "target", "dist", ".next", ".nuxt", ".output",
        ]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent

            if skipDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }

            let ext = url.pathExtension
            guard let language = Language.from(extension: ext) else { continue }

            results.append((url.path, language))
        }

        return results
    }
}
