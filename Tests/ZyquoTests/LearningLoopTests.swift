import XCTest
@testable import Zyquo

final class LearningLoopTests: XCTestCase {

    // MARK: - SkillStats

    func testSkillStatsRecordingCounts() {
        var s = SkillStats(skillId: "demo")
        s = s.recording(succeeded: true, steps: 4, costUSD: 0.1, outcome: "ok")
        s = s.recording(succeeded: false, steps: 6, costUSD: 0.2, outcome: "fail", failureNote: "boom")
        XCTAssertEqual(s.runs, 2)
        XCTAssertEqual(s.successes, 1)
        XCTAssertEqual(s.failures, 1)
        XCTAssertEqual(s.successRate, 0.5, accuracy: 0.0001)
        XCTAssertEqual(s.avgSteps, 5.0, accuracy: 0.0001)
        XCTAssertTrue(s.recentFailureNotes.contains("boom"))
    }

    func testSkillStatsWarrantsRefinement() {
        var s = SkillStats(skillId: "flaky")
        for _ in 0..<5 {
            s = s.recording(succeeded: false, steps: 3, costUSD: 0.1, outcome: "fail", failureNote: "x")
        }
        XCTAssertTrue(s.warrantsRefinement(minRuns: 5))
        XCTAssertFalse(s.warrantsRefinement(minRuns: 10), "Not enough runs yet")
    }

    func testSkillStatsHealthySkillNotRefined() {
        var s = SkillStats(skillId: "good")
        for _ in 0..<6 {
            s = s.recording(succeeded: true, steps: 3, costUSD: 0.1, outcome: "ok")
        }
        XCTAssertFalse(s.warrantsRefinement(minRuns: 5))
    }

    func testFailureNotesAreCapped() {
        var s = SkillStats(skillId: "noisy")
        for i in 0..<10 {
            s = s.recording(succeeded: false, steps: 1, costUSD: 0, outcome: "fail", failureNote: "note\(i)")
        }
        XCTAssertEqual(s.recentFailureNotes.count, SkillStats.maxFailureNotes)
        XCTAssertEqual(s.recentFailureNotes.last, "note9")
    }

    // MARK: - NudgeEngine

    func testNudgeForReusableSession() {
        let candidate = ExtractedSkillCandidate(
            suggestedId: "fix_build",
            suggestedTitle: "Fix build",
            toolsUsed: ["shell.run"],
            stepsCount: 5,
            successRate: 1.0,
            suggestedPrompt: "x",
            suggestedBudget: SkillBudget(),
            confidence: 0.8
        )
        let nudges = NudgeEngine().generate(from: .init(skillCandidate: candidate))
        XCTAssertTrue(nudges.contains { $0.kind == .saveSkill })
        XCTAssertTrue(nudges.contains { $0.actionCommand == "zyquo skills accept fix_build" })
    }

    func testNudgeForStaleMemory() {
        let nudges = NudgeEngine().generate(from: .init(
            projectMemoryStale: true,
            sessionsSinceMemoryUpdate: 12
        ))
        XCTAssertTrue(nudges.contains { $0.kind == .refreshMemory })
    }

    func testNudgeForRefinedSkill() {
        let nudges = NudgeEngine().generate(from: .init(refinedSkillIds: ["flaky"]))
        XCTAssertTrue(nudges.contains { $0.kind == .refineSkill && $0.actionCommand == "zyquo skills refine flaky" })
    }

    func testNoNudgesWhenNothingHappened() {
        let nudges = NudgeEngine().generate(from: .init())
        XCTAssertTrue(nudges.isEmpty)
    }

    func testNudgeIdsAreDeterministic() {
        let a = LearningNudge.makeId(kind: .saveSkill, subject: "fix_build")
        let b = LearningNudge.makeId(kind: .saveSkill, subject: "fix_build")
        XCTAssertEqual(a, b)
    }

