import Foundation

public enum SpinnerStyle: Sendable {
    case braille
    case dots
    case line

    public var frames: [Character] {
        switch self {
        case .braille: return Array("\u{280B}\u{2819}\u{2839}\u{2838}\u{283C}\u{2834}\u{2826}\u{2827}\u{2807}\u{280F}")
        case .dots: return Array("\u{2801}\u{2802}\u{2804}\u{2840}\u{2880}\u{2820}\u{2810}\u{2808}")
        case .line: return Array("-\\|/")
        }
    }

    public var intervalMs: Int {
        switch self {
        case .braille: return 80
        case .dots: return 100
        case .line: return 120
        }
    }
}

public struct Spinner: Renderable, Sendable {
    public let style: SpinnerStyle
    public let label: String
    public let frame: Int

    public var isAnimated: Bool { true }

    public init(style: SpinnerStyle = .braille, label: String = "", frame: Int = 0) {
        self.style = style
        self.label = label
        self.frame = frame
    }

    public func tick() -> Spinner {
        Spinner(style: style, label: label, frame: frame + 1)
    }

    public var currentFrame: Character {
        let frames = style.frames
        return frames[frame % frames.count]
    }

    public func sizeThatFits(_ available: Size) -> Size {
        let w = label.isEmpty ? 1 : label.count + 2
        return Size(width: min(w, available.width), height: 1)
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.height >= 1, region.width >= 1 else { return buf }

        let ch = currentFrame
        buf[0, 0] = Cell(character: ch, fg: theme.colors.accent, bg: .default, bold: false, italic: false, underline: false)

        if !label.isEmpty, region.width > 2 {
            let text = String(label.prefix(region.width - 2))
            buf.write(text, x: 2, y: 0, fg: theme.colors.fg)
        }
        return buf
    }
}
