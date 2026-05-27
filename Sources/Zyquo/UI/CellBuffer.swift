import Foundation

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
            guard col < width else { break }
            self[col, y] = Cell(character: char, fg: fg, bg: bg, bold: bold, italic: italic, underline: underline)
            col += 1
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
