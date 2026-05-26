import XCTest
@testable import Zyquo

final class CellBufferTests: XCTestCase {
    func testEmptyBuffer() {
        let buf = CellBuffer(width: 10, height: 5)
        XCTAssertEqual(buf.width, 10)
        XCTAssertEqual(buf.height, 5)
        XCTAssertEqual(buf.cells.count, 50)
        XCTAssertEqual(buf[0, 0], .empty)
    }

    func testWriteText() {
        var buf = CellBuffer(width: 20, height: 1)
        buf.write("Hello", x: 0, y: 0, fg: .green)
        XCTAssertEqual(buf[0, 0].character, "H")
        XCTAssertEqual(buf[4, 0].character, "o")
        XCTAssertEqual(buf[0, 0].fg, .green)
        XCTAssertEqual(buf[5, 0], .empty)
    }

    func testOutOfBoundsRead() {
        let buf = CellBuffer(width: 5, height: 5)
        XCTAssertEqual(buf[-1, 0], .empty)
        XCTAssertEqual(buf[0, -1], .empty)
        XCTAssertEqual(buf[5, 0], .empty)
        XCTAssertEqual(buf[0, 5], .empty)
    }

    func testDrawBox() {
        var buf = CellBuffer(width: 10, height: 5)
        buf.drawBox(x: 0, y: 0, width: 10, height: 5, fg: .white)

        XCTAssertEqual(buf[0, 0].character, "╭")
        XCTAssertEqual(buf[9, 0].character, "╮")
        XCTAssertEqual(buf[0, 4].character, "╰")
        XCTAssertEqual(buf[9, 4].character, "╯")
        XCTAssertEqual(buf[1, 0].character, "─")
        XCTAssertEqual(buf[0, 1].character, "│")
    }

    func testFill() {
        var buf = CellBuffer(width: 10, height: 10)
        let fillCell = Cell(character: "#", fg: .red, bg: .default, bold: false, italic: false, underline: false)
        buf.fill(x: 2, y: 2, width: 3, height: 3, cell: fillCell)

        XCTAssertEqual(buf[2, 2].character, "#")
        XCTAssertEqual(buf[4, 4].character, "#")
        XCTAssertEqual(buf[1, 1], .empty)
        XCTAssertEqual(buf[5, 5], .empty)
    }
}
