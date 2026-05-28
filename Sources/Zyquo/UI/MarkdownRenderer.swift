import Foundation

public struct MarkdownRenderer: Renderable, Sendable {
    public let markdown: String

    public init(_ markdown: String) {
        self.markdown = markdown
    }

    public func sizeThatFits(_ available: Size) -> Size {
        let rendered = renderLines(width: available.width)
        return Size(width: available.width, height: min(rendered.count, available.height))
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.width >= 4, region.height >= 1 else { return buf }

        let lines = renderLines(width: region.width)
        for (i, line) in lines.enumerated() {
            guard i < region.height else { break }
            writeMDLine(line, into: &buf, row: i, width: region.width, theme: theme)
        }
        return buf
    }

    struct MDLine: Sendable {
        enum Kind: Sendable {
            case heading(level: Int)
            case codeBlock
            case bullet
            case numbered(Int)
            case plain
        }
        let kind: Kind
        let segments: [MDSegment]
    }

    enum MDSegment: Sendable {
        case text(String)
        case bold(String)
        case italic(String)
        case code(String)
        case link(text: String, url: String)
    }

    func renderLines(width: Int) -> [MDLine] {
        var result: [MDLine] = []
        var inCodeBlock = false
        let rawLines = markdown.components(separatedBy: "\n")

        for line in rawLines {
            if line.hasPrefix("```") {
                inCodeBlock = !inCodeBlock
                continue
            }

            if inCodeBlock {
                result.append(MDLine(kind: .codeBlock, segments: [.text(line)]))
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### ") {
                let content = String(trimmed.dropFirst(4))
                result.append(MDLine(kind: .heading(level: 3), segments: parseInline(content)))
            } else if trimmed.hasPrefix("## ") {
                let content = String(trimmed.dropFirst(3))
                result.append(MDLine(kind: .heading(level: 2), segments: parseInline(content)))
            } else if trimmed.hasPrefix("# ") {
                let content = String(trimmed.dropFirst(2))
                result.append(MDLine(kind: .heading(level: 1), segments: parseInline(content)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2))
                result.append(MDLine(kind: .bullet, segments: parseInline(content)))
            } else if let (num, rest) = parseNumberedList(trimmed) {
                result.append(MDLine(kind: .numbered(num), segments: parseInline(rest)))
            } else {
                result.append(MDLine(kind: .plain, segments: parseInline(trimmed)))
            }
        }
        return result
    }

    private func parseNumberedList(_ line: String) -> (Int, String)? {
        var idx = line.startIndex
        var digits = ""
        while idx < line.endIndex, line[idx].isNumber {
            digits.append(line[idx])
            idx = line.index(after: idx)
        }
        guard !digits.isEmpty,
              idx < line.endIndex, line[idx] == ".",
              let num = Int(digits) else { return nil }
        idx = line.index(after: idx)
        while idx < line.endIndex, line[idx] == " " {
            idx = line.index(after: idx)
        }
        return (num, String(line[idx...]))
    }

    func parseInline(_ text: String) -> [MDSegment] {
        var segments: [MDSegment] = []
        var remaining = text[...]

        while !remaining.isEmpty {
            if remaining.hasPrefix("`") {
                remaining = remaining.dropFirst()
                if let end = remaining.firstIndex(of: "`") {
                    segments.append(.code(String(remaining[..<end])))
                    remaining = remaining[remaining.index(after: end)...]
                } else {
                    segments.append(.text("`" + String(remaining)))
                    break
                }
            } else if remaining.hasPrefix("**") {
                remaining = remaining.dropFirst(2)
                if let range = remaining.range(of: "**") {
                    segments.append(.bold(String(remaining[..<range.lowerBound])))
                    remaining = remaining[range.upperBound...]
                } else {
                    segments.append(.text("**" + String(remaining)))
                    break
                }
            } else if remaining.hasPrefix("*") || remaining.hasPrefix("_") {
                guard let marker = remaining.first else { break }
                remaining = remaining.dropFirst()
                if let end = remaining.firstIndex(of: marker) {
                    segments.append(.italic(String(remaining[..<end])))
                    remaining = remaining[remaining.index(after: end)...]
                } else {
                    segments.append(.text(String(marker) + String(remaining)))
                    break
                }
            } else if remaining.hasPrefix("[") {
                remaining = remaining.dropFirst()
                if let closeBracket = remaining.firstIndex(of: "]"),
                   remaining[remaining.index(after: closeBracket)...].hasPrefix("("),
                   let closeParen = remaining[remaining.index(closeBracket, offsetBy: 2)...].firstIndex(of: ")") {
                    let linkText = String(remaining[..<closeBracket])
                    let url = String(remaining[remaining.index(closeBracket, offsetBy: 2)..<closeParen])
                    segments.append(.link(text: linkText, url: url))
                    remaining = remaining[remaining.index(after: closeParen)...]
                } else {
                    segments.append(.text("["))
                }
            } else {
                var plain = ""
                while let ch = remaining.first {
                    if ch == "`" || ch == "*" || ch == "_" || ch == "[" { break }
                    plain.append(ch)
                    remaining = remaining.dropFirst()
                }
                if !plain.isEmpty {
                    segments.append(.text(plain))
                }
            }
        }
        return segments
    }

