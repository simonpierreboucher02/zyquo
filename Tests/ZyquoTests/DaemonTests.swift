import XCTest
@testable import Zyquo

// MARK: - DaemonStatus Tests

final class DaemonStatusTests: XCTestCase {

    func testAllStatusValues() {
        // Verify all expected status values exist and have correct raw values
        XCTAssertEqual(DaemonStatus.stopped.rawValue, "stopped")
        XCTAssertEqual(DaemonStatus.starting.rawValue, "starting")
        XCTAssertEqual(DaemonStatus.running.rawValue, "running")
        XCTAssertEqual(DaemonStatus.indexing.rawValue, "indexing")
        XCTAssertEqual(DaemonStatus.idle.rawValue, "idle")
        XCTAssertEqual(DaemonStatus.stopping.rawValue, "stopping")
        XCTAssertEqual(DaemonStatus.error.rawValue, "error")
    }

    func testStatusFromRawValue() {
        XCTAssertEqual(DaemonStatus(rawValue: "stopped"), .stopped)
        XCTAssertEqual(DaemonStatus(rawValue: "running"), .running)
        XCTAssertEqual(DaemonStatus(rawValue: "idle"), .idle)
        XCTAssertNil(DaemonStatus(rawValue: "invalid"))
    }
}

// MARK: - DaemonHealthReport Tests

final class DaemonHealthReportTests: XCTestCase {

    func testHealthReportProperties() {
        let now = Date()
        let report = DaemonHealthReport(
            status: .idle,
            uptimeSeconds: 3661,
            filesIndexed: 150,
            symbolsIndexed: 2500,
            vectorsStored: 800,
            lastIndexTime: now,
            memoryUsageMB: 45,
            cpuPercent: 2.5
        )

        XCTAssertEqual(report.status, .idle)
        XCTAssertEqual(report.uptimeSeconds, 3661)
        XCTAssertEqual(report.filesIndexed, 150)
        XCTAssertEqual(report.symbolsIndexed, 2500)
        XCTAssertEqual(report.vectorsStored, 800)
        XCTAssertEqual(report.lastIndexTime, now)
        XCTAssertEqual(report.memoryUsageMB, 45)
        XCTAssertEqual(report.cpuPercent, 2.5)
    }

    func testHealthReportSummaryCard() {
        let report = DaemonHealthReport(
            status: .running,
            uptimeSeconds: 120,
            filesIndexed: 50,
            symbolsIndexed: 100,
            vectorsStored: 0,
            lastIndexTime: nil,
            memoryUsageMB: 30,
            cpuPercent: 1.0
        )

        let card = report.summaryCard
        XCTAssertTrue(card.contains("running"))
        XCTAssertTrue(card.contains("Files indexed: 50"))
        XCTAssertTrue(card.contains("Symbols indexed: 100"))
        XCTAssertTrue(card.contains("Vectors stored: 0"))
        XCTAssertTrue(card.contains("Memory: 30 MB"))
    }

    func testHealthReportSummaryCardWithUptime() {
        let report = DaemonHealthReport(
            status: .idle,
            uptimeSeconds: 7200,
            filesIndexed: 0,
            symbolsIndexed: 0,
            vectorsStored: 0,
            lastIndexTime: nil,
            memoryUsageMB: 10,
            cpuPercent: 0.0
        )

        let card = report.summaryCard
        XCTAssertTrue(card.contains("2h 0m"))
    }

    func testHealthReportZeroUptime() {
        let report = DaemonHealthReport(
            status: .stopped,
            uptimeSeconds: 0,
            filesIndexed: 0,
            symbolsIndexed: 0,
            vectorsStored: 0,
            lastIndexTime: nil,
            memoryUsageMB: 0,
            cpuPercent: 0.0
        )

        let card = report.summaryCard
        // Should not contain Uptime line when uptime is 0
        XCTAssertFalse(card.contains("Uptime:"))
        XCTAssertTrue(card.contains("stopped"))
    }
}

// MARK: - FSFileChange Tests

final class FSFileChangeTests: XCTestCase {

    func testCreation() {
        let now = Date()
        let change = FSFileChange(path: "/tmp/test.swift", kind: .created, timestamp: now)

        XCTAssertEqual(change.path, "/tmp/test.swift")
        XCTAssertEqual(change.kind, .created)
        XCTAssertEqual(change.timestamp, now)
    }

