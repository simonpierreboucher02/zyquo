import Foundation

public struct SplashScreen: Sendable {
    let workspace: String
    let provider: String
    let model: String
    let version: String
    let budget: String
    let fileCount: Int?
    let language: String?
    let theme: Theme
    let capability: TerminalCapability
    let noColor: Bool
    let animated: Bool

    public init(
        workspace: String,
        provider: String,
        model: String,
        version: String,
        budget: String = "$5.00",
        fileCount: Int? = nil,
        language: String? = nil,
        noColor: Bool = false,
        animated: Bool = true
    ) {
        self.workspace = workspace
        self.provider = provider
        self.model = model
        self.version = version
        self.budget = budget
        self.fileCount = fileCount
        self.language = language
        self.noColor = noColor || ProcessInfo.processInfo.environment["NO_COLOR"] != nil
        self.animated = animated
        self.capability = self.noColor ? .monochrome : TerminalCapability.detect()
        self.theme = .zyquoDark
    }

    // MARK: - Logo

    private static let logoLines: [String] = [
        "███████╗██╗   ██╗ ██████╗ ██╗   ██╗ ██████╗ ",
        "╚══███╔╝╚██╗ ██╔╝██╔═══██╗██║   ██║██╔═══██╗",
        "  ███╔╝  ╚████╔╝ ██║   ██║██║   ██║██║   ██║",
        " ███╔╝    ╚██╔╝  ██║▄▄ ██║██║   ██║██║   ██║",
        "███████╗   ██║   ╚██████╔╝╚██████╔╝╚██████╔╝",
        "╚══════╝   ╚═╝    ╚══▀▀═╝  ╚═════╝  ╚═════╝ ",
    ]

    // MARK: - Gradient Colors

    /// Interpolate between two RGB colors across a number of steps.
    private func gradientColors(steps: Int) -> [(r: UInt8, g: UInt8, b: UInt8)] {
        // accent start:  #5BA8FF  (91, 168, 255)
        // accent end:    #2F80ED  (47, 128, 237)
        let startR: Double = 91, startG: Double = 168, startB: Double = 255
        let endR: Double = 47, endG: Double = 128, endB: Double = 237
        guard steps > 1 else {
            return [(r: UInt8(startR), g: UInt8(startG), b: UInt8(startB))]
        }
        return (0..<steps).map { i in
            let t = Double(i) / Double(steps - 1)
            let r = UInt8(startR + (endR - startR) * t)
            let g = UInt8(startG + (endG - startG) * t)
            let b = UInt8(startB + (endB - startB) * t)
            return (r: r, g: g, b: b)
        }
    }

    // MARK: - ANSI Helpers

    private var esc: String { "\u{1B}[" }
    private var resetCode: String { noColor ? "" : "\u{1B}[0m" }

    private func fgTrueColor(r: UInt8, g: UInt8, b: UInt8) -> String {
        guard !noColor else { return "" }
        return "\u{1B}[38;2;\(r);\(g);\(b)m"
    }

    private func fgFromANSI(_ color: ANSIColor) -> String {
        guard !noColor else { return "" }
        let resolved = theme.resolve(color, capability: capability)
        if case .default = resolved { return "" }
        return "\u{1B}[\(resolved.fgCode)m"
    }

    private var boldCode: String { noColor ? "" : "\u{1B}[1m" }

    // MARK: - Border Helpers

    private var tl: String { noColor ? "+" : "\u{256D}" }
    private var tr: String { noColor ? "+" : "\u{256E}" }
    private var bl: String { noColor ? "+" : "\u{2570}" }
    private var br: String { noColor ? "+" : "\u{256F}" }
    private var hz: String { noColor ? "-" : "\u{2500}" }
    private var vt: String { noColor ? "|" : "\u{2502}" }

    // MARK: - Display

