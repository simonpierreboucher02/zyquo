import Foundation

// MARK: - ApprovalResponse

/// The user's response to an interactive approval prompt.
public enum ApprovalResponse: Sendable {
    /// The user approved the action.
    case approve
    /// The user denied the action.
    case deny
    /// The user wants to always approve this action.
    case alwaysApprove
    /// The user wants an explanation before deciding.
    case explain
    /// The user wants to edit the command before execution.
    case edit
    /// The user cancelled (Escape or Ctrl-C).
    case cancel
}

// MARK: - ApprovalPanel

/// Renders an interactive approval prompt to stdout and reads the user's response.
///
/// For DANGEROUS/CRITICAL risks, the panel uses double borders (heavy visual weight).
/// For SAFE/MODERATE, single rounded borders are used.
///
/// Reference: CLAUDE.md §19.4, §7
public struct ApprovalPanel: Sendable {
    let noColor: Bool

    private var theme: Theme { .zyquoDark }
    private var capability: TerminalCapability {
        noColor ? .monochrome : TerminalCapability.detect()
    }
    private var width: Int { max(40, Terminal.size.width) }

    public init(noColor: Bool = false) {
        self.noColor = noColor
    }

    // MARK: - ANSI Helpers

    private func fg(_ color: ANSIColor) -> String {
        guard !noColor else { return "" }
        let resolved = theme.resolve(color, capability: capability)
        if case .default = resolved { return "" }
        return "\u{1B}[\(resolved.fgCode)m"
    }

    private func ansi(_ code: String) -> String {
        noColor ? "" : "\u{1B}[\(code)m"
    }

    private func reset() -> String {
        noColor ? "" : "\u{1B}[0m"
    }

    // MARK: - Render

    /// Print the approval panel to stdout.
    ///
    /// - Parameters:
    ///   - command: The command or tool invocation requiring approval.
    ///   - risk: The risk level display name (e.g. "DANGEROUS", "CRITICAL").
    ///   - reasons: Human-readable reasons for the risk classification.
    public func render(command: String, risk: String, reasons: [String]) {
        let rst = reset()
        let bold = ansi("1")

        let isHighRisk = risk == "DANGEROUS" || risk == "CRITICAL"

        // Select border style
        let tl: String
        let tr: String
        let bl: String
        let br: String
        let hz: String
        let vt: String

        if noColor {
            if isHighRisk {
                tl = "#"; tr = "#"; bl = "#"; br = "#"; hz = "="; vt = "#"
            } else {
                tl = "+"; tr = "+"; bl = "+"; br = "+"; hz = "-"; vt = "|"
            }
        } else {
            if isHighRisk {
                tl = "\u{2554}"; tr = "\u{2557}"; bl = "\u{255A}"; br = "\u{255D}"
                hz = "\u{2550}"; vt = "\u{2551}"
            } else {
                tl = "\u{256D}"; tr = "\u{256E}"; bl = "\u{2570}"; br = "\u{256F}"
                hz = "\u{2500}"; vt = "\u{2502}"
            }
        }

        let borderColor: ANSIColor
        let riskColor: ANSIColor
        if isHighRisk {
            borderColor = risk == "CRITICAL" ? theme.colors.critical : theme.colors.risk
            riskColor = risk == "CRITICAL" ? theme.colors.critical : theme.colors.risk
        } else {
            borderColor = theme.colors.border
            riskColor = risk == "MODERATE" ? theme.colors.warn : theme.colors.ok
        }

        let bc = fg(borderColor)
        let rc = fg(riskColor)
        let mutedColor = fg(theme.colors.fgMuted)
        let fgColor = fg(theme.colors.fg)
        let accentColor = fg(theme.colors.accent)

        let innerWidth = width - 2

        // Top border with title and risk badge
        let title = "APPROBATION REQUISE"
        let badge = risk
        let titleLen = title.count + 3 // "hz title "
        let badgeLen = badge.count + 3 // " badge hz"
        let fillLen = max(0, innerWidth - titleLen - badgeLen)

        var topLine = bc + tl + hz + rst
        topLine += " " + bold + fgColor + title + rst + " "
        topLine += bc + String(repeating: hz, count: fillLen) + rst
        topLine += " " + bold + rc + badge + rst + " "
        topLine += bc + tr + rst
        print(topLine)

        // Empty line
        printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: "", rst: rst)

