import Foundation

/// Renders the interactive REPL surface in the "Premium Panels" style:
/// raised filled cards with iris-gradient titles, vivid rounded borders, a
/// gradient left gutter for streamed AI text, and gradient hairline rules.
///
/// Public API is unchanged so `InteractiveCommand` needs no edits. All output
/// degrades gracefully (no bg fill on 16-color/mono, ASCII borders on NO_COLOR).
public struct InteractiveBoxRenderer: Sendable {
    let theme: Theme
    let capability: TerminalCapability
    let noColor: Bool
    private let panel: PremiumPanel
    private let grad: Gradient

    public init(theme: Theme? = nil, noColor: Bool = false) {
        let t = theme ?? .zyquoDark
        let cap: TerminalCapability = noColor ? .monochrome : TerminalCapability.detect()
        self.theme = t
        self.capability = cap
        self.noColor = noColor
        self.panel = PremiumPanel(theme: t, capability: cap, noColor: noColor)
        self.grad = Gradient(theme: t, capability: cap, noColor: noColor)
    }

    private var width: Int { min(max(40, Terminal.size.width), 100) }
    private var rst: String { noColor ? "" : "\u{1B}[0m" }
    private var dim: String { noColor ? "" : "\u{1B}[2m" }
    private var bold: String { noColor ? "" : "\u{1B}[1m" }

    private var fgRGB: RGB { RGB(ansi: theme.colors.fg) }
    private var mutedRGB: RGB { RGB(ansi: theme.colors.fg).mix(RGB(ansi: theme.colors.fgMuted), 1.0) }
    private func rgb(_ c: ANSIColor) -> RGB { RGB(ansi: c) }

    private func fg(_ c: ANSIColor) -> String { grad.fg(c) }

    // MARK: - User Input

    public func renderUserInput(_ text: String) {
        let textWidth = width - 4
        let rows = wrap(text, textWidth).map { [PremiumPanel.Segment($0, fgRGB)] }
        let body = rows.isEmpty ? [[PremiumPanel.Segment("", fgRGB)]] : rows
        print()
        for line in panel.panel(title: "You", icon: glyph(">", "\u{276F}"), bodyRows: body, width: width) {
            print(line)
        }
    }

    // MARK: - AI Response (streamed)

    public func renderResponseStart(model: String) {
        print()
        // Rounded header with gradient title, then start the gradient gutter.
        print(panel.headerLine(title: model, icon: glyph("*", "\u{2726}"), inner: width - 2))
        print(gutter(), terminator: "")
        fflush(stdout)
    }

    public func renderResponseDelta(_ text: String) {
        for ch in text {
            if ch == "\n" {
                print()
                print(gutter(), terminator: "")
            } else {
                print(String(ch), terminator: "")
            }
        }
        fflush(stdout)
    }

    public func renderResponseEnd() {
        print()
        // Gradient hairline closes the response block.
        print(" " + panel.rule(width: width - 2))
    }

    /// The iris gradient left gutter prefix for a streamed line.
    private func gutter() -> String {
        guard !noColor else { return "| " }
        let bar = "\u{258C}" // ▌
        return grad.fg(grad.start) + bar + rst + " "
    }

    // MARK: - Tool Call

    public func renderToolCall(name: String, preview: String, isError: Bool = false) {
        let accent = isError ? rgb(theme.colors.risk) : rgb(theme.colors.accent)
        let statusGlyph = isError ? glyph("FAIL", "\u{2717}") : glyph("OK", "\u{2713}")
        let statusColor = isError ? rgb(theme.colors.risk) : rgb(theme.colors.ok)
        let icon = isError ? glyph("x", "\u{2717}") : glyph(">", "\u{27E2}")

        let innerText = width - 6
        let clean = preview.replacingOccurrences(of: "\n", with: " ")
        var rows: [[PremiumPanel.Segment]] = wrap(clean, innerText).prefix(3).map {
            [PremiumPanel.Segment($0, mutedRGB, dim: true)]
        }
        rows.append([
            PremiumPanel.Segment("\(statusGlyph) ", statusColor, bold: true),
            PremiumPanel.Segment(isError ? "failed" : "done", statusColor),
        ])

        let lines = panel.panel(
            title: name, icon: icon, bodyRows: rows, width: width - 2, accent: accent
        )
        for line in lines { print("  " + line) }
    }

    public func renderToolDuration(_ durationMs: Int) {
        let s = durationMs >= 1000 ? String(format: "%.1fs", Double(durationMs) / 1000) : "\(durationMs)ms"
        print("    \(dim)\(fg(theme.colors.fgMuted))\(glyph("~", "\u{231A}")) \(s)\(rst)")
    }

    // MARK: - Session Stats

