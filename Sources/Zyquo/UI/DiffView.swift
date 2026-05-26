import Foundation

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

public struct DiffFile: Sendable {
    public let path: String
    public let hunks: [DiffHunk]
    public let linesAdded: Int
    public let linesRemoved: Int

    public init(path: String, hunks: [DiffHunk], linesAdded: Int, linesRemoved: Int) {
        self.path = path
        self.hunks = hunks
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }
}

public struct DiffSummary: Sendable {
    public let filesChanged: Int
    public let totalAdded: Int
    public let totalRemoved: Int

    public init(files: [DiffFile]) {
        self.filesChanged = files.count
        self.totalAdded = files.reduce(0) { $0 + $1.linesAdded }
        self.totalRemoved = files.reduce(0) { $0 + $1.linesRemoved }
    }

    public var summaryText: String {
        "\(filesChanged) file\(filesChanged == 1 ? "" : "s") changed \u{00B7} +\(totalAdded) / \u{2212}\(totalRemoved)"
    }
}

public struct DiffView: Renderable, Sendable {
    public let files: [DiffFile]
    public let workspacePath: String?

    public init(files: [DiffFile], workspacePath: String? = nil) {
        self.files = files
        self.workspacePath = workspacePath
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
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.width >= 10, region.height >= 3 else { return buf }

        var row = 0
        let summary = DiffSummary(files: files)
        let sumText = summary.summaryText
        buf.write(sumText, x: 0, y: row, fg: theme.colors.fg, bold: true)
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