    func testDefaultTimestamp() {
        let before = Date()
        let change = FSFileChange(path: "/tmp/test.swift", kind: .modified)
        let after = Date()

        XCTAssertGreaterThanOrEqual(change.timestamp, before)
        XCTAssertLessThanOrEqual(change.timestamp, after)
    }

    func testAllChangeKinds() {
        let created = FSFileChange(path: "/a", kind: .created)
        let modified = FSFileChange(path: "/b", kind: .modified)
        let deleted = FSFileChange(path: "/c", kind: .deleted)
        let renamed = FSFileChange(path: "/d", kind: .renamed)

        XCTAssertEqual(created.kind, .created)
        XCTAssertEqual(modified.kind, .modified)
        XCTAssertEqual(deleted.kind, .deleted)
        XCTAssertEqual(renamed.kind, .renamed)
    }
}

// MARK: - FileChangeKind Tests

final class FileChangeKindTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(FileChangeKind.created.rawValue, "created")
        XCTAssertEqual(FileChangeKind.modified.rawValue, "modified")
        XCTAssertEqual(FileChangeKind.deleted.rawValue, "deleted")
        XCTAssertEqual(FileChangeKind.renamed.rawValue, "renamed")
    }

    func testFromRawValue() {
        XCTAssertEqual(FileChangeKind(rawValue: "created"), .created)
        XCTAssertEqual(FileChangeKind(rawValue: "deleted"), .deleted)
        XCTAssertNil(FileChangeKind(rawValue: "unknown"))
    }
}

// MARK: - FileWatcher Tests

final class FileWatcherTests: XCTestCase {

    func testCreation() {
        let path = URL(fileURLWithPath: "/tmp")
        let watcher = FileWatcher(path: path) { _ in }

        XCTAssertEqual(watcher.watchPath.path, path.standardizedFileURL.path)
        XCTAssertEqual(watcher.latency, 0.5)
        XCTAssertFalse(watcher.isRunning)
    }

    func testCreationWithCustomLatency() {
        let path = URL(fileURLWithPath: "/tmp")
        let watcher = FileWatcher(path: path, latency: 1.0) { _ in }

        XCTAssertEqual(watcher.latency, 1.0)
    }

    func testInitialNotRunning() {
        let watcher = FileWatcher(path: URL(fileURLWithPath: "/tmp")) { _ in }
        XCTAssertFalse(watcher.isRunning)
    }

    func testStopWhenNotRunning() {
        // Stopping a watcher that was never started should be a no-op
        let watcher = FileWatcher(path: URL(fileURLWithPath: "/tmp")) { _ in }
        watcher.stop()  // Should not crash
        XCTAssertFalse(watcher.isRunning)
    }
}

// MARK: - IndexerStats Tests

final class IndexerStatsTests: XCTestCase {

    func testDefaultValues() {
        let stats = IndexerStats()
        XCTAssertEqual(stats.filesProcessed, 0)
        XCTAssertEqual(stats.symbolsExtracted, 0)
        XCTAssertNil(stats.lastFullIndexTime)
        XCTAssertNil(stats.lastIncrementalTime)
        XCTAssertEqual(stats.averageFileTimeMs, 0.0)
    }

    func testCustomValues() {
        let now = Date()
        let stats = IndexerStats(
            filesProcessed: 100,
            symbolsExtracted: 500,
            lastFullIndexTime: now,
            lastIncrementalTime: now,
            averageFileTimeMs: 12.5
        )

        XCTAssertEqual(stats.filesProcessed, 100)
        XCTAssertEqual(stats.symbolsExtracted, 500)
        XCTAssertEqual(stats.lastFullIndexTime, now)
        XCTAssertEqual(stats.lastIncrementalTime, now)
        XCTAssertEqual(stats.averageFileTimeMs, 12.5)
    }
}

// MARK: - IncrementalIndexer Tests

final class IncrementalIndexerTests: XCTestCase {

    func testInitialStats() async {
        let indexer = IncrementalIndexer()
        let stats = await indexer.stats

        XCTAssertEqual(stats.filesProcessed, 0)
        XCTAssertEqual(stats.symbolsExtracted, 0)
        XCTAssertNil(stats.lastFullIndexTime)
        XCTAssertNil(stats.lastIncrementalTime)
        XCTAssertEqual(stats.averageFileTimeMs, 0.0)
    }

