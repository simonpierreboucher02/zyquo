import Foundation

/// Renders beautiful bordered boxes for the interactive REPL.
/// Wraps user prompts, AI responses, tool calls, and session stats
/// in styled Unicode-bordered panels.
public struct InteractiveBoxRenderer: Sendable {
    let theme: Theme
    let capability: TerminalCapability
    let noColor: Bool

    public init(theme: Theme? = nil, noColor: Bool = false) {
        self.theme = theme ?? .zyquoDark
        self.capability = noColor ? .monochrome : TerminalCapability.detect()
        self.noColor = noColor
    }

    // MARK: - ANSI Helpers

    private func fg(_ color: ANSIColor) -> String {
        guard !noColor else { return "" }
        let resolved = theme.resolve(color, capability: capability)
        if case .default = resolved { return "" }
        return "\u{1B}[\(resolved.fgCode)m"
    }

    private var rst: String { noColor ? "" : "\u{1B}[0m" }
    private var bold: String { noColor ? "" : "\u{1B}[1m" }
    private var dim: String { noColor ? "" : "\u{1B}[2m" }

    private var tl: String { noColor ? "+" : "\u{256D}" }
    private var tr: String { noColor ? "+" : "\u{256E}" }
    private var bl: String { noColor ? "+" : "\u{2570}" }
    private var br: String { noColor ? "+" : "\u{256F}" }
    private var hz: String { noColor ? "-" : "\u{2500}" }
    private var vt: String { noColor ? "|" : "\u{2502}" }

    private var width: Int { max(40, Terminal.size.width) }

    // MARK: - User Input Box

    /// Renders a compact box showing the user's input message.
    public func renderUserInput(_ text: String) {
        let w = width
        let innerWidth = w - 2
        let borderColor = fg(theme.colors.accent)
        let titleColor = fg(theme.colors.accent)
        let textColor = fg(theme.colors.fg)
        let icon = noColor ? ">" : "\u{276F}"

        // Top with title
        let titleText = " \(icon) You "
        let titleLen = stripANSI(titleText).count
        let rightFill = max(0, innerWidth - 1 - titleLen)
        print("\(borderColor)\(tl)\(hz)\(rst)\(bold)\(titleColor)\(titleText)\(rst)\(borderColor)\(String(repeating: hz, count: rightFill))\(tr)\(rst)")

        // Content lines
        let lines = wrapText(text, maxWidth: innerWidth - 2)
        for line in lines {
            let padLen = max(0, innerWidth - visibleLength(line) - 2)
            print("\(borderColor)\(vt)\(rst) \(textColor)\(line)\(rst)\(String(repeating: " ", count: padLen)) \(borderColor)\(vt)\(rst)")
        }

        // Bottom
        print("\(borderColor)\(bl)\(String(repeating: hz, count: innerWidth))\(br)\(rst)")
    }

    // MARK: - AI Response Box

    /// Call before streaming to print the top border of the response box.
    public func renderResponseStart(model: String) {
        let w = width
        let innerWidth = w - 2
        let borderColor = fg(theme.colors.border)
        let titleColor = fg(theme.colors.accentStrong)
        let accentColor = fg(theme.colors.accent)
        let icon = noColor ? "*" : "\u{2726}"

        let titleText = " \(icon) \(model) "
        let titleLen = stripANSI(titleText).count
        let rightFill = max(0, innerWidth - 1 - titleLen)

        print()
        print("\(borderColor)\(tl)\(hz)\(rst)\(bold)\(titleColor)\(titleText)\(rst)\(borderColor)\(String(repeating: hz, count: rightFill))\(tr)\(rst)")
        // Left gutter bar for first content line
        print("\(accentColor)\(vt)\(rst) ", terminator: "")
        fflush(stdout)
    }

    /// Call for each streaming text delta during response.
    /// Uses a colored left gutter bar to frame the streaming content.
    public func renderResponseDelta(_ text: String) {
        let accentColor = fg(theme.colors.accent)

        for char in text {
            if char == "\n" {
                print()
                print("\(accentColor)\(vt)\(rst) ", terminator: "")
            } else {
                print(String(char), terminator: "")
            }
        }
        fflush(stdout)
    }

    /// Call after streaming ends to close the response box.
    public func renderResponseEnd() {
        let w = width
        let innerWidth = w - 2
        let borderColor = fg(theme.colors.border)

        // End the last content line
        print()
        // Bottom border
        print("\(borderColor)\(bl)\(String(repeating: hz, count: innerWidth))\(br)\(rst)")
    }

    // MARK: - Tool Call Box

