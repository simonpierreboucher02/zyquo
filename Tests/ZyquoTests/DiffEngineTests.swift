import XCTest
@testable import Zyquo

// MARK: - DiffEngine Tests

final class DiffEngineTests: XCTestCase {

    let engine = DiffEngine(contextLines: 3)

    // MARK: - Empty / Identical

    func testEmptyStringsDiff() {
        let diff = engine.diff(old: "", new: "")
        XCTAssertTrue(diff.isEmpty, "Diff between two empty strings should be empty")
        XCTAssertEqual(diff.hunks.count, 0)
        XCTAssertEqual(diff.linesAdded, 0)
        XCTAssertEqual(diff.linesRemoved, 0)
    }

    func testIdenticalStringsDiff() {
        let content = "line 1\nline 2\nline 3\n"
        let diff = engine.diff(old: content, new: content)
        XCTAssertTrue(diff.isEmpty, "Diff between identical strings should be empty")
        XCTAssertEqual(diff.hunks.count, 0)
        XCTAssertEqual(diff.linesAdded, 0)
        XCTAssertEqual(diff.linesRemoved, 0)
    }

    // MARK: - Single Line Changes

    func testSingleLineAdded() {
        let old = "line 1\nline 2\n"
        let new = "line 1\nline 2\nline 3\n"
        let diff = engine.diff(old: old, new: new)

        XCTAssertFalse(diff.isEmpty)
        XCTAssertEqual(diff.linesAdded, 1)
        XCTAssertEqual(diff.linesRemoved, 0)

        // Verify the added line content
        let addedLines = diff.hunks.flatMap { $0.lines }.filter { $0.kind == .added }
        XCTAssertEqual(addedLines.count, 1)
        XCTAssertEqual(addedLines[0].content, "line 3")
    }

    func testSingleLineRemoved() {
        let old = "line 1\nline 2\nline 3\n"
        let new = "line 1\nline 2\n"
        let diff = engine.diff(old: old, new: new)

        XCTAssertFalse(diff.isEmpty)
        XCTAssertEqual(diff.linesAdded, 0)
        XCTAssertEqual(diff.linesRemoved, 1)

        let removedLines = diff.hunks.flatMap { $0.lines }.filter { $0.kind == .removed }
        XCTAssertEqual(removedLines.count, 1)
        XCTAssertEqual(removedLines[0].content, "line 3")
    }

    func testSingleLineChanged() {
        let old = "line 1\nold line\nline 3\n"
        let new = "line 1\nnew line\nline 3\n"
        let diff = engine.diff(old: old, new: new)

        XCTAssertFalse(diff.isEmpty)
        XCTAssertEqual(diff.linesAdded, 1)
        XCTAssertEqual(diff.linesRemoved, 1)

        let removedLines = diff.hunks.flatMap { $0.lines }.filter { $0.kind == .removed }
        let addedLines = diff.hunks.flatMap { $0.lines }.filter { $0.kind == .added }
        XCTAssertEqual(removedLines.count, 1)
        XCTAssertEqual(addedLines.count, 1)
        XCTAssertEqual(removedLines[0].content, "old line")
        XCTAssertEqual(addedLines[0].content, "new line")
    }

    // MARK: - Multi-Line Changes

    func testMultiLineAdditions() {
        let old = "header\nfooter\n"
        let new = "header\nline a\nline b\nline c\nfooter\n"
        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(diff.linesAdded, 3)
        XCTAssertEqual(diff.linesRemoved, 0)
    }

    func testMultiLineRemovals() {
        let old = "header\nline a\nline b\nline c\nfooter\n"
        let new = "header\nfooter\n"
        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(diff.linesAdded, 0)
        XCTAssertEqual(diff.linesRemoved, 3)
    }

    // MARK: - Context Lines