    // MARK: - NudgeStore

    func testNudgeStoreDedupesPending() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-nudges-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = NudgeStore(fileURL: file)
        let nudge = LearningNudge(id: "saveSkill:foo", kind: .saveSkill, message: "save foo?")
        let added1 = try await store.add([nudge])
        let added2 = try await store.add([nudge])
        XCTAssertEqual(added1.count, 1)
        XCTAssertEqual(added2.count, 0, "Same pending id should not be re-added")
        let pendingCount = await store.pending().count
        XCTAssertEqual(pendingCount, 1)
    }

    func testNudgeStoreDismiss() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-nudges-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = NudgeStore(fileURL: file)
        try await store.add([LearningNudge(id: "n1", kind: .refreshMemory, message: "m")])
        try await store.markDismissed(id: "n1")
        let pending = await store.pending()
        XCTAssertTrue(pending.isEmpty)
        let all = await store.all()
        XCTAssertEqual(all.first?.state, .dismissed)
    }

    // MARK: - Extraction → candidate store

    private func makeDoneSession(steps: Int) -> (SessionRecord, [SessionEvent]) {
        let record = SessionRecord(
            sessionId: SessionID(value: "zq_20260529_test"),
            intent: "fix the failing swift build",
            planSteps: (0..<steps).map { PersistablePlanStep(goal: "step \($0)", successCriteria: "ok") },
            status: "done",
            model: "claude-sonnet-4-6",
            provider: "anthropic",
            totalInputTokens: 100,
            totalOutputTokens: 50,
            totalCostUSD: 0.02,
            startedAt: Date(),
            updatedAt: Date(),
            stepsCompleted: steps,
            stepsTotal: steps
        )
        let events: [SessionEvent] = (0..<steps).map { _ in
            .toolExecuted(ToolExecutedEvent(
                toolName: "shell.run", summary: "ran tests", isError: false, durationMs: 10
            ))
        }
        return (record, events)
    }

    func testExtractorProducesViableCandidate() {
        let (record, events) = makeDoneSession(steps: 5)
        let candidate = SkillExtractor().analyze(session: record, events: events)
        XCTAssertNotNil(candidate)
        XCTAssertTrue(candidate?.isViable ?? false)
        XCTAssertTrue(candidate?.toolsUsed.contains("shell.run") ?? false)
    }

    func testExtractorRejectsTrivialSession() {
        let (record, events) = makeDoneSession(steps: 1)
        XCTAssertNil(SkillExtractor().analyze(session: record, events: events))
    }

    func testCandidateStoreRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-cand-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SkillCandidateStore(baseDir: dir)
        let (record, events) = makeDoneSession(steps: 5)
        let candidate = try XCTUnwrap(SkillExtractor().analyze(session: record, events: events))

        try await store.save(candidate)
        let existsAfterSave = await store.exists(id: candidate.suggestedId)
        XCTAssertTrue(existsAfterSave)

        let loaded = await store.load(id: candidate.suggestedId)
        XCTAssertEqual(loaded?.suggestedId, candidate.suggestedId)
        let listCount = await store.list().count
        XCTAssertEqual(listCount, 1)

        try await store.delete(id: candidate.suggestedId)
        let existsAfterDelete = await store.exists(id: candidate.suggestedId)
        XCTAssertFalse(existsAfterDelete)
    }

    // MARK: - SkillStatsStore

    func testStatsStoreRecordAndLoad() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-stats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SkillStatsStore(skillsDir: dir)
        _ = try await store.record(id: "demo", succeeded: true, steps: 3, costUSD: 0.1, outcome: "ok")
        _ = try await store.record(id: "demo", succeeded: false, steps: 5, costUSD: 0.2, outcome: "fail", failureNote: "x")

        let loaded = await store.load(id: "demo")
        XCTAssertEqual(loaded.runs, 2)
        XCTAssertEqual(loaded.failures, 1)
    }
}
