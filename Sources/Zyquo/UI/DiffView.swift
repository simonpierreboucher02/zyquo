import Foundation

public enum DiffDisplayMode: Sendable {
    case unified
    case sideBySide
}

public struct DiffHunk: Sendable {
    public let header: String
    public let lines: [DiffLine]

    public init(header: String, lines: [DiffLine]) {
        self.header = header
        self.lines = lines
    }
}

public struct DiffLine: Sendable {
    public enum Kind: Sendable {
        case context
        case added
        case removed
    }

    public let kind: Kind
    public let text: String
    public let lineNumber: Int?

    public init(kind: Kind, text: String, lineNumber: Int? = nil) {
        self.kind = kind
        self.text = text
        self.lineNumber = lineNumber
    }
}

public enum DiffFileRisk: String, Sendable {
    case safe = "SAFE"
    case moderate = "MODERATE"
    case dangerous = "DANGEROUS"
}

public struct DiffFile: Sendable {
    public let path: String
    public let hunks: [DiffHunk]
    public let linesAdded: Int
    public let linesRemoved: Int
    public let risk: DiffFileRisk

    public init(path: String, hunks: [DiffHunk], linesAdded: Int, linesRemoved: Int, risk: DiffFileRisk = .moderate) {
        self.path = path
        self.hunks = hunks
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.risk = risk
    }
}

public struct DiffSummary: Sendable {
    public let filesChanged: Int
    public let totalAdded: Int
    public let totalRemoved: Int
    public let riskCounts: [DiffFileRisk: Int]

    public init(files: [DiffFile]) {
        self.filesChanged = files.count
        self.totalAdded = files.reduce(0) { $0 + $1.linesAdded }
        self.totalRemoved = files.reduce(0) { $0 + $1.linesRemoved }
        var counts: [DiffFileRisk: Int] = [:]
        for file in files {
            counts[file.risk, default: 0] += 1
        }
        self.riskCounts = counts
    }

    public var summaryText: String {
        var text = "\(filesChanged) file\(filesChanged == 1 ? "" : "s") changed \u{00B7} +\(totalAdded) / \u{2212}\(totalRemoved)"
        // Append risk breakdown (dangerous first, then moderate)
        if let dangerous = riskCounts[.dangerous], dangerous > 0 {
            text += " \u{00B7} \(dangerous) risk DANGEROUS"
        }
        if let moderate = riskCounts[.moderate], moderate > 0 {
            text += " \u{00B7} \(moderate) risk MODERATE"
        }
        if let safe = riskCounts[.safe], safe > 0 {
            text += " \u{00B7} \(safe) risk SAFE"
        }
        return text
    }
}

public struct DiffView: Renderable, Sendable {
    public let files: [DiffFile]
    public let workspacePath: String?
    public let displayMode: DiffDisplayMode

    public init(files: [DiffFile], workspacePath: String? = nil, displayMode: DiffDisplayMode = .unified) {
        self.files = files
        self.workspacePath = workspacePath
        self.displayMode = displayMode
    }

    public func sizeThatFits(_ available: Size) -> Size {
        var totalLines = 1
        for file in files {
            totalLines += 2
            for hunk in file.hunks {
                totalLines += 1 + hunk.lines.count
            }
            totalLines += 1
        }
        return Size(width: available.width, height: min(totalLines, available.height))
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        // Force unified mode if region is too narrow for side-by-side
        let effectiveMode = region.width < 80 ? .unified : displayMode
        switch effectiveMode {
        case .unified:
            return renderUnified(in: region, theme: theme)
        case .sideBySide:
            return renderSideBySide(in: region, theme: theme)
        }
    }

    private func renderUnified(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.width >= 10, region.height >= 3 else { return buf }

        var row = 0
        let summary = DiffSummary(files: files)
        let sumText = summary.summaryText

        // Render summary banner with border
        let bannerBorder = Cell(character: "\u{2500}", fg: theme.colors.border, bg: .default, bold: false, italic: false, underline: false)
        for col in 0..<region.width {
            buf[col, row] = bannerBorder
        }
        // Overlay summary text centered or left-aligned with padding
        let displaySum = String(sumText.prefix(region.width - 4))
        buf.write(displaySum, x: 2, y: row, fg: theme.colors.fg, bold: true)
        row += 1

        for file in files {
            guard row < region.height else { break }

            let borderChar: Character = "─"
            let borderCell = Cell(character: borderChar, fg: theme.colors.border, bg: .default, bold: false, italic: false, underline: false)
            for col in 0..<region.width {
                buf[col, row] = borderCell
            }

            var headerParts = file.path
            if let ws = workspacePath {
                headerParts += "  \u{00B7}  \(ws)"
            }
            buf.write(String(headerParts.prefix(region.width - 4)), x: 2, y: row, fg: theme.colors.accent, bold: true)
            row += 1

            for hunk in file.hunks {
                guard row < region.height else { break }
                buf.write(String(hunk.header.prefix(region.width - 2)), x: 1, y: row, fg: theme.colors.fgMuted)
                row += 1

                for line in hunk.lines {
                    guard row < region.height else { break }
                    renderDiffLine(line, into: &buf, row: row, width: region.width, theme: theme)
                    row += 1
                }
            }

            if row < region.height {
                let fileSum = "\u{2500}\u{2500} \(file.hunks.count) hunk\(file.hunks.count == 1 ? "" : "s") \u{00B7} \u{2212}\(file.linesRemoved) / +\(file.linesAdded) lines"
                buf.write(String(fileSum.prefix(region.width)), x: 0, y: row, fg: theme.colors.fgMuted)
                row += 1
            }
        }

        return buf
    }

