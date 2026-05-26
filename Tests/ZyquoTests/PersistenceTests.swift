import XCTest
@testable import Zyquo

// MARK: - SessionStore Tests

final class SessionStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: SessionStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SessionStore(baseDir: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - SessionRecord Tests

    func testSaveAndLoadSessionRecord() async throws {
        let id = SessionID(value: "zq_20260526_test1")
        let record = makeRecord(id: id, intent: "fix failing tests")

        try await store.save(record)
        let loaded = try await store.load(id: id)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.sessionId, id)
        XCTAssertEqual(loaded?.intent, "fix failing tests")
        XCTAssertEqual(loaded?.status, "done")
        XCTAssertEqual(loaded?.model, "claude-sonnet-4-6")
        XCTAssertEqual(loaded?.provider, "anthropic")
        XCTAssertEqual(loaded?.stepsCompleted, 3)
        XCTAssertEqual(loaded?.stepsTotal, 5)
    }

    func testLoadNonExistentSessionReturnsNil() async throws {
        let id = SessionID(value: "zq_20260526_doesnotexist")
        let loaded = try await store.load(id: id)
        XCTAssertNil(loaded)
    }

    func testListSessionsSortedByDateDescending() async throws {
        let now = Date()

        let id1 = SessionID(value: "zq_20260524_old")
        let record1 = makeRecord(id: id1, intent: "oldest", updatedAt: now.addingTimeInterval(-86400))

        let id2 = SessionID(value: "zq_20260525_mid")
        let record2 = makeRecord(id: id2, intent: "middle", updatedAt: now.addingTimeInterval(-3600))

        let id3 = SessionID(value: "zq_20260526_new")
        let record3 = makeRecord(id: id3, intent: "newest", updatedAt: now)

        try await store.save(record1)
        try await store.save(record2)
        try await store.save(record3)

        let list = await store.list(limit: 50)
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].sessionId, id3)  // newest first
        XCTAssertEqual(list[1].sessionId, id2)
        XCTAssertEqual(list[2].sessionId, id1)  // oldest last
    }

    func testDeleteRemovesSessionFile() async throws {
        let id = SessionID(value: "zq_20260526_del")
        let record = makeRecord(id: id, intent: "to be deleted")

        try await store.save(record)
        let beforeDelete = try await store.load(id: id)
        XCTAssertNotNil(beforeDelete)

        try await store.delete(id: id)
        let afterDelete = try await store.load(id: id)
        XCTAssertNil(afterDelete)
    }

    func testMultipleSessionsListedCorrectly() async throws {
        for i in 0..<5 {
            let id = SessionID(value: "zq_20260526_multi\(i)")
            let record = makeRecord(id: id, intent: "session \(i)")
            try await store.save(record)
        }

        let list = await store.list(limit: 10)
        XCTAssertEqual(list.count, 5)
    }

    func testListRespectsLimit() async throws {
        for i in 0..<10 {
            let id = SessionID(value: "zq_20260526_lim\(i)")
            let record = makeRecord(id: id, intent: "session \(i)")
            try await store.save(record)
        }

        let list = await store.list(limit: 3)
        XCTAssertEqual(list.count, 3)
    }

    func testSessionRecordEncodesDecodesCorrectly() throws {
        let id = SessionID(value: "zq_20260526_enc")
        let record = SessionRecord(
            sessionId: id,
            intent: "test encoding",
            planSteps: [
                PersistablePlanStep(goal: "step 1", successCriteria: "tests pass"),
                PersistablePlanStep(goal: "step 2", successCriteria: "builds clean"),
            ],
            status: "done",
            model: "claude-sonnet-4-6",
            provider: "anthropic",
            totalInputTokens: 5000,
            totalOutputTokens: 2000,
            totalCostUSD: 0.042,
            startedAt: Date(timeIntervalSince1970: 1716710400),
            updatedAt: Date(timeIntervalSince1970: 1716710500),
            stepsCompleted: 2,
            stepsTotal: 2,
            checkpointHash: "abc123"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionRecord.self, from: data)

        XCTAssertEqual(decoded.sessionId, id)
        XCTAssertEqual(decoded.intent, "test encoding")
        XCTAssertEqual(decoded.planSteps.count, 2)
        XCTAssertEqual(decoded.planSteps[0].goal, "step 1")
        XCTAssertEqual(decoded.status, "done")
        XCTAssertEqual(decoded.totalInputTokens, 5000)
        XCTAssertEqual(decoded.totalOutputTokens, 2000)
        XCTAssertEqual(decoded.totalCostUSD, 0.042)
        XCTAssertEqual(decoded.stepsCompleted, 2)
        XCTAssertEqual(decoded.checkpointHash, "abc123")
    }

    // MARK: - SessionEvent Tests

    func testAppendAndLoadEvents() async throws {
        let id = SessionID(value: "zq_20260526_evt")

        let event1 = SessionEvent.stepStarted(StepStartedEvent(stepIndex: 0, goal: "read files"))
        let event2 = SessionEvent.toolExecuted(ToolExecutedEvent(
            toolName: "file.read", summary: "Read main.swift", isError: false, durationMs: 12
        ))
        let event3 = SessionEvent.stepCompleted(StepCompletedEvent(
            stepIndex: 0, verdict: "pass", durationMs: 150
        ))

        try await store.appendEvent(sessionId: id, event: event1)
        try await store.appendEvent(sessionId: id, event: event2)
        try await store.appendEvent(sessionId: id, event: event3)

        let events = await store.loadEvents(sessionId: id)
        XCTAssertEqual(events.count, 3)

        // Check first event
        if case .stepStarted(let e) = events[0] {
            XCTAssertEqual(e.stepIndex, 0)
            XCTAssertEqual(e.goal, "read files")
        } else {
            XCTFail("Expected stepStarted event")
        }

        // Check second event
        if case .toolExecuted(let e) = events[1] {
            XCTAssertEqual(e.toolName, "file.read")
            XCTAssertFalse(e.isError)
        } else {
            XCTFail("Expected toolExecuted event")
        }

        // Check third event
        if case .stepCompleted(let e) = events[2] {
            XCTAssertEqual(e.verdict, "pass")
            XCTAssertEqual(e.durationMs, 150)
        } else {
            XCTFail("Expected stepCompleted event")
        }
    }

    func testEventJSONLRoundTrip() throws {
        let event = SessionEvent.error(ErrorEvent(
            message: "Tool failed", code: "tool.error"
        ))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionEvent.self, from: data)

        if case .error(let e) = decoded {
            XCTAssertEqual(e.message, "Tool failed")
            XCTAssertEqual(e.code, "tool.error")
        } else {
            XCTFail("Expected error event")
        }
    }

    func testLoadEventsFromEmptyFileReturnsEmpty() async {
        let id = SessionID(value: "zq_20260526_nope")
        let events = await store.loadEvents(sessionId: id)
        XCTAssertTrue(events.isEmpty)
    }

    func testDeleteAlsoRemovesEvents() async throws {
        let id = SessionID(value: "zq_20260526_delboth")
        let record = makeRecord(id: id, intent: "delete both")
        try await store.save(record)

        let event = SessionEvent.stepStarted(StepStartedEvent(stepIndex: 0, goal: "test"))
        try await store.appendEvent(sessionId: id, event: event)

        try await store.delete(id: id)

        let loaded = try await store.load(id: id)
        XCTAssertNil(loaded)
        let events = await store.loadEvents(sessionId: id)
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - SessionRecord Helpers

    func testIntentPreview() {
        let short = makeRecord(
            id: SessionID(value: "zq_test_short"),
            intent: "fix tests"
        )
        XCTAssertEqual(short.intentPreview, "fix tests")

        let long = makeRecord(
            id: SessionID(value: "zq_test_long"),
            intent: String(repeating: "a", count: 100)
        )
        XCTAssertEqual(long.intentPreview.count, 60)
        XCTAssertTrue(long.intentPreview.hasSuffix("..."))
    }

    func testFormattedCost() {
        let record = makeRecord(
            id: SessionID(value: "zq_test_cost"),
            intent: "cost test",
            costUSD: 0.0567
        )
        XCTAssertEqual(record.formattedCost, "$0.0567")
    }

    // MARK: - Helpers

    private func makeRecord(
        id: SessionID,
        intent: String,
        updatedAt: Date = Date(),
        costUSD: Double = 0.0
    ) -> SessionRecord {
        SessionRecord(
            sessionId: id,
            intent: intent,
            planSteps: [
                PersistablePlanStep(goal: "step 1", successCriteria: "ok"),
            ],
            status: "done",
            model: "claude-sonnet-4-6",
            provider: "anthropic",
            totalInputTokens: 1000,
            totalOutputTokens: 500,
            totalCostUSD: costUSD,
            startedAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            stepsCompleted: 3,
            stepsTotal: 5
        )
    }
}

