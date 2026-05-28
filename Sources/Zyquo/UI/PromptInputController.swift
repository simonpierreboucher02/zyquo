import Foundation
#if canImport(Darwin)
import Darwin
#endif

public final class PromptInputController: @unchecked Sendable {
    private var state: PromptInput
    private let noColor: Bool
    private let theme: Theme
    private let prompt: String
    private let slashCommands: [String]

    public init(
        prompt: String = "zyquo>",
        slashCommands: [String] = ["/help", "/status", "/cost", "/model", "/tools", "/history", "/reset", "/clear", "/exit"],
        noColor: Bool = false
    ) {
        self.prompt = prompt
        self.slashCommands = slashCommands
        self.noColor = noColor
        self.theme = .zyquoDark
        self.state = PromptInput(prompt: prompt)
    }

    /// Read a line of input using raw terminal mode with full editing support.
    /// Returns the submitted text, or nil if cancelled (Ctrl-C/Ctrl-D).
    public func readLine() -> String? {
        Terminal.enableRawMode()
        writeOutput("\u{1B}[?2004h")  // enable bracketed paste
        defer {
            writeOutput("\u{1B}[?2004l")  // disable bracketed paste
            Terminal.restore()
        }

        state = PromptInput(
            prompt: state.prompt, text: "", cursorPosition: 0,
            history: state.history, historyIndex: nil, multiline: false
        )
        redrawLine()

        var tabCompletionIndex: Int? = nil
        var tabCompletionMatches: [String] = []

        while true {
            var byte: UInt8 = 0
            let n = read(STDIN_FILENO, &byte, 1)
            guard n == 1 else { continue }

            // Reset tab completion state on any non-tab key
            if byte != 0x09 {
                tabCompletionIndex = nil
                tabCompletionMatches = []
            }

            switch byte {
            // Enter
            case 0x0D, 0x0A:
                let (submitted, updated) = state.submit()
                state = updated
                writeOutput("\r\n")
                return submitted

            // Ctrl-C
            case 0x03:
                writeOutput("\r\n")
                return nil

            // Ctrl-D
            case 0x04:
                if state.text.isEmpty {
                    writeOutput("\r\n")
                    return nil
                }

            // Backspace (0x7F) or Ctrl-H (0x08)
            case 0x7F, 0x08:
                state = state.deleteBackward()
                redrawLine()

            // Tab
            case 0x09:
                handleTabCompletion(&tabCompletionIndex, &tabCompletionMatches)

            // Ctrl-W: delete word backward
            case 0x17:
                deleteWordBackward()
                redrawLine()

            // Ctrl-U: clear line
            case 0x15:
                state = PromptInput(
                    prompt: state.prompt, text: "", cursorPosition: 0,
                    history: state.history, historyIndex: state.historyIndex, multiline: false
                )
                redrawLine()

            // Ctrl-A: move to start
            case 0x01:
                state = state.moveCursorHome()
                redrawLine()

            // Ctrl-E: move to end
            case 0x05:
                state = state.moveCursorEnd()
                redrawLine()

            // Escape sequence
            case 0x1B:
                handleEscapeSequence()

            // Printable ASCII
            case 0x20...0x7E:
                state = state.insertCharacter(Character(UnicodeScalar(byte)))
                redrawLine()

            // UTF-8 multi-byte start
            default:
                if byte & 0x80 != 0 {
                    handleUTF8(firstByte: byte)
                }
            }
        }
    }

    // MARK: - Escape Sequence Handling

    private func handleEscapeSequence() {
        var seq1: UInt8 = 0
        guard read(STDIN_FILENO, &seq1, 1) == 1 else { return }

        if seq1 == UInt8(ascii: "[") {
            var seq2: UInt8 = 0
            guard read(STDIN_FILENO, &seq2, 1) == 1 else { return }

            switch seq2 {
            // Arrow Up
            case UInt8(ascii: "A"):
                state = state.historyUp()
                redrawLine()
            // Arrow Down
            case UInt8(ascii: "B"):
                state = state.historyDown()
                redrawLine()
            // Arrow Right
            case UInt8(ascii: "C"):
                state = state.moveCursorRight()
                redrawLine()
            // Arrow Left
            case UInt8(ascii: "D"):
                state = state.moveCursorLeft()
                redrawLine()
            // Home
            case UInt8(ascii: "H"):
                state = state.moveCursorHome()
                redrawLine()
            // End
            case UInt8(ascii: "F"):
                state = state.moveCursorEnd()
                redrawLine()
            // \x1b[2~ (Insert) or \x1b[200~ (bracketed paste start)
            case UInt8(ascii: "2"):
                var next: UInt8 = 0
                guard read(STDIN_FILENO, &next, 1) == 1 else { return }
                if next == UInt8(ascii: "0") {
                    // Could be \e[200~ (paste start)
                    var next2: UInt8 = 0
                    guard read(STDIN_FILENO, &next2, 1) == 1 else { return }
                    if next2 == UInt8(ascii: "0") {
                        var tilde: UInt8 = 0
                        _ = read(STDIN_FILENO, &tilde, 1)  // consume ~
                        handleBracketedPaste()
                        return
                    }
                } else if next == UInt8(ascii: "~") {
                    // Insert key — ignore
                    return
                }
            // Sequences like \x1b[1~ (Home), \x1b[3~ (Delete), \x1b[4~ (End)
            case UInt8(ascii: "1"), UInt8(ascii: "3"), UInt8(ascii: "4"):
                var tilde: UInt8 = 0
                if read(STDIN_FILENO, &tilde, 1) == 1, tilde == UInt8(ascii: "~") {
                    switch seq2 {
                    case UInt8(ascii: "1"):
                        state = state.moveCursorHome()
                        redrawLine()
                    case UInt8(ascii: "3"):
                        state = state.deleteForward()
                        redrawLine()
                    case UInt8(ascii: "4"):
                        state = state.moveCursorEnd()
                        redrawLine()
                    default:
                        break
                    }
                }
            default:
                break
            }
        }
    }