    private func renderSideBySide(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.width >= 10, region.height >= 3 else { return buf }

        let leftWidth = (region.width - 1) / 2
        let rightWidth = region.width - leftWidth - 1
        let gutterX = leftWidth

        var row = 0
        let summary = DiffSummary(files: files)
        let sumText = summary.summaryText

        // Render summary banner with border
        let bannerBorder = Cell(character: "\u{2500}", fg: theme.colors.border, bg: .default, bold: false, italic: false, underline: false)
        for col in 0..<region.width {
            buf[col, row] = bannerBorder
        }
        let displaySum = String(sumText.prefix(region.width - 4))
        buf.write(displaySum, x: 2, y: row, fg: theme.colors.fg, bold: true)
        row += 1

        for file in files {
            guard row < region.height else { break }

            // File header border
            let borderCell = Cell(character: "─", fg: theme.colors.border, bg: .default, bold: false, italic: false, underline: false)
            for col in 0..<region.width {
                buf[col, row] = borderCell
            }

            var headerParts = file.path
            if let ws = workspacePath {
                headerParts += "  \u{00B7}  \(ws)"
            }
            buf.write(String(headerParts.prefix(region.width - 4)), x: 2, y: row, fg: theme.colors.accent, bold: true)
            row += 1

            for hunk in file.hunks {
                guard row < region.height else { break }
                buf.write(String(hunk.header.prefix(region.width - 2)), x: 1, y: row, fg: theme.colors.fgMuted)
                row += 1

                // Build paired lines for side-by-side display
                let pairedLines = buildSideBySidePairs(from: hunk.lines)

                for pair in pairedLines {
                    guard row < region.height else { break }

                    // Render left side (removed / context)
                    renderSideBySideHalf(
                        pair.left, into: &buf, row: row,
                        startX: 0, halfWidth: leftWidth, theme: theme, side: .left
                    )

                    // Render center gutter
                    buf[gutterX, row] = Cell(
                        character: "\u{2502}", fg: theme.colors.border,
                        bg: .default, bold: false, italic: false, underline: false
                    )

                    // Render right side (added / context)
                    renderSideBySideHalf(
                        pair.right, into: &buf, row: row,
                        startX: gutterX + 1, halfWidth: rightWidth, theme: theme, side: .right
                    )

                    row += 1
                }
            }

            if row < region.height {
                let fileSum = "\u{2500}\u{2500} \(file.hunks.count) hunk\(file.hunks.count == 1 ? "" : "s") \u{00B7} \u{2212}\(file.linesRemoved) / +\(file.linesAdded) lines"
                buf.write(String(fileSum.prefix(region.width)), x: 0, y: row, fg: theme.colors.fgMuted)
                row += 1
            }
        }

        return buf
    }

    private struct SideBySidePair {
        let left: SideBySideEntry?
        let right: SideBySideEntry?
    }

    private struct SideBySideEntry {
        let text: String
        let lineNumber: Int?
        let kind: DiffLine.Kind
    }

    private enum SideBySideSide {
        case left
        case right
    }

    private func buildSideBySidePairs(from lines: [DiffLine]) -> [SideBySidePair] {
        var pairs: [SideBySidePair] = []
        var removedQueue: [DiffLine] = []
        var addedQueue: [DiffLine] = []

        func flushQueues() {
            let count = max(removedQueue.count, addedQueue.count)
            for i in 0..<count {
                let left = i < removedQueue.count
                    ? SideBySideEntry(text: removedQueue[i].text, lineNumber: removedQueue[i].lineNumber, kind: .removed)
                    : nil
                let right = i < addedQueue.count
                    ? SideBySideEntry(text: addedQueue[i].text, lineNumber: addedQueue[i].lineNumber, kind: .added)
                    : nil
                pairs.append(SideBySidePair(left: left, right: right))
            }
            removedQueue.removeAll()
            addedQueue.removeAll()
        }

        for line in lines {
            switch line.kind {
            case .context:
                flushQueues()
                let entry = SideBySideEntry(text: line.text, lineNumber: line.lineNumber, kind: .context)
                pairs.append(SideBySidePair(left: entry, right: entry))
            case .removed:
                removedQueue.append(line)
            case .added:
                addedQueue.append(line)
            }
        }
        flushQueues()

        return pairs
    }

