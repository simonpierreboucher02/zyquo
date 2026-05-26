import XCTest
@testable import Zyquo

final class DiffViewTests: XCTestCase {
    let theme = Theme.zyquoDark

    func testDiffSummary() {
        let files = [
            DiffFile(path: "a.swift", hunks: [], linesAdded: 10, linesRemoved: 5),
            DiffFile(path: "b.swift", hunks: [], linesAdded: 3, linesRemoved: 1),
        ]
        let summary = DiffSummary(files: files)
        XCTAssertEqual(summary.filesChanged, 2)
        XCTAssertEqual(summary.totalAdded, 13)
        XCTAssertEqual(summary.totalRemoved, 6)
        XCTAssertTrue(summary.summaryText.contains("2 files"))
        XCTAssertTrue(summary.summaryText.contains("+13"))
    }

    func testSingleFileSummary() {
        let files = [DiffFile(path: "x.txt", hunks: [], linesAdded: 1, linesRemoved: 0)]
        let summary = DiffSummary(files: files)
        XCTAssertTrue(summary.summaryText.contains("1 file changed"))
    }

    func testDiffViewRendersSummaryLine() {
        let files = [
            DiffFile(
                path: "main.swift",
                hunks: [
                    DiffHunk(header: "@@ -1,3 +1,3 @@", lines: [
                        DiffLine(kind: .context, text: "import Foundation"),
                        DiffLine(kind: .removed, text: "let x = 1"),
                        DiffLine(kind: .added, text: "let x = 2"),
                    ])
                ],
                linesAdded: 1,
                linesRemoved: 1
            )
        ]
        let view = DiffView(files: files)
        let buf = view.render(in: Region(x: 0, y: 0, width: 60, height: 10), theme: theme)

        let firstLine = buf.extractText(y: 0)
        XCTAssertTrue(firstLine.contains("1 file"))
    }

    func testDiffViewRendersAddedLine() {
        let files = [
            DiffFile(
                path: "test.swift",
                hunks: [
                    DiffHunk(header: "@@ -1 +1,2 @@", lines: [
                        DiffLine(kind: .added, text: "new line"),
                    ])
                ],
                linesAdded: 1,
                linesRemoved: 0
            )
        ]
        let view = DiffView(files: files)
        let buf = view.render(in: Region(x: 0, y: 0, width: 60, height: 10), theme: theme)

        var foundAdded = false
        for y in 0..<buf.height {
            let line = buf.extractText(y: y)
            if line.hasPrefix("+") && line.contains("new line") {
                foundAdded = true
                XCTAssertEqual(buf[0, y].fg, theme.diff.addedFg)
                XCTAssertEqual(buf[0, y].bg, theme.diff.added)
                break
            }
        }
        XCTAssertTrue(foundAdded, "Should find added line in output")
    }

    func testDiffViewRendersRemovedLine() {
        let files = [
            DiffFile(
                path: "test.swift",
                hunks: [
                    DiffHunk(header: "@@ -1,2 +1 @@", lines: [
                        DiffLine(kind: .removed, text: "old line"),
                    ])
                ],
                linesAdded: 0,
                linesRemoved: 1
            )
        ]
        let view = DiffView(files: files)
        let buf = view.render(in: Region(x: 0, y: 0, width: 60, height: 10), theme: theme)

        var foundRemoved = false
        for y in 0..<buf.height {
            let line = buf.extractText(y: y)
            if line.hasPrefix("-") && line.contains("old line") {
                foundRemoved = true
                XCTAssertEqual(buf[0, y].fg, theme.diff.removedFg)
                XCTAssertEqual(buf[0, y].bg, theme.diff.removed)
                break
            }
        }
        XCTAssertTrue(foundRemoved, "Should find removed line in output")
    }

    func testParseUnifiedDiff() {
        let diff = """
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,4 @@
         import Foundation
        -let x = 1
        +let x = 2
        +let y = 3
         print(x)
        """
        let files = DiffView.parse(unifiedDiff: diff)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "foo.swift")
        XCTAssertEqual(files[0].linesAdded, 2)
        XCTAssertEqual(files[0].linesRemoved, 1)
        XCTAssertEqual(files[0].hunks.count, 1)
        XCTAssertTrue(files[0].hunks[0].lines.count >= 4)
    }

    func testParseMultiFileDiff() {
        let diff = """
        --- a/a.swift
        +++ b/a.swift
        @@ -1 +1 @@
        -old
        +new
        --- a/b.swift
        +++ b/b.swift
        @@ -1 +1,2 @@
         existing
        +added
        """
        let files = DiffView.parse(unifiedDiff: diff)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].path, "a.swift")
        XCTAssertEqual(files[1].path, "b.swift")
    }

    func testDiffViewSmallRegion() {
        let files = [DiffFile(path: "x.swift", hunks: [], linesAdded: 0, linesRemoved: 0)]
        let view = DiffView(files: files)
        let buf = view.render(in: Region(x: 0, y: 0, width: 5, height: 2), theme: theme)
        XCTAssertEqual(buf.width, 5)
    }
}