    func testProcessCreatedFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a Swift source file
        let swiftFile = tmpDir.appendingPathComponent("Test.swift")
        try "struct Hello { func greet() {} }".write(to: swiftFile, atomically: true, encoding: .utf8)

        let indexer = IncrementalIndexer()
        let symbolIndex = SymbolIndex()
        let workspace = Workspace(root: tmpDir)

        let change = FSFileChange(path: swiftFile.path, kind: .created)
        await indexer.processChanges([change], symbolIndex: symbolIndex, workspace: workspace)

        let stats = await indexer.stats
        XCTAssertEqual(stats.filesProcessed, 1)
        XCTAssertNotNil(stats.lastIncrementalTime)

        // Verify symbols were extracted
        let symbols = await symbolIndex.symbols(inFile: swiftFile.path)
        XCTAssertFalse(symbols.isEmpty, "Should have extracted symbols from Test.swift")
    }

    func testProcessDeletedFile() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create and index a file first
        let swiftFile = tmpDir.appendingPathComponent("Deleted.swift")
        try "class Foo { }".write(to: swiftFile, atomically: true, encoding: .utf8)

        let indexer = IncrementalIndexer()
        let symbolIndex = SymbolIndex()
        let workspace = Workspace(root: tmpDir)

        // First, index the file
        let createChange = FSFileChange(path: swiftFile.path, kind: .created)
        await indexer.processChanges([createChange], symbolIndex: symbolIndex, workspace: workspace)

        let symbolsBefore = await symbolIndex.symbols(inFile: swiftFile.path)
        XCTAssertFalse(symbolsBefore.isEmpty, "File should be indexed before delete")

        // Now delete the file and process the delete change
        try FileManager.default.removeItem(at: swiftFile)
        let deleteChange = FSFileChange(path: swiftFile.path, kind: .deleted)
        await indexer.processChanges([deleteChange], symbolIndex: symbolIndex, workspace: workspace)

        let symbolsAfter = await symbolIndex.symbols(inFile: swiftFile.path)
        XCTAssertTrue(symbolsAfter.isEmpty, "Symbols should be removed after file delete")
    }

    func testFullIndex() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create some Swift source files
        try "struct Alpha {}".write(
            to: tmpDir.appendingPathComponent("Alpha.swift"),
            atomically: true, encoding: .utf8
        )
        try "struct Beta {}".write(
            to: tmpDir.appendingPathComponent("Beta.swift"),
            atomically: true, encoding: .utf8
        )

        let indexer = IncrementalIndexer()
        let symbolIndex = SymbolIndex()
        let workspace = Workspace(root: tmpDir)

        await indexer.fullIndex(workspace: workspace, symbolIndex: symbolIndex)

        let stats = await indexer.stats
        XCTAssertGreaterThanOrEqual(stats.filesProcessed, 2)
        XCTAssertNotNil(stats.lastFullIndexTime)
        XCTAssertGreaterThan(stats.symbolsExtracted, 0)
    }

    func testStatsTrackAverageTime() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let swiftFile = tmpDir.appendingPathComponent("Stats.swift")
        try "func hello() {}".write(to: swiftFile, atomically: true, encoding: .utf8)

        let indexer = IncrementalIndexer()
        let symbolIndex = SymbolIndex()
        let workspace = Workspace(root: tmpDir)

        let change = FSFileChange(path: swiftFile.path, kind: .modified)
        await indexer.processChanges([change], symbolIndex: symbolIndex, workspace: workspace)

        let stats = await indexer.stats
        XCTAssertGreaterThanOrEqual(stats.averageFileTimeMs, 0.0)
    }
}

// MARK: - CleanupResult Tests

final class CleanupResultTests: XCTestCase {

    func testProperties() {
        let result = CleanupResult(
            itemsRemoved: 5,
            bytesFreed: 1024 * 1024,
            description: "Cleaned 5 files"
        )

        XCTAssertEqual(result.itemsRemoved, 5)
        XCTAssertEqual(result.bytesFreed, 1024 * 1024)
        XCTAssertEqual(result.description, "Cleaned 5 files")
    }

    func testEmptyResult() {
        let result = CleanupResult.empty
        XCTAssertEqual(result.itemsRemoved, 0)
        XCTAssertEqual(result.bytesFreed, 0)
        XCTAssertEqual(result.description, "No stale data found")
    }
}

