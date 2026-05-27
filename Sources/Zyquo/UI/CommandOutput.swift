import Foundation

public struct CommandOutput: Sendable {
    let theme: Theme
    let capability: TerminalCapability
    let noColor: Bool
    let width: Int

    public init(noColor: Bool = false, width: Int? = nil) {
        let isNoColor = noColor || ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        self.noColor = isNoColor
        self.capability = isNoColor ? .monochrome : TerminalCapability.detect()
        self.theme = .zyquoDark
        if let w = width {
            self.width = w
        } else {
            self.width = max(40, Terminal.size.width)
        }
    }

    // MARK: - ANSI Helpers

    /// Returns an ANSI escape code string, or empty if noColor is set.
    public func ansi(_ code: String) -> String {
        noColor ? "" : "\u{1B}[\(code)m"
    }

    /// Returns the ANSI foreground code for a color, resolving for capability.
    public func fg(_ color: ANSIColor) -> String {
        guard !noColor else { return "" }
        let resolved = theme.resolve(color, capability: capability)
        if case .default = resolved { return "" }
        return "\u{1B}[\(resolved.fgCode)m"
    }

    /// Returns ANSI reset or empty string.
    public func reset() -> String {
        noColor ? "" : "\u{1B}[0m"
    }

    /// Print a blank line.
    public func blank() {
        print("")
    }

    // MARK: - Border Characters

    private var tl: String { noColor ? "+" : "\u{256D}" }
    private var tr: String { noColor ? "+" : "\u{256E}" }
    private var bl: String { noColor ? "+" : "\u{2570}" }
    private var br: String { noColor ? "+" : "\u{256F}" }
    private var hz: String { noColor ? "-" : "\u{2500}" }
    private var vt: String { noColor ? "|" : "\u{2502}" }

    // MARK: - Panels

    /// Render a header panel with a left-aligned title and optional right-aligned badge.
    ///
    /// ```
    /// +-- Title --------------------------------- BADGE -+
    /// ```
    public func header(title: String, subtitle: String? = nil, badge: String? = nil, badgeColor: ANSIColor? = nil) {
        let borderColor = fg(theme.colors.border)
        let titleColor = fg(theme.colors.accent)
        let rst = reset()
        let boldCode = ansi("1")

        let innerWidth = width - 2

        // Top border with title and optional badge
        var top = borderColor + tl + hz + rst
        top += " " + boldCode + titleColor + title + rst + " "

        let titleVisibleLen = title.count + 4  // "─ Title "
        var badgeVisibleLen = 0

        if let badge = badge {
            badgeVisibleLen = badge.count + 3  // " BADGE ─"
        }

        let fillLen = max(0, innerWidth - titleVisibleLen - badgeVisibleLen)
        top += borderColor + String(repeating: hz, count: fillLen) + rst

        if let badge = badge {
            let bColor = badgeColor.map { fg($0) } ?? fg(theme.colors.fgMuted)
            top += " " + boldCode + bColor + badge + rst + " "
        }

        top += borderColor + tr + rst
        print(top)

        // Subtitle line (if provided)
        if let subtitle = subtitle {
            let mutedColor = fg(theme.colors.fgMuted)
            let subText = String(subtitle.prefix(innerWidth - 2))
            let pad = max(0, innerWidth - subText.count - 2)
            let line = borderColor + vt + rst
                + " " + mutedColor + subText + rst
                + String(repeating: " ", count: pad) + " "
                + borderColor + vt + rst
            print(line)
        }
    }

    /// Render a footer panel with key-value pairs.
    public func footer(items: [(String, String)]) {
        let borderColor = fg(theme.colors.border)
        let mutedColor = fg(theme.colors.fgMuted)
        let fgColor = fg(theme.colors.fg)
        let rst = reset()

        let innerWidth = width - 2

        // Separator before footer items
        let sep = borderColor + vt + rst
            + " " + borderColor + String(repeating: hz, count: innerWidth - 2) + rst + " "
            + borderColor + vt + rst
        print(sep)

        // Key-value items
        for (key, value) in items {
            let contentLen = key.count + 2 + value.count  // "key: value"
            let trailing = max(0, innerWidth - contentLen - 2)
            let line = borderColor + vt + rst
                + " " + mutedColor + key + ":" + rst + " " + fgColor + value + rst
                + String(repeating: " ", count: trailing) + " "
                + borderColor + vt + rst
            print(line)
        }

        // Bottom border
        let bottom = borderColor + bl + String(repeating: hz, count: innerWidth) + br + rst
        print(bottom)
    }

    /// Print a colored section header with a dim underline separator.
    public func section(title: String) {
        let boldCode = ansi("1")
        let accentColor = fg(theme.colors.accent)
        let borderColor = fg(theme.colors.border)
        let rst = reset()

        print(boldCode + accentColor + title + rst)
        let underlineLen = min(title.count + 4, width)
        print(borderColor + String(repeating: hz, count: underlineLen) + rst)
    }

    // MARK: - Content

    /// Print a key-value pair with optional indent.
    public func keyValue(_ key: String, _ value: String, indent: Int = 2) {
        let mutedColor = fg(theme.colors.fgMuted)
        let fgColor = fg(theme.colors.fg)
        let rst = reset()
        let pad = String(repeating: " ", count: indent)
        print("\(pad)\(mutedColor)\(key):\(rst) \(fgColor)\(value)\(rst)")
    }

    /// Print a success check item: check-mark icon in green.
    public func checkItem(_ label: String, detail: String? = nil) {
        statusItem(icon: noColor ? "[OK]" : "\u{2713}", color: theme.colors.ok, label: label, detail: detail)
    }

    /// Print a failure item: cross icon in red.
    public func failItem(_ label: String, detail: String? = nil) {
        statusItem(icon: noColor ? "[FAIL]" : "\u{2717}", color: theme.colors.risk, label: label, detail: detail)
    }

    /// Print a warning item: exclamation icon in yellow.
    public func warnItem(_ label: String, detail: String? = nil) {
        statusItem(icon: noColor ? "[WARN]" : "!", color: theme.colors.warn, label: label, detail: detail)
    }

    /// Print an info item: info icon in accent color.
    public func infoItem(_ label: String, detail: String? = nil) {
        statusItem(icon: noColor ? "[INFO]" : "\u{2139}", color: theme.colors.accent, label: label, detail: detail)
    }

    /// Print a neutral/pending item: circle icon in muted color.
    public func pendingItem(_ label: String, detail: String? = nil) {
        statusItem(icon: noColor ? "[--]" : "\u{25CB}", color: theme.colors.fgMuted, label: label, detail: detail)
    }

    private func statusItem(icon: String, color: ANSIColor, label: String, detail: String?) {
        let iconColor = fg(color)
        let fgColor = fg(theme.colors.fg)
        let mutedColor = fg(theme.colors.fgMuted)
        let rst = reset()
        var line = "  \(iconColor)\(icon)\(rst) \(fgColor)\(label)\(rst)"
        if let detail = detail {
            line += " \(mutedColor)\(detail)\(rst)"
        }
        print(line)
    }

    // MARK: - Streaming

    /// Print opening context before streaming output begins.
    public func streamStart() {
        print("", terminator: "")
        fflush(stdout)
    }

    /// Print a newline after streaming output ends.
    public func streamEnd() {
        print("")
        fflush(stdout)
    }
}