    // MARK: - Bracketed Paste

    private func handleBracketedPaste() {
        var pasteBuffer = ""
        while true {
            var byte: UInt8 = 0
            guard read(STDIN_FILENO, &byte, 1) == 1 else { break }

            if byte == 0x1B {
                // Check for paste end sequence: \e[201~
                var seq: [UInt8] = [0, 0, 0, 0]
                let n = read(STDIN_FILENO, &seq, 4)
                if n == 4, seq[0] == UInt8(ascii: "["),
                   seq[1] == UInt8(ascii: "2"), seq[2] == UInt8(ascii: "0"),
                   seq[3] == UInt8(ascii: "1") {
                    var tilde: UInt8 = 0
                    _ = read(STDIN_FILENO, &tilde, 1)  // consume ~
                    break
                }
                // Not end sequence — add bytes to buffer
                pasteBuffer.append(Character(UnicodeScalar(0x1B)))
                for i in 0..<n { pasteBuffer.append(Character(UnicodeScalar(seq[i]))) }
            } else {
                if byte >= 0x20 {
                    pasteBuffer.append(Character(UnicodeScalar(byte)))
                } else if byte == 0x0A || byte == 0x0D {
                    pasteBuffer.append("\n")
                }
            }
        }

        for ch in pasteBuffer {
            state = state.insertCharacter(ch)
        }
        redrawLine()
    }

    // MARK: - UTF-8 Handling

    private func handleUTF8(firstByte: UInt8) {
        let continuationCount: Int
        if firstByte & 0xE0 == 0xC0 {
            continuationCount = 1
        } else if firstByte & 0xF0 == 0xE0 {
            continuationCount = 2
        } else if firstByte & 0xF8 == 0xF0 {
            continuationCount = 3
        } else {
            return
        }

        var bytes: [UInt8] = [firstByte]
        for _ in 0..<continuationCount {
            var b: UInt8 = 0
            guard read(STDIN_FILENO, &b, 1) == 1 else { return }
            bytes.append(b)
        }

        if let str = String(bytes: bytes, encoding: .utf8), let ch = str.first {
            state = state.insertCharacter(ch)
            redrawLine()
        }
    }

    // MARK: - Tab Completion

    private func handleTabCompletion(_ index: inout Int?, _ matches: inout [String]) {
        let currentText = state.text

        if index == nil {
            // First tab press: find matches
            if currentText.hasPrefix("/") {
                matches = slashCommands.filter { $0.hasPrefix(currentText) }
            } else {
                matches = slashCommands.filter { $0.hasPrefix("/\(currentText)") }
            }
            guard !matches.isEmpty else { return }
            index = 0
        } else {
            // Cycle through matches
            guard !matches.isEmpty else { return }
            index = ((index ?? 0) + 1) % matches.count
        }

        if let idx = index, idx < matches.count {
            let completion = matches[idx]
            state = PromptInput(
                prompt: state.prompt, text: completion, cursorPosition: completion.count,
                history: state.history, historyIndex: nil, multiline: false
            )
            redrawLine()
        }
    }

    // MARK: - Word Deletion

    private func deleteWordBackward() {
        var text = state.text
        var pos = state.cursorPosition
        guard pos > 0 else { return }

        // Skip trailing whitespace
        while pos > 0 {
            let idx = text.index(text.startIndex, offsetBy: pos - 1)
            if text[idx] == " " {
                pos -= 1
            } else {
                break
            }
        }

        // Delete until next whitespace or start
        while pos > 0 {
            let idx = text.index(text.startIndex, offsetBy: pos - 1)
            if text[idx] == " " {
                break
            }
            text.remove(at: idx)
            pos -= 1
        }

        state = PromptInput(
            prompt: state.prompt, text: text, cursorPosition: pos,
            history: state.history, historyIndex: state.historyIndex, multiline: false
        )
    }

    // MARK: - Rendering

    private func redrawLine() {
        let displayText = state.historyIndex.flatMap { idx in
            idx < state.history.count ? state.history[idx] : nil
        } ?? state.text

        var output = "\r\u{1B}[2K"

        if noColor {
            output += prompt
        } else {
            output += "\u{1B}[1;36m\(prompt)\u{1B}[0m"
        }

        output += " \(displayText)"

        // Position cursor
        let cursorCol = prompt.count + 1 + state.cursorPosition
        output += "\r\u{1B}[\(cursorCol + 1)G"

        writeOutput(output)
    }

    private func writeOutput(_ str: String) {
        var data = Array(str.utf8)
        _ = data.withUnsafeMutableBufferPointer { ptr in
            write(STDOUT_FILENO, ptr.baseAddress, ptr.count)
        }
    }
}