// MARK: - StaleDataCleaner Tests

final class StaleDataCleanerTests: XCTestCase {

    func testCleanOldSnapshots() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create files: one "old" (we'll backdate it) and one "new"
        let oldFile = tmpDir.appendingPathComponent("old_snapshot.gz")
        let newFile = tmpDir.appendingPathComponent("new_snapshot.gz")

        try "old data".write(to: oldFile, atomically: true, encoding: .utf8)
        try "new data".write(to: newFile, atomically: true, encoding: .utf8)

        // Backdate the old file to 60 days ago
        let sixtyDaysAgo = Date().addingTimeInterval(-60 * 86400)
        try FileManager.default.setAttributes(
            [.modificationDate: sixtyDaysAgo],
            ofItemAtPath: oldFile.path
        )

        let cleaner = StaleDataCleaner()
        let result = try cleaner.cleanSnapshots(olderThan: 30, at: tmpDir)

        XCTAssertEqual(result.itemsRemoved, 1, "Should remove the old snapshot")
        XCTAssertGreaterThan(result.bytesFreed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
    }

    func testCleanOldSessions() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let oldSession = tmpDir.appendingPathComponent("old_session.jsonl")
        try "old session data".write(to: oldSession, atomically: true, encoding: .utf8)

        let hundredDaysAgo = Date().addingTimeInterval(-100 * 86400)
        try FileManager.default.setAttributes(
            [.modificationDate: hundredDaysAgo],
            ofItemAtPath: oldSession.path
        )

        let cleaner = StaleDataCleaner()
        let result = try cleaner.cleanSessions(olderThan: 90, at: tmpDir)

        XCTAssertEqual(result.itemsRemoved, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldSession.path))
    }

    func testCleanNonexistentDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-nonexistent-\(UUID().uuidString)")

        let cleaner = StaleDataCleaner()
        let result = try cleaner.cleanSnapshots(olderThan: 30, at: tmpDir)

        XCTAssertEqual(result.itemsRemoved, 0)
        XCTAssertEqual(result.bytesFreed, 0)
    }

    func testCleanOrphanedVectors() async {
        let vectorPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-vectors-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: vectorPath) }

        let store = VectorStore(path: vectorPath)

        // Add vectors for two files
        let chunk1 = EmbeddedChunk(
            chunk: CodeChunkRef(filePath: "/exists/file.swift", startLine: 1, endLine: 10, name: "test", kind: "function"),
            vector: [1.0, 0.0, 0.0]
        )
        let chunk2 = EmbeddedChunk(
            chunk: CodeChunkRef(filePath: "/orphaned/file.swift", startLine: 1, endLine: 5, name: "old", kind: "function"),
            vector: [0.0, 1.0, 0.0]
        )

        await store.add(chunk1)
        await store.add(chunk2)

        let cleaner = StaleDataCleaner()
        let existingFiles: Set<String> = ["/exists/file.swift"]
        let result = await cleaner.cleanOrphanedVectors(vectorStore: store, existingFiles: existingFiles)

        XCTAssertEqual(result.itemsRemoved, 1)
        let remaining = await store.count
        XCTAssertEqual(remaining, 1)
    }

    func testCleanNoOrphanedVectors() async {
        let vectorPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-vectors-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: vectorPath) }

        let store = VectorStore(path: vectorPath)

        let chunk = EmbeddedChunk(
            chunk: CodeChunkRef(filePath: "/exists/file.swift", startLine: 1, endLine: 10, name: "test", kind: "function"),
            vector: [1.0, 0.0, 0.0]
        )
        await store.add(chunk)

        let cleaner = StaleDataCleaner()
        let existingFiles: Set<String> = ["/exists/file.swift"]
        let result = await cleaner.cleanOrphanedVectors(vectorStore: store, existingFiles: existingFiles)

        XCTAssertEqual(result.itemsRemoved, 0)
        let remaining = await store.count
        XCTAssertEqual(remaining, 1)
    }

    func testCleanNothingToClean() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-clean-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a recent file
        let recentFile = tmpDir.appendingPathComponent("recent.gz")
        try "data".write(to: recentFile, atomically: true, encoding: .utf8)

        let cleaner = StaleDataCleaner()
        let result = try cleaner.cleanSnapshots(olderThan: 30, at: tmpDir)

        XCTAssertEqual(result.itemsRemoved, 0)
    }
}

