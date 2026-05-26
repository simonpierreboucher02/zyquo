import XCTest
@testable import Zyquo

final class ThemeTests: XCTestCase {
    func testBuiltInThemesExist() {
        XCTAssertEqual(Theme.builtInThemes.count, 3)
        XCTAssertNotNil(Theme.builtIn(named: "zyquo-dark"))
        XCTAssertNotNil(Theme.builtIn(named: "minimal"))
        XCTAssertNotNil(Theme.builtIn(named: "high-contrast"))
        XCTAssertNil(Theme.builtIn(named: "nonexistent"))
    }

    func testZyquoDarkThemeColors() {
        let theme = Theme.zyquoDark
        XCTAssertEqual(theme.name, "zyquo-dark")
        XCTAssertTrue(theme.truecolor)

        if case .trueColor(let r, let g, let b) = theme.colors.bg {
            XCTAssertEqual(r, 0x0B)
            XCTAssertEqual(g, 0x0F)
            XCTAssertEqual(b, 0x14)
        } else {
            XCTFail("Expected truecolor bg")
        }

        if case .trueColor(let r, _, _) = theme.colors.ok {
            XCTAssertEqual(r, 0x4A)
        } else {
            XCTFail("Expected truecolor ok")
        }
    }

    func testMinimalThemeUses16Color() {
        let theme = Theme.minimal
        XCTAssertFalse(theme.truecolor)
        XCTAssertEqual(theme.colors.fg, .white)
        XCTAssertEqual(theme.colors.ok, .green)
        XCTAssertEqual(theme.colors.risk, .red)
    }

    func testHighContrastTheme() {
        let theme = Theme.highContrast
        XCTAssertEqual(theme.name, "high-contrast")
        XCTAssertTrue(theme.truecolor)

        if case .trueColor(let r, let g, let b) = theme.colors.bg {
            XCTAssertEqual(r, 0)
            XCTAssertEqual(g, 0)
            XCTAssertEqual(b, 0)
        } else {
            XCTFail("Expected truecolor bg")
        }

        if case .trueColor(let r, let g, let b) = theme.colors.fg {
            XCTAssertEqual(r, 255)
            XCTAssertEqual(g, 255)
            XCTAssertEqual(b, 255)
        } else {
            XCTFail("Expected truecolor fg")
        }
    }

    func testHexParsing() {
        let color = ANSIColor.fromHex("#FF8800")
        if case .trueColor(let r, let g, let b) = color {
            XCTAssertEqual(r, 255)
            XCTAssertEqual(g, 0x88)
            XCTAssertEqual(b, 0)
        } else {
            XCTFail("Expected truecolor from hex")
        }
    }

    func testHexParsingWithoutHash() {
        let color = ANSIColor.fromHex("00FF00")
        if case .trueColor(let r, let g, let b) = color {
            XCTAssertEqual(r, 0)
            XCTAssertEqual(g, 255)
            XCTAssertEqual(b, 0)
        } else {
            XCTFail("Expected truecolor from hex")
        }
    }

    func testHexParsingInvalid() {
        let color = ANSIColor.fromHex("xyz")
        XCTAssertEqual(color, .default)
    }

    func testColorTo256() {
        let color = ANSIColor.trueColor(r: 255, g: 0, b: 0)
        let result = color.to256()
        if case .color256(let n) = result {
            XCTAssertTrue(n >= 16)
        } else {
            XCTFail("Expected color256")
        }
    }

    func testColorTo16() {
        let color = ANSIColor.trueColor(r: 200, g: 20, b: 20)
        let result = color.to16()
        // Should map to a 16-color value, not remain trueColor
        switch result {
        case .trueColor: XCTFail("Should be 16-color, not trueColor")
        case .color256: XCTFail("Should be 16-color, not 256")
        default: break
        }
    }

    func testThemeResolveMonochrome() {
        let theme = Theme.zyquoDark
        let resolved = theme.resolve(theme.colors.accent, capability: .monochrome)
        XCTAssertEqual(resolved, .default)
    }

    func testThemeResolveTrueColor() {
        let theme = Theme.zyquoDark
        let resolved = theme.resolve(theme.colors.accent, capability: .trueColor)
        XCTAssertEqual(resolved, theme.colors.accent)
    }

    func testThemeEngineLoadsBuiltin() {
        let engine = ThemeEngine(capability: .trueColor)
        let theme = engine.load(named: "zyquo-dark")
        XCTAssertEqual(theme.name, "zyquo-dark")
    }

    func testThemeEngineFallsBackToDefault() {
        let engine = ThemeEngine(capability: .trueColor)
        let theme = engine.load(named: "doesnt-exist-xyz")
        XCTAssertEqual(theme.name, "zyquo-dark")
    }

    func testThemeEngineAvailableThemes() {
        let engine = ThemeEngine(capability: .trueColor)
        let themes = engine.availableThemes()
        XCTAssertTrue(themes.contains("zyquo-dark"))
        XCTAssertTrue(themes.contains("minimal"))
        XCTAssertTrue(themes.contains("high-contrast"))
    }
}
