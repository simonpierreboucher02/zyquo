import Foundation

public struct KeymapOverlay: Sendable {
    public struct Binding: Sendable {
        public let key: String
        public let action: String

        public init(_ key: String, _ action: String) {
            self.key = key
            self.action = action
        }
    }

    public static let defaultBindings: [Binding] = [
        Binding("?", "Toggle this overlay"),
        Binding("Ctrl-C", "Cancel / exit if idle"),
        Binding("Ctrl-D", "Exit at idle"),
        Binding("Ctrl-L", "Clear screen"),
        Binding("\u{2191}/\u{2193}", "Input history"),
        Binding("Tab", "Completion"),
        Binding("Esc", "Close modal / cancel"),
        Binding("Enter", "Submit"),
        Binding("y / n", "Approve / deny"),
        Binding("a", "Always approve"),
        Binding("e", "Edit command"),
        Binding("s", "Toggle side-by-side diff"),
    ]

    private let bindings: [Binding]
    private let noColor: Bool

    public init(bindings: [Binding]? = nil, noColor: Bool = false) {
        self.bindings = bindings ?? Self.defaultBindings
        self.noColor = noColor
    }

    public func render() -> String {
        let theme = Theme.zyquoDark

        let maxKeyLen = bindings.map(\.key.count).max() ?? 8
        let maxActionLen = bindings.map(\.action.count).max() ?? 20
        let innerWidth = maxKeyLen + 3 + maxActionLen + 4
        let totalWidth = innerWidth + 2

        let bold = noColor ? "" : "\u{1B}[1m"
        let dim = noColor ? "" : "\u{1B}[2m"
        let cyan = noColor ? "" : "\u{1B}[36m"
        let reset = noColor ? "" : "\u{1B}[0m"
        let border = noColor ? "" : "\u{1B}[2m"

        let hz = noColor ? "-" : "\u{2500}"
        let vt = noColor ? "|" : "\u{2502}"
        let tl = noColor ? "+" : "\u{256D}"
        let tr = noColor ? "+" : "\u{256E}"
        let bl = noColor ? "+" : "\u{2570}"
        let br = noColor ? "+" : "\u{256F}"

        var lines: [String] = []

        let title = " Keymap "
        let titlePad = innerWidth - title.count
        let lp = titlePad / 2
        let rp = titlePad - lp
        lines.append("\(border)\(tl)\(String(repeating: hz, count: lp))\(reset)\(bold)\(title)\(reset)\(border)\(String(repeating: hz, count: rp))\(tr)\(reset)")

        for binding in bindings {
            let keyPad = String(repeating: " ", count: max(0, maxKeyLen - binding.key.count))
            let actionPad = String(repeating: " ", count: max(0, maxActionLen - binding.action.count))
            lines.append("\(border)\(vt)\(reset) \(cyan)\(bold)\(binding.key)\(reset)\(keyPad)  \(dim)\(binding.action)\(reset)\(actionPad) \(border)\(vt)\(reset)")
        }

        lines.append("\(border)\(bl)\(String(repeating: hz, count: innerWidth))\(br)\(reset)")
        lines.append("\(dim)Press ? to close\(reset)")

        return lines.joined(separator: "\n")
    }

    public func display() {
        let rendered = render()
        let lines = rendered.components(separatedBy: "\n")
        let termWidth = Terminal.size.width
        let termHeight = Terminal.size.height

        let overlayWidth = lines.map({ stripANSI($0).count }).max() ?? 40
        let startCol = max(1, (termWidth - overlayWidth) / 2)
        let startRow = max(1, (termHeight - lines.count) / 2)

        // Save cursor, draw overlay
        print("\u{1B}7", terminator: "")
        for (i, line) in lines.enumerated() {
            print("\u{1B}[\(startRow + i);\(startCol)H\(line)", terminator: "")
        }
        print("\u{1B}8", terminator: "")
        fflush(stdout)
    }

    private func stripANSI(_ str: String) -> String {
        var result = ""
        var inEscape = false
        for char in str {
            if char == "\u{1B}" { inEscape = true; continue }
            if inEscape { if char == "m" { inEscape = false }; continue }
            result.append(char)
        }
        return result
    }
}
