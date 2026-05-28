import Foundation

// MARK: - DaemonStatus

/// The lifecycle state of the background daemon service.
///
/// Transitions follow this graph:
/// ```
/// stopped -> starting -> running -> idle
///                                 -> indexing -> idle
///                                 -> stopping -> stopped
///                          error  <-  (any)
/// ```
public enum DaemonStatus: String, Sendable {
    case stopped
    case starting
    case running
    case indexing
    case idle
    case stopping
    case error
}

// MARK: - DaemonHealthReport

/// A snapshot of daemon health and resource usage.
///
/// Returned by `DaemonService.healthReport()` and displayed
/// via `zyquo daemon status`.
public struct DaemonHealthReport: Sendable {
    /// Current daemon lifecycle state.
    public let status: DaemonStatus
    /// Seconds since the daemon was started (0 if stopped).
    public let uptimeSeconds: Int
    /// Number of files currently in the workspace index.
    public let filesIndexed: Int
    /// Number of symbols currently in the symbol index.
    public let symbolsIndexed: Int
    /// Number of vectors stored in the vector store.
    public let vectorsStored: Int
    /// When the last full or incremental index completed.
    public let lastIndexTime: Date?
    /// Approximate resident memory in megabytes.
    public let memoryUsageMB: Int
    /// Approximate CPU usage as a percentage (0.0 - 100.0+).
    public let cpuPercent: Double

    public init(
        status: DaemonStatus,
        uptimeSeconds: Int,
        filesIndexed: Int,
        symbolsIndexed: Int,
        vectorsStored: Int,
        lastIndexTime: Date?,
        memoryUsageMB: Int,
        cpuPercent: Double
    ) {
        self.status = status
        self.uptimeSeconds = uptimeSeconds
        self.filesIndexed = filesIndexed
        self.symbolsIndexed = symbolsIndexed
        self.vectorsStored = vectorsStored
        self.lastIndexTime = lastIndexTime
        self.memoryUsageMB = memoryUsageMB
        self.cpuPercent = cpuPercent
    }

    /// A human-readable summary for terminal display.
    public var summaryCard: String {
        var lines: [String] = []
        lines.append("Daemon Status: \(status.rawValue)")
        if uptimeSeconds > 0 {
            lines.append("Uptime: \(formatDuration(uptimeSeconds))")
        }
        lines.append("Files indexed: \(filesIndexed)")
        lines.append("Symbols indexed: \(symbolsIndexed)")
        lines.append("Vectors stored: \(vectorsStored)")
        if let lastIndex = lastIndexTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            lines.append("Last index: \(formatter.localizedString(for: lastIndex, relativeTo: Date()))")
        }
        lines.append("Memory: \(memoryUsageMB) MB")
        lines.append("CPU: \(String(format: "%.1f", cpuPercent))%")
        return lines.joined(separator: "\n")
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return "\(h)h \(m)m"
    }
}

// MARK: - DaemonService

