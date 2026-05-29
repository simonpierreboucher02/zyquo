import XCTest
@testable import Zyquo

final class UserModelTests: XCTestCase {

    private func obs(
        _ trait: UserTrait,
        _ statement: String,
        confidence: Double,
        seen: Date,
        session: String = "s1"
    ) -> UserObservation {
        UserObservation(
            id: UserObservation.makeId(trait: trait, statement: statement),
            trait: trait,
            statement: statement,
            confidence: confidence,
            evidenceCount: 1,
            firstSeen: seen,
            lastSeen: seen,
            sourceSessions: [session]
        )
    }

    // MARK: - Merge

    func testMergeInsertsNewObservation() {
        let now = Date()
        let model = UserModel.empty
        let merged = model.merging([obs(.stack, "Works in Swift", confidence: 0.6, seen: now)], now: now)
        XCTAssertEqual(merged.observations.count, 1)
        XCTAssertEqual(merged.observations.first?.statement, "Works in Swift")
    }

    func testMergeReinforcesExistingFact() {
        let now = Date()
        let first = obs(.preference, "Prefers concise output", confidence: 0.5, seen: now, session: "s1")
        let model = UserModel(observations: [first])

        // Same statement → same id → reinforce.
        let again = obs(.preference, "Prefers concise output", confidence: 0.4, seen: now, session: "s2")
        let merged = model.merging([again], now: now)

        XCTAssertEqual(merged.observations.count, 1, "Should dedupe by id, not duplicate")
        let o = merged.observations[0]
        XCTAssertEqual(o.evidenceCount, 2)
        XCTAssertEqual(o.confidence, min(1.0, 0.5 + UserModel.reinforcement), accuracy: 0.0001)
        XCTAssertTrue(o.sourceSessions.contains("s1"))
        XCTAssertTrue(o.sourceSessions.contains("s2"))
    }

    func testMergeSortsByConfidenceDescending() {
        let now = Date()
        let model = UserModel.empty.merging([
            obs(.stack, "low", confidence: 0.3, seen: now),
            obs(.stack, "high", confidence: 0.9, seen: now),
        ], now: now)
        XCTAssertEqual(model.observations.first?.statement, "high")
    }

    // MARK: - Decay

    func testDecayReducesStaleConfidence() {
        let now = Date()
        let old = now.addingTimeInterval(-86_400 * 120) // 120 days ago
        let model = UserModel(observations: [obs(.preference, "stale fact", confidence: 0.5, seen: old)])
        let decayed = model.decayed(now: now)
        if let o = decayed.observations.first {
            XCTAssertLessThan(o.confidence, 0.5, "Stale fact confidence should decay")
        }
    }

    func testDecayPrunesBelowFloor() {
        let now = Date()
        let veryOld = now.addingTimeInterval(-86_400 * 400)
        let model = UserModel(observations: [obs(.preference, "ancient", confidence: 0.1, seen: veryOld)])
        let decayed = model.decayed(now: now)
        XCTAssertTrue(decayed.observations.isEmpty, "Heavily decayed facts should be pruned")
    }

    func testRecentFactDoesNotDecay() {
        let now = Date()
        let model = UserModel(observations: [obs(.stack, "fresh", confidence: 0.6, seen: now)])
        let decayed = model.decayed(now: now)
        XCTAssertEqual(decayed.observations.first?.confidence ?? 0, 0.6, accuracy: 0.0001)
    }

    // MARK: - Rendering

    func testRenderForContextOmitsLowConfidence() {
        let now = Date()
        let model = UserModel(observations: [
            obs(.stack, "confident", confidence: 0.8, seen: now),
            obs(.stack, "unsure", confidence: 0.1, seen: now),
        ])
        let rendered = model.renderForContext(minConfidence: 0.3) ?? ""
        XCTAssertTrue(rendered.contains("confident"))
        XCTAssertFalse(rendered.contains("unsure"))
    }

    func testRenderForContextNilWhenEmpty() {
        XCTAssertNil(UserModel.empty.renderForContext())
    }

    func testRenderMarkdownHasNotesSection() {
        let md = UserModel.empty.renderMarkdown()
        XCTAssertTrue(md.contains("## Notes (user-editable)"))
    }

    // MARK: - Store round-trip

    func testStoreRoundTripPreservesObservations() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = UserModelStore(baseDir: dir)
        let now = Date()
        let model = UserModel(observations: [obs(.domainExpertise, "macOS native dev", confidence: 0.7, seen: now)])
        try await store.save(model)

        let loaded = await store.load()
        XCTAssertEqual(loaded.observations.count, 1)
        XCTAssertEqual(loaded.observations.first?.statement, "macOS native dev")
    }

    func testStorePreservesUserEditedNotes() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Simulate a user hand-editing the markdown notes section.
        let mdPath = dir.appendingPathComponent("user_model.md")
        let handEdited = """
        # User Model

        ## Notes (user-editable)

        Always address me in French.
        """
        try handEdited.write(to: mdPath, atomically: true, encoding: .utf8)

        let store = UserModelStore(baseDir: dir)
        // A machine save must not clobber the user's notes.
        try await store.save(UserModel(observations: []))
        let loaded = await store.load()
        XCTAssertTrue(loaded.userEditedNotes.contains("Always address me in French"))
    }
}
