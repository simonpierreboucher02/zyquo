import Foundation

public struct ProgressBar: Renderable, Sendable {
    public static let animationsEnabled: Bool = ProcessInfo.processInfo.environment["TERM"] != "dumb" && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    public enum Mode: Sendable {
        case determinate(Double)
        case indeterminate(frame: Int)
    }

    public let mode: Mode
    public let label: String

    public var isAnimated: Bool {
        guard Self.animationsEnabled else { return false }
        if case .indeterminate = mode { return true }
        return false
    }

    public init(mode: Mode, label: String = "") {
        self.mode = mode
        self.label = label
    }

    public static func determinate(_ progress: Double, label: String = "") -> ProgressBar {
        ProgressBar(mode: .determinate(min(1.0, max(0.0, progress))), label: label)
    }

    public static func indeterminate(frame: Int = 0, label: String = "") -> ProgressBar {
        ProgressBar(mode: .indeterminate(frame: frame), label: label)
    }

    public func tick() -> ProgressBar {
        switch mode {
        case .determinate:
            return self
        case .indeterminate(let f):
            return ProgressBar(mode: .indeterminate(frame: f + 1), label: label)
        }
    }

    public func sizeThatFits(_ available: Size) -> Size {
        Size(width: available.width, height: 1)
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.height >= 1, region.width >= 4 else { return buf }

        let labelPart = label.isEmpty ? "" : "\(label) "
        let labelLen = labelPart.count

        if !labelPart.isEmpty {
            buf.write(labelPart, x: 0, y: 0, fg: theme.colors.fg)
        }

        let barWidth = region.width - labelLen - 2
        guard barWidth > 0 else { return buf }

        let barStart = labelLen

        switch mode {
        case .determinate(let progress):
            let pctStr = "\(Int(progress * 100))%"
            let effectiveBarW = barWidth - pctStr.count - 1
            guard effectiveBarW > 0 else { return buf }

            buf.write("[", x: barStart, y: 0, fg: theme.colors.fgMuted)
            let filled = Int(Double(effectiveBarW) * progress)
            for i in 0..<effectiveBarW {
                let ch: Character = i < filled ? "\u{2588}" : "\u{2591}"
                let color = i < filled ? theme.colors.accent : theme.colors.fgMuted
                buf[barStart + 1 + i, 0] = Cell(character: ch, fg: color, bg: .default, bold: false, italic: false, underline: false)
            }
            buf.write("]", x: barStart + 1 + effectiveBarW, y: 0, fg: theme.colors.fgMuted)
            buf.write(pctStr, x: barStart + effectiveBarW + 3, y: 0, fg: theme.colors.fg)

        case .indeterminate(let frame):
            buf.write("[", x: barStart, y: 0, fg: theme.colors.fgMuted)
            let innerW = barWidth
            let pos = frame % (innerW * 2)
            let bouncePos = pos < innerW ? pos : (innerW * 2 - pos - 1)
            for i in 0..<innerW {
                let dist = abs(i - bouncePos)
                let ch: Character = dist == 0 ? "\u{2588}" : (dist == 1 ? "\u{2593}" : "\u{2591}")
                let color = dist <= 1 ? theme.colors.accent : theme.colors.fgMuted
                buf[barStart + 1 + i, 0] = Cell(character: ch, fg: color, bg: .default, bold: false, italic: false, underline: false)
            }
            buf.write("]", x: barStart + 1 + innerW, y: 0, fg: theme.colors.fgMuted)
        }

        return buf
    }
}
