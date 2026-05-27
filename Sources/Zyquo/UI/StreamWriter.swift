import Foundation

public struct StreamWriter: Sendable {
    public let theme: Theme
    public let capability: TerminalCapability
    public let noColor: Bool
    public let width: Int

    public init(theme: Theme? = nil, noColor: Bool = false) {
        self.theme = theme ?? .zyquoDark
        self.capability = TerminalCapability.detect()
        self.noColor = noColor || self.capability == .monochrome
        self.width = Terminal.size.width
    }

    // MARK: - Internal ANSI Helpers

    private var colorsEnabled: Bool { !noColor }

    private func resolve(_ color: ANSIColor) -> ANSIColor {
        theme.resolve(color, capability: capability)
    }

    private func ansiStart(fg: ANSIColor? = nil, bg: ANSIColor? = nil, bold: Bool = false, dim: Bool = false, italic: Bool = false) -> String {
        guard colorsEnabled else { return "" }
        var codes: [String] = []
        if bold { codes.append("1") }
        if dim { codes.append("2") }
        if italic { codes.append("3") }
        if let fg = fg {
            let resolved = resolve(fg)
            if resolved != .default { codes.append(resolved.fgCode) }
        }
        if let bg = bg {
            let resolved = resolve(bg)
            if resolved != .default { codes.append(resolved.bgCode) }
        }
        guard !codes.isEmpty else { return "" }
        return "\u{1B}[\(codes.joined(separator: ";"))m"
    }

    private func ansiReset() -> String {
        guard colorsEnabled else { return "" }
        return "\u{1B}[0m"
    }

    private func writeRaw(_ str: String) {
        print(str, terminator: "")
        fflush(stdout)
    }

    // MARK: - Core Output

    public func text(_ str: String, fg: ANSIColor? = nil, bg: ANSIColor? = nil, bold: Bool = false, dim: Bool = false, italic: Bool = false) {
        let prefix = ansiStart(fg: fg, bg: bg, bold: bold, dim: dim, italic: italic)
        let suffix = prefix.isEmpty ? "" : ansiReset()
        writeRaw("\(prefix)\(str)\(suffix)")
    }

    public func line(_ str: String = "", fg: ANSIColor? = nil, bold: Bool = false, dim: Bool = false, indent: Int = 0) {
        let pad = String(repeating: " ", count: indent)
        let prefix = ansiStart(fg: fg, bold: bold, dim: dim)
        let suffix = prefix.isEmpty ? "" : ansiReset()
        writeRaw("\(pad)\(prefix)\(str)\(suffix)\n")
    }

    public func blank() {
        writeRaw("\n")
    }

    // MARK: - Structured Output

    public func panel(title: String, content: [String], style: BoxBorderStyle = .rounded, borderColor: ANSIColor? = nil, width panelWidth: Int? = nil) {
        let effectiveWidth = min(panelWidth ?? self.width, self.width)
        guard effectiveWidth >= 4 else { return }

        let bc = borderColor ?? theme.colors.border
        let tl = String(style.topLeft)
        let tr = String(style.topRight)
        let bl = String(style.bottomLeft)
        let br = String(style.bottomRight)
        let hz = String(style.horizontal)
        let vt = String(style.vertical)

        // Top border with title
        let titleInset = " \(title) "
        let titleLen = titleInset.count
        let availableHz = effectiveWidth - 2 // minus corners
        let leftHz: Int
        let rightHz: Int
        if titleLen <= availableHz {
            leftHz = 1
            rightHz = max(0, availableHz - leftHz - titleLen)
        } else {
            leftHz = availableHz
            rightHz = 0
        }

        var topLine = ""
        topLine += tl
        topLine += String(repeating: hz, count: leftHz)
        if titleLen <= availableHz {
            topLine += titleInset
        }
        topLine += String(repeating: hz, count: rightHz)
        topLine += tr

        // Truncate/pad to exact width
        topLine = padOrTruncate(topLine, to: effectiveWidth)

        text(topLine, fg: bc)
        writeRaw("\n")

        // Content lines
        let innerWidth = effectiveWidth - 4 // border + 1 space padding each side
        for contentLine in content {
            let truncated = truncateToWidth(contentLine, max: max(0, innerWidth))
            let padded = truncated + String(repeating: " ", count: max(0, innerWidth - truncated.count))
            text(vt, fg: bc)
            writeRaw(" \(padded) ")
            text(vt, fg: bc)
            writeRaw("\n")
        }

        // Bottom border
        let bottomLine = bl + String(repeating: hz, count: max(0, effectiveWidth - 2)) + br
        text(bottomLine, fg: bc)
        writeRaw("\n")
    }

    public func separator(width sepWidth: Int? = nil) {
        let w = min(sepWidth ?? self.width, self.width)
        text(String(repeating: "\u{2500}", count: w), fg: theme.colors.border, dim: true)
        writeRaw("\n")
    }

    public func keyValue(_ key: String, _ value: String, indent: Int = 2) {
        let pad = String(repeating: " ", count: indent)
        text(pad)
        text(key, fg: theme.colors.fgMuted)
        text(": ")
        text(value, fg: theme.colors.fg)
        writeRaw("\n")
    }

    // MARK: - Status Items

    public func checkItem(_ label: String, detail: String? = nil) {
        statusItem(icon: colorsEnabled ? "\u{2713}" : "[OK]", color: theme.colors.ok, label: label, detail: detail)
    }

    public func failItem(_ label: String, detail: String? = nil) {
        statusItem(icon: colorsEnabled ? "\u{2717}" : "[FAIL]", color: theme.colors.risk, label: label, detail: detail)
    }

    public func warnItem(_ label: String, detail: String? = nil) {
        statusItem(icon: colorsEnabled ? "!" : "[WARN]", color: theme.colors.warn, label: label, detail: detail)
    }

    public func infoItem(_ label: String, detail: String? = nil) {
        statusItem(icon: colorsEnabled ? "\u{2139}" : "[i]", color: theme.colors.accent, label: label, detail: detail)
    }

    public func pendingItem(_ label: String, detail: String? = nil) {
        statusItem(icon: colorsEnabled ? "\u{25CB}" : "[--]", color: theme.colors.fgMuted, label: label, detail: detail, dim: true)
    }

    // MARK: - Private Helpers

    private func statusItem(icon: String, color: ANSIColor, label: String, detail: String?, dim: Bool = false) {
        text("  ")
        text(icon, fg: color, bold: !dim)
        text(" ")
        text(label, fg: dim ? theme.colors.fgMuted : theme.colors.fg, dim: dim)
        if let detail = detail {
            text(" ")
            text(detail, fg: theme.colors.fgMuted, dim: true)
        }
        writeRaw("\n")
    }

    private func truncateToWidth(_ str: String, max maxWidth: Int) -> String {
        guard maxWidth >= 0 else { return "" }
        if str.count <= maxWidth { return str }
        if maxWidth <= 3 { return String(str.prefix(maxWidth)) }
        return String(str.prefix(maxWidth - 3)) + "..."
    }

    private func padOrTruncate(_ str: String, to targetWidth: Int) -> String {
        if str.count == targetWidth { return str }
        if str.count > targetWidth { return String(str.prefix(targetWidth)) }
        return str + String(repeating: " ", count: targetWidth - str.count)
    }
}