// MARK: - MemoryStore Tests

final class MemoryStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: MemoryStore!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-mem-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = MemoryStore(baseDir: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testReadProjectMemoryFromFile() async throws {
        let content = """
        # Project Memory

        ## Architecture

        This is a Swift CLI tool.

        ## Conventions

        Use 4-space indentation.
        """
        let path = tempDir.appendingPathComponent("project.md")
        try content.write(to: path, atomically: true, encoding: .utf8)

        let result = await store.readProject()
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("Swift CLI tool"))
    }

    func testReadReturnsNilWhenFileMissing() async {
        let result = await store.readProject()
        XCTAssertNil(result)
    }

    func testSearchFindsMatchingChunks() async throws {
        let content = """
        # Project Memory

        ## Architecture

        This project uses Swift concurrency with actors and structured tasks.

        ## Testing

        Run swift test to execute the test suite. Use XCTest framework.
        """
        let path = tempDir.appendingPathComponent("project.md")
        try content.write(to: path, atomically: true, encoding: .utf8)

        let results = await store.search(query: "swift concurrency actors", scope: .project, limit: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results[0].content.contains("concurrency"))
    }

    func testSearchEmptyQueryReturnsNothing() async throws {
        let content = "# Project\n\n## Section\n\nSome content here."
        let path = tempDir.appendingPathComponent("project.md")
        try content.write(to: path, atomically: true, encoding: .utf8)

        let results = await store.search(query: "", scope: .project, limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testAppendDecisionCreatesFile() async throws {
        let entry = DecisionEntry(
            title: "Use actors for stores",
            context: "Need thread-safe persistence",
            decision: "Use Swift actors for all store types",
            consequences: "Simple concurrency model but requires async calls",
            alternatives: "Dispatch queues, locks",
            status: "accepted"
        )

        try await store.appendDecision(entry)

        let decisions = await store.readDecisions()
        XCTAssertNotNil(decisions)
        XCTAssertTrue(decisions!.contains("Use actors for stores"))
        XCTAssertTrue(decisions!.contains("accepted"))
    }

    func testAppendMultipleDecisions() async throws {
        let entry1 = DecisionEntry(
            title: "Decision 1",
            context: "Context 1",
            decision: "Do thing 1",
            consequences: "Result 1",
            alternatives: "None"
        )
        let entry2 = DecisionEntry(
            title: "Decision 2",
            context: "Context 2",
            decision: "Do thing 2",
            consequences: "Result 2",
            alternatives: "Thing 3"
        )

        try await store.appendDecision(entry1)
        try await store.appendDecision(entry2)

        let decisions = await store.readDecisions()
        XCTAssertNotNil(decisions)
        XCTAssertTrue(decisions!.contains("Decision 1"))
        XCTAssertTrue(decisions!.contains("Decision 2"))
    }

    func testSearchAcrossScopes() async throws {
        let project = "# Project\n\n## Config\n\nUses TOML configuration files for settings."
        let arch = "# Architecture\n\n## Layers\n\nThree-layer architecture with TOML config."
        try project.write(to: tempDir.appendingPathComponent("project.md"), atomically: true, encoding: .utf8)
        try arch.write(to: tempDir.appendingPathComponent("architecture.md"), atomically: true, encoding: .utf8)

        let results = await store.search(query: "TOML configuration", scope: .all, limit: 10)
        XCTAssertGreaterThanOrEqual(results.count, 2)

        let sources = Set(results.map(\.source))
        XCTAssertTrue(sources.contains("project"))
        XCTAssertTrue(sources.contains("architecture"))
    }

    func testSearchNoMatchReturnsEmpty() async throws {
        let content = "# Project\n\n## Notes\n\nThis is about database design."
        try content.write(to: tempDir.appendingPathComponent("project.md"), atomically: true, encoding: .utf8)

        let results = await store.search(query: "kubernetes deployment", scope: .project, limit: 10)
        XCTAssertTrue(results.isEmpty)
    }
}

// MARK: - SessionMemory Tests

final class SessionMemoryTests: XCTestCase {

    func testAppendAndRecallEntries() {
        var memory = SessionMemory()

        memory.append(MemoryEntry(
            kind: .toolCall,
            content: "Executed file.read on main.swift",
            metadata: ["tool": "file.read", "file": "main.swift"]
        ))
        memory.append(MemoryEntry(
            kind: .observation,
            content: "File main.swift contains 120 lines of Swift code",
            metadata: ["tool": "file.read"]
        ))
        memory.append(MemoryEntry(
            kind: .toolCall,
            content: "Executed shell.run: swift test",
            metadata: ["tool": "shell.run"]
        ))

        XCTAssertEqual(memory.entries.count, 3)

        let results = memory.recall(query: "swift main", limit: 5)
        XCTAssertFalse(results.isEmpty)
        // Both entries mentioning "swift" should be returned
        XCTAssertTrue(results.contains(where: { $0.content.contains("main.swift") }))
    }

    func testRecallFiltersAndRanks() {
        var memory = SessionMemory()

        memory.append(MemoryEntry(
            kind: .note,
            content: "The authentication module handles user login and token refresh"
        ))
        memory.append(MemoryEntry(
            kind: .note,
            content: "Database schema uses SQLite with FTS5 for search"
        ))
        memory.append(MemoryEntry(
            kind: .note,
            content: "Authentication tokens are stored securely in the macOS Keychain"
        ))

        let results = memory.recall(query: "authentication token", limit: 5)
        XCTAssertGreaterThanOrEqual(results.count, 2)
        // Both auth entries should rank higher than the database entry
        XCTAssertTrue(results[0].content.lowercased().contains("authentication") ||
                      results[0].content.lowercased().contains("token"))
    }

    func testEmptyMemoryReturnsEmpty() {
        let memory = SessionMemory()
        let results = memory.recall(query: "anything", limit: 10)
        XCTAssertTrue(results.isEmpty)
    }

    func testMemoryEntryEncoding() throws {
        let entry = MemoryEntry(
            timestamp: Date(timeIntervalSince1970: 1716710400),
            kind: .decision,
            content: "Decided to use actors",
            metadata: ["scope": "persistence"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MemoryEntry.self, from: data)

        XCTAssertEqual(decoded.kind, .decision)
        XCTAssertEqual(decoded.content, "Decided to use actors")
        XCTAssertEqual(decoded.metadata["scope"], "persistence")
    }

    func testRecallWithEmptyQuery() {
        var memory = SessionMemory()
        memory.append(MemoryEntry(kind: .note, content: "some content"))

        let results = memory.recall(query: "", limit: 10)
        XCTAssertTrue(results.isEmpty)
    }
}

// MARK: - ProjectMemory Tests

final class ProjectMemoryTests: XCTestCase {

    func testParseSectionsFromMarkdown() {
        let content = """
        # Project Memory

        ## Architecture

        This is a Swift CLI tool with actor-based persistence.

        ## Conventions

        Use 4-space indentation. Prefer value types.

        ## Test Commands

        swift test
        """

        let pm = ProjectMemory(content: content)
        XCTAssertEqual(pm.sections.count, 4) // "Project Memory", "Architecture", "Conventions", "Test Commands"
        XCTAssertTrue(pm.sections.contains(where: { $0.title == "Architecture" }))
        XCTAssertTrue(pm.sections.contains(where: { $0.title == "Conventions" }))
    }

    func testSectionLookupByName() {
        let content = """
        # Project

        ## Build

        Run swift build to compile.

        ## Test

        Run swift test to test.
        """

        let pm = ProjectMemory(content: content)
        let build = pm.section(named: "Build")
        XCTAssertNotNil(build)
        XCTAssertTrue(build!.contains("swift build"))

        let test = pm.section(named: "Test")
        XCTAssertNotNil(test)
        XCTAssertTrue(test!.contains("swift test"))
    }

    func testSectionLookupCaseInsensitive() {
        let content = "# Proj\n\n## Architecture\n\nDetails here."
        let pm = ProjectMemory(content: content)

        XCTAssertNotNil(pm.section(named: "architecture"))
        XCTAssertNotNil(pm.section(named: "ARCHITECTURE"))
    }

    func testEmptyContent() {
        let pm = ProjectMemory(content: "")
        XCTAssertTrue(pm.sections.isEmpty)
        XCTAssertNil(pm.section(named: "anything"))
    }

    func testUserWrittenDetection() {
        let content = """
        # Project

        ## My Notes

        These are my personal notes about the project.

        ## Auto Section

        <!-- generated by zyquo -->
        This was auto-generated.
        """

        let pm = ProjectMemory(content: content)

        let myNotes = pm.sections.first(where: { $0.title == "My Notes" })
        XCTAssertNotNil(myNotes)
        XCTAssertTrue(myNotes!.isUserWritten)

        let autoSection = pm.sections.first(where: { $0.title == "Auto Section" })
        XCTAssertNotNil(autoSection)
        XCTAssertFalse(autoSection!.isUserWritten)
    }

    func testSectionWithoutContent() {
        let content = """
        # Project

        ## Empty Section

        ## Another Section

        Has content.
        """

        let pm = ProjectMemory(content: content)
        let empty = pm.section(named: "Empty Section")
        XCTAssertNotNil(empty)
        XCTAssertEqual(empty, "")
    }

    func testNonExistentSectionReturnsNil() {
        let content = "# Project\n\n## Existing\n\nContent."
        let pm = ProjectMemory(content: content)
        XCTAssertNil(pm.section(named: "NonExistent"))
    }
}

// MARK: - MemoryCompressor Tests

final class MemoryCompressorTests: XCTestCase {

    func testCompressReducesEntryCount() {
        let compressor = MemoryCompressor()

        var entries: [MemoryEntry] = []
        for i in 0..<20 {
            entries.append(MemoryEntry(
                kind: .toolCall,
                content: "Executed file.read on file_\(i).swift to read source code for analysis",
                metadata: ["tool": "file.read", "file": "file_\(i).swift"]
            ))
        }

        // Set a very small token budget to force compression
        let compressed = compressor.compress(entries: entries, maxTokens: 50)

        XCTAssertLessThan(compressed.count, entries.count)
    }

    func testDecisionsPreservedVerbatim() {
        let compressor = MemoryCompressor()

        var entries: [MemoryEntry] = []
        // Add many regular entries
        for i in 0..<15 {
            entries.append(MemoryEntry(
                kind: .toolCall,
                content: "Regular tool call number \(i) with some extra padding text for token usage",
                metadata: ["tool": "file.read"]
            ))
        }
        // Add a decision
        let decision = MemoryEntry(
            kind: .decision,
            content: "Important decision: use actors for thread safety",
            metadata: ["scope": "architecture"]
        )
        entries.append(decision)
        // Add an error
        let error = MemoryEntry(
            kind: .error,
            content: "Build failed with error in AuthManager.swift",
            metadata: ["code": "build.failed"]
        )
        entries.append(error)

        let compressed = compressor.compress(entries: entries, maxTokens: 50)

        // Decision and error should be preserved
        XCTAssertTrue(compressed.contains(where: { $0.kind == .decision }))
        XCTAssertTrue(compressed.contains(where: { $0.kind == .error }))
        XCTAssertTrue(compressed.contains(where: { $0.content.contains("actors for thread safety") }))
    }

    func testEmptyInputReturnsEmpty() {
        let compressor = MemoryCompressor()
        let result = compressor.compress(entries: [], maxTokens: 1000)
        XCTAssertTrue(result.isEmpty)
    }

    func testEntriesWithinBudgetReturnedAsIs() {
        let compressor = MemoryCompressor()

        let entries = [
            MemoryEntry(kind: .note, content: "Short note"),
            MemoryEntry(kind: .note, content: "Another short note"),
        ]

        // Very large budget - should return as-is
        let result = compressor.compress(entries: entries, maxTokens: 100000)
        XCTAssertEqual(result.count, entries.count)
    }
}

// MARK: - MemoryRetriever Tests

final class MemoryRetrieverTests: XCTestCase {

    func testKeywordRetrieverSearches() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-ret-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = """
        # Project

        ## Architecture

        Uses Swift actors for concurrency safety and structured tasks.

        ## Database

        SQLite with FTS5 for full-text search.
        """
        try content.write(
            to: tempDir.appendingPathComponent("project.md"),
            atomically: true,
            encoding: .utf8
        )

        let memoryStore = MemoryStore(baseDir: tempDir)
        let retriever = KeywordMemoryRetriever(memoryStore: memoryStore)

        let chunks = try await retriever.recall(query: "swift actors concurrency", scope: .project, limit: 5)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks[0].content.contains("actors"))
    }
}