    public func renderSessionStats(tokens: String, cost: String, requests: String) {
        let sep = PremiumPanel.Segment("  \(glyph("|", "\u{2502}"))  ", rgb(theme.colors.border))
        let row: [PremiumPanel.Segment] = [
            PremiumPanel.Segment(glyph("tok", "\u{25C8}") + " ", rgb(theme.colors.accent)),
            PremiumPanel.Segment(tokens, fgRGB),
            sep,
            PremiumPanel.Segment("$ ", rgb(theme.colors.ok)),
            PremiumPanel.Segment(cost, fgRGB),
            sep,
            PremiumPanel.Segment("# ", rgb(theme.colors.warn)),
            PremiumPanel.Segment(requests, fgRGB),
        ]
        print()
        for line in panel.panel(title: "Session", icon: glyph("=", "\u{25B8}"), bodyRows: [row], width: width) {
            print(line)
        }
    }

    // MARK: - Prompt

    public func renderPrompt() {
        let icon = glyph(">", "\u{276F}")
        let label = grad.text("\(icon) zyquo", bold: true)
        print("\(label) \(dim)\(fg(theme.colors.fgMuted))\(glyph("|", "\u{2502}"))\(rst) ", terminator: "")
        fflush(stdout)
    }

    // MARK: - Slash Command Results

    public func renderCommandResult(title: String, items: [(String, String)]) {
        let keyWidth = (items.map { DisplayWidth.width($0.0) }.max() ?? 6) + 2
        let rows: [[PremiumPanel.Segment]] = items.map { key, value in
            let label = DisplayWidth.pad(key, to: keyWidth)
            return [
                PremiumPanel.Segment(label, mutedRGB),
                PremiumPanel.Segment(value, fgRGB),
            ]
        }
        print()
        for line in panel.panel(title: title, bodyRows: rows.isEmpty ? [[PremiumPanel.Segment("", fgRGB)]] : rows, width: width) {
            print(line)
        }
        print()
    }

    public func renderListPanel(title: String, entries: [(String, String)], keyColor: ANSIColor? = nil) {
        let kc = rgb(keyColor ?? theme.colors.accent)
        let keyWidth = (entries.map { DisplayWidth.width($0.0) }.max() ?? 8) + 2
        let rows: [[PremiumPanel.Segment]] = entries.map { key, desc in
            [
                PremiumPanel.Segment(DisplayWidth.pad(key, to: keyWidth), kc, bold: true),
                PremiumPanel.Segment(desc, mutedRGB),
            ]
        }
        print()
        for line in panel.panel(title: title, bodyRows: rows.isEmpty ? [[PremiumPanel.Segment("", fgRGB)]] : rows, width: width) {
            print(line)
        }
        print()
    }

    // MARK: - Thinking

    private static let braille = ["\u{280B}", "\u{2819}", "\u{2839}", "\u{2838}", "\u{283C}", "\u{2834}", "\u{2826}", "\u{2827}", "\u{2807}", "\u{280F}"]

    public func renderThinking() {
        let spin = noColor ? "..." : Self.braille[0]
        print("  \(fg(theme.colors.accent))\(spin)\(rst) \(dim)\(fg(theme.colors.fgMuted))thinking\(rst)", terminator: "\r")
        fflush(stdout)
    }

    public func clearThinking() {
        print("\r\(String(repeating: " ", count: width))\r", terminator: "")
        fflush(stdout)
    }

    // MARK: - Error

    public func renderError(_ message: String, hint: String? = nil) {
        let risk = rgb(theme.colors.risk)
        let textWidth = width - 4
        var rows: [[PremiumPanel.Segment]] = wrap(message, textWidth).map {
            [PremiumPanel.Segment($0, risk)]
        }
        if let hint {
            rows.append([PremiumPanel.Segment(String(repeating: glyph("-", "\u{2500}"), count: textWidth), rgb(theme.colors.border))])
            for line in wrap("Hint: \(hint)", textWidth) {
                rows.append([PremiumPanel.Segment(line, mutedRGB, dim: true)])
            }
        }
        print()
        for line in panel.panel(title: "Error", icon: glyph("!", "\u{26A0}"), bodyRows: rows, width: width, accent: risk) {
            print(line)
        }
    }

    // MARK: - Separator

    public func renderSeparator() { print() }

    // MARK: - Utilities

    private func glyph(_ ascii: String, _ unicode: String) -> String {
        noColor ? ascii : unicode
    }

    private func wrap(_ text: String, _ maxWidth: Int) -> [String] {
        guard maxWidth > 0 else { return [text] }
        var result: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if DisplayWidth.width(raw) <= maxWidth {
                result.append(raw)
                continue
            }
            var remaining = raw
            while DisplayWidth.width(remaining) > maxWidth {
                let head = DisplayWidth.truncate(remaining, to: maxWidth)
                // try to break at the last space within head
                if let spaceIdx = head.lastIndex(of: " "), spaceIdx != head.startIndex {
                    result.append(String(head[..<spaceIdx]))
                    remaining = String(remaining[remaining.index(after: spaceIdx)...])
                } else {
                    result.append(head)
                    remaining = String(remaining.dropFirst(head.count))
                }
            }
            if !remaining.isEmpty { result.append(remaining) }
        }
        return result.isEmpty ? [""] : result
    }
}