        // Command display inside an inner box
        let innerTl = noColor ? "[" : "\u{256D}"
        let innerTr = noColor ? "]" : "\u{256E}"
        let innerBl = noColor ? "[" : "\u{2570}"
        let innerBr = noColor ? "]" : "\u{256F}"
        let innerHz = noColor ? "-" : "\u{2500}"

        let cmdBoxInner = innerWidth - 6 // 2 for outer padding + 2 for inner border + 2 for inner padding
        let cmdBoxWidth = cmdBoxInner + 2 // +2 for inner border chars

        // Inner box top
        let innerTopLine = "  " + mutedColor + innerTl + String(repeating: innerHz, count: cmdBoxInner) + innerTr + rst
        printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: innerTopLine, rst: rst)

        // Command content (may wrap if long)
        let cmdLines = wrapText(command, maxWidth: max(10, cmdBoxInner - 2))
        for cmdLine in cmdLines {
            let padLen = max(0, cmdBoxInner - 2 - cmdLine.count)
            let innerContent = "  " + mutedColor + (noColor ? "|" : "\u{2502}") + rst
                + " " + bold + fgColor + cmdLine + rst
                + String(repeating: " ", count: padLen) + " "
                + mutedColor + (noColor ? "|" : "\u{2502}") + rst
            printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: innerContent, rst: rst)
        }

        // Inner box bottom
        let innerBottomLine = "  " + mutedColor + innerBl + String(repeating: innerHz, count: cmdBoxInner) + innerBr + rst
        printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: innerBottomLine, rst: rst)

        // Empty line
        printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: "", rst: rst)

        // Reasons
        if !reasons.isEmpty {
            for reason in reasons {
                let bullet = noColor ? "  * " : "  \u{2022} "
                let reasonText = String(reason.prefix(max(10, innerWidth - 8)))
                let content = mutedColor + bullet + rst + fgColor + reasonText + rst
                printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: content, rst: rst)
            }

            // Empty line
            printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: "", rst: rst)
        }

        // Approval options
        let options = buildOptionLine(accentColor: accentColor, fgColor: fgColor, rst: rst)
        printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: options, rst: rst)

        // Empty line
        printPaddedLine(vt: vt, bc: bc, innerWidth: innerWidth, content: "", rst: rst)

        // Bottom border
        let bottomLine = bc + bl + String(repeating: hz, count: innerWidth) + br + rst
        print(bottomLine)
    }

    // MARK: - Read Response

    /// Read a single-character response from stdin and map to ApprovalResponse.
    ///
    /// Attempts raw mode for single-keypress input. Falls back to readLine() if
    /// raw mode is not available.
    public func readResponse() -> ApprovalResponse {
        // Try raw mode single-char read
        if let response = readSingleChar() {
            return response
        }

        // Fallback: use readLine
        let mutedColor = fg(theme.colors.fgMuted)
        let rst = reset()
        print("\(mutedColor)> \(rst)", terminator: "")
        fflush(stdout)

        guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !line.isEmpty else {
            return .cancel
        }

        return mapCharToResponse(Character(String(line.prefix(1))))
    }

    // MARK: - Private Helpers

    private func printPaddedLine(vt: String, bc: String, innerWidth: Int, content: String, rst: String) {
        // Content is already styled with ANSI codes; we need visible length for padding.
        let visibleLen = stripANSI(content).count
        let padLen = max(0, innerWidth - visibleLen - 2)
        let line = bc + vt + rst
            + " " + content + String(repeating: " ", count: padLen) + " "
            + bc + vt + rst
        print(line)
    }

    private func buildOptionLine(accentColor: String, fgColor: String, rst: String) -> String {
        let bold = ansi("1")
        if noColor {
            return "[y] Approve  [n] Deny  [a] Always  [e] Edit  [?] Explain  [Esc] Cancel"
        }
        return "\(bold)\(accentColor)[y]\(rst)\(fgColor) Approve  \(rst)"
            + "\(bold)\(accentColor)[n]\(rst)\(fgColor) Deny  \(rst)"
            + "\(bold)\(accentColor)[a]\(rst)\(fgColor) Always  \(rst)"
            + "\(bold)\(accentColor)[e]\(rst)\(fgColor) Edit  \(rst)"
            + "\(bold)\(accentColor)[?]\(rst)\(fgColor) Explain  \(rst)"
            + "\(bold)\(accentColor)[Esc]\(rst)\(fgColor) Cancel\(rst)"
    }

    private func wrapText(_ text: String, maxWidth: Int) -> [String] {
        guard maxWidth > 0 else { return [text] }
        if text.count <= maxWidth { return [text] }

        var lines: [String] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            if remaining.count <= maxWidth {
                lines.append(String(remaining))
                break
            }
            // Try to break at a space
            let chunk = remaining.prefix(maxWidth)
            if let lastSpace = chunk.lastIndex(of: " ") {
                lines.append(String(remaining[remaining.startIndex...lastSpace]).trimmingCharacters(in: .whitespaces))
                remaining = remaining[remaining.index(after: lastSpace)...]
            } else {
                // Hard break
                let endIndex = remaining.index(remaining.startIndex, offsetBy: maxWidth)
                lines.append(String(remaining[remaining.startIndex..<endIndex]))
                remaining = remaining[endIndex...]
            }
        }

        return lines.isEmpty ? [text] : lines
    }

    private func stripANSI(_ str: String) -> String {
        // Remove ANSI escape sequences for visible length calculation
        var result = ""
        var inEscape = false
        for char in str {
            if char == "\u{1B}" {
                inEscape = true
                continue
            }
            if inEscape {
                if char == "m" {
                    inEscape = false
                }
                continue
            }
            result.append(char)
        }
        return result
    }

    /// Attempt to read a single character in raw mode.
    /// Returns nil if raw mode is unavailable.
    private func readSingleChar() -> ApprovalResponse? {
        // Save current terminal settings
        var originalTermios = termios()
        guard tcgetattr(STDIN_FILENO, &originalTermios) == 0 else {
            return nil
        }

        // Enable raw mode for single-char input
        var raw = originalTermios
        raw.c_lflag &= ~UInt(ICANON | ECHO)
        raw.c_cc.16 = 1  // VMIN = 1
        raw.c_cc.17 = 0  // VTIME = 0
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else {
            return nil
        }

        defer {
            // Restore terminal settings
            var restore = originalTermios
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &restore)
        }

        var buf: [UInt8] = [0]
        let bytesRead = read(STDIN_FILENO, &buf, 1)
        guard bytesRead == 1 else {
            return .cancel
        }

        let byte = buf[0]

        // Check for Escape key (could be Esc or start of escape sequence)
        if byte == 0x1B {
            // Check if there are more bytes (arrow key or other escape sequence)
            var checkBuf: [UInt8] = [0]
            // Set a short timeout to distinguish standalone Esc from sequences
            var timeoutTermios = raw
            timeoutTermios.c_cc.16 = 0  // VMIN = 0
            timeoutTermios.c_cc.17 = 1  // VTIME = 0.1s
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &timeoutTermios)

            let extraBytes = read(STDIN_FILENO, &checkBuf, 1)
            if extraBytes <= 0 {
                // Standalone Escape
                return .cancel
            }
            // Part of an escape sequence -- consume remaining and treat as cancel
            var drain: [UInt8] = [0]
            while true {
                let n = read(STDIN_FILENO, &drain, 1)
                if n <= 0 { break }
            }
            return .cancel
        }

        // Ctrl-C
        if byte == 0x03 {
            return .cancel
        }

        return mapCharToResponse(Character(UnicodeScalar(byte)))
    }

    private func mapCharToResponse(_ char: Character) -> ApprovalResponse {
        switch char.lowercased().first {
        case "y": return .approve
        case "n": return .deny
        case "a": return .alwaysApprove
        case "e": return .edit
        case "?": return .explain
        default:  return .cancel
        }
    }
}