    func writeMDLine(_ line: MDLine, into buf: inout CellBuffer, row: Int, width: Int, theme: Theme) {
        var col = 0

        switch line.kind {
        case .heading:
            for seg in line.segments {
                col = writeSegment(seg, into: &buf, row: row, col: col, width: width,
                                   theme: theme, bold: true, baseFg: theme.colors.accentStrong)
            }
        case .codeBlock:
            for seg in line.segments {
                let text = segmentText(seg)
                for ch in text.prefix(width - col) {
                    buf[col, row] = Cell(character: ch, fg: theme.syntax.string, bg: theme.colors.bgPanel,
                                         bold: false, italic: false, underline: false)
                    col += 1
                }
            }
        case .bullet:
            buf.write("  \u{2022} ", x: 0, y: row, fg: theme.colors.accent)
            col = 4
            for seg in line.segments {
                col = writeSegment(seg, into: &buf, row: row, col: col, width: width,
                                   theme: theme, bold: false, baseFg: theme.colors.fg)
            }
        case .numbered(let n):
            let prefix = "  \(n). "
            buf.write(prefix, x: 0, y: row, fg: theme.colors.accent)
            col = prefix.count
            for seg in line.segments {
                col = writeSegment(seg, into: &buf, row: row, col: col, width: width,
                                   theme: theme, bold: false, baseFg: theme.colors.fg)
            }
        case .plain:
            for seg in line.segments {
                col = writeSegment(seg, into: &buf, row: row, col: col, width: width,
                                   theme: theme, bold: false, baseFg: theme.colors.fg)
            }
        }
    }

    private func writeSegment(_ seg: MDSegment, into buf: inout CellBuffer, row: Int, col: Int,
                              width: Int, theme: Theme, bold: Bool, baseFg: ANSIColor) -> Int {
        var c = col
        switch seg {
        case .text(let t):
            buf.write(String(t.prefix(width - c)), x: c, y: row, fg: baseFg, bold: bold)
            c += min(t.count, width - c)
        case .bold(let t):
            buf.write(String(t.prefix(width - c)), x: c, y: row, fg: baseFg, bold: true)
            c += min(t.count, width - c)
        case .italic(let t):
            buf.write(String(t.prefix(width - c)), x: c, y: row, fg: baseFg, italic: true)
            c += min(t.count, width - c)
        case .code(let t):
            for ch in t.prefix(width - c) {
                buf[c, row] = Cell(character: ch, fg: theme.syntax.string, bg: theme.colors.bgPanel,
                                   bold: false, italic: false, underline: false)
                c += 1
            }
        case .link(let text, _):
            buf.write(String(text.prefix(width - c)), x: c, y: row, fg: theme.colors.accent, underline: true)
            c += min(text.count, width - c)
        }
        return c
    }

    private func segmentText(_ seg: MDSegment) -> String {
        switch seg {
        case .text(let t): return t
        case .bold(let t): return t
        case .italic(let t): return t
        case .code(let t): return t
        case .link(let t, _): return t
        }
    }
}
