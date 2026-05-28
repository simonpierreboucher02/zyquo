import XCTest
@testable import Zyquo

final class SnapshotTests: XCTestCase {
    let theme = Theme.zyquoDark
    let snapshotDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Snapshots")

    private func assertSnapshot(
        _ buf: CellBuffer,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rendered = buf.renderPlainText()
        let goldenPath = snapshotDir.appendingPathComponent("\(name).golden")

        if FileManager.default.fileExists(atPath: goldenPath.path) {
            let expected = (try? String(contentsOf: goldenPath, encoding: .utf8)) ?? ""
            XCTAssertEqual(rendered, expected, "Snapshot mismatch for '\(name)'", file: file, line: line)
        } else {
            try? FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
            try? rendered.write(to: goldenPath, atomically: true, encoding: .utf8)
            XCTFail("Golden file created at \(goldenPath.path). Re-run to validate.", file: file, line: line)
        }
    }

    func testSnapshotPanelBasic() {
        let panel = Panel(
            title: "Test Panel",
            content: [
                StyledLine("Hello, Zyquo!"),
                StyledLine("This is a snapshot test baseline."),
            ]
        )
        let buf = panel.render(in: Region(x: 0, y: 0, width: 80, height: 4), theme: theme)
        assertSnapshot(buf, name: "PanelBasic80x24")
    }

    func testSnapshotPanelEmpty() {
        let panel = Panel(title: "Empty Panel", content: [])
        let buf = panel.render(in: Region(x: 0, y: 0, width: 60, height: 3), theme: theme)
        assertSnapshot(buf, name: "PanelEmpty60x3")
    }

    func testSnapshotSpinner() {
        let spinner = Spinner(style: .dots)
        let buf = spinner.render(in: Region(x: 0, y: 0, width: 20, height: 1), theme: theme)
        assertSnapshot(buf, name: "SpinnerDots20x1")
    }

    func testSnapshotStatusBadge() {
        let badge = StatusBadge(.safe)
        let buf = badge.render(in: Region(x: 0, y: 0, width: 12, height: 1), theme: theme)
        assertSnapshot(buf, name: "StatusBadgeSafe12x1")
    }

    func testSnapshotProgressBar() {
        let bar = ProgressBar.determinate(0.65, label: "Building")
        let buf = bar.render(in: Region(x: 0, y: 0, width: 40, height: 1), theme: theme)
        assertSnapshot(buf, name: "ProgressBar40x1")
    }
}