    private func renderSideBySideHalf(
        _ entry: SideBySideEntry?, into buf: inout CellBuffer,
        row: Int, startX: Int, halfWidth: Int,
        theme: Theme, side: SideBySideSide
    ) {
        guard let entry else {
            // Empty half -- leave blank
            return
        }

        let fg: ANSIColor
        let bg: ANSIColor
        let lineNumWidth = 4

        switch entry.kind {
        case .context:
            fg = theme.diff.context
            bg = .default
        case .added:
            fg = theme.diff.addedFg
            bg = theme.diff.added
        case .removed:
            fg = theme.diff.removedFg
            bg = theme.diff.removed
        }

        // Fill background for added/removed lines
        if entry.kind != .context {
            for col in startX..<min(startX + halfWidth, buf.width) {
                buf[col, row] = Cell(character: " ", fg: .default, bg: bg, bold: false, italic: false, underline: false)
            }
        }

        // Line number
        if let num = entry.lineNumber {
            let numStr = String(num).padding(toLength: lineNumWidth - 1, withPad: " ", startingAt: 0)
            buf.write(numStr, x: startX, y: row, fg: theme.colors.fgMuted, bg: bg)
        }

        // Text content
        let textStart = startX + lineNumWidth
        let maxTextW = halfWidth - lineNumWidth
        if maxTextW > 0 {
            let displayText = String(entry.text.prefix(maxTextW))
            for (i, ch) in displayText.enumerated() {
                let col = textStart + i
                guard col < startX + halfWidth, col < buf.width else { break }
                buf[col, row] = Cell(character: ch, fg: fg, bg: bg, bold: false, italic: false, underline: false)
            }
        }
    }

    private func renderDiffLine(_ line: DiffLine, into buf: inout CellBuffer, row: Int, width: Int, theme: Theme) {
        let prefix: String
        let fg: ANSIColor
        let bg: ANSIColor

        switch line.kind {
        case .context:
            prefix = " "
            fg = theme.diff.context
            bg = .default
        case .added:
            prefix = "+"
            fg = theme.diff.addedFg
            bg = theme.diff.added
        case .removed:
            prefix = "-"
            fg = theme.diff.removedFg
            bg = theme.diff.removed
        }

        let text = prefix + " " + line.text
        let display = String(text.prefix(width))

        for (i, ch) in display.enumerated() {
            guard i < width else { break }
            buf[i, row] = Cell(character: ch, fg: fg, bg: bg, bold: false, italic: false, underline: false)
        }

        if case .added = line.kind {
            for i in display.count..<width {
                buf[i, row] = Cell(character: " ", fg: .default, bg: bg, bold: false, italic: false, underline: false)
            }
        } else if case .removed = line.kind {
            for i in display.count..<width {
                buf[i, row] = Cell(character: " ", fg: .default, bg: bg, bold: false, italic: false, underline: false)
            }
        }
    }
}

extension DiffView {
    public static func parse(unifiedDiff: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentPath: String?
        var currentHunks: [DiffHunk] = []
        var currentHunkHeader: String?
        var currentHunkLines: [DiffLine] = []
        var added = 0
        var removed = 0

        func flushHunk() {
            if let header = currentHunkHeader {
                currentHunks.append(DiffHunk(header: header, lines: currentHunkLines))
                currentHunkLines = []
                currentHunkHeader = nil
            }
        }

        func flushFile() {
            flushHunk()
            if let path = currentPath {
                files.append(DiffFile(path: path, hunks: currentHunks, linesAdded: added, linesRemoved: removed))
                currentHunks = []
                added = 0
                removed = 0
                currentPath = nil
            }
        }

        for line in unifiedDiff.components(separatedBy: "\n") {
            if line.hasPrefix("+++ b/") || line.hasPrefix("+++ ") {
                let path = line.hasPrefix("+++ b/")
                    ? String(line.dropFirst(6))
                    : String(line.dropFirst(4))
                if currentPath != nil { flushFile() }
                currentPath = path
            } else if line.hasPrefix("--- ") {
                continue
            } else if line.hasPrefix("@@") {
                flushHunk()
                currentHunkHeader = line
            } else if line.hasPrefix("+") {
                currentHunkLines.append(DiffLine(kind: .added, text: String(line.dropFirst())))
                added += 1
            } else if line.hasPrefix("-") {
                currentHunkLines.append(DiffLine(kind: .removed, text: String(line.dropFirst())))
                removed += 1
            } else if line.hasPrefix(" ") {
                currentHunkLines.append(DiffLine(kind: .context, text: String(line.dropFirst())))
            }
        }
        flushFile()

        return files
    }
}