// MARK: - DaemonService Tests

final class DaemonServiceTests: XCTestCase {

    func testInitialStatus() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let daemon = DaemonService(workspaceRoot: tmpDir)
        let status = await daemon.status
        XCTAssertEqual(status, .stopped)
    }

    func testStartAndStop() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let daemon = DaemonService(workspaceRoot: tmpDir)

        // Start the daemon
        await daemon.start()
        let runningStatus = await daemon.status
        XCTAssertEqual(runningStatus, .idle, "After start, daemon should be idle")

        // Stop the daemon
        await daemon.stop()
        let stoppedStatus = await daemon.status
        XCTAssertEqual(stoppedStatus, .stopped)
    }

    func testStartIsIdempotent() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let daemon = DaemonService(workspaceRoot: tmpDir)

        await daemon.start()
        let statusAfterFirst = await daemon.status
        XCTAssertEqual(statusAfterFirst, .idle)

        // Second start should be a no-op
        await daemon.start()
        let statusAfterSecond = await daemon.status
        XCTAssertEqual(statusAfterSecond, .idle)

        await daemon.stop()
    }

    func testStopIsIdempotent() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let daemon = DaemonService(workspaceRoot: tmpDir)

        // Stop without start should be a no-op
        await daemon.stop()
        let status = await daemon.status
        XCTAssertEqual(status, .stopped)
    }

    func testHealthReportWhenStopped() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let daemon = DaemonService(workspaceRoot: tmpDir)
        let report = await daemon.healthReport()

        XCTAssertEqual(report.status, .stopped)
        XCTAssertEqual(report.uptimeSeconds, 0)
        XCTAssertEqual(report.filesIndexed, 0)
        XCTAssertNil(report.lastIndexTime)
    }

    func testHealthReportAfterStart() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let daemon = DaemonService(workspaceRoot: tmpDir)
        await daemon.start()

        let report = await daemon.healthReport()
        XCTAssertEqual(report.status, .idle)
        XCTAssertGreaterThanOrEqual(report.uptimeSeconds, 0)
        XCTAssertNotNil(report.lastIndexTime)
        XCTAssertGreaterThanOrEqual(report.memoryUsageMB, 0)

        await daemon.stop()
    }

    func testEnrichedHealthReport() async {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let symbolIndex = SymbolIndex()
        let daemon = DaemonService(
            workspaceRoot: tmpDir,
            symbolIndex: symbolIndex
        )

        // Add a symbol to verify it appears in the report
        await symbolIndex.indexSource("struct Test {}", filePath: "/test.swift", language: .swift)

        let report = await daemon.enrichedHealthReport()
        XCTAssertGreaterThan(report.symbolsIndexed, 0, "Should reflect symbols from injected index")
    }

    func testProcessFileChanges() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a source file
        let swiftFile = tmpDir.appendingPathComponent("Process.swift")
        try "struct ProcessTest {}".write(to: swiftFile, atomically: true, encoding: .utf8)

        let workspace = Workspace(root: tmpDir)
        let symbolIndex = SymbolIndex()
        let daemon = DaemonService(
            workspaceRoot: tmpDir,
            workspace: workspace,
            symbolIndex: symbolIndex
        )

        await daemon.start()

        // Process a file change
        let change = FSFileChange(path: swiftFile.path, kind: .created)
        await daemon.processFileChanges([change])

        let status = await daemon.status
        XCTAssertEqual(status, .idle, "Status should return to idle after processing")

        await daemon.stop()
    }

    func testIndexWorkspace() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-daemon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try "enum Direction { case north, south }".write(
            to: tmpDir.appendingPathComponent("Direction.swift"),
            atomically: true, encoding: .utf8
        )

        let daemon = DaemonService(workspaceRoot: tmpDir)
        await daemon.indexWorkspace()

        let report = await daemon.healthReport()
        XCTAssertNotNil(report.lastIndexTime)
        XCTAssertGreaterThanOrEqual(report.filesIndexed, 1)
    }

    func testWorkspaceRootPreserved() async {
        let path = URL(fileURLWithPath: "/tmp/test-workspace")
        let daemon = DaemonService(workspaceRoot: path)
        let root = await daemon.workspaceRoot
        XCTAssertEqual(root.path, path.standardizedFileURL.path)
    }
}
