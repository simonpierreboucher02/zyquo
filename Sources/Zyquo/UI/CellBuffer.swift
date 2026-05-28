import Foundation

public func displayWidth(_ c: Character) -> Int {
    let scalars = c.unicodeScalars
    guard let first = scalars.first else { return 0 }
    let v = first.value

    // Combining marks — zero width
    if (0x0300...0x036F).contains(v) || (0x1AB0...0x1AFF).contains(v) ||
       (0x1DC0...0x1DFF).contains(v) || (0x20D0...0x20FF).contains(v) ||
       (0xFE20...0xFE2F).contains(v) {
        return 0
    }

    // CJK ranges — double width
    if (0x1100...0x115F).contains(v) ||  // Hangul Jamo
       (0x2E80...0x303E).contains(v) ||  // CJK Radicals
       (0x3041...0x33BF).contains(v) ||  // Hiragana..CJK Compatibility
       (0x3400...0x4DBF).contains(v) ||  // CJK Unified Ext A
       (0x4E00...0x9FFF).contains(v) ||  // CJK Unified
       (0xA000...0xA4CF).contains(v) ||  // Yi
       (0xAC00...0xD7AF).contains(v) ||  // Hangul Syllables
       (0xF900...0xFAFF).contains(v) ||  // CJK Compatibility Ideographs
       (0xFE30...0xFE6F).contains(v) ||  // CJK Compatibility Forms
       (0xFF01...0xFF60).contains(v) ||  // Fullwidth Forms
       (0xFFE0...0xFFE6).contains(v) ||  // Fullwidth Signs
       (0x20000...0x2FA1F).contains(v) { // CJK Ext B..Compatibility Supp
        return 2
    }

    // Emoji presentation — double width (simplified check for emoji with high codepoints)
    if scalars.count > 1 {
        return 2
    }
    if v > 0x23F, first.properties.isEmoji {
        return 2
    }

    // Control characters
    if v < 0x20 || v == 0x7F { return 0 }

    return 1
}

public enum BoxBorderStyle: Sendable {
    case rounded    // ╭─╮│╰╯
    case square     // ┌─┐│└┘
    case double     // ╔═╗║╚╝
    case heavy      // ┏━┓┃┗┛

    public var topLeft: Character {
        switch self {
        case .rounded: return "╭"
        case .square:  return "┌"
        case .double:  return "╔"
        case .heavy:   return "┏"
        }
    }

    public var topRight: Character {
        switch self {
        case .rounded: return "╮"
        case .square:  return "┐"
        case .double:  return "╗"
        case .heavy:   return "┓"
        }
    }

    public var bottomLeft: Character {
        switch self {
        case .rounded: return "╰"
        case .square:  return "└"
        case .double:  return "╚"
        case .heavy:   return "┗"
        }
    }

    public var bottomRight: Character {
        switch self {
        case .rounded: return "╯"
        case .square:  return "┘"
        case .double:  return "╝"
        case .heavy:   return "┛"
        }
    }

    public var horizontal: Character {
        switch self {
        case .rounded, .square: return "─"
        case .double:           return "═"
        case .heavy:            return "━"
        }
    }

    public var vertical: Character {
        switch self {
        case .rounded, .square: return "│"
        case .double:           return "║"
        case .heavy:            return "┃"
        }
    }
}

public struct Cell: Sendable, Equatable {
    public var character: Character
    public var fg: ANSIColor
    public var bg: ANSIColor
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool

    public static let empty = Cell(
        character: " ",
        fg: .default,
        bg: .default,
        bold: false,
        italic: false,
        underline: false
    )
}

