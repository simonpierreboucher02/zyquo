import XCTest
@testable import Zyquo

final class PanelTests: XCTestCase {
    let theme = Theme.zyquoDark

    func testPanelRendersBox() {
        let panel = Panel(title: "Test", content: [StyledLine("Hello")])
        let buf = panel.render(in: Region(x: 0, y: 0, width: 30, height: 5), theme: theme)

        XCTAssertEqual(buf[0, 0].character, "\u{256D}")
        XCTAssertEqual(buf[29, 0].character, "\u{256E}")
        XCTAssertEqual(buf[0, 4].character, "\u{2570}")
        XCTAssertEqual(buf[29, 4].character, "\u{256F}")
    }

    func testPanelRendersTitle() {
        let panel = Panel(title: "My Panel", content: [])
        let buf = panel.render(in: Region(x: 0, y: 0, width: 40, height: 3), theme: theme)

        let topRow = buf.extractText(y: 0)
        XCTAssertTrue(topRow.contains("My Panel"))
    }

    func testPanelRendersContent() {
        let panel = Panel(title: "Test", content: [
            StyledLine("Line 1"),
            StyledLine("Line 2"),
        ])
        let buf = panel.render(in: Region(x: 0, y: 0, width: 30, height: 5), theme: theme)

        let row1 = buf.extractText(y: 1)
        XCTAssertTrue(row1.contains("Line 1"))

        let row2 = buf.extractText(y: 2)
        XCTAssertTrue(row2.contains("Line 2"))
    }

    func testPanelTooSmall() {
        let panel = Panel(title: "Test", content: [StyledLine("Hello")])
        let buf = panel.render(in: Region(x: 0, y: 0, width: 2, height: 1), theme: theme)
        XCTAssertEqual(buf.width, 2)
        XCTAssertEqual(buf.height, 1)
    }

    func testPanelCenterTitle() {
        let panel = Panel(title: "Center", content: [], titleAlignment: .center)
        let buf = panel.render(in: Region(x: 0, y: 0, width: 40, height: 3), theme: theme)
        let topRow = buf.extractText(y: 0)
        XCTAssertTrue(topRow.contains("Center"))
    }

    func testPanelSizeThatFits() {
        let panel = Panel(title: "T", content: [
            StyledLine("A"),
            StyledLine("B"),
            StyledLine("C"),
        ])
        let size = panel.sizeThatFits(Size(width: 80, height: 24))
        XCTAssertEqual(size.width, 80)
        XCTAssertEqual(size.height, 5)
    }

    func testPanelContentClipping() {
        let panel = Panel(title: "Clip", content: [
            StyledLine("Line 1"),
            StyledLine("Line 2"),
            StyledLine("Line 3"),
            StyledLine("Line 4"),
        ])
        let buf = panel.render(in: Region(x: 0, y: 0, width: 30, height: 4), theme: theme)
        let row1 = buf.extractText(y: 1)
        XCTAssertTrue(row1.contains("Line 1"))
        let row2 = buf.extractText(y: 2)
        XCTAssertTrue(row2.contains("Line 2"))
    }

    func testStyledLineColors() {
        let panel = Panel(title: "Colors", content: [
            StyledLine("Red text", fg: .red, bold: true),
        ])
        let buf = panel.render(in: Region(x: 0, y: 0, width: 30, height: 4), theme: theme)
        let cell = buf[2, 1]
        XCTAssertEqual(cell.fg, .red)
        XCTAssertTrue(cell.bold)
    }
}
