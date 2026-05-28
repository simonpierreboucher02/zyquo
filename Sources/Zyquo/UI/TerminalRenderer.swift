import Foundation

public struct Size: Sendable, Equatable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct Region: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum TerminalCapability: Sendable {
    case trueColor
    case color256
    case color16
    case monochrome

    public static func detect() -> TerminalCapability {
        let env = ProcessInfo.processInfo.environment
        if env["NO_COLOR"] != nil { return .monochrome }
        let colorTerm = env["COLORTERM"] ?? ""
        if colorTerm == "truecolor" || colorTerm == "24bit" { return .trueColor }
        let term = env["TERM"] ?? ""
        if term.contains("256color") { return .color256 }
        if term == "dumb" { return .monochrome }
        return .color16
    }
}

public final class TerminalRendererEngine: @unchecked Sendable {
    private var frontBuffer: CellBuffer
    private var backBuffer: CellBuffer
    private let capability: TerminalCapability
    private var size: Size

    private var inAltScreen = false

    public init() {
        let termSize = Terminal.size
        self.size = Size(width: termSize.width, height: termSize.height)
        self.frontBuffer = CellBuffer(width: size.width, height: size.height)
        self.backBuffer = CellBuffer(width: size.width, height: size.height)
        self.capability = TerminalCapability.detect()
    }

    public func enterAltScreen() {
        guard capability != .monochrome else { return }
        print("\u{1B}[?1049h", terminator: "")
        fflush(stdout)
        inAltScreen = true
    }

    public func leaveAltScreen() {
        guard capability != .monochrome else { return }
        print("\u{1B}[?1049l", terminator: "")
        fflush(stdout)
        inAltScreen = false
    }

    public func resize() {
        let termSize = Terminal.size
        size = Size(width: termSize.width, height: termSize.height)
        frontBuffer = CellBuffer(width: size.width, height: size.height)
        backBuffer = CellBuffer(width: size.width, height: size.height)
    }

    public func clear() {
        backBuffer = CellBuffer(width: size.width, height: size.height)
    }

    public func write(_ text: String, x: Int, y: Int, fg: ANSIColor = .default, bg: ANSIColor = .default, bold: Bool = false) {
        backBuffer.write(text, x: x, y: y, fg: fg, bg: bg, bold: bold)
    }

    public func drawBox(x: Int, y: Int, width: Int, height: Int, fg: ANSIColor = .default) {
        backBuffer.drawBox(x: x, y: y, width: width, height: height, fg: fg)
    }

    public func flush() {
        guard capability != .monochrome || true else { return }

        var output = ""
        output.reserveCapacity(size.width * size.height * 4)

        // Begin synchronized output, save cursor position, hide cursor
        output += "\u{1B}[?2026h"  // begin sync
        output += "\u{1B}7"         // save cursor (DECSC)
        output += "\u{1B}[?25l"     // hide cursor

        // Track current SGR state to avoid redundant escapes
        var currentFg: ANSIColor = .default
        var currentBg: ANSIColor = .default
        var currentBold = false
        var currentItalic = false
        var currentUnderline = false

        for y in 0..<size.height {
            for x in 0..<size.width {
                let newCell = backBuffer[x, y]
                let oldCell = frontBuffer[x, y]

                if newCell != oldCell {
                    output += "\u{1B}[\(y + 1);\(x + 1)H"

                    let needsChange = newCell.fg != currentFg || newCell.bg != currentBg ||
                                      newCell.bold != currentBold || newCell.italic != currentItalic ||
                                      newCell.underline != currentUnderline

                    if needsChange {
                        output += "\u{1B}[0m"  // reset
                        var codes: [String] = []
                        if newCell.bold { codes.append("1") }
                        if newCell.italic { codes.append("3") }
                        if newCell.underline { codes.append("4") }
                        if newCell.fg != .default { codes.append(newCell.fg.fgCode) }
                        if newCell.bg != .default { codes.append(newCell.bg.bgCode) }
                        if !codes.isEmpty {
                            output += "\u{1B}[\(codes.joined(separator: ";"))m"
                        }
                        currentFg = newCell.fg
                        currentBg = newCell.bg
                        currentBold = newCell.bold
                        currentItalic = newCell.italic
                        currentUnderline = newCell.underline
                    }

                    output.append(newCell.character)
                }
            }
        }

        // Reset SGR if any style was active
        if currentFg != .default || currentBg != .default || currentBold || currentItalic || currentUnderline {
            output += "\u{1B}[0m"
        }

        // Show cursor, restore cursor position, end synchronized output
        output += "\u{1B}[?25h"     // show cursor
        output += "\u{1B}8"         // restore cursor (DECRC)
        output += "\u{1B}[?2026l"   // end sync

        frontBuffer = backBuffer
        print(output, terminator: "")
        fflush(stdout)
    }

    public var currentSize: Size { size }
}
