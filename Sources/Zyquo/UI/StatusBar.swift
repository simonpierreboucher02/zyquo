@preconcurrency import Foundation

public actor StatusBarManager {
    public struct Content: Sendable {
        public var left: String
        public var center: String
        public var right: String

        public init(left: String = "", center: String = "", right: String = "") {
            self.left = left
            self.center = center
            self.right = right
        }
    }

    private var content: Content
    private let writer: StreamWriter
    private var enabled: Bool
    private var terminalHeight: Int
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    public init(writer: StreamWriter) {
        self.content = Content()
        self.writer = writer
        self.enabled = false
        self.terminalHeight = Terminal.size.height
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func enable() {
        guard !writer.noColor else { return }
        enabled = true
        terminalHeight = Terminal.size.height
        // Set scroll region to exclude the last row
        let esc = "\u{1B}[1;\(terminalHeight - 1)r"
        // Move cursor to row 1
        let move = "\u{1B}[1;1H"
        print("\(esc)\(move)", terminator: "")
        fflush(stdout)
        startListeningForResize()
        redrawInternal()
    }

    public func disable() {
        guard enabled else { return }
        enabled = false
        // Reset scroll region to full terminal
        print("\u{1B}[r", terminator: "")
        // Clear the status bar line
        print("\u{1B}[\(terminalHeight);1H\u{1B}[2K", terminator: "")
        fflush(stdout)
        stopListeningForResize()
    }

    public func update(_ content: Content) {
        self.content = content
        guard enabled else { return }
        redrawInternal()
    }

    public func redraw() {
        guard enabled else { return }
        redrawInternal()
    }

    // MARK: - Private

    private func redrawInternal() {
        guard !writer.noColor else { return }

        let width = Terminal.size.width
        guard width > 0 else { return }

        // Save cursor
        var output = "\u{1B}7"
        // Move to last row
        output += "\u{1B}[\(terminalHeight);1H"

        // Build bar content: left | center | right
        let leftText = content.left
        let centerText = content.center
        let rightText = content.right

        let leftLen = leftText.count
        let centerLen = centerText.count
        let rightLen = rightText.count

        // Layout: [left] ... [center] ... [right]
        var bar = ""
        bar += " \(leftText)"
        let currentLen = leftLen + 1 // leading space

        let centerStart = max(currentLen, (width - centerLen) / 2)
        let padToCenter = centerStart - currentLen
        bar += String(repeating: " ", count: max(0, padToCenter))
        bar += centerText

        let afterCenter = currentLen + max(0, padToCenter) + centerLen
        let rightStart = max(afterCenter, width - rightLen - 1)
        let padToRight = rightStart - afterCenter
        bar += String(repeating: " ", count: max(0, padToRight))
        bar += rightText

        // Pad to full width
        let totalLen = bar.count
        if totalLen < width {
            bar += String(repeating: " ", count: width - totalLen)
        } else if totalLen > width {
            bar = String(bar.prefix(width))
        }

        // Emit with theme colors
        let bgColor = writer.theme.colors.bgPanel
        let fgColor = writer.theme.colors.fgMuted
        let resolvedBg = writer.theme.resolve(bgColor, capability: writer.capability)
        let resolvedFg = writer.theme.resolve(fgColor, capability: writer.capability)

        var codes: [String] = []
        if resolvedFg != .default { codes.append(resolvedFg.fgCode) }
        if resolvedBg != .default { codes.append(resolvedBg.bgCode) }

        if !codes.isEmpty {
            output += "\u{1B}[\(codes.joined(separator: ";"))m"
        }
        output += bar
        if !codes.isEmpty {
            output += "\u{1B}[0m"
        }

        // Restore cursor
        output += "\u{1B}8"

        print(output, terminator: "")
        fflush(stdout)
    }

    private func startListeningForResize() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .terminalResized,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task {
                await self.handleResize()
            }
        }
    }

    private func stopListeningForResize() {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func handleResize() {
        let newSize = Terminal.size
        terminalHeight = newSize.height
        guard enabled, !writer.noColor else { return }
        // Update scroll region
        print("\u{1B}[1;\(terminalHeight - 1)r", terminator: "")
        fflush(stdout)
        redrawInternal()
    }
}