    func testContextLinesIncluded() {
        // Create a file with enough lines to see context
        var oldLines: [String] = []
        for i in 1...10 {
            oldLines.append("line \(i)")
        }
        var newLines = oldLines
        newLines[4] = "CHANGED line 5" // change line 5

        let old = oldLines.joined(separator: "\n") + "\n"
        let new = newLines.joined(separator: "\n") + "\n"

        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(diff.hunks.count, 1)
        let hunk = diff.hunks[0]

        // Should have 3 context lines before + 1 removed + 1 added + 3 context lines after = 8 total
        let contextLines = hunk.lines.filter { $0.kind == .context }
        XCTAssertGreaterThanOrEqual(contextLines.count, 3, "Should have at least 3 context lines")
    }

    // MARK: - Large File Diff

    func testLargeFileDiff() {
        var oldLines: [String] = []
        var newLines: [String] = []
        for i in 1...150 {
            oldLines.append("line \(i)")
            if i == 50 {
                newLines.append("MODIFIED line \(i)")
            } else if i == 100 {
                newLines.append("MODIFIED line \(i)")
                newLines.append("INSERTED after \(i)")
            } else {
                newLines.append("line \(i)")
            }
        }

        let old = oldLines.joined(separator: "\n") + "\n"
        let new = newLines.joined(separator: "\n") + "\n"

        let diff = engine.diff(old: old, new: new)

        XCTAssertFalse(diff.isEmpty)
        XCTAssertGreaterThan(diff.linesAdded, 0)
        XCTAssertGreaterThan(diff.linesRemoved, 0)
        XCTAssertGreaterThanOrEqual(diff.hunks.count, 2, "Changes at lines 50 and 100 should produce at least 2 hunks")
    }

    // MARK: - Round-Trip

    func testRoundTripDiffApply() {
        let old = "import Foundation\n\nfunc greet() {\n    print(\"Hello\")\n}\n"
        let new = "import Foundation\nimport UIKit\n\nfunc greet(name: String) {\n    print(\"Hello, \\(name)\")\n}\n"

        let diff = engine.diff(old: old, new: new)
        let patchEngine = PatchEngine()

        do {
            let result = try patchEngine.apply(diff, to: old)
            XCTAssertEqual(result, new, "Applying diff(old, new) to old should produce new")
        } catch {
            XCTFail("Patch application failed: \(error)")
        }
    }

    // MARK: - From Empty / To Empty

    func testDiffFromEmpty() {
        let old = ""
        let new = "line 1\nline 2\n"
        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(diff.linesAdded, 2)
        XCTAssertEqual(diff.linesRemoved, 0)
    }

    func testDiffToEmpty() {
        let old = "line 1\nline 2\n"
        let new = ""
        let diff = engine.diff(old: old, new: new)

        XCTAssertEqual(diff.linesAdded, 0)
        XCTAssertEqual(diff.linesRemoved, 2)
    }

    // MARK: - Paths

    func testDiffIncludesPaths() {
        let diff = engine.diff(old: "a\n", new: "b\n", oldPath: "old.txt", newPath: "new.txt")
        XCTAssertEqual(diff.oldPath, "old.txt")
        XCTAssertEqual(diff.newPath, "new.txt")
    }

    // MARK: - Render

    func testDiffRenderFormat() {
        let old = "line 1\nold\nline 3\n"
        let new = "line 1\nnew\nline 3\n"
        let diff = engine.diff(old: old, new: new, oldPath: "test.txt", newPath: "test.txt")
        let rendered = diff.render()

        XCTAssertTrue(rendered.contains("--- a/test.txt"))
        XCTAssertTrue(rendered.contains("+++ b/test.txt"))
        XCTAssertTrue(rendered.contains("@@"))
        XCTAssertTrue(rendered.contains("-old"))
        XCTAssertTrue(rendered.contains("+new"))
    }

    // MARK: - SHA-256

    func testSHA256Consistency() {
        let content = "hello world"
        let hash1 = DiffEngine.sha256(of: content)
        let hash2 = DiffEngine.sha256(of: content)
        XCTAssertEqual(hash1, hash2, "Same content should produce same SHA-256")
        XCTAssertEqual(hash1.count, 64, "SHA-256 hex string should be 64 characters")
    }

    func testSHA256DifferentContent() {
        let hash1 = DiffEngine.sha256(of: "hello")
        let hash2 = DiffEngine.sha256(of: "world")
        XCTAssertNotEqual(hash1, hash2, "Different content should produce different SHA-256")
    }

