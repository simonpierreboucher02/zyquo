import XCTest
@testable import Zyquo

/// Guards the premium TUI primitives: correct display-width measurement and
/// pixel-perfect panel alignment (every rendered line is exactly the panel
/// width once ANSI is stripped — the alignment bug the old renderer had).
final class TUIRenderingTests: XCTestCase {

    // MARK: - DisplayWidth

    func testASCIIWidth() {
        XCTAssertEqual(DisplayWidth.width("hello"), 5)
    }

    func testWideCJKWidth() {
        XCTAssertEqual(DisplayWidth.width("你好"), 4, "Each CJK char is 2 columns")
    }

    func testEmojiWidth() {
        XCTAssertEqual(DisplayWidth.width("✦"), 1)
        XCTAssertEqual(DisplayWidth.width("🚀"), 2, "Emoji occupies 2 columns")
    }

    func testCombiningMarkIsZeroWidth() {
        // "e" + combining acute accent → 1 column
        XCTAssertEqual(DisplayWidth.width("e\u{0301}"), 1)
    }

    func testStripANSI() {
        let s = "\u{1B}[38;2;91;168;255mhi\u{1B}[0m"
        XCTAssertEqual(DisplayWidth.stripANSI(s), "hi")
        XCTAssertEqual(DisplayWidth.width(s), 2)
    }

    func testPadUsesDisplayWidth() {
        XCTAssertEqual(DisplayWidth.width(DisplayWidth.pad("你", to: 6)), 6)
    }

    func testTruncate() {
        XCTAssertEqual(DisplayWidth.truncate("hello world", to: 5), "hello")
    }

    // MARK: - Gradient

    func testGradientRampEndpoints() {
        let g = Gradient(theme: .zyquoDark, capability: .trueColor, noColor: false)
        let ramp = g.ramp(5)
        XCTAssertEqual(ramp.first, g.start)
        XCTAssertEqual(ramp.last, g.end)
        XCTAssertEqual(ramp.count, 5)
    }

    func testGradientDegradesToNoColor() {
        let g = Gradient(theme: .zyquoDark, capability: .monochrome, noColor: true)
        XCTAssertEqual(g.text("hello"), "hello", "No ANSI when noColor")
        XCTAssertEqual(g.bg(g.start), "", "No background fill when noColor")
    }

    // MARK: - PremiumPanel alignment

    private func allLinesWidth(_ lines: [String]) -> Set<Int> {
        Set(lines.map { DisplayWidth.width($0) })
    }

    func testPanelLinesAreExactlyWidth_truecolor() {
        let p = PremiumPanel(theme: .zyquoDark, capability: .trueColor, noColor: false)
        let width = 60
        let lines = p.panel(
            title: "Session",
            icon: "\u{25B8}",
            bodyRows: [
                [PremiumPanel.Segment("Provider", p.mutedRGB), PremiumPanel.Segment("  anthropic", p.fgRGB)],
                [PremiumPanel.Segment("Model", p.mutedRGB), PremiumPanel.Segment("  Claude Sonnet 4.6", p.fgRGB)],
            ],
            width: width
        )
        XCTAssertEqual(allLinesWidth(lines), [width], "Every panel line must be exactly \(width) columns")
    }

    func testPanelLinesAreExactlyWidth_noColor() {
        let p = PremiumPanel(theme: .zyquoDark, capability: .monochrome, noColor: true)
        let width = 48
        let lines = p.panel(
            title: "Help",
            bodyRows: [[PremiumPanel.Segment("hello world", nil)]],
            width: width
        )
        XCTAssertEqual(allLinesWidth(lines), [width])
    }

    func testPanelHandlesWideCharsInBody() {
        let p = PremiumPanel(theme: .zyquoDark, capability: .trueColor, noColor: false)
        let width = 50
        let lines = p.panel(
            title: "CJK",
            bodyRows: [[PremiumPanel.Segment("你好世界 mixed 文字", p.fgRGB)]],
            width: width
        )
        XCTAssertEqual(allLinesWidth(lines), [width], "Wide chars must not break alignment")
    }

    func testRuleWidth() {
        let p = PremiumPanel(theme: .zyquoDark, capability: .trueColor, noColor: false)
        XCTAssertEqual(DisplayWidth.width(p.rule(width: 30)), 30)
    }
}