public struct CellBuffer: Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [Cell]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.cells = Array(repeating: .empty, count: width * height)
    }

    public subscript(x: Int, y: Int) -> Cell {
        get {
            guard x >= 0, x < width, y >= 0, y < height else { return .empty }
            return cells[y * width + x]
        }
        set {
            guard x >= 0, x < width, y >= 0, y < height else { return }
            cells[y * width + x] = newValue
        }
    }

    public mutating func write(_ text: String, x: Int, y: Int, fg: ANSIColor = .default, bg: ANSIColor = .default, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
        var col = x
        for char in text {
            let w = displayWidth(char)
            guard col + w <= width else { break }
            self[col, y] = Cell(character: char, fg: fg, bg: bg, bold: bold, italic: italic, underline: underline)
            if w == 2, col + 1 < width {
                // Write a padding cell for the second column of a double-width character
                self[col + 1, y] = Cell(character: "\0", fg: fg, bg: bg, bold: false, italic: false, underline: false)
            }
            col += w
        }
    }

    public mutating func blit(_ source: CellBuffer, at x: Int, y: Int) {
        for sy in 0..<source.height {
            for sx in 0..<source.width {
                let cell = source[sx, sy]
                if cell != .empty {
                    self[x + sx, y + sy] = cell
                }
            }
        }
    }

    public func extractText(y: Int) -> String {
        guard y >= 0, y < height else { return "" }
        var result = ""
        for x in 0..<width {
            result.append(self[x, y].character)
        }
        return result.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    public func renderPlainText() -> String {
        (0..<height).map { extractText(y: $0) }.joined(separator: "\n") + "\n"
    }

    public mutating func fill(x: Int, y: Int, width w: Int, height h: Int, cell: Cell = .empty) {
        for row in y..<min(y + h, height) {
            for col in x..<min(x + w, self.width) {
                self[col, row] = cell
            }
        }
    }

    @available(*, deprecated, message: "Use drawBox(x:y:width:height:fg:style:) instead")
    public mutating func drawBox(x: Int, y: Int, width w: Int, height h: Int, fg: ANSIColor = .default, rounded: Bool) {
        drawBox(x: x, y: y, width: w, height: h, fg: fg, style: rounded ? .rounded : .square)
    }

    public mutating func drawBox(x: Int, y: Int, width w: Int, height h: Int, fg: ANSIColor = .default, style: BoxBorderStyle = .rounded) {
        guard w >= 2, h >= 2 else {
            if h == 1, w >= 2 {
                let hz = style.horizontal
                let cell = { (c: Character) in Cell(character: c, fg: fg, bg: .default, bold: false, italic: false, underline: false) }
                for col in x..<(x + w) {
                    self[col, y] = cell(hz)
                }
            }
            return
        }

        let cell = { (c: Character) in Cell(character: c, fg: fg, bg: .default, bold: false, italic: false, underline: false) }

        self[x, y] = cell(style.topLeft)
        self[x + w - 1, y] = cell(style.topRight)
        self[x, y + h - 1] = cell(style.bottomLeft)
        self[x + w - 1, y + h - 1] = cell(style.bottomRight)

        for col in (x + 1)..<(x + w - 1) {
            self[col, y] = cell(style.horizontal)
            self[col, y + h - 1] = cell(style.horizontal)
        }
        for row in (y + 1)..<(y + h - 1) {
            self[x, row] = cell(style.vertical)
            self[x + w - 1, row] = cell(style.vertical)
        }
    }
}

public enum ANSIColor: Sendable, Equatable {
    case `default`
    case black, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
    case color256(UInt8)
    case trueColor(r: UInt8, g: UInt8, b: UInt8)

    public var fgCode: String {
        switch self {
        case .default: return "39"
        case .black: return "30"
        case .red: return "31"
        case .green: return "32"
        case .yellow: return "33"
        case .blue: return "34"
        case .magenta: return "35"
        case .cyan: return "36"
        case .white: return "37"
        case .brightBlack: return "90"
        case .brightRed: return "91"
        case .brightGreen: return "92"
        case .brightYellow: return "93"
        case .brightBlue: return "94"
        case .brightMagenta: return "95"
        case .brightCyan: return "96"
        case .brightWhite: return "97"
        case .color256(let n): return "38;5;\(n)"
        case .trueColor(let r, let g, let b): return "38;2;\(r);\(g);\(b)"
        }
    }

    public var bgCode: String {
        switch self {
        case .default: return "49"
        case .black: return "40"
        case .red: return "41"
        case .green: return "42"
        case .yellow: return "43"
        case .blue: return "44"
        case .magenta: return "45"
        case .cyan: return "46"
        case .white: return "47"
        case .brightBlack: return "100"
        case .brightRed: return "101"
        case .brightGreen: return "102"
        case .brightYellow: return "103"
        case .brightBlue: return "104"
        case .brightMagenta: return "105"
        case .brightCyan: return "106"
        case .brightWhite: return "107"
        case .color256(let n): return "48;5;\(n)"
        case .trueColor(let r, let g, let b): return "48;2;\(r);\(g);\(b)"
        }
    }
}