    // MARK: - IntraLine Diff

    func testIntraLineDiff() {
        let (oldRanges, newRanges) = engine.intraLineDiff(
            oldLine: "let x = 1",
            newLine: "let x = 2"
        )
        // Should detect that "1" -> "2" changed
        XCTAssertFalse(oldRanges.isEmpty || newRanges.isEmpty, "Should detect intra-line change")
    }
}

// MARK: - PatchEngine Tests

final class PatchEngineTests: XCTestCase {

    let diffEngine = DiffEngine(contextLines: 3)
    let patchEngine = PatchEngine()

    func testApplySimpleDiff() throws {
        let old = "line 1\nline 2\nline 3\n"
        let new = "line 1\nline 2 modified\nline 3\n"
        let diff = diffEngine.diff(old: old, new: new)

        let result = try patchEngine.apply(diff, to: old)
        XCTAssertEqual(result, new)
    }

    func testApplyMultiHunkDiff() throws {
        var oldLines: [String] = []
        for i in 1...20 {
            oldLines.append("line \(i)")
        }
        var newLines = oldLines
        newLines[2] = "CHANGED line 3"
        newLines[17] = "CHANGED line 18"

        let old = oldLines.joined(separator: "\n") + "\n"
        let new = newLines.joined(separator: "\n") + "\n"

        let diff = diffEngine.diff(old: old, new: new)
        let result = try patchEngine.apply(diff, to: old)
        XCTAssertEqual(result, new)
    }

    func testReverseDiffAndApply() throws {
        let old = "line 1\nline 2\nline 3\n"
        let new = "line 1\nNEW line 2\nline 3\nextra line\n"

        let diff = diffEngine.diff(old: old, new: new)
        let reversed = patchEngine.reverse(diff)

        // Apply reverse to new should get back old
        let restored = try patchEngine.apply(reversed, to: new)
        XCTAssertEqual(restored, old)
    }

    func testRoundTripProperty() throws {
        let old = "func hello() {\n    print(\"hi\")\n}\n"
        let new = "func hello(name: String) {\n    print(\"hi \\(name)\")\n}\n\nfunc bye() {}\n"

        let diff = diffEngine.diff(old: old, new: new)
        let result = try patchEngine.apply(diff, to: old)
        XCTAssertEqual(result, new, "diff then apply should produce new content")
    }

    func testReverseRoundTrip() throws {
        let old = "alpha\nbeta\ngamma\n"
        let new = "alpha\nBETA\ngamma\ndelta\n"

        let diff = diffEngine.diff(old: old, new: new)

        // Forward: old -> new
        let patched = try patchEngine.apply(diff, to: old)
        XCTAssertEqual(patched, new)

        // Reverse: new -> old
        let reversed = patchEngine.reverse(diff)
        let restored = try patchEngine.apply(reversed, to: new)
        XCTAssertEqual(restored, old, "Reverse round-trip should restore original")
    }

    func testAtomicFileWrite() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-patch-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filePath = tempDir.appendingPathComponent("test.txt")
        let old = "original content\nline 2\n"
        let new = "modified content\nline 2\n"

        // Write original file
        try old.write(to: filePath, atomically: true, encoding: .utf8)

        let diff = diffEngine.diff(old: old, new: new)
        try patchEngine.applyToFile(diff: diff, path: filePath)