/// Background intelligence service providing continuous workspace awareness.
///
/// Manages file watching (FSEvents), incremental symbol re-indexing,
/// vector store maintenance, and stale data cleanup. Designed to run
/// as a long-lived in-process actor or, in V2, as a launchd agent
/// communicating via XPC.
///
/// Reference: CLAUDE.md V2 Phase 4 - Background Intelligence Runtime
public actor DaemonService {

    // MARK: - Properties

    /// The workspace root being monitored.
    public let workspaceRoot: URL

    /// Current lifecycle status.
    public private(set) var status: DaemonStatus = .stopped

    /// When the daemon was last started.
    private var startedAt: Date?

    /// Last time indexing completed.
    private var lastIndexTime: Date?

    /// The file watcher (FSEvents-based).
    private var fileWatcher: FileWatcher?

    /// The incremental indexer for processing file changes.
    private let indexer: IncrementalIndexer

    /// The workspace actor for scanning and boundary checks.
    private let workspace: Workspace

    /// The symbol index for code intelligence.
    private let symbolIndex: SymbolIndex

    /// The vector store for semantic memory (optional; nil if not configured).
    private let vectorStore: VectorStore?

    /// Ignore rules loaded from .gitignore and .zyquoignore.
    private let ignoreRules: IgnoreRules

    /// Accumulated count of files indexed during this daemon lifetime.
    private var filesIndexedCount: Int = 0

    /// Pending changes batched from the file watcher.
    private var pendingChanges: [FSFileChange] = []

    /// Whether a processing task is currently running.
    private var isProcessing: Bool = false

    // MARK: - Init

    /// Create a new daemon service for the given workspace.
    ///
    /// - Parameters:
    ///   - workspaceRoot: The root directory to monitor.
    ///   - workspace: The workspace actor for file operations.
    ///   - symbolIndex: The symbol index to keep updated.
    ///   - vectorStore: Optional vector store for semantic vectors.
    ///   - indexer: The incremental indexer (created internally if nil).
    public init(
        workspaceRoot: URL,
        workspace: Workspace? = nil,
        symbolIndex: SymbolIndex? = nil,
        vectorStore: VectorStore? = nil,
        indexer: IncrementalIndexer? = nil
    ) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
        self.workspace = workspace ?? Workspace(root: workspaceRoot)
        self.symbolIndex = symbolIndex ?? SymbolIndex()
        self.vectorStore = vectorStore
        self.indexer = indexer ?? IncrementalIndexer()

        // Load ignore rules
        var ignoreURLs: [URL] = []
        let gitignore = workspaceRoot.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: gitignore.path) {
            ignoreURLs.append(gitignore)
        }
        let zyquoignore = workspaceRoot.appendingPathComponent(".zyquoignore")
        if FileManager.default.fileExists(atPath: zyquoignore.path) {
            ignoreURLs.append(zyquoignore)
        }
        self.ignoreRules = IgnoreRules.load(from: ignoreURLs)
    }

    // MARK: - Lifecycle

    /// Start the daemon: begin file watching and perform an initial index.
    ///
    /// Transitions: stopped -> starting -> running -> idle.
    /// If already running, this is a no-op.
    public func start() async {
        guard status == .stopped || status == .error else { return }

        status = .starting
        startedAt = Date()

        // Perform initial workspace index
        await indexWorkspace()

        // Set up the file watcher
        let watcher = FileWatcher(
            path: workspaceRoot,
            latency: 0.5
        ) { [weak self] changes in
            guard let self else { return }
            Task {
                await self.enqueueChanges(changes)
            }
        }
        self.fileWatcher = watcher
        watcher.start()

        status = .idle
    }

    /// Stop the daemon: tear down file watcher and finalize state.
    ///
    /// Transitions: (any) -> stopping -> stopped.
    public func stop() async {
        guard status != .stopped else { return }

        status = .stopping

        fileWatcher?.stop()
        fileWatcher = nil

        // Persist vector store if it has unsaved changes
        if let vs = vectorStore {
            let hasChanges = await vs.hasUnsavedChanges
            if hasChanges {
                try? await vs.save()
            }
        }

        startedAt = nil
        status = .stopped
    }

    /// Trigger a full workspace re-index.
    ///
    /// This rescans the entire workspace, re-extracts all symbols,
    /// and updates the symbol index.
    public func indexWorkspace() async {
        let previousStatus = status
        status = .indexing

        let wsIndex = await workspace.rescan()
        filesIndexedCount = wsIndex.fileCount

        await indexer.fullIndex(workspace: workspace, symbolIndex: symbolIndex)

        lastIndexTime = Date()

        // Restore to idle if we were running, otherwise to the previous status
        if previousStatus == .starting {
            status = .running
        } else {
            status = .idle
        }
    }

    /// Process a batch of file changes from the file watcher.
    ///
    /// Filters out ignored paths, then delegates to the incremental
    /// indexer for efficient per-file re-indexing.
    ///
    /// - Parameter changes: The file changes to process.
    public func processFileChanges(_ changes: [FSFileChange]) async {
        guard !changes.isEmpty else { return }

        // Filter out ignored paths
        let workspacePath = workspaceRoot.path
        let filteredChanges = changes.filter { change in
            let relativePath: String
            if change.path.hasPrefix(workspacePath) {
                relativePath = String(change.path.dropFirst(workspacePath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            } else {
                relativePath = change.path
            }
            return !ignoreRules.isIgnored(relativePath)
        }

        guard !filteredChanges.isEmpty else { return }

        let previousStatus = status
        status = .indexing

        await indexer.processChanges(
            filteredChanges,
            symbolIndex: symbolIndex,
            workspace: workspace
        )

        lastIndexTime = Date()

        // Update file count from indexer stats
        let stats = await indexer.stats
        filesIndexedCount = stats.filesProcessed

        status = previousStatus == .starting ? .running : .idle
    }

    /// Refresh memory subsystems: compact vectors, clean stale data.
    ///
    /// Called periodically or on demand via `zyquo daemon clean`.
    public func refreshMemory() async {
        let zyquoDir = workspaceRoot.appendingPathComponent(".zyquo")
        let cleaner = StaleDataCleaner()

        // Clean old snapshots (older than 30 days)
        let snapshotsDir = zyquoDir.appendingPathComponent("snapshots")
        _ = try? cleaner.cleanSnapshots(olderThan: 30, at: snapshotsDir)

        // Clean old sessions (older than 90 days)
        let sessionsDir = zyquoDir.appendingPathComponent("memory/sessions")
        _ = try? cleaner.cleanSessions(olderThan: 90, at: sessionsDir)

        // Clean orphaned vectors
        if let vs = vectorStore {
            // Use the vector store's own indexed files as the baseline.
            // A full implementation would collect actual file paths from
            // the workspace scan and compare against stored vectors.
            let indexedFiles = await vs.indexedFiles
            _ = await cleaner.cleanOrphanedVectors(
                vectorStore: vs,
                existingFiles: indexedFiles
            )
        }
    }

    /// Prune stale data from snapshots, sessions, and vectors.
    ///
    /// Delegates to `StaleDataCleaner` with default retention periods.
    public func pruneStaleData() async {
        await refreshMemory()
    }

    /// Generate a health report reflecting current daemon state.
    ///
    /// - Returns: A snapshot of daemon health metrics.
    public func healthReport() -> DaemonHealthReport {
        let uptime: Int
        if let started = startedAt {
            uptime = Int(Date().timeIntervalSince(started))
        } else {
            uptime = 0
        }

        return DaemonHealthReport(
            status: status,
            uptimeSeconds: uptime,
            filesIndexed: filesIndexedCount,
            symbolsIndexed: 0,  // Will be populated when accessed cross-actor
            vectorsStored: 0,   // Will be populated when accessed cross-actor
            lastIndexTime: lastIndexTime,
            memoryUsageMB: currentMemoryMB(),
            cpuPercent: currentCPUPercent()
        )
    }

    /// Generate an enriched health report that queries cross-actor state.
    ///
    /// - Returns: A health report with accurate symbol and vector counts.
    public func enrichedHealthReport() async -> DaemonHealthReport {
        let uptime: Int
        if let started = startedAt {
            uptime = Int(Date().timeIntervalSince(started))
        } else {
            uptime = 0
        }

        let symbolCount = await symbolIndex.totalSymbols
        let vectorCount: Int
        if let vs = vectorStore {
            vectorCount = await vs.count
        } else {
            vectorCount = 0
        }

        return DaemonHealthReport(
            status: status,
            uptimeSeconds: uptime,
            filesIndexed: filesIndexedCount,
            symbolsIndexed: symbolCount,
            vectorsStored: vectorCount,
            lastIndexTime: lastIndexTime,
            memoryUsageMB: currentMemoryMB(),
            cpuPercent: currentCPUPercent()
        )
    }

    // MARK: - Internal

    /// Enqueue changes from the file watcher for processing.
    private func enqueueChanges(_ changes: [FSFileChange]) {
        pendingChanges.append(contentsOf: changes)

        guard !isProcessing else { return }
        isProcessing = true

        Task {
            // Drain all pending changes
            while !pendingChanges.isEmpty {
                let batch = pendingChanges
                pendingChanges = []
                await processFileChanges(batch)
            }
            isProcessing = false
        }
    }

    /// Get current process memory usage in MB.
    private func currentMemoryMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Int(info.resident_size) / (1024 * 1024)
        }
        return 0
    }

    /// Estimate current CPU usage by sampling thread times.
    private func currentCPUPercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else { return 0.0 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: threads),
                vm_size_t(Int(threadCount) * MemoryLayout<thread_act_t>.size)
            )
        }

        var totalUserTime: Double = 0
        var totalSystemTime: Double = 0

        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
            let infoResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if infoResult == KERN_SUCCESS {
                if info.flags & TH_FLAGS_IDLE == 0 {
                    totalUserTime += Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000.0
                    totalSystemTime += Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000.0
                }
            }
        }

        guard let started = startedAt else { return 0.0 }
        let wallTime = Date().timeIntervalSince(started)
        guard wallTime > 0 else { return 0.0 }

        return ((totalUserTime + totalSystemTime) / wallTime) * 100.0
    }
}
