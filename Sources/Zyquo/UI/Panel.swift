import Foundation

public struct Panel: Renderable, Sendable {
    public let title: String
    public let content: [StyledLine]
    public let titleAlignment: TitleAlignment

    public enum TitleAlignment: Sendable {
        case left
        case center
    }

    public init(title: String, content: [StyledLine] = [], titleAlignment: TitleAlignment = .left) {
        self.title = title
        self.content = content
        self.titleAlignment = titleAlignment
    }

    public func sizeThatFits(_ available: Size) -> Size {
        let h = content.count + 2
        return Size(width: available.width, height: min(h, available.height))
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.width >= 4, region.height >= 2 else { return buf }

        let borderColor = theme.colors.border
        let titleColor = theme.colors.accent
        let fgColor = theme.colors.fg

        buf.drawBox(x: 0, y: 0, width: region.width, height: region.height, fg: borderColor)

        if !title.isEmpty {
            let maxTitleLen = region.width - 6
            let displayTitle = String(title.prefix(maxTitleLen))
            let label = " \(displayTitle) "
            let startX: Int
            switch titleAlignment {
            case .left:
                startX = 2
            case .center:
                startX = max(2, (region.width - label.count) / 2)
            }
            buf.write(label, x: startX, y: 0, fg: titleColor, bold: true)
        }

        let innerWidth = region.width - 4
        for (i, line) in content.enumerated() {
            let row = i + 1
            guard row < region.height - 1 else { break }
            let text = String(line.text.prefix(innerWidth))
            buf.write(text, x: 2, y: row, fg: line.fg ?? fgColor, bg: line.bg ?? .default, bold: line.bold)
        }

        return buf
    }
}

public struct StyledLine: Sendable {
    public let text: String
    public var fg: ANSIColor?
    public var bg: ANSIColor?
    public var bold: Bool

    public init(_ text: String, fg: ANSIColor? = nil, bg: ANSIColor? = nil, bold: Bool = false) {
        self.text = text
        self.fg = fg
        self.bg = bg
        self.bold = bold
    }
}