        // Verify file exists and has correct content
        let result = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertEqual(result, new)
    }

    func testRejectStalePatch() {
        let old = "line 1\nline 2\n"
        let new = "line 1\nmodified\n"
        let diff = diffEngine.diff(old: old, new: new)

        let wrongSHA = "0000000000000000000000000000000000000000000000000000000000000000"

        XCTAssertThrowsError(try patchEngine.apply(diff, to: old, expectSHA: wrongSHA)) { error in
            guard case PatchError.stalePreImage = error else {
                XCTFail("Expected stalePreImage error, got \(error)")
                return
            }
        }
    }

    func testApplyToEmptyFile() throws {
        let old = ""
        let new = "new content\nanother line\n"
        let diff = diffEngine.diff(old: old, new: new)

        let result = try patchEngine.apply(diff, to: old)
        XCTAssertEqual(result, new, "Should apply to empty content (file creation)")
    }

    func testCorrectSHAPasses() throws {
        let old = "hello\nworld\n"
        let new = "hello\nmodified\n"
        let diff = diffEngine.diff(old: old, new: new)
        let correctSHA = DiffEngine.sha256(of: old)

        let result = try patchEngine.apply(diff, to: old, expectSHA: correctSHA)
        XCTAssertEqual(result, new)
    }

    func testReverseDiffProperties() {
        let old = "a\nb\nc\n"
        let new = "a\nB\nc\nd\n"
        let diff = diffEngine.diff(old: old, new: new)
        let reversed = patchEngine.reverse(diff)

        XCTAssertEqual(reversed.linesAdded, diff.linesRemoved)
        XCTAssertEqual(reversed.linesRemoved, diff.linesAdded)
        XCTAssertEqual(reversed.oldPath, diff.newPath)
        XCTAssertEqual(reversed.newPath, diff.oldPath)
    }
}

// MARK: - HunkParser Tests

final class HunkParserTests: XCTestCase {

    let parser = HunkParser()

    func testParseSingleFileDiff() {
        let text = """
        --- a/test.swift
        +++ b/test.swift
        @@ -1,3 +1,3 @@
         import Foundation
        -let x = 1
        +let x = 2
         print(x)
        """

        let diffs = parser.parse(text)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].oldPath, "test.swift")
        XCTAssertEqual(diffs[0].newPath, "test.swift")
        XCTAssertEqual(diffs[0].hunks.count, 1)
        XCTAssertEqual(diffs[0].linesAdded, 1)
        XCTAssertEqual(diffs[0].linesRemoved, 1)
    }

    func testParseMultiFileDiff() {
        let text = """
        --- a/file1.swift
        +++ b/file1.swift
        @@ -1,2 +1,2 @@
        -old line
        +new line
         context
        --- a/file2.swift
        +++ b/file2.swift
        @@ -1 +1,2 @@
         existing
        +added
        """

        let diffs = parser.parse(text)
        XCTAssertEqual(diffs.count, 2)
        XCTAssertEqual(diffs[0].newPath, "file1.swift")
        XCTAssertEqual(diffs[1].newPath, "file2.swift")
    }

    func testParseHunkHeader() {
        let text = """
        --- a/test.txt
        +++ b/test.txt
        @@ -10,5 +10,7 @@
         context
        +added1
        +added2
         context
         context
         context
         context
        """

        let diffs = parser.parse(text)
        XCTAssertEqual(diffs.count, 1)
        let hunk = diffs[0].hunks[0]
        XCTAssertEqual(hunk.oldStart, 10)
        XCTAssertEqual(hunk.oldCount, 5)
        XCTAssertEqual(hunk.newStart, 10)
        XCTAssertEqual(hunk.newCount, 7)
    }

    func testParseEmptyInput() {
        let diffs = parser.parse("")
        XCTAssertEqual(diffs.count, 0)
    }

    func testRoundTripRenderParse() {
        let engine = DiffEngine(contextLines: 3)
        let old = "line 1\nline 2\nline 3\nline 4\nline 5\n"
        let new = "line 1\nMODIFIED\nline 3\nline 4\nline 5\n"

        let diff = engine.diff(old: old, new: new, oldPath: "test.txt", newPath: "test.txt")
        let rendered = diff.render()

        let parsed = parser.parse(rendered)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].linesAdded, diff.linesAdded)
        XCTAssertEqual(parsed[0].linesRemoved, diff.linesRemoved)
    }
}

// MARK: - ChangeSet Tests

final class ChangeSetTests: XCTestCase {

