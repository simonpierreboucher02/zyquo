import Foundation
import TOMLKit

public struct ThemeColors: Sendable, Equatable {
    public var bg: ANSIColor
    public var bgPanel: ANSIColor
    public var fg: ANSIColor
    public var fgMuted: ANSIColor
    public var border: ANSIColor
    public var accent: ANSIColor
    public var accentStrong: ANSIColor
    public var ok: ANSIColor
    public var warn: ANSIColor
    public var risk: ANSIColor
    public var critical: ANSIColor
}

public struct SyntaxColors: Sendable, Equatable {
    public var keyword: ANSIColor
    public var string: ANSIColor
    public var number: ANSIColor
    public var comment: ANSIColor
    public var type: ANSIColor
    public var function: ANSIColor
}

public struct DiffColors: Sendable, Equatable {
    public var added: ANSIColor
    public var addedFg: ANSIColor
    public var removed: ANSIColor
    public var removedFg: ANSIColor
    public var context: ANSIColor
}

public struct Theme: Sendable, Equatable {
    public let name: String
    public let truecolor: Bool
    public let colors: ThemeColors
    public let syntax: SyntaxColors
    public let diff: DiffColors

    public func resolve(_ color: ANSIColor, capability: TerminalCapability) -> ANSIColor {
        switch capability {
        case .trueColor:
            return color
        case .color256:
            return color.to256()
        case .color16:
            return color.to16()
        case .monochrome:
            return .default
        }
    }
}

extension ANSIColor {
    func to256() -> ANSIColor {
        switch self {
        case .trueColor(let r, let g, let b):
            let ri = Int(r) * 5 / 255
            let gi = Int(g) * 5 / 255
            let bi = Int(b) * 5 / 255
            let idx = 16 + 36 * ri + 6 * gi + bi
            return .color256(UInt8(idx))
        default:
            return self
        }
    }

    func to16() -> ANSIColor {
        switch self {
        case .trueColor(let r, let g, let b):
            let brightness = (Int(r) + Int(g) + Int(b)) / 3
            if brightness < 32 { return .black }
            if brightness < 96 { return .brightBlack }
            let maxC = max(r, g, b)
            if maxC == r && g < 128 && b < 128 { return brightness > 180 ? .brightRed : .red }
            if maxC == g && r < 128 && b < 128 { return brightness > 180 ? .brightGreen : .green }
            if maxC == b && r < 128 && g < 128 { return brightness > 180 ? .brightBlue : .blue }
            if r > 128 && g > 128 && b < 128 { return brightness > 180 ? .brightYellow : .yellow }
            if r > 128 && b > 128 && g < 128 { return brightness > 180 ? .brightMagenta : .magenta }
            if g > 128 && b > 128 && r < 128 { return brightness > 180 ? .brightCyan : .cyan }
            return brightness > 180 ? .brightWhite : .white
        case .color256:
            return .white
        default:
            return self
        }
    }

    static func fromHex(_ hex: String) -> ANSIColor {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let val = UInt32(h, radix: 16) else { return .default }
        let r = UInt8((val >> 16) & 0xFF)
        let g = UInt8((val >> 8) & 0xFF)
        let b = UInt8(val & 0xFF)
        return .trueColor(r: r, g: g, b: b)
    }
}

// MARK: - Built-in Themes

extension Theme {
    public static let zyquoDark = Theme(
        name: "zyquo-dark",
        truecolor: true,
        colors: ThemeColors(
            bg: .fromHex("#0B0F14"),
            bgPanel: .fromHex("#0F141B"),
            fg: .fromHex("#D7DEE7"),
            fgMuted: .fromHex("#7A8693"),
            border: .fromHex("#2E4257"),
            accent: .fromHex("#5BA8FF"),
            accentStrong: .fromHex("#2F80ED"),
            ok: .fromHex("#4ADE80"),
            warn: .fromHex("#F59E0B"),
            risk: .fromHex("#EF4444"),
            critical: .fromHex("#B91C1C")
        ),
        syntax: SyntaxColors(
            keyword: .fromHex("#9D7CFF"),
            string: .fromHex("#7DD3FC"),
            number: .fromHex("#F0ABFC"),
            comment: .fromHex("#566677"),
            type: .fromHex("#5EEAD4"),
            function: .fromHex("#FBBF24")
        ),
        diff: DiffColors(
            added: .fromHex("#163E2F"),
            addedFg: .fromHex("#A7F3D0"),
            removed: .fromHex("#3B1418"),
            removedFg: .fromHex("#FCA5A5"),
            context: .fromHex("#7A8693")
        )
    )

    public static let minimal = Theme(
        name: "minimal",
        truecolor: false,
        colors: ThemeColors(
            bg: .default,
            bgPanel: .default,
            fg: .white,
            fgMuted: .brightBlack,
            border: .brightBlack,
            accent: .white,
            accentStrong: .brightWhite,
            ok: .green,
            warn: .yellow,
            risk: .red,
            critical: .brightRed
        ),
        syntax: SyntaxColors(
            keyword: .cyan,
            string: .green,
            number: .magenta,
            comment: .brightBlack,
            type: .yellow,
            function: .blue
        ),
        diff: DiffColors(
            added: .default,
            addedFg: .green,
            removed: .default,
            removedFg: .red,
            context: .brightBlack
        )
    )

