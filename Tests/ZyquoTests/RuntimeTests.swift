import XCTest
@testable import Zyquo

final class RuntimeTests: XCTestCase {

    // MARK: - SessionCheckpoint Tests

    func testSessionCheckpointEncodingDecoding() throws {
        let cp = SessionCheckpoint(
            id: "zcp_test_s5_abc1",
            sessionId: "zq_20260526_1234",
            timestamp: Date(timeIntervalSince1970: 1716700000),
            stepIndex: 5,
            status: "executing",
            contextSummary: "Intent: fix tests | Steps: 5/8 | Status: executing",
            tokensUsed: 12000,
            cost: 0.0234
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cp)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionCheckpoint.self, from: data)

        XCTAssertEqual(decoded.id, cp.id)
        XCTAssertEqual(decoded.sessionId, cp.sessionId)
        XCTAssertEqual(decoded.stepIndex, 5)
        XCTAssertEqual(decoded.status, "executing")
        XCTAssertEqual(decoded.contextSummary, cp.contextSummary)
        XCTAssertEqual(decoded.tokensUsed, 12000)
        XCTAssertEqual(decoded.cost, 0.0234, accuracy: 0.0001)
    }

    func testSessionCheckpointGenerateId() {
        let id = SessionCheckpoint.generateId(sessionId: "zq_test", stepIndex: 7)
        XCTAssertTrue(id.hasPrefix("zcp_zq_test_s7_"))
    }

    // MARK: - LongLivedSession Tests

    func testLongLivedSessionCheckpointAndResumeCount() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionId = SessionID(value: "zq_test_lls")
        let session = LongLivedSession(
            sessionId: sessionId,
            storageDir: tempDir,
            checkpointInterval: 3
        )

        let state = AgentState(
            sessionId: sessionId,
            intent: "Fix failing tests",
            plan: Plan(steps: [
                PlanStep(goal: "Read test output", successCriteria: "Got output"),
                PlanStep(goal: "Fix code", successCriteria: "Code fixed"),
            ]),
            steps: [
                AgentStep(index: 0, goal: "Read test output", successCriteria: "Got output"),
                AgentStep(index: 1, goal: "Fix code", successCriteria: "Code fixed"),
                AgentStep(index: 2, goal: "Re-run tests", successCriteria: "Tests pass"),
            ],
            status: .executing
        )

        try await session.checkpoint(state: state)

        let checkpoints = await session.checkpoints
        XCTAssertEqual(checkpoints.count, 1)
        XCTAssertEqual(checkpoints[0].stepIndex, 3)
        XCTAssertEqual(checkpoints[0].status, "executing")

        // Resume should increment count
        let resumeCount1 = await session.resumeCount
        XCTAssertEqual(resumeCount1, 0)

        _ = try await session.resume()
        let resumeCount2 = await session.resumeCount
        XCTAssertEqual(resumeCount2, 1)

        _ = try await session.resume()
        let resumeCount3 = await session.resumeCount
        XCTAssertEqual(resumeCount3, 2)
    }

    func testLongLivedSessionStaleDetection() async {
        let sessionId = SessionID(value: "zq_stale_test")
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_\(UUID().uuidString)")

        // Created 31 days ago, never resumed
        let oldDate = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
        let session = LongLivedSession(
            sessionId: sessionId,
            storageDir: tempDir,
            createdAt: oldDate
        )

        let stale = await session.isStale
        XCTAssertTrue(stale)

        // A session created today should not be stale
        let freshSession = LongLivedSession(
            sessionId: SessionID(value: "zq_fresh_test"),
            storageDir: tempDir,
            createdAt: Date()
        )

        let freshStale = await freshSession.isStale
        XCTAssertFalse(freshStale)
    }

    func testLongLivedSessionShouldCheckpoint() async {
        let session = LongLivedSession(
            sessionId: SessionID(value: "zq_cp_interval"),
            storageDir: FileManager.default.temporaryDirectory,
            checkpointInterval: 5
        )

        let should0 = await session.shouldCheckpoint(stepIndex: 0)
        XCTAssertFalse(should0)

        let should3 = await session.shouldCheckpoint(stepIndex: 3)
        XCTAssertFalse(should3)

        let should5 = await session.shouldCheckpoint(stepIndex: 5)
        XCTAssertTrue(should5)

        let should10 = await session.shouldCheckpoint(stepIndex: 10)
        XCTAssertTrue(should10)
    }

    func testLongLivedSessionHistory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sessionId = SessionID(value: "zq_history_test")
        let session = LongLivedSession(
            sessionId: sessionId,
            storageDir: tempDir,
            checkpointInterval: 2
        )

        // Create multiple checkpoints
        for i in 0..<3 {
            let state = AgentState(
                sessionId: sessionId,
                intent: "test intent",
                steps: (0...i).map { AgentStep(index: $0, goal: "step \($0)", successCriteria: "done") },
                status: .executing
            )
            try await session.checkpoint(state: state)
        }

        let history = await session.history()
        XCTAssertEqual(history.count, 3)
        // Verify chronological order
        for i in 1..<history.count {
            XCTAssertTrue(history[i].timestamp >= history[i - 1].timestamp)
        }
    }

    // MARK: - ScheduledWorkflow Tests

    func testScheduledWorkflowEncodingDecoding() throws {
        let workflow = ScheduledWorkflow(
            id: "zwf_test_abc",
            name: "Daily Test Run",
            schedule: .daily(hour: 9, minute: 30),
            intent: "Run all tests and report failures",
            skillId: "fix_failing_tests",
            maxCostPerRun: 1.50,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 1716700000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(workflow)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ScheduledWorkflow.self, from: data)

        XCTAssertEqual(decoded.id, workflow.id)
        XCTAssertEqual(decoded.name, "Daily Test Run")
        XCTAssertEqual(decoded.intent, "Run all tests and report failures")
        XCTAssertEqual(decoded.skillId, "fix_failing_tests")
        XCTAssertEqual(decoded.maxCostPerRun, 1.50, accuracy: 0.01)
        XCTAssertTrue(decoded.enabled)
        XCTAssertNil(decoded.lastRunAt)
        XCTAssertNil(decoded.lastResult)
    }

    func testScheduledWorkflowGenerateId() {
        let id = ScheduledWorkflow.generateId(name: "My Test Workflow")
        XCTAssertTrue(id.hasPrefix("zwf_"))
        XCTAssertTrue(id.contains("my_test_workflow"))
    }

    func testScheduledWorkflowIntentPreview() {
        let short = ScheduledWorkflow(
            id: "w1", name: "w", schedule: .interval(seconds: 60),
            intent: "Short intent"
        )
        XCTAssertEqual(short.intentPreview, "Short intent")

        let long = ScheduledWorkflow(
            id: "w2", name: "w", schedule: .interval(seconds: 60),
            intent: String(repeating: "a", count: 100)
        )
        XCTAssertTrue(long.intentPreview.count <= 50)
        XCTAssertTrue(long.intentPreview.hasSuffix("..."))
    }

    func testScheduledWorkflowShouldRunNowInterval() {
        let now = Date()
        let fiveMinutesAgo = now.addingTimeInterval(-300)

        var workflow = ScheduledWorkflow(
            id: "w1", name: "w", schedule: .interval(seconds: 60),
            intent: "test", enabled: true
        )
        // Never run before — should run
        XCTAssertTrue(workflow.shouldRunNow(currentTime: now))

        // Ran recently — should not run
        workflow.lastRunAt = now.addingTimeInterval(-30)
        XCTAssertFalse(workflow.shouldRunNow(currentTime: now))

        // Ran long enough ago — should run
        workflow.lastRunAt = fiveMinutesAgo
        XCTAssertTrue(workflow.shouldRunNow(currentTime: now))
    }

    func testScheduledWorkflowDisabledDoesNotRun() {
        let workflow = ScheduledWorkflow(
            id: "w1", name: "w", schedule: .interval(seconds: 1),
            intent: "test", enabled: false
        )
        XCTAssertFalse(workflow.shouldRunNow())
    }

    // MARK: - WorkflowSchedule Tests

    func testWorkflowScheduleIntervalEncodeDecode() throws {
        let schedule = WorkflowSchedule.interval(seconds: 300)
        let encoder = JSONEncoder()
        let data = try encoder.encode(schedule)
        let decoded = try JSONDecoder().decode(WorkflowSchedule.self, from: data)
        XCTAssertEqual(decoded, schedule)
    }

    func testWorkflowScheduleDailyEncodeDecode() throws {
        let schedule = WorkflowSchedule.daily(hour: 14, minute: 30)
        let encoder = JSONEncoder()
        let data = try encoder.encode(schedule)
        let decoded = try JSONDecoder().decode(WorkflowSchedule.self, from: data)
        XCTAssertEqual(decoded, schedule)
    }

    func testWorkflowScheduleWeeklyEncodeDecode() throws {
        let schedule = WorkflowSchedule.weekly(dayOfWeek: 2, hour: 9, minute: 0)
        let encoder = JSONEncoder()
        let data = try encoder.encode(schedule)
        let decoded = try JSONDecoder().decode(WorkflowSchedule.self, from: data)
        XCTAssertEqual(decoded, schedule)
    }

    func testWorkflowScheduleOnFileChangeEncodeDecode() throws {
        let schedule = WorkflowSchedule.onFileChange(patterns: ["*.swift", "Package.swift"])
        let encoder = JSONEncoder()
        let data = try encoder.encode(schedule)
        let decoded = try JSONDecoder().decode(WorkflowSchedule.self, from: data)
        XCTAssertEqual(decoded, schedule)
    }

    func testWorkflowScheduleDisplayString() {
        XCTAssertEqual(
            WorkflowSchedule.interval(seconds: 300).displayString,
            "every 5m"
        )
        XCTAssertEqual(
            WorkflowSchedule.interval(seconds: 7200).displayString,
            "every 2h"
        )
        XCTAssertEqual(
            WorkflowSchedule.interval(seconds: 45).displayString,
            "every 45s"
        )
        XCTAssertEqual(
            WorkflowSchedule.daily(hour: 9, minute: 5).displayString,
            "daily at 09:05"
        )
        XCTAssertEqual(
            WorkflowSchedule.weekly(dayOfWeek: 2, hour: 14, minute: 0).displayString,
            "Monday at 14:00"
        )
        XCTAssertTrue(
            WorkflowSchedule.onFileChange(patterns: ["*.swift"]).displayString.contains("*.swift")
        )
    }

    // MARK: - WorkflowRunResult Tests

    func testWorkflowRunResultProperties() {
        let start = Date(timeIntervalSince1970: 1716700000)
        let finish = Date(timeIntervalSince1970: 1716700090)

        let result = WorkflowRunResult(
            workflowId: "zwf_test",
            runId: "zwr_test_abc",
            startedAt: start,
            finishedAt: finish,
            status: .success,
            summary: "All tests passed",
            cost: 0.0456
        )

        XCTAssertEqual(result.workflowId, "zwf_test")
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.duration, 90.0, accuracy: 0.1)
        XCTAssertEqual(result.formattedDuration, "1m 30s")
        XCTAssertEqual(result.cost, 0.0456, accuracy: 0.0001)
    }

    func testWorkflowRunResultEncodeDecode() throws {
        let result = WorkflowRunResult(
            workflowId: "zwf_test",
            runId: "zwr_test_123",
            startedAt: Date(timeIntervalSince1970: 1716700000),
            finishedAt: Date(timeIntervalSince1970: 1716700060),
            status: .failure,
            summary: "Build failed",
            cost: 0.12
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkflowRunResult.self, from: data)

        XCTAssertEqual(decoded, result)
    }

    func testWorkflowRunResultGenerateRunId() {
        let id = WorkflowRunResult.generateRunId(workflowId: "zwf_test")
        XCTAssertTrue(id.hasPrefix("zwr_zwf_test_"))
    }

    // MARK: - WorkflowStore Tests

    func testWorkflowStoreSaveLoadListDelete() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_wfstore_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkflowStore(path: tempDir)

        let wf1 = ScheduledWorkflow(
            id: "zwf_alpha", name: "Alpha",
            schedule: .interval(seconds: 60),
            intent: "Run alpha task",
            createdAt: Date(timeIntervalSince1970: 1716700000)
        )
        let wf2 = ScheduledWorkflow(
            id: "zwf_beta", name: "Beta",
            schedule: .daily(hour: 10, minute: 0),
            intent: "Run beta task",
            createdAt: Date(timeIntervalSince1970: 1716800000)
        )

        // Save
        try await store.save(wf1)
        try await store.save(wf2)

        // Load
        let loaded = await store.load(id: "zwf_alpha")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "Alpha")

        // List
        let all = await store.list()
        XCTAssertEqual(all.count, 2)

        // Load non-existent
        let missing = await store.load(id: "zwf_nonexistent")
        XCTAssertNil(missing)

        // Delete
        try await store.delete(id: "zwf_alpha")
        let afterDelete = await store.list()
        XCTAssertEqual(afterDelete.count, 1)
        XCTAssertEqual(afterDelete[0].id, "zwf_beta")
    }

    func testWorkflowStoreRecordAndHistory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_wfhist_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = WorkflowStore(path: tempDir)

        let workflow = ScheduledWorkflow(
            id: "zwf_hist_test", name: "History Test",
            schedule: .interval(seconds: 300),
            intent: "Test history recording"
        )
        try await store.save(workflow)

        // Record multiple runs
        for i in 0..<3 {
            let result = WorkflowRunResult(
                workflowId: "zwf_hist_test",
                runId: "zwr_\(i)",
                startedAt: Date(timeIntervalSince1970: Double(1716700000 + i * 600)),
                finishedAt: Date(timeIntervalSince1970: Double(1716700060 + i * 600)),
                status: i == 1 ? .failure : .success,
                summary: "Run \(i)",
                cost: 0.01 * Double(i + 1)
            )
            try await store.recordRun(result)
        }

        // Query history
        let history = await store.history(workflowId: "zwf_hist_test", limit: 10)
        XCTAssertEqual(history.count, 3)
        // Newest first
        XCTAssertEqual(history[0].runId, "zwr_2")
        XCTAssertEqual(history[2].runId, "zwr_0")

        // Verify workflow was updated with last run info
        let updated = await store.load(id: "zwf_hist_test")
        XCTAssertNotNil(updated?.lastRunAt)
        XCTAssertNotNil(updated?.lastResult)
        XCTAssertEqual(updated?.lastResult?.runId, "zwr_2")
    }

    // MARK: - SkillExtractor Tests

    func testSkillExtractorAnalyzesSuccessfulSession() {
        let extractor = SkillExtractor()

        let session = SessionRecord(
            sessionId: SessionID(value: "zq_extract_test"),
            intent: "Fix the failing Swift build errors",
            planSteps: [
                PersistablePlanStep(goal: "Read build output", successCriteria: "Got output"),
                PersistablePlanStep(goal: "Analyze errors", successCriteria: "Found root cause"),
                PersistablePlanStep(goal: "Apply fix", successCriteria: "Code patched"),
                PersistablePlanStep(goal: "Re-run build", successCriteria: "Build passes"),
                PersistablePlanStep(goal: "Run tests", successCriteria: "Tests pass"),
            ],
            status: "done",
            model: "claude-sonnet-4-6",
            provider: "anthropic",
            totalInputTokens: 15000,
            totalOutputTokens: 3000,
            totalCostUSD: 0.08,
            startedAt: Date(),
            updatedAt: Date(),
            stepsCompleted: 5,
            stepsTotal: 5
        )

        let events: [SessionEvent] = [
            .toolExecuted(ToolExecutedEvent(toolName: "shell.run", summary: "swift build", isError: true, durationMs: 5000)),
            .toolExecuted(ToolExecutedEvent(toolName: "file.read", summary: "read error output", isError: false, durationMs: 50)),
            .toolExecuted(ToolExecutedEvent(toolName: "file.patch", summary: "fix code", isError: false, durationMs: 100)),
            .toolExecuted(ToolExecutedEvent(toolName: "shell.run", summary: "swift build", isError: false, durationMs: 8000)),
            .toolExecuted(ToolExecutedEvent(toolName: "shell.run", summary: "swift test", isError: false, durationMs: 12000)),
        ]

        let candidate = extractor.analyze(session: session, events: events)
        XCTAssertNotNil(candidate)
        XCTAssertFalse(candidate!.suggestedId.isEmpty)
        XCTAssertFalse(candidate!.suggestedTitle.isEmpty)
        XCTAssertTrue(candidate!.toolsUsed.contains("shell.run"))
        XCTAssertTrue(candidate!.toolsUsed.contains("file.read"))
        XCTAssertTrue(candidate!.toolsUsed.contains("file.patch"))
        XCTAssertEqual(candidate!.stepsCount, 5)
        XCTAssertTrue(candidate!.successRate >= 0.6)
        XCTAssertTrue(candidate!.confidence > 0.0)
        XCTAssertFalse(candidate!.suggestedPrompt.isEmpty)
    }

    func testSkillExtractorReturnsNilForFailedSession() {
        let extractor = SkillExtractor()

        let session = SessionRecord(
            sessionId: SessionID(value: "zq_failed_test"),
            intent: "Fix something",
            planSteps: [],
            status: "failed",
            model: "claude-sonnet-4-6",
            provider: "anthropic",
            totalInputTokens: 5000,
            totalOutputTokens: 1000,
            totalCostUSD: 0.02,
            startedAt: Date(),
            updatedAt: Date(),
            stepsCompleted: 2,
            stepsTotal: 5
        )

        let events: [SessionEvent] = [
            .toolExecuted(ToolExecutedEvent(toolName: "shell.run", summary: "cmd", isError: true, durationMs: 100)),
        ]

        let candidate = extractor.analyze(session: session, events: events)
        XCTAssertNil(candidate)
    }

    func testSkillExtractorReturnsNilForTooFewSteps() {
        let extractor = SkillExtractor()

        let session = SessionRecord(
            sessionId: SessionID(value: "zq_short_test"),
            intent: "Quick check",
            planSteps: [],
            status: "done",
            model: "claude-sonnet-4-6",
            provider: "anthropic",
            totalInputTokens: 1000,
            totalOutputTokens: 200,
            totalCostUSD: 0.005,
            startedAt: Date(),
            updatedAt: Date(),
            stepsCompleted: 2,
            stepsTotal: 2
        )

        let events: [SessionEvent] = [
            .toolExecuted(ToolExecutedEvent(toolName: "file.read", summary: "read", isError: false, durationMs: 10)),
        ]

        let candidate = extractor.analyze(session: session, events: events)
        XCTAssertNil(candidate)
    }

    func testExtractedSkillCandidateProperties() {
        let candidate = ExtractedSkillCandidate(
            suggestedId: "fix_build",
            suggestedTitle: "Fix Build Errors",
            toolsUsed: ["shell.run", "file.read", "file.patch"],
            stepsCount: 5,
            successRate: 0.9,
            suggestedPrompt: "Fix the build",
            suggestedBudget: SkillBudget(maxSteps: 10, maxCostUSD: 1.0),
            confidence: 0.75
        )

        XCTAssertTrue(candidate.isViable)
        XCTAssertEqual(candidate.suggestedId, "fix_build")
        XCTAssertEqual(candidate.toolsUsed.count, 3)

        let manifest = candidate.toManifest()
        XCTAssertEqual(manifest.id, "fix_build")
        XCTAssertEqual(manifest.title, "Fix Build Errors")
        XCTAssertEqual(manifest.toolsAllowed, ["shell.run", "file.read", "file.patch"])
        XCTAssertEqual(manifest.budget.maxSteps, 10)
    }

    func testExtractedSkillCandidateLowConfidenceNotViable() {
        let candidate = ExtractedSkillCandidate(
            suggestedId: "weak_skill",
            suggestedTitle: "Weak Skill",
            toolsUsed: ["file.read"],
            stepsCount: 3,
            successRate: 0.5,
            suggestedPrompt: "Do something",
            suggestedBudget: SkillBudget(),
            confidence: 0.2
        )

        XCTAssertFalse(candidate.isViable)
    }

    // MARK: - ProjectSnapshot Tests

    func testProjectSnapshotEncodingDecoding() throws {
        let snapshot = ProjectSnapshot(
            date: Date(timeIntervalSince1970: 1716700000),
            fileCount: 150,
            totalLines: 22000,
            languageBreakdown: ["Swift": 120, "Markdown": 20, "YAML": 10],
            testFileCount: 25,
            docFileCount: 8,
            frameworkCount: 3
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ProjectSnapshot.self, from: data)

        XCTAssertEqual(decoded.fileCount, 150)
        XCTAssertEqual(decoded.totalLines, 22000)
        XCTAssertEqual(decoded.languageBreakdown["Swift"], 120)
        XCTAssertEqual(decoded.testFileCount, 25)
        XCTAssertEqual(decoded.docFileCount, 8)
        XCTAssertEqual(decoded.frameworkCount, 3)
    }

    func testProjectSnapshotPrimaryLanguage() {
        let snapshot = ProjectSnapshot(
            fileCount: 100,
            totalLines: 10000,
            languageBreakdown: ["Swift": 80, "Python": 15, "Shell": 5]
        )
        XCTAssertEqual(snapshot.primaryLanguage, "Swift")
    }

    func testProjectSnapshotTestRatio() {
        let snapshot = ProjectSnapshot(
            fileCount: 100,
            totalLines: 10000,
            testFileCount: 20,
            docFileCount: 5
        )
        // sourceFiles = 100 - 20 - 5 = 75
        // testRatio = 20 / 75
        XCTAssertEqual(snapshot.testRatio, 20.0 / 75.0, accuracy: 0.001)
    }

    // MARK: - ProjectEvolution Tests

    func testProjectEvolutionCompareProducesDelta() {
        let evolution = ProjectEvolution()

        let old = ProjectSnapshot(
            date: Date(timeIntervalSince1970: 1716000000),
            fileCount: 100,
            totalLines: 10000,
            languageBreakdown: ["Swift": 80, "Python": 20],
            testFileCount: 15,
            docFileCount: 5,
            frameworkCount: 2
        )

        let new = ProjectSnapshot(
            date: Date(timeIntervalSince1970: 1716700000),
            fileCount: 130,
            totalLines: 14000,
            languageBreakdown: ["Swift": 100, "Python": 20, "TypeScript": 10],
            testFileCount: 22,
            docFileCount: 8,
            frameworkCount: 3
        )

        let delta = evolution.compare(old: old, new: new)

        XCTAssertEqual(delta.filesAdded, 30)
        XCTAssertEqual(delta.filesRemoved, 0)
        XCTAssertEqual(delta.linesAdded, 4000)
        XCTAssertEqual(delta.linesRemoved, 0)
        XCTAssertEqual(delta.newLanguages, ["TypeScript"])
        XCTAssertFalse(delta.summary.isEmpty)
        XCTAssertTrue(delta.summary.contains("+30 files"))
    }

    func testProjectEvolutionTrendGrowing() {
        let evolution = ProjectEvolution()

        let snapshots = [
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716000000),
                            fileCount: 100, totalLines: 10000),
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716100000),
                            fileCount: 120, totalLines: 12000),
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716200000),
                            fileCount: 145, totalLines: 14500),
        ]

        let trend = evolution.trend(snapshots: snapshots)
        XCTAssertEqual(trend.direction, .growing)
        XCTAssertTrue(trend.growthRate > 0)
        XCTAssertFalse(trend.description.isEmpty)
    }

    func testProjectEvolutionTrendStable() {
        let evolution = ProjectEvolution()

        let snapshots = [
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716000000),
                            fileCount: 100, totalLines: 10000),
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716100000),
                            fileCount: 101, totalLines: 10100),
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716200000),
                            fileCount: 100, totalLines: 10000),
        ]

        let trend = evolution.trend(snapshots: snapshots)
        XCTAssertEqual(trend.direction, .stable)
    }

    func testProjectEvolutionTrendShrinking() {
        let evolution = ProjectEvolution()

        let snapshots = [
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716000000),
                            fileCount: 200, totalLines: 20000),
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716100000),
                            fileCount: 160, totalLines: 16000),
            ProjectSnapshot(date: Date(timeIntervalSince1970: 1716200000),
                            fileCount: 120, totalLines: 12000),
        ]

        let trend = evolution.trend(snapshots: snapshots)
        XCTAssertEqual(trend.direction, .shrinking)
        XCTAssertTrue(trend.growthRate < 0)
    }

    func testProjectEvolutionTrendInsufficientData() {
        let evolution = ProjectEvolution()

        let trend = evolution.trend(snapshots: [
            ProjectSnapshot(fileCount: 100, totalLines: 10000)
        ])
        XCTAssertEqual(trend.direction, .stable)
        XCTAssertEqual(trend.growthRate, 0.0)
        XCTAssertTrue(trend.description.contains("Not enough"))
    }

    func testEvolutionDeltaSummary() {
        let delta = EvolutionDelta(
            period: "7 days",
            filesAdded: 10,
            filesRemoved: 2,
            linesAdded: 500,
            linesRemoved: 100,
            newLanguages: ["Rust"],
            summary: "Over 7 days, +10 files, +500 lines, new: Rust"
        )

        XCTAssertEqual(delta.netFiles, 8)
        XCTAssertEqual(delta.netLines, 400)
        XCTAssertTrue(delta.summary.contains("Rust"))
    }

    // MARK: - AdaptivePlanner Tests

    func testAdaptivePlannerAdjustsStepsBasedOnHistory() {
        let planner = AdaptivePlanner()

        let outcomes: [SessionOutcome] = (0..<5).map { i in
            SessionOutcome(
                sessionId: "zq_\(i)",
                intent: "fix the failing tests in the project",
                succeeded: true,
                stepsUsed: 8 + i,
                stepsPlanned: 5,
                toolFailures: 0,
                totalCost: 0.05,
                duration: 30.0
            )
        }

        let sessions: [SessionRecord] = outcomes.map { outcome in
            SessionRecord(
                sessionId: SessionID(value: outcome.sessionId),
                intent: outcome.intent,
                planSteps: [],
                status: "done",
                model: "claude-sonnet-4-6",
                provider: "anthropic",
                totalInputTokens: 10000,
                totalOutputTokens: 2000,
                totalCostUSD: outcome.totalCost,
                startedAt: Date(),
                updatedAt: Date(),
                stepsCompleted: outcome.stepsUsed,
                stepsTotal: outcome.stepsPlanned
            )
        }

        let strategy = planner.adjustStrategy(
            intent: "fix failing tests",
            pastSessions: sessions,
            pastOutcomes: outcomes
        )

        // Should suggest more steps than the original plan of 5
        XCTAssertGreaterThan(strategy.suggestedMaxSteps, 5)
        XCTAssertGreaterThan(strategy.confidence, 0.0)
        XCTAssertFalse(strategy.rationale.isEmpty)
    }

    func testAdaptivePlannerAvoidsFailingTools() {
        let planner = AdaptivePlanner()

        let outcomes: [SessionOutcome] = (0..<5).map { i in
            SessionOutcome(
                sessionId: "zq_fail_\(i)",
                intent: "fix the build errors in the swift project",
                succeeded: false,
                stepsUsed: 15,
                stepsPlanned: 10,
                toolFailures: 8,
                totalCost: 0.10,
                duration: 60.0
            )
        }

        let sessions: [SessionRecord] = outcomes.map { outcome in
            SessionRecord(
                sessionId: SessionID(value: outcome.sessionId),
                intent: outcome.intent,
                planSteps: [],
                status: "failed",
                model: "claude-sonnet-4-6",
                provider: "anthropic",
                totalInputTokens: 20000,
                totalOutputTokens: 4000,
                totalCostUSD: outcome.totalCost,
                startedAt: Date(),
                updatedAt: Date(),
                stepsCompleted: outcome.stepsUsed,
                stepsTotal: outcome.stepsPlanned
            )
        }

        let strategy = planner.adjustStrategy(
            intent: "fix build errors in swift project",
            pastSessions: sessions,
            pastOutcomes: outcomes
        )

        // With high failure rate, avoid patterns should be populated
        XCTAssertFalse(strategy.avoidPatterns.isEmpty)
    }

    func testPlanningStrategyDefaults() {
        let strategy = PlanningStrategy.default
        XCTAssertEqual(strategy.suggestedMaxSteps, 40)
        XCTAssertNil(strategy.suggestedModel)
        XCTAssertTrue(strategy.preferredTools.isEmpty)
        XCTAssertTrue(strategy.avoidPatterns.isEmpty)
        XCTAssertEqual(strategy.confidence, 0.0)
        XCTAssertFalse(strategy.rationale.isEmpty)
    }

    func testAdaptivePlannerInsufficientHistory() {
        let planner = AdaptivePlanner()

        let strategy = planner.adjustStrategy(
            intent: "something totally new",
            pastSessions: [],
            pastOutcomes: []
        )

        XCTAssertEqual(strategy.confidence, 0.0)
        XCTAssertTrue(strategy.rationale.contains("Insufficient"))
    }

    // MARK: - SessionOutcome Tests

    func testSessionOutcomeEncodingDecoding() throws {
        let outcome = SessionOutcome(
            sessionId: "zq_outcome_test",
            intent: "Fix the build",
            succeeded: true,
            stepsUsed: 8,
            stepsPlanned: 5,
            toolFailures: 1,
            totalCost: 0.0456,
            duration: 45.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(outcome)
        let decoded = try JSONDecoder().decode(SessionOutcome.self, from: data)

        XCTAssertEqual(decoded.sessionId, outcome.sessionId)
        XCTAssertEqual(decoded.intent, outcome.intent)
        XCTAssertTrue(decoded.succeeded)
        XCTAssertEqual(decoded.stepsUsed, 8)
        XCTAssertEqual(decoded.stepsPlanned, 5)
        XCTAssertEqual(decoded.toolFailures, 1)
        XCTAssertEqual(decoded.totalCost, 0.0456, accuracy: 0.0001)
        XCTAssertEqual(decoded.duration, 45.0, accuracy: 0.1)
    }

    func testSessionOutcomeOverran() {
        let overran = SessionOutcome(
            sessionId: "s1", intent: "test",
            succeeded: true, stepsUsed: 12, stepsPlanned: 8,
            toolFailures: 0, totalCost: 0.05, duration: 30.0
        )
        XCTAssertTrue(overran.overran)

        let underran = SessionOutcome(
            sessionId: "s2", intent: "test",
            succeeded: true, stepsUsed: 5, stepsPlanned: 8,
            toolFailures: 0, totalCost: 0.03, duration: 20.0
        )
        XCTAssertFalse(underran.overran)
    }

    func testSessionOutcomeEfficiency() {
        let outcome = SessionOutcome(
            sessionId: "s1", intent: "test",
            succeeded: true, stepsUsed: 10, stepsPlanned: 5,
            toolFailures: 0, totalCost: 0.05, duration: 30.0
        )
        // efficiency = stepsUsed / stepsPlanned = 10 / 5 = 2.0
        XCTAssertEqual(outcome.efficiency, 2.0, accuracy: 0.01)
    }

    func testSessionOutcomeFailureRate() {
        let outcome = SessionOutcome(
            sessionId: "s1", intent: "test",
            succeeded: false, stepsUsed: 10, stepsPlanned: 10,
            toolFailures: 4, totalCost: 0.08, duration: 60.0
        )
        XCTAssertEqual(outcome.failureRate, 0.4, accuracy: 0.01)
    }
}
