import Foundation

// MARK: - PremiumPanel

/// Renders "premium" filled cards: a raised `bgPanel` surface, an iris-gradient
/// title, vivid iris-tinted rounded borders, and display-width-correct padding.
///
/// Lines are composed from typed `Segment`s and emit a single SGR reset at the
/// very end, so the panel background never bleeds and never gets cleared mid
/// line. Degrades gracefully: no background fill on 16-color/mono, ASCII
/// borders when `noColor`.
public struct PremiumPanel: Sendable {

    /// A run of text with one foreground color.
    public struct Segment: Sendable {
        public let text: String
        public let color: RGB?      // nil → default fg
        public let bold: Bool
        public let dim: Bool
        public init(_ text: String, _ color: RGB? = nil, bold: Bool = false, dim: Bool = false) {
            self.text = text; self.color = color; self.bold = bold; self.dim = dim
        }
    }

    let gradient: Gradient
    let theme: Theme
    let capability: TerminalCapability
    let noColor: Bool

    public init(theme: Theme, capability: TerminalCapability, noColor: Bool) {
        self.theme = theme
        self.capability = capability
        self.noColor = noColor
        self.gradient = Gradient(theme: theme, capability: capability, noColor: noColor)
    }

    // MARK: - Derived colors

    /// Iris-tinted, visibly brighter border than the raw (very dark) theme one.
    public var borderRGB: RGB {
        RGB(ansi: theme.colors.border)
            .mix(gradient.start, 0.5)
            .mix(RGB(0xFF, 0xFF, 0xFF), 0.06)
    }
    public var panelBG: RGB { RGB(ansi: theme.colors.bgPanel) }
    public var fgRGB: RGB { RGB(ansi: theme.colors.fg) }
    public var mutedRGB: RGB { RGB(ansi: theme.colors.fgMuted) }

    private var filled: Bool { !noColor && (capability == .trueColor || capability == .color256) }

    // MARK: - Border glyphs

    private var tl: String { noColor ? "+" : "\u{256D}" }
    private var tr: String { noColor ? "+" : "\u{256E}" }
    private var bl: String { noColor ? "+" : "\u{2570}" }
    private var br: String { noColor ? "+" : "\u{256F}" }
    private var hz: String { noColor ? "-" : "\u{2500}" }
    private var vt: String { noColor ? "|" : "\u{2502}" }

    // MARK: - Low-level SGR (no mid-line resets)

    private func fgCode(_ rgb: RGB?) -> String {
        guard !noColor, let rgb else { return "" }
        return gradient.fg(rgb)
    }
    private var bgCode: String { filled ? gradient.bg(panelBG) : "" }
    private var reset: String { noColor ? "" : "\u{1B}[0m" }
    private var boldCode: String { noColor ? "" : "\u{1B}[1m" }

    // MARK: - Public API

    /// Build a full panel: rounded header with gradient title, filled body, and
    /// rounded footer. `bodyRows` is a list of segment-rows.
    ///
    /// - Parameters:
    ///   - title: header label (rendered with the iris gradient).
    ///   - icon: optional leading glyph in the header.
    ///   - bodyRows: each inner row as an array of `Segment`s.
    ///   - width: total panel width in columns.
    ///   - accent: header/border color override (defaults to iris border).
    public func panel(
        title: String,
        icon: String? = nil,
        bodyRows: [[Segment]],
        width: Int,
        accent: RGB? = nil
    ) -> [String] {
        let inner = max(8, width - 2)              // columns between the borders
        let textWidth = inner - 2                  // 1-space gutter each side
        var lines: [String] = []
        lines.append(headerLine(title: title, icon: icon, inner: inner, accent: accent))
        for row in bodyRows {
            lines.append(bodyLine(row, textWidth: textWidth, inner: inner))
        }
        lines.append(footerLine(inner: inner, accent: accent))
        return lines
    }

    /// A header line on its own (rounded top with gradient title).
    public func headerLine(title: String, icon: String?, inner: Int, accent: RGB? = nil) -> String {
        let border = accent ?? borderRGB
        let label = icon != nil ? "\(icon!) \(title)" : title
        let labelW = DisplayWidth.width(label)
        // Inner columns (between the corners) = hz + " " + label + " " + fill.
        let used = 1 + 1 + labelW + 1   // "─" + " " + label + " "
        let fill = max(0, inner - used)

        var s = bgCode + fgCode(border) + tl + hz + " "
        s += gradientLabel(label)              // no reset inside
        s += fgCode(border) + " " + String(repeating: hz, count: fill) + tr + reset
        return s
    }

    /// A filled body row from typed segments.
    public func bodyLine(_ segments: [Segment], textWidth: Int, inner: Int) -> String {
        var content = ""
        var used = 0
        for seg in segments {
            let w = DisplayWidth.width(seg.text)
            // truncate if a single line overflows
            let text: String
            if used + w > textWidth {
                text = DisplayWidth.truncate(seg.text, to: max(0, textWidth - used))
            } else {
                text = seg.text
            }
            let attrs = (seg.bold ? boldCode : "") + (seg.dim ? (noColor ? "" : "\u{1B}[2m") : "")
            content += attrs + fgCode(seg.color) + text
            used += DisplayWidth.width(text)
            // After bold/dim we must reset attributes but keep bg+restore: emit
            // a lightweight attribute-off by re-stating fg only. Simpler: avoid
            // mixing bold/dim mid-row; callers use one style per segment.
            if seg.bold || seg.dim { content += noColor ? "" : "\u{1B}[22m" }
            if used >= textWidth { break }
        }
        let pad = max(0, textWidth - used)
        var s = bgCode + fgCode(borderRGB) + vt + " "
        s += content
        s += String(repeating: " ", count: pad)
        s += " " + fgCode(borderRGB) + vt + reset
        return s
    }

    /// The rounded footer line.
    public func footerLine(inner: Int, accent: RGB? = nil) -> String {
        let border = accent ?? borderRGB
        return bgCode + fgCode(border) + bl + String(repeating: hz, count: inner) + br + reset
    }

    /// A gradient hairline rule (no panel), `width` columns.
    public func rule(width: Int, heavy: Bool = false) -> String {
        gradient.rule(width: width, glyph: heavy ? "\u{2501}" : "\u{2500}")
    }

    /// A single iris-gradient title string (per-char fg, no trailing reset so it
    /// composes inside a filled line; bold).
    public func gradientLabel(_ text: String) -> String {
        guard !noColor else { return text }
        guard capability == .trueColor else {
            return boldCode + gradient.fg(theme.colors.accent) + text
        }
        let chars = Array(text)
        guard chars.count > 1 else {
            return boldCode + gradient.fg(gradient.start) + text
        }
        var out = boldCode
        for (i, ch) in chars.enumerated() {
            let c = gradient.color(at: Double(i) / Double(chars.count - 1))
            out += "\u{1B}[38;2;\(c.r);\(c.g);\(c.b)m\(ch)"
        }
        return out
    }
}