    func testPatchIDFormat() {
        let id = PatchID()
        XCTAssertTrue(id.value.hasPrefix("zp_"), "PatchID should start with 'zp_'")
        XCTAssertTrue(PatchID.isValid(id.value), "Generated PatchID should pass validation")

        // Check components
        let parts = id.value.components(separatedBy: "_")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], "zp")
        XCTAssertEqual(parts[1].count, 8, "Date portion should be 8 characters (YYYYMMDD)")
        XCTAssertEqual(parts[2].count, 8, "UUID portion should be 8 characters")
    }

    func testPatchIDValidation() {
        XCTAssertTrue(PatchID.isValid("zp_20260526_abcd1234"))
        XCTAssertFalse(PatchID.isValid("zp_2026_abcd1234")) // date too short
        XCTAssertFalse(PatchID.isValid("xx_20260526_abcd1234")) // wrong prefix
        XCTAssertFalse(PatchID.isValid("zp_20260526_abc")) // uuid too short
        XCTAssertFalse(PatchID.isValid("not_a_valid_id"))
    }

    func testMultiFileChangeSet() {
        let engine = DiffEngine(contextLines: 3)

        let diff1 = engine.diff(old: "old1\n", new: "new1\n", oldPath: "a.swift", newPath: "a.swift")
        let diff2 = engine.diff(old: "old2\n", new: "new2\nextra\n", oldPath: "b.swift", newPath: "b.swift")

        let changeSet = ChangeSet(
            files: [
                FileChange(path: "a.swift", diff: diff1, risk: .moderate),
                FileChange(path: "b.swift", diff: diff2, risk: .dangerous),
            ]
        )

        XCTAssertEqual(changeSet.filesChanged, 2)
        XCTAssertEqual(changeSet.totalAdded, 3) // "new1" + "new2" + "extra"
        XCTAssertEqual(changeSet.totalRemoved, 2) // "old1" + "old2"
        XCTAssertEqual(changeSet.maxRisk, .dangerous)
    }

    func testChangeSetSummaryText() {
        let engine = DiffEngine(contextLines: 3)
        let diff = engine.diff(old: "a\n", new: "b\nc\n")

        let changeSet = ChangeSet(
            files: [FileChange(path: "test.swift", diff: diff, risk: .moderate)]
        )

        let summary = changeSet.summaryText
        XCTAssertTrue(summary.contains("1 file changed"))
        XCTAssertTrue(summary.contains("MODERATE"))
    }

    func testChangeSetSubset() {
        let engine = DiffEngine(contextLines: 3)
        let diff1 = engine.diff(old: "a\n", new: "b\n")
        let diff2 = engine.diff(old: "c\n", new: "d\n")

        let changeSet = ChangeSet(files: [
            FileChange(path: "keep.swift", diff: diff1, risk: .safe),
            FileChange(path: "drop.swift", diff: diff2, risk: .moderate),
        ])

        let subset = changeSet.subset(paths: Set(["keep.swift"]))
        XCTAssertEqual(subset.filesChanged, 1)
        XCTAssertEqual(subset.files[0].path, "keep.swift")
    }

    func testPatchIDCodable() throws {
        let id = PatchID()
        let encoder = JSONEncoder()
        let data = try encoder.encode(id)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PatchID.self, from: data)
        XCTAssertEqual(id, decoded)
    }
}

// MARK: - ConflictResolver Tests

final class ConflictResolverTests: XCTestCase {

    let resolver = ConflictResolver()

    func testCleanMergeNonOverlapping() {
        let base = "line 1\nline 2\nline 3\nline 4\nline 5\n"
        let ours = "MODIFIED 1\nline 2\nline 3\nline 4\nline 5\n"   // changed line 1
        let theirs = "line 1\nline 2\nline 3\nline 4\nMODIFIED 5\n" // changed line 5

        let result = resolver.threeWayMerge(base: base, ours: ours, theirs: theirs)

        switch result {
        case .clean(let merged):
            XCTAssertTrue(merged.contains("MODIFIED 1"), "Should include our change")
            XCTAssertTrue(merged.contains("MODIFIED 5"), "Should include their change")
        case .conflicted:
            XCTFail("Non-overlapping changes should merge cleanly")
        }
    }