    /// Renders a tool invocation with its result in a compact styled panel.
    public func renderToolCall(name: String, preview: String, isError: Bool = false) {
        let w = width
        let innerWidth = w - 4
        let borderColor = fg(theme.colors.fgMuted)
        let toolColor = isError ? fg(theme.colors.risk) : fg(theme.colors.warn)
        let icon = isError
            ? (noColor ? "[X]" : "\u{2717}")
            : (noColor ? "[>]" : "\u{25B6}")
        let statusIcon = isError
            ? (noColor ? "FAIL" : "\u{2717}")
            : (noColor ? "OK" : "\u{2713}")
        let statusColor = isError ? fg(theme.colors.risk) : fg(theme.colors.ok)

        // Single-line compact tool header
        let headerText = " \(icon) \(name) "
        let headerLen = stripANSI(headerText).count + 2
        let rightFill = max(0, innerWidth - headerLen + 2)

        print("  \(borderColor)\(tl)\(hz)\(rst)\(bold)\(toolColor)\(headerText)\(rst)\(borderColor)\(String(repeating: hz, count: rightFill))\(tr)\(rst)")

        // Preview line(s)
        let truncatedPreview = String(preview.prefix(max(10, innerWidth - 4)))
            .replacingOccurrences(of: "\n", with: " ")
        let lines = wrapText(truncatedPreview, maxWidth: innerWidth - 2)
        for line in lines {
            let padLen = max(0, innerWidth - visibleLength(line) - 2)
            print("  \(borderColor)\(vt)\(rst) \(dim)\(line)\(rst)\(String(repeating: " ", count: padLen)) \(borderColor)\(vt)\(rst)")
        }

        // Status + bottom
        let statusText = " \(statusIcon) "
        let statusLen = stripANSI(statusText).count + 2
        let bottomFill = max(0, innerWidth - statusLen + 2)
        print("  \(borderColor)\(bl)\(String(repeating: hz, count: bottomFill))\(rst)\(statusColor)\(statusText)\(rst)\(borderColor)\(hz)\(br)\(rst)")
    }

    /// Renders tool execution duration.
    public func renderToolDuration(_ durationMs: Int) {
        let durationStr = durationMs >= 1000
            ? String(format: "%.1fs", Double(durationMs) / 1000.0)
            : "\(durationMs)ms"
        print("  \(dim)\(fg(theme.colors.fgMuted))  \u{231A} \(durationStr)\(rst)")
    }

    // MARK: - Session Stats Box

    /// Renders the session cost/token footer in a styled panel.
    public func renderSessionStats(tokens: String, cost: String, requests: String) {
        let w = width
        let innerWidth = w - 2
        let borderColor = fg(theme.colors.border)
        let mutedColor = fg(theme.colors.fgMuted)
        let fgColor = fg(theme.colors.fg)

        // Top thin separator
        print("\(borderColor)\(tl)\(String(repeating: hz, count: innerWidth))\(tr)\(rst)")

        // Stats items inline
        let items: [(String, String, String)] = [
            ("tok", "Tokens", tokens),
            ("$", "Cost", cost),
            ("#", "Reqs", requests),
        ]
        let itemStrings = items.map { icon, label, val in
            noColor ? "\(label): \(val)" : "\(mutedColor)\(icon)\(rst) \(fgColor)\(val)\(rst)"
        }
        let joined = itemStrings.joined(separator: "  \(borderColor)\u{2502}\(rst)  ")
        let contentLen = items.reduce(0) { $0 + $1.0.count + 1 + $1.2.count } + (items.count - 1) * 5
        let padLen = max(0, innerWidth - contentLen - 2)

        print("\(borderColor)\(vt)\(rst) \(joined)\(String(repeating: " ", count: padLen)) \(borderColor)\(vt)\(rst)")

        // Bottom
        print("\(borderColor)\(bl)\(String(repeating: hz, count: innerWidth))\(br)\(rst)")
    }

    // MARK: - Prompt Line

    /// Renders the interactive prompt with a styled prefix.
    public func renderPrompt() {
        let accentColor = fg(theme.colors.accent)
        let icon = noColor ? ">" : "\u{276F}"
        print("\(bold)\(accentColor)\(icon) zyquo\(rst) \(dim)\(fg(theme.colors.fgMuted))\u{2502}\(rst) ", terminator: "")
        fflush(stdout)
    }

    // MARK: - Slash Command Results

    /// Renders a slash command result in a panel.
    public func renderCommandResult(title: String, items: [(String, String)]) {
        let w = width
        let innerWidth = w - 2
        let borderColor = fg(theme.colors.border)
        let titleColor = fg(theme.colors.accent)
        let fgColor = fg(theme.colors.fg)
        let mutedColor = fg(theme.colors.fgMuted)

        let titleText = " \(title) "
        let titleLen = titleText.count
        let rightFill = max(0, innerWidth - 1 - titleLen)

        print()
        print("\(borderColor)\(tl)\(hz)\(rst)\(bold)\(titleColor)\(titleText)\(rst)\(borderColor)\(String(repeating: hz, count: rightFill))\(tr)\(rst)")

        for (key, value) in items {
            let content = "\(key):  \(value)"
            let contentLen = content.count
            let padLen = max(0, innerWidth - contentLen - 2)
            print("\(borderColor)\(vt)\(rst) \(mutedColor)\(key):\(rst)  \(fgColor)\(value)\(rst)\(String(repeating: " ", count: padLen)) \(borderColor)\(vt)\(rst)")
        }

        print("\(borderColor)\(bl)\(String(repeating: hz, count: innerWidth))\(br)\(rst)")
        print()
    }