    public static let highContrast = Theme(
        name: "high-contrast",
        truecolor: true,
        colors: ThemeColors(
            bg: .fromHex("#000000"),
            bgPanel: .fromHex("#0A0A0A"),
            fg: .fromHex("#FFFFFF"),
            fgMuted: .fromHex("#BBBBBB"),
            border: .fromHex("#FFFFFF"),
            accent: .fromHex("#00DDFF"),
            accentStrong: .fromHex("#00AAFF"),
            ok: .fromHex("#00FF00"),
            warn: .fromHex("#FFFF00"),
            risk: .fromHex("#FF4444"),
            critical: .fromHex("#FF0000")
        ),
        syntax: SyntaxColors(
            keyword: .fromHex("#FF77FF"),
            string: .fromHex("#00FF77"),
            number: .fromHex("#FFAA00"),
            comment: .fromHex("#888888"),
            type: .fromHex("#00FFFF"),
            function: .fromHex("#FFFF00")
        ),
        diff: DiffColors(
            added: .fromHex("#003300"),
            addedFg: .fromHex("#00FF00"),
            removed: .fromHex("#330000"),
            removedFg: .fromHex("#FF0000"),
            context: .fromHex("#BBBBBB")
        )
    )

    public static let solarizedDark = Theme(
        name: "solarized-dark",
        truecolor: true,
        colors: ThemeColors(
            bg: .fromHex("#002B36"),
            bgPanel: .fromHex("#073642"),
            fg: .fromHex("#839496"),
            fgMuted: .fromHex("#586E75"),
            border: .fromHex("#586E75"),
            accent: .fromHex("#268BD2"),
            accentStrong: .fromHex("#6C71C4"),
            ok: .fromHex("#859900"),
            warn: .fromHex("#B58900"),
            risk: .fromHex("#DC322F"),
            critical: .fromHex("#CB4B16")
        ),
        syntax: SyntaxColors(
            keyword: .fromHex("#859900"),
            string: .fromHex("#2AA198"),
            number: .fromHex("#D33682"),
            comment: .fromHex("#586E75"),
            type: .fromHex("#B58900"),
            function: .fromHex("#268BD2")
        ),
        diff: DiffColors(
            added: .fromHex("#073642"),
            addedFg: .fromHex("#859900"),
            removed: .fromHex("#073642"),
            removedFg: .fromHex("#DC322F"),
            context: .fromHex("#586E75")
        )
    )

    public static let builtInThemes: [Theme] = [.zyquoDark, .minimal, .highContrast, .solarizedDark]

    public static func builtIn(named name: String) -> Theme? {
        builtInThemes.first { $0.name == name }
    }
}

// MARK: - ThemeEngine

public final class ThemeEngine: Sendable {
    private let capability: TerminalCapability

    public init(capability: TerminalCapability = .detect()) {
        self.capability = capability
    }

    public func load(named name: String) -> Theme {
        if let builtin = Theme.builtIn(named: name) {
            return builtin
        }
        if let fromFile = loadFromFile(named: name) {
            return fromFile
        }
        return .zyquoDark
    }

    public func availableThemes() -> [String] {
        var names = Theme.builtInThemes.map(\.name)
        let themesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo/themes")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: themesDir, includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "toml" {
                let n = file.deletingPathExtension().lastPathComponent
                if !names.contains(n) { names.append(n) }
            }
        }
        return names
    }

    public func resolve(_ color: ANSIColor) -> ANSIColor {
        switch capability {
        case .trueColor: return color
        case .color256: return color.to256()
        case .color16: return color.to16()
        case .monochrome: return .default
        }
    }

    private func loadFromFile(named name: String) -> Theme? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo/themes/\(name).toml")
        guard let content = try? String(contentsOf: path, encoding: .utf8),
              let table = try? TOMLTable(string: content) else { return nil }
        return parseTheme(table, name: name)
    }

    private func parseTheme(_ table: TOMLTable, name: String) -> Theme {
        let hex = { (section: String, key: String, fallback: String) -> ANSIColor in
            guard let sub = table[section] as? TOMLTable,
                  let val = sub[key] as? String else {
                return .fromHex(fallback)
            }
            return .fromHex(val)
        }

        let tc = (table["truecolor"] as? Bool) ?? true

        return Theme(
            name: name,
            truecolor: tc,
            colors: ThemeColors(
                bg: hex("colors", "bg", "#0B0F14"),
                bgPanel: hex("colors", "bg_panel", "#0F141B"),
                fg: hex("colors", "fg", "#D7DEE7"),
                fgMuted: hex("colors", "fg_muted", "#7A8693"),
                border: hex("colors", "border", "#1F2A37"),
                accent: hex("colors", "accent", "#5BA8FF"),
                accentStrong: hex("colors", "accent_strong", "#2F80ED"),
                ok: hex("colors", "ok", "#4ADE80"),
                warn: hex("colors", "warn", "#F59E0B"),
                risk: hex("colors", "risk", "#EF4444"),
                critical: hex("colors", "critical", "#B91C1C")
            ),
            syntax: SyntaxColors(
                keyword: hex("syntax", "keyword", "#9D7CFF"),
                string: hex("syntax", "string", "#7DD3FC"),
                number: hex("syntax", "number", "#F0ABFC"),
                comment: hex("syntax", "comment", "#566677"),
                type: hex("syntax", "type", "#5EEAD4"),
                function: hex("syntax", "function", "#FBBF24")
            ),
            diff: DiffColors(
                added: hex("diff", "added", "#163E2F"),
                addedFg: hex("diff", "added_fg", "#A7F3D0"),
                removed: hex("diff", "removed", "#3B1418"),
                removedFg: hex("diff", "removed_fg", "#FCA5A5"),
                context: hex("diff", "context", "#7A8693")
            )
        )
    }
}