    func testConflictingSameLineChanged() {
        let base = "line 1\nline 2\nline 3\n"
        let ours = "line 1\nOUR line 2\nline 3\n"
        let theirs = "line 1\nTHEIR line 2\nline 3\n"

        let result = resolver.threeWayMerge(base: base, ours: ours, theirs: theirs)

        switch result {
        case .clean:
            XCTFail("Same-line changes should produce a conflict")
        case .conflicted(let content, let conflicts):
            XCTAssertFalse(conflicts.isEmpty, "Should have at least one conflict")
            XCTAssertTrue(content.contains("<<<<<<< ours"), "Should contain conflict markers")
            XCTAssertTrue(content.contains("======="), "Should contain separator")
            XCTAssertTrue(content.contains(">>>>>>> theirs"), "Should contain end marker")
            XCTAssertTrue(content.contains("OUR line 2"))
            XCTAssertTrue(content.contains("THEIR line 2"))
        }
    }

    func testOneSidedChangeOurs() {
        let base = "line 1\nline 2\nline 3\n"
        let ours = "line 1\nMODIFIED\nline 3\n"
        let theirs = base // theirs is unchanged

        let result = resolver.threeWayMerge(base: base, ours: ours, theirs: theirs)

        switch result {
        case .clean(let merged):
            XCTAssertEqual(merged, ours, "One-sided change should take ours")
        case .conflicted:
            XCTFail("One-sided change should merge cleanly")
        }
    }

    func testOneSidedChangeTheirs() {
        let base = "line 1\nline 2\nline 3\n"
        let ours = base // ours is unchanged
        let theirs = "line 1\nMODIFIED\nline 3\n"

        let result = resolver.threeWayMerge(base: base, ours: ours, theirs: theirs)

        switch result {
        case .clean(let merged):
            XCTAssertEqual(merged, theirs, "One-sided change should take theirs")
        case .conflicted:
            XCTFail("One-sided change should merge cleanly")
        }
    }

    func testConflictRegionInfo() {
        let base = "a\nb\nc\n"
        let ours = "a\nOUR\nc\n"
        let theirs = "a\nTHEIR\nc\n"

        let result = resolver.threeWayMerge(base: base, ours: ours, theirs: theirs)

        if case .conflicted(_, let conflicts) = result {
            XCTAssertEqual(conflicts.count, 1)
            let conflict = conflicts[0]
            XCTAssertEqual(conflict.ours, "OUR")
            XCTAssertEqual(conflict.theirs, "THEIR")
            XCTAssertGreaterThan(conflict.startLine, 0)
            XCTAssertGreaterThanOrEqual(conflict.endLine, conflict.startLine)
        } else {
            XCTFail("Expected conflicted result")
        }
    }

    func testIdenticalChangesNoConflict() {
        let base = "line 1\nline 2\nline 3\n"
        let ours = "line 1\nSAME CHANGE\nline 3\n"
        let theirs = ours // both sides make the same change

        let result = resolver.threeWayMerge(base: base, ours: ours, theirs: theirs)

        switch result {
        case .clean(let merged):
            XCTAssertEqual(merged, ours)
        case .conflicted:
            XCTFail("Identical changes should not conflict")
        }
    }
}

// MARK: - SnapshotStore Tests