    public func display() {
        let termWidth = Terminal.size.width
        let logoWidth = Self.logoLines.first?.count ?? 46
        // Panel inner width must fit the logo plus padding
        let innerWidth = max(logoWidth + 4, min(termWidth - 2, 64))
        let panelWidth = innerWidth + 2  // +2 for left/right borders

        let borderFg = fgFromANSI(theme.colors.border)
        let mutedFg = fgFromANSI(theme.colors.fgMuted)
        let accentFg = fgFromANSI(theme.colors.accent)

        var lines: [String] = []

        // Blank line
        lines.append("")

        // Top border
        let topBorder = borderFg + tl + String(repeating: hz, count: innerWidth) + tr + resetCode
        lines.append(topBorder)

        // Logo lines (centered inside panel)
        let gradientSteps = gradientColors(steps: Self.logoLines.count)
        for (i, logoLine) in Self.logoLines.enumerated() {
            let pad = max(0, innerWidth - logoLine.count)
            let leftPad = pad / 2
            let rightPad = pad - leftPad
            let coloredLogo: String
            switch capability {
            case .trueColor:
                let c = gradientSteps[i]
                coloredLogo = fgTrueColor(r: c.r, g: c.g, b: c.b) + logoLine + resetCode
            case .color256, .color16:
                coloredLogo = accentFg + logoLine + resetCode
            case .monochrome:
                coloredLogo = logoLine
            }
            let line = borderFg + vt + resetCode
                + String(repeating: " ", count: leftPad)
                + coloredLogo
                + String(repeating: " ", count: rightPad)
                + borderFg + vt + resetCode
            lines.append(line)
        }

        // Subtitle line: "Native macOS AI Terminal Agent . v{version} . {model}"
        let subtitle = "Native macOS AI Terminal Agent \u{00B7} v\(version) \u{00B7} \(model)"
        let subPad = max(0, innerWidth - subtitle.count)
        let subLeft = subPad / 2
        let subRight = subPad - subLeft
        let subtitleLine = borderFg + vt + resetCode
            + String(repeating: " ", count: subLeft)
            + mutedFg + subtitle + resetCode
            + String(repeating: " ", count: subRight)
            + borderFg + vt + resetCode
        lines.append(subtitleLine)

        // Thin separator line
        let sep = borderFg + vt + resetCode
            + " " + borderFg + String(repeating: hz, count: innerWidth - 2) + resetCode + " "
            + borderFg + vt + resetCode
        lines.append(sep)

        // Workspace info line
        var wsInfo = "Workspace  \(workspace)"
        if let lang = language {
            wsInfo += " \u{00B7} \(lang)"
        }
        if let fc = fileCount {
            wsInfo += " \u{00B7} \(fc) files"
        }
        let wsPad = max(0, innerWidth - wsInfo.count - 2)
        let wsLine = borderFg + vt + resetCode
            + " " + mutedFg + String(wsInfo.prefix(innerWidth - 2)) + resetCode
            + String(repeating: " ", count: wsPad) + " "
            + borderFg + vt + resetCode
        lines.append(wsLine)

        // Provider info line
        let pvInfo = "Provider   \(provider) \u{00B7} Budget \(budget)"
        let pvPad = max(0, innerWidth - pvInfo.count - 2)
        let pvLine = borderFg + vt + resetCode
            + " " + mutedFg + String(pvInfo.prefix(innerWidth - 2)) + resetCode
            + String(repeating: " ", count: pvPad) + " "
            + borderFg + vt + resetCode
        lines.append(pvLine)

        // Blank line inside panel
        let blankInner = borderFg + vt + resetCode
            + String(repeating: " ", count: innerWidth)
            + borderFg + vt + resetCode
        lines.append(blankInner)

        // Hint line
        let hint = "Type your intent or /help for commands"
        let hintPad = max(0, innerWidth - hint.count - 2)
        let hintLeft = (innerWidth - hint.count) / 2
        let hintRight = max(0, innerWidth - hint.count - hintLeft)
        let hintLine = borderFg + vt + resetCode
            + String(repeating: " ", count: hintLeft)
            + mutedFg + hint + resetCode
            + String(repeating: " ", count: hintRight)
            + borderFg + vt + resetCode
        lines.append(hintLine)

        // Bottom border
        let bottomBorder = borderFg + bl + String(repeating: hz, count: innerWidth) + br + resetCode
        lines.append(bottomBorder)

        // Trailing blank line
        lines.append("")

        // Print with optional animation
        if animated && !noColor {
            for line in lines {
                print(line)
                fflush(stdout)
                usleep(40000)
            }
        } else {
            for line in lines {
                print(line)
            }
        }
        fflush(stdout)
    }
}
