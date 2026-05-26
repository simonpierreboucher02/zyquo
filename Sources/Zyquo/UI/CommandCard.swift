import Foundation

public struct CommandCard: Renderable, Sendable {
    public let command: String
    public let risk: BadgeKind
    public let estimatedTime: String?
    public let reason: String?
    public let showApproval: Bool

    public init(
        command: String,
        risk: BadgeKind = .safe,
        estimatedTime: String? = nil,
        reason: String? = nil,
        showApproval: Bool = true
    ) {
        self.command = command
        self.risk = risk
        self.estimatedTime = estimatedTime
        self.reason = reason
        self.showApproval = showApproval
    }

    public func sizeThatFits(_ available: Size) -> Size {
        var lines = 2
        if estimatedTime != nil || reason != nil { lines += 1 }
        if reason != nil { lines += 1 }
        if showApproval { lines += 1 }
        return Size(width: available.width, height: lines + 2)
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.width >= 20, region.height >= 4 else { return buf }

        buf.drawBox(x: 0, y: 0, width: region.width, height: region.height, fg: theme.colors.border)

        let title = " Proposed Command "
        buf.write(title, x: 2, y: 0, fg: theme.colors.accent, bold: true)

        let innerW = region.width - 4
        var row = 1

        let prompt = "$ " + String(command.prefix(innerW - 2))
        buf.write(prompt, x: 2, y: row, fg: theme.colors.fg, bold: true)
        row += 1

        let riskLabel = "Risk: "
        buf.write(riskLabel, x: 2, y: row, fg: theme.colors.fgMuted)
        let badge = StatusBadge(risk)
        let badgeBuf = badge.render(
            in: Region(x: 0, y: 0, width: risk.paddedLabel.count, height: 1),
            theme: theme
        )
        buf.blit(badgeBuf, at: 2 + riskLabel.count, y: row)

        if let est = estimatedTime {
            let estLabel = "Estimated: \(est)"
            let estX = region.width - 2 - estLabel.count
            if estX > 2 + riskLabel.count + risk.paddedLabel.count + 2 {
                buf.write(estLabel, x: estX, y: row, fg: theme.colors.fgMuted)
            }
        }
        row += 1

        if let reason = reason, row < region.height - 1 {
            let reasonText = "Reason: " + String(reason.prefix(innerW - 8))
            buf.write(reasonText, x: 2, y: row, fg: theme.colors.fgMuted)
            row += 1
        }

        if showApproval, row < region.height - 1 {
            let approvalText = "Approve? [y]es  [n]o  [a]lways  [?]explain"
            buf.write(String(approvalText.prefix(innerW)), x: 2, y: row, fg: theme.colors.warn, bold: true)
        }

        return buf
    }
}