final class SnapshotStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: SnapshotStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-snapshot-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let snapshotDir = tempDir.appendingPathComponent("snapshots")
        store = SnapshotStore(storageDir: snapshotDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSnapshotAndRestore() throws {
        let content = "Hello, World! This is a test file.\nSecond line.\n"
        let filePath = tempDir.appendingPathComponent("test.txt")
        try content.write(to: filePath, atomically: true, encoding: .utf8)

        let ref = try store.snapshot(path: filePath)

        // Restore and verify
        let restored = store.restoreString(ref: ref)
        XCTAssertEqual(restored, content, "Restored content should match original")
    }

    func testContentAddressed() throws {
        let content = "identical content\n"

        let ref1 = try store.snapshot(content: content, originalPath: "/path/a.txt")
        let ref2 = try store.snapshot(content: content, originalPath: "/path/b.txt")

        XCTAssertEqual(ref1.sha256, ref2.sha256, "Same content should produce same SHA")
    }

    func testDifferentContentDifferentSHA() throws {
        let ref1 = try store.snapshot(content: "content A\n", originalPath: "a.txt")
        let ref2 = try store.snapshot(content: "content B\n", originalPath: "b.txt")

        XCTAssertNotEqual(ref1.sha256, ref2.sha256)
    }

    func testNonExistentSnapshotReturnsNil() {
        let fakeSHA = "0000000000000000000000000000000000000000000000000000000000000000"
        let result = store.restore(sha: fakeSHA)
        XCTAssertNil(result, "Non-existent snapshot should return nil")
    }

    func testExistsCheck() throws {
        let ref = try store.snapshot(content: "test\n", originalPath: "test.txt")

        XCTAssertTrue(store.exists(sha: ref.sha256))
        XCTAssertFalse(store.exists(sha: "nonexistent"))
    }

    func testListAll() throws {
        _ = try store.snapshot(content: "file1\n", originalPath: "1.txt")
        _ = try store.snapshot(content: "file2\n", originalPath: "2.txt")
        _ = try store.snapshot(content: "file3\n", originalPath: "3.txt")

        let all = store.listAll()
        XCTAssertEqual(all.count, 3)
    }

    func testSnapshotRefCodable() throws {
        let ref = SnapshotRef(sha256: "abc123", originalPath: "/test.txt", size: 42)
        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(SnapshotRef.self, from: data)
        XCTAssertEqual(decoded.sha256, ref.sha256)
        XCTAssertEqual(decoded.originalPath, ref.originalPath)
        XCTAssertEqual(decoded.size, ref.size)
    }
}

// MARK: - PatchStore Tests

final class PatchStoreTests: XCTestCase {

