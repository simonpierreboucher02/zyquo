import Foundation

public enum BadgeKind: String, Sendable, CaseIterable {
    case planning = "PLANNING"
    case executing = "EXECUTING"
    case waiting = "WAITING"
    case blocked = "BLOCKED"
    case done = "DONE"
    case safe = "SAFE"
    case moderate = "MODERATE"
    case dangerous = "DANGEROUS"
    case critical = "CRITICAL"
    case pending = "PENDING"
    case active = "ACTIVE"
    case failed = "FAILED"

    public var paddedLabel: String {
        let maxLen = 10
        let raw = rawValue
        let pad = max(0, maxLen - raw.count)
        let left = pad / 2
        let right = pad - left
        return String(repeating: " ", count: left) + raw + String(repeating: " ", count: right)
    }

    public func color(from theme: Theme) -> ANSIColor {
        switch self {
        case .planning, .active: return theme.colors.accent
        case .executing: return theme.colors.accentStrong
        case .waiting, .pending: return theme.colors.fgMuted
        case .blocked: return theme.colors.warn
        case .done: return theme.colors.ok
        case .safe: return theme.colors.ok
        case .moderate: return theme.colors.warn
        case .dangerous: return theme.colors.risk
        case .critical: return theme.colors.critical
        case .failed: return theme.colors.risk
        }
    }
}

public struct StatusBadge: Renderable, Sendable {
    public let kind: BadgeKind

    public init(_ kind: BadgeKind) {
        self.kind = kind
    }

    public func sizeThatFits(_ available: Size) -> Size {
        Size(width: kind.paddedLabel.count, height: 1)
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.height >= 1 else { return buf }
        let label = kind.paddedLabel
        let color = kind.color(from: theme)
        let text = String(label.prefix(region.width))
        buf.write(text, x: 0, y: 0, fg: color, bold: true)
        return buf
    }
}
