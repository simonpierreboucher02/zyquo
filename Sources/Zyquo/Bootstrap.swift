import Foundation
import os

enum Bootstrap {
    static func setupSignalHandlers() {
        signal(SIGINT) { _ in
            Terminal.restore()
            _Exit(130)
        }
        signal(SIGTERM) { _ in
            Terminal.restore()
            _Exit(1)
        }
        signal(SIGWINCH) { _ in
            NotificationCenter.default.post(name: .terminalResized, object: nil)
        }
    }

    static func ensureDirectories() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let dirs = [
            home.appendingPathComponent(".zyquo"),
            home.appendingPathComponent(".zyquo/themes"),
            home.appendingPathComponent("Library/Logs/Zyquo"),
        ]

        for dir in dirs {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func detectWorkspaceRoot(override: String?) -> URL {
        if let override {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

extension Notification.Name {
    static let terminalResized = Notification.Name("dev.zyquo.terminalResized")
}

enum CursorShape: Int {
    case block = 2
    case underline = 4
    case bar = 6
}

enum Terminal {
    private static let originalTermios = OSAllocatedUnfairLock<termios?>(initialState: nil)

    static func enableRawMode() {
        var raw = termios()
        tcgetattr(STDIN_FILENO, &raw)
        let saved = raw
        originalTermios.withLock { $0 = saved }
        cfmakeraw(&raw)
        raw.c_cc.16 = 1  // VMIN
        raw.c_cc.17 = 0  // VTIME
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    static func restore() {
        if var original = originalTermios.withLock({ $0 }) {
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
            originalTermios.withLock { $0 = nil }
        }
        print("\u{1B}[0 q", terminator: "")  // reset cursor shape to default
        print("\u{1B}[?25h", terminator: "")  // show cursor
        fflush(stdout)
    }

    static func setWindowTitle(_ title: String) {
        print("\u{1B}]0;\(title)\u{07}", terminator: "")
        fflush(stdout)
    }

    static func setCursorShape(_ shape: CursorShape) {
        print("\u{1B}[\(shape.rawValue) q", terminator: "")
        fflush(stdout)
    }

    static var size: (width: Int, height: Int) {
        var ws = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 {
            return (Int(ws.ws_col), Int(ws.ws_row))
        }
        return (80, 24)
    }
}