    private var tempDir: URL!
    private var patchStoreDir: URL!
    private var store: PatchStore!
    private let engine = DiffEngine(contextLines: 3)

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-patchstore-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        patchStoreDir = tempDir.appendingPathComponent("patches")
        store = PatchStore(storageDir: patchStoreDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRecordAndLoadChangeSet() throws {
        let diff = engine.diff(old: "old\n", new: "new\n", oldPath: "test.swift", newPath: "test.swift")
        let patchEngine = PatchEngine()
        let reverseDiff = patchEngine.reverse(diff)

        let changeSet = ChangeSet(
            files: [FileChange(path: "test.swift", diff: diff, preImageSHA: "abc123", risk: .moderate)],
            summary: "Test patch"
        )

        try store.record(changeSet: changeSet, reverseDiffs: [reverseDiff])

        // Load it back
        let loaded = store.load(id: changeSet.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, changeSet.id)
        XCTAssertEqual(loaded?.files.count, 1)
        XCTAssertEqual(loaded?.summary, "Test patch")
    }

    func testLoadReversePatch() throws {
        let diff = engine.diff(old: "original\n", new: "modified\n", oldPath: "f.txt", newPath: "f.txt")
        let patchEngine = PatchEngine()
        let reverseDiff = patchEngine.reverse(diff)

        let changeSet = ChangeSet(files: [FileChange(path: "f.txt", diff: diff, risk: .safe)])
        try store.record(changeSet: changeSet, reverseDiffs: [reverseDiff])

        let loaded = store.loadReverse(id: changeSet.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
    }

    func testListAllPatches() throws {
        for i in 0..<3 {
            let diff = engine.diff(old: "old\(i)\n", new: "new\(i)\n")
            let patchEngine = PatchEngine()
            let reverseDiff = patchEngine.reverse(diff)
            let cs = ChangeSet(files: [FileChange(path: "file\(i).txt", diff: diff, risk: .safe)])
            try store.record(changeSet: cs, reverseDiffs: [reverseDiff])
        }

        let all = store.listAll()
        XCTAssertEqual(all.count, 3)
    }

    func testRollbackAppliesReverse() throws {
        let filePath = tempDir.appendingPathComponent("rollback-test.txt")
        let original = "original content\nline 2\n"
        let modified = "modified content\nline 2\n"

        // Write original file
        try original.write(to: filePath, atomically: true, encoding: .utf8)

        // Create diff and changeset
        let diff = engine.diff(old: original, new: modified, oldPath: "rollback-test.txt", newPath: "rollback-test.txt")
        let patchEngine = PatchEngine()
        let reverseDiff = patchEngine.reverse(diff)
        let changeSet = ChangeSet(files: [FileChange(path: filePath.path, diff: diff, risk: .moderate)])

        // Apply forward patch
        try patchEngine.applyToFile(diff: diff, path: filePath)
        let afterPatch = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertEqual(afterPatch, modified)

        // Record and rollback
        try store.record(changeSet: changeSet, reverseDiffs: [reverseDiff])
        try store.rollback(id: changeSet.id, workspaceRoot: tempDir)

        let afterRollback = try String(contentsOf: filePath, encoding: .utf8)
        XCTAssertEqual(afterRollback, original, "Rollback should restore original content")
    }

    func testRemovePatch() throws {
        let diff = engine.diff(old: "a\n", new: "b\n")
        let patchEngine = PatchEngine()
        let reverse = patchEngine.reverse(diff)
        let cs = ChangeSet(files: [FileChange(path: "x.txt", diff: diff, risk: .safe)])
        try store.record(changeSet: cs, reverseDiffs: [reverse])

        XCTAssertNotNil(store.load(id: cs.id))

        try store.remove(id: cs.id)

        XCTAssertNil(store.load(id: cs.id))
        XCTAssertNil(store.loadReverse(id: cs.id))
    }
}

// MARK: - Integration / Property Tests

final class DiffIntegrationTests: XCTestCase {

    func testFullWorkflow() throws {
        let engine = DiffEngine(contextLines: 3)
        let patchEngine = PatchEngine()

        let original = """
        import Foundation

        struct Calculator {
            func add(_ a: Int, _ b: Int) -> Int {
                return a + b
            }

            func subtract(_ a: Int, _ b: Int) -> Int {
                return a - b
            }
        }

        """

        let modified = """
        import Foundation
        import UIKit

        struct Calculator {
            func add(_ a: Int, _ b: Int) -> Int {
                return a + b
            }

            func multiply(_ a: Int, _ b: Int) -> Int {
                return a * b
            }
        }

        """

        // 1. Compute diff
        let diff = engine.diff(old: original, new: modified, oldPath: "Calculator.swift", newPath: "Calculator.swift")
        XCTAssertFalse(diff.isEmpty)

        // 2. Apply diff
        let patched = try patchEngine.apply(diff, to: original)
        XCTAssertEqual(patched, modified)

        // 3. Compute reverse
        let reversed = patchEngine.reverse(diff)

        // 4. Apply reverse to get back original
        let restored = try patchEngine.apply(reversed, to: modified)
        XCTAssertEqual(restored, original)

        // 5. Render and parse round-trip
        let rendered = diff.render()
        let parser = HunkParser()
        let parsed = parser.parse(rendered)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].linesAdded, diff.linesAdded)
        XCTAssertEqual(parsed[0].linesRemoved, diff.linesRemoved)
    }

    func testDiffWithOnlyAdditions() throws {
        let engine = DiffEngine(contextLines: 3)
        let patchEngine = PatchEngine()

        let old = ""
        let new = "line 1\nline 2\nline 3\n"

        let diff = engine.diff(old: old, new: new)
        XCTAssertEqual(diff.linesAdded, 3)
        XCTAssertEqual(diff.linesRemoved, 0)

        let result = try patchEngine.apply(diff, to: old)
        XCTAssertEqual(result, new)
    }

    func testDiffWithOnlyDeletions() throws {
        let engine = DiffEngine(contextLines: 3)
        let patchEngine = PatchEngine()

        let old = "line 1\nline 2\nline 3\n"
        let new = ""

        let diff = engine.diff(old: old, new: new)
        XCTAssertEqual(diff.linesAdded, 0)
        XCTAssertEqual(diff.linesRemoved, 3)

        let result = try patchEngine.apply(diff, to: old)
        XCTAssertEqual(result, new)
    }
}
