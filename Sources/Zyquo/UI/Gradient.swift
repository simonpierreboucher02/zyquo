import Foundation

// MARK: - RGB

/// A simple 8-bit-per-channel RGB color used for gradient math.
public struct RGB: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    /// Parse `#RRGGBB`.
    public init(hex: String) {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count != 6 { h = "5BA8FF" }
        let v = UInt32(h, radix: 16) ?? 0x5BA8FF
        self.init(UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    /// Build from an `ANSIColor` truecolor case (falls back to iris blue).
    public init(ansi: ANSIColor) {
        if case .trueColor(let r, let g, let b) = ansi {
            self.init(r, g, b)
        } else {
            self.init(0x5B, 0xA8, 0xFF)
        }
    }

    /// Linear interpolation toward another color (t in 0…1).
    public func lerp(to other: RGB, _ t: Double) -> RGB {
        let tt = min(1, max(0, t))
        return RGB(
            UInt8(Double(r) + (Double(other.r) - Double(r)) * tt),
            UInt8(Double(g) + (Double(other.g) - Double(g)) * tt),
            UInt8(Double(b) + (Double(other.b) - Double(b)) * tt)
        )
    }

    /// Mix toward another color by amount (alias for lerp).
    public func mix(_ other: RGB, _ amount: Double) -> RGB { lerp(to: other, amount) }

    public var ansi: ANSIColor { .trueColor(r: r, g: g, b: b) }
}

// MARK: - Gradient

/// Renderer-level gradient + truecolor helpers for the premium TUI. Reads its
/// endpoints from the active theme so it follows `/theme` switches: the iris
/// signature runs `accent` → `syntax.keyword` (blue → violet in zyquo-dark).
///
/// All emitters are capability-aware: truecolor gets exact RGB, 256/16 fall
/// back to the theme's resolved color, monochrome emits nothing.
public struct Gradient: Sendable {
    public let start: RGB
    public let end: RGB
    public let capability: TerminalCapability
    public let noColor: Bool
    private let theme: Theme

    public init(theme: Theme, capability: TerminalCapability, noColor: Bool) {
        self.theme = theme
        self.capability = capability
        self.noColor = noColor
        self.start = RGB(ansi: theme.colors.accent)
        self.end = RGB(ansi: theme.syntax.keyword) // iris violet endpoint
    }

    private var isTrue: Bool { !noColor && capability == .trueColor }

    /// Color sampled along the gradient at position `t` (0…1).
    public func color(at t: Double) -> RGB { start.lerp(to: end, t) }

    /// `steps` evenly spaced colors across the gradient.
    public func ramp(_ steps: Int) -> [RGB] {
        guard steps > 1 else { return [start] }
        return (0..<steps).map { start.lerp(to: end, Double($0) / Double(steps - 1)) }
    }

    // MARK: - ANSI

    public var reset: String { noColor ? "" : "\u{1B}[0m" }
    public var bold: String { noColor ? "" : "\u{1B}[1m" }
    public var dim: String { noColor ? "" : "\u{1B}[2m" }
    public var italic: String { noColor ? "" : "\u{1B}[3m" }

    /// Foreground for a theme `ANSIColor`, capability-resolved.
    public func fg(_ color: ANSIColor) -> String {
        guard !noColor else { return "" }
        let resolved = theme.resolve(color, capability: capability)
        if case .default = resolved { return "" }
        return "\u{1B}[\(resolved.fgCode)m"
    }

    /// Background for a theme `ANSIColor`, capability-resolved. Only emits for
    /// truecolor/256 (filled surfaces are skipped on 16-color/mono to avoid
    /// muddy output).
    public func bg(_ color: ANSIColor) -> String {
        guard !noColor, capability == .trueColor || capability == .color256 else { return "" }
        let resolved = theme.resolve(color, capability: capability)
        if case .default = resolved { return "" }
        return "\u{1B}[\(resolved.bgCode)m"
    }

    /// Foreground for an explicit RGB (truecolor); on 256/16 resolves via theme.
    public func fg(_ rgb: RGB) -> String {
        guard !noColor else { return "" }
        if isTrue { return "\u{1B}[38;2;\(rgb.r);\(rgb.g);\(rgb.b)m" }
        let resolved = theme.resolve(rgb.ansi, capability: capability)
        if case .default = resolved { return "" }
        return "\u{1B}[\(resolved.fgCode)m"
    }

    public func bg(_ rgb: RGB) -> String {
        guard !noColor, capability == .trueColor || capability == .color256 else { return "" }
        if isTrue { return "\u{1B}[48;2;\(rgb.r);\(rgb.g);\(rgb.b)m" }
        let resolved = theme.resolve(rgb.ansi, capability: capability)
        if case .default = resolved { return "" }
        return "\u{1B}[\(resolved.bgCode)m"
    }

    /// Render `text` with each character stepped along the gradient (truecolor).
    /// Falls back to a flat accent color when not truecolor.
    public func text(_ text: String, bold useBold: Bool = false) -> String {
        guard isTrue else {
            return "\(useBold ? bold : "")\(fg(theme.colors.accent))\(text)\(reset)"
        }
        let chars = Array(text)
        guard chars.count > 1 else {
            return "\(useBold ? bold : "")\(fg(start))\(text)\(reset)"
        }
        var out = useBold ? bold : ""
        for (i, ch) in chars.enumerated() {
            let c = color(at: Double(i) / Double(chars.count - 1))
            out += "\u{1B}[38;2;\(c.r);\(c.g);\(c.b)m\(ch)"
        }
        return out + reset
    }

    /// A horizontal rule of `width` columns drawn with the gradient (truecolor),
    /// using the given glyph (default a thin line). Flat dim line otherwise.
    public func rule(width: Int, glyph: String = "\u{2500}") -> String {
        guard width > 0 else { return "" }
        guard isTrue else {
            return "\(dim)\(fg(theme.colors.border))\(String(repeating: glyph, count: width))\(reset)"
        }
        var out = ""
        for i in 0..<width {
            let c = color(at: Double(i) / Double(max(1, width - 1)))
            out += "\u{1B}[38;2;\(c.r);\(c.g);\(c.b)m\(glyph)"
        }
        return out + reset
    }
}
