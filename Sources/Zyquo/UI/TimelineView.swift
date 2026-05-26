import Foundation

public struct TimelineEntry: Sendable {
    public let elapsed: Double
    public let description: String
    public let status: BadgeKind

    public init(elapsed: Double, description: String, status: BadgeKind) {
        self.elapsed = elapsed
        self.description = description
        self.status = status
    }
}

public struct TimelineView: Renderable, Sendable {
    public let entries: [TimelineEntry]

    public init(entries: [TimelineEntry]) {
        self.entries = entries
    }

    public func sizeThatFits(_ available: Size) -> Size {
        Size(width: available.width, height: min(entries.count, available.height))
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.width >= 20 else { return buf }

        let badgeWidth = 10
        let timeWidth = 6
        let markerWidth = 4

        for (i, entry) in entries.enumerated() {
            guard i < region.height else { break }

            let timeStr = formatElapsed(entry.elapsed)
            let padded = String(repeating: " ", count: max(0, timeWidth - timeStr.count)) + timeStr
            buf.write(padded, x: 0, y: i, fg: theme.colors.fgMuted)

            buf.write("\u{25B8}", x: timeWidth + 1, y: i, fg: theme.colors.accent)

            let descWidth = region.width - timeWidth - markerWidth - badgeWidth - 2
            let desc = String(entry.description.prefix(max(0, descWidth)))
            buf.write(desc, x: timeWidth + markerWidth, y: i, fg: theme.colors.fg)

            let badge = StatusBadge(entry.status)
            let badgeBuf = badge.render(
                in: Region(x: 0, y: 0, width: badgeWidth, height: 1),
                theme: theme
            )
            buf.blit(badgeBuf, at: region.width - badgeWidth, y: i)
        }
        return buf
    }

    private func formatElapsed(_ seconds: Double) -> String {
        if seconds < 10 {
            return String(format: "%.1fs", seconds)
        } else if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return "\(m)m\(s)s"
        }
    }
}
