import XCTest
@testable import Zyquo

final class SpinnerTests: XCTestCase {
    let theme = Theme.zyquoDark

    func testBrailleFrames() {
        let spinner = Spinner(style: .braille)
        XCTAssertEqual(spinner.currentFrame, "\u{280B}")
        XCTAssertEqual(spinner.tick().currentFrame, "\u{2819}")
    }

    func testDotsFrames() {
        let spinner = Spinner(style: .dots)
        XCTAssertEqual(spinner.currentFrame, "\u{2801}")
        let next = spinner.tick()
        XCTAssertEqual(next.currentFrame, "\u{2802}")
    }

    func testLineFrames() {
        let spinner = Spinner(style: .line)
        let frames = SpinnerStyle.line.frames
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(spinner.currentFrame, "-")
    }

    func testFrameCycling() {
        var spinner = Spinner(style: .braille)
        let frameCount = SpinnerStyle.braille.frames.count
        for _ in 0..<frameCount {
            spinner = spinner.tick()
        }
        XCTAssertEqual(spinner.currentFrame, SpinnerStyle.braille.frames[0])
    }

    func testSpinnerIsAnimated() {
        let spinner = Spinner(style: .braille)
        XCTAssertTrue(spinner.isAnimated)
    }

    func testSpinnerRendersCharacter() {
        let spinner = Spinner(style: .braille, label: "Loading")
        let buf = spinner.render(in: Region(x: 0, y: 0, width: 20, height: 1), theme: theme)
        XCTAssertEqual(buf[0, 0].character, "\u{280B}")
        XCTAssertEqual(buf[0, 0].fg, theme.colors.accent)
    }

    func testSpinnerRendersLabel() {
        let spinner = Spinner(style: .braille, label: "Loading")
        let buf = spinner.render(in: Region(x: 0, y: 0, width: 20, height: 1), theme: theme)
        let text = buf.extractText(y: 0)
        XCTAssertTrue(text.contains("Loading"))
    }

    func testSpinnerSizeThatFits() {
        let spinner = Spinner(style: .braille, label: "")
        let size = spinner.sizeThatFits(Size(width: 80, height: 24))
        XCTAssertEqual(size.width, 1)
        XCTAssertEqual(size.height, 1)
    }

    func testSpinnerWithLabelSizeThatFits() {
        let spinner = Spinner(style: .braille, label: "Working")
        let size = spinner.sizeThatFits(Size(width: 80, height: 24))
        XCTAssertEqual(size.width, 9) // "Working" (7) + 2 for spinner + space
        XCTAssertEqual(size.height, 1)
    }

    func testSpinnerIntervalValues() {
        XCTAssertEqual(SpinnerStyle.braille.intervalMs, 80)
        XCTAssertEqual(SpinnerStyle.dots.intervalMs, 100)
        XCTAssertEqual(SpinnerStyle.line.intervalMs, 120)
    }
}