// MARK: - ConfigStore Tests

final class ConfigStoreTests: XCTestCase {

    func testLoadWorkspaceConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-cfg-\(UUID().uuidString)")
        let zyquoDir = tempDir.appendingPathComponent(".zyquo")
        try FileManager.default.createDirectory(at: zyquoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config: [String: Any] = [
            "version": 1,
            "provider": "anthropic",
            "model": "claude-sonnet-4-6",
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted])
        try data.write(to: zyquoDir.appendingPathComponent("config.json"))

        let loaded = ConfigStore.loadWorkspaceConfig(at: tempDir)
        XCTAssertEqual(loaded["version"] as? Int, 1)
        XCTAssertEqual(loaded["provider"] as? String, "anthropic")
    }

    func testLoadMissingWorkspaceConfigReturnsEmpty() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-cfg-missing-\(UUID().uuidString)")
        let loaded = ConfigStore.loadWorkspaceConfig(at: tempDir)
        XCTAssertTrue(loaded.isEmpty)
    }

    func testSaveAndLoadWorkspaceConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-cfg-save-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config: [String: Any] = [
            "version": 1,
            "provider": "openrouter",
        ]

        try ConfigStore.saveWorkspaceConfig(config, at: tempDir)

        let loaded = ConfigStore.loadWorkspaceConfig(at: tempDir)
        XCTAssertEqual(loaded["version"] as? Int, 1)
        XCTAssertEqual(loaded["provider"] as? String, "openrouter")
    }
}