    /// Renders a simple list panel (for /help, /tools, etc.).
    public func renderListPanel(title: String, entries: [(String, String)], keyColor: ANSIColor? = nil) {
        let w = width
        let innerWidth = w - 2
        let borderColor = fg(theme.colors.border)
        let titleColor = fg(theme.colors.accent)
        let kColor = fg(keyColor ?? theme.colors.accent)
        let descColor = fg(theme.colors.fgMuted)

        let titleText = " \(title) "
        let titleLen = titleText.count
        let rightFill = max(0, innerWidth - 1 - titleLen)

        print()
        print("\(borderColor)\(tl)\(hz)\(rst)\(bold)\(titleColor)\(titleText)\(rst)\(borderColor)\(String(repeating: hz, count: rightFill))\(tr)\(rst)")

        let maxKeyLen = entries.map { $0.0.count }.max() ?? 10
        for (key, desc) in entries {
            let pad = String(repeating: " ", count: max(1, maxKeyLen - key.count + 2))
            let content = "\(key)\(pad)\(desc)"
            let contentLen = content.count
            let rightPad = max(0, innerWidth - contentLen - 2)
            print("\(borderColor)\(vt)\(rst) \(kColor)\(key)\(rst)\(pad)\(descColor)\(desc)\(rst)\(String(repeating: " ", count: rightPad)) \(borderColor)\(vt)\(rst)")
        }

        print("\(borderColor)\(bl)\(String(repeating: hz, count: innerWidth))\(br)\(rst)")
        print()
    }

    // MARK: - Thinking Indicator

    /// Renders a thinking/processing indicator before streaming starts.
    public func renderThinking() {
        let mutedColor = fg(theme.colors.fgMuted)
        let icon = noColor ? "..." : "\u{2026}"
        print("  \(dim)\(mutedColor)\(icon) thinking\(rst)", terminator: "\r")
        fflush(stdout)
    }

    /// Clears the thinking indicator line.
    public func clearThinking() {
        let w = width
        print("\r\(String(repeating: " ", count: w))\r", terminator: "")
        fflush(stdout)
    }

    // MARK: - Error Box

    /// Renders an error in a distinctly-styled box.
    public func renderError(_ message: String, hint: String? = nil) {
        let w = width
        let innerWidth = w - 2
        let borderColor = fg(theme.colors.risk)
        let icon = noColor ? "[!]" : "\u{26A0}"

        let titleText = " \(icon) Error "
        let titleLen = stripANSI(titleText).count
        let rightFill = max(0, innerWidth - 1 - titleLen)

        print("\(borderColor)\(tl)\(hz)\(rst)\(bold)\(borderColor)\(titleText)\(rst)\(borderColor)\(String(repeating: hz, count: rightFill))\(tr)\(rst)")

        let lines = wrapText(message, maxWidth: innerWidth - 2)
        for line in lines {
            let padLen = max(0, innerWidth - visibleLength(line) - 2)
            print("\(borderColor)\(vt)\(rst) \(fg(theme.colors.risk))\(line)\(rst)\(String(repeating: " ", count: padLen)) \(borderColor)\(vt)\(rst)")
        }

        if let hint = hint {
            // Separator
            print("\(borderColor)\(vt)\(rst) \(borderColor)\(String(repeating: hz, count: innerWidth - 2))\(rst) \(borderColor)\(vt)\(rst)")
            let hintLines = wrapText("Hint: \(hint)", maxWidth: innerWidth - 2)
            for line in hintLines {
                let padLen = max(0, innerWidth - visibleLength(line) - 2)
                print("\(borderColor)\(vt)\(rst) \(dim)\(fg(theme.colors.fgMuted))\(line)\(rst)\(String(repeating: " ", count: padLen)) \(borderColor)\(vt)\(rst)")
            }
        }

        print("\(borderColor)\(bl)\(String(repeating: hz, count: innerWidth))\(br)\(rst)")
    }

    // MARK: - Separator

    /// Renders a thin decorative separator between exchanges.
    public func renderSeparator() {
        print()
    }

    // MARK: - Text Utilities

    private func wrapText(_ text: String, maxWidth: Int) -> [String] {
        guard maxWidth > 0 else { return [text] }
        var result: [String] = []
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for rawLine in rawLines {
            if rawLine.count <= maxWidth {
                result.append(rawLine)
            } else {
                var remaining = rawLine
                while remaining.count > maxWidth {
                    let breakIdx = remaining.index(remaining.startIndex, offsetBy: maxWidth)
                    // Try to break at a space
                    if let spaceIdx = remaining[..<breakIdx].lastIndex(of: " ") {
                        result.append(String(remaining[..<spaceIdx]))
                        remaining = String(remaining[remaining.index(after: spaceIdx)...])
                    } else {
                        result.append(String(remaining.prefix(maxWidth)))
                        remaining = String(remaining.dropFirst(maxWidth))
                    }
                }
                if !remaining.isEmpty {
                    result.append(remaining)
                }
            }
        }
        return result.isEmpty ? [""] : result
    }

    private func stripANSI(_ str: String) -> String {
        str.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private func visibleLength(_ str: String) -> Int {
        stripANSI(str).count
    }
}
