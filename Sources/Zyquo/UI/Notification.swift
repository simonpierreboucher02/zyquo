import Foundation

public struct ToastNotification: Sendable {
    public enum Level: Sendable {
        case info
        case success
        case warning
        case error
    }

    public let message: String
    public let level: Level
    public let durationMs: Int

    public init(_ message: String, level: Level = .info, durationMs: Int = 3000) {
        self.message = message
        self.level = level
        self.durationMs = durationMs
    }

    public func display(noColor: Bool = false) {
        let termWidth = Terminal.size.width
        let termHeight = Terminal.size.height

        let icon: String
        let colorCode: String
        switch level {
        case .info:    icon = noColor ? "[i]" : "\u{2139}"; colorCode = "36"
        case .success: icon = noColor ? "[OK]" : "\u{2713}"; colorCode = "32"
        case .warning: icon = noColor ? "[!]" : "\u{26A0}"; colorCode = "33"
        case .error:   icon = noColor ? "[X]" : "\u{2717}"; colorCode = "31"
        }

        let truncated = String(message.prefix(max(10, termWidth - 12)))
        let content = " \(icon) \(truncated) "
        let padded = content + String(repeating: " ", count: max(0, content.count < 4 ? 0 : 0))

        let hz = noColor ? "-" : "\u{2500}"
        let tl = noColor ? "+" : "\u{256D}"
        let tr = noColor ? "+" : "\u{256E}"
        let bl = noColor ? "+" : "\u{2570}"
        let br = noColor ? "+" : "\u{256F}"
        let vt = noColor ? "|" : "\u{2502}"

        let boxWidth = padded.count + 2
        let col = max(1, termWidth - boxWidth - 1)
        let row = max(1, termHeight - 4)

        let bold = noColor ? "" : "\u{1B}[1m"
        let fg = noColor ? "" : "\u{1B}[\(colorCode)m"
        let dim = noColor ? "" : "\u{1B}[2m"
        let reset = noColor ? "" : "\u{1B}[0m"

        let topLine = "\(dim)\(tl)\(String(repeating: hz, count: boxWidth - 2))\(tr)\(reset)"
        let midLine = "\(dim)\(vt)\(reset)\(fg)\(bold)\(padded)\(reset)\(dim)\(vt)\(reset)"
        let botLine = "\(dim)\(bl)\(String(repeating: hz, count: boxWidth - 2))\(br)\(reset)"

        // Save cursor, draw toast
        print("\u{1B}7", terminator: "")
        print("\u{1B}[\(row);\(col)H\(topLine)", terminator: "")
        print("\u{1B}[\(row + 1);\(col)H\(midLine)", terminator: "")
        print("\u{1B}[\(row + 2);\(col)H\(botLine)", terminator: "")
        print("\u{1B}8", terminator: "")
        fflush(stdout)

        // Schedule clear
        Task {
            try? await Task.sleep(nanoseconds: UInt64(durationMs) * 1_000_000)
            await MainActor.run {
                // Clear the toast area
                print("\u{1B}7", terminator: "")
                let blank = String(repeating: " ", count: boxWidth)
                for i in 0..<3 {
                    print("\u{1B}[\(row + i);\(col)H\(blank)", terminator: "")
                }
                print("\u{1B}8", terminator: "")
                fflush(stdout)
            }
        }
    }
}