// MARK: - DecisionEntry Tests

final class DecisionEntryTests: XCTestCase {

    func testRenderMarkdown() {
        let entry = DecisionEntry(
            title: "Use actors",
            context: "Need thread safety",
            decision: "Use Swift actors",
            consequences: "Requires async calls",
            alternatives: "Locks, queues",
            status: "accepted",
            date: Date(timeIntervalSince1970: 1716710400)
        )

        let md = entry.renderMarkdown()
        XCTAssertTrue(md.contains("## Use actors"))
        XCTAssertTrue(md.contains("**Status:** accepted"))
        XCTAssertTrue(md.contains("**Decision:** Use Swift actors"))
        XCTAssertTrue(md.contains("**Alternatives considered:** Locks, queues"))
    }

    func testDecisionEntryEncodable() throws {
        let entry = DecisionEntry(
            title: "Test",
            context: "ctx",
            decision: "dec",
            consequences: "con",
            alternatives: "alt",
            date: Date(timeIntervalSince1970: 1716710400)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DecisionEntry.self, from: data)

        XCTAssertEqual(decoded.title, "Test")
        XCTAssertEqual(decoded.status, "accepted")
    }
}

// MARK: - PersistablePlanStep Tests

final class PersistablePlanStepTests: XCTestCase {

    func testInitFromPlanStep() {
        let planStep = PlanStep(goal: "Read files", successCriteria: "All files read")
        let persistable = PersistablePlanStep(from: planStep)
        XCTAssertEqual(persistable.goal, "Read files")
        XCTAssertEqual(persistable.successCriteria, "All files read")
    }
}
