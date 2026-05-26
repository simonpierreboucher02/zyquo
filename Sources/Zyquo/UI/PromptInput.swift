import Foundation

public struct PromptInput: Renderable, Sendable {
    public let prompt: String
    public let text: String
    public let cursorPosition: Int
    public let history: [String]
    public let historyIndex: Int?
    public let multiline: Bool

    public init(
        prompt: String = "> ",
        text: String = "",
        cursorPosition: Int = 0,
        history: [String] = [],
        historyIndex: Int? = nil,
        multiline: Bool = false
    ) {
        self.prompt = prompt
        self.text = text
        self.cursorPosition = cursorPosition
        self.history = history
        self.historyIndex = historyIndex
        self.multiline = multiline
    }

    public func sizeThatFits(_ available: Size) -> Size {
        if multiline {
            let lineCount = text.components(separatedBy: "\n").count
            return Size(width: available.width, height: min(lineCount + 1, available.height))
        }
        return Size(width: available.width, height: 1)
    }

    public func render(in region: Region, theme: Theme) -> CellBuffer {
        var buf = CellBuffer(width: region.width, height: region.height)
        guard region.width > prompt.count + 1, region.height >= 1 else { return buf }

        buf.write(prompt, x: 0, y: 0, fg: theme.colors.accent, bold: true)

        let displayText = historyIndex.flatMap { idx in
            idx < history.count ? history[idx] : nil
        } ?? text

        if multiline {
            let lines = displayText.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                guard i < region.height else { break }
                let xOff = i == 0 ? prompt.count : 0
                let maxW = region.width - xOff
                buf.write(String(line.prefix(maxW)), x: xOff, y: i, fg: theme.colors.fg)
            }
        } else {
            let textStart = prompt.count
            let maxTextW = region.width - textStart
            let visibleText = String(displayText.prefix(maxTextW))
            buf.write(visibleText, x: textStart, y: 0, fg: theme.colors.fg)

            let cursorX = textStart + min(cursorPosition, maxTextW)
            if cursorX < region.width {
                let cursorChar = cursorPosition < displayText.count
                    ? displayText[displayText.index(displayText.startIndex, offsetBy: cursorPosition)]
                    : " "
                buf[cursorX, 0] = Cell(
                    character: cursorChar,
                    fg: theme.colors.bg,
                    bg: theme.colors.fg,
                    bold: false, italic: false, underline: false
                )
            }
        }

        return buf
    }

    // Input handling
    public func insertCharacter(_ ch: Character) -> PromptInput {
        var newText = text
        let idx = newText.index(newText.startIndex, offsetBy: min(cursorPosition, newText.count))
        newText.insert(ch, at: idx)
        return PromptInput(prompt: prompt, text: newText, cursorPosition: cursorPosition + 1,
                          history: history, historyIndex: nil, multiline: multiline)
    }

    public func deleteBackward() -> PromptInput {
        guard cursorPosition > 0 else { return self }
        var newText = text
        let idx = newText.index(newText.startIndex, offsetBy: cursorPosition - 1)
        newText.remove(at: idx)
        return PromptInput(prompt: prompt, text: newText, cursorPosition: cursorPosition - 1,
                          history: history, historyIndex: historyIndex, multiline: multiline)
    }

    public func deleteForward() -> PromptInput {
        guard cursorPosition < text.count else { return self }
        var newText = text
        let idx = newText.index(newText.startIndex, offsetBy: cursorPosition)
        newText.remove(at: idx)
        return PromptInput(prompt: prompt, text: newText, cursorPosition: cursorPosition,
                          history: history, historyIndex: historyIndex, multiline: multiline)
    }

    public func moveCursorLeft() -> PromptInput {
        guard cursorPosition > 0 else { return self }
        return PromptInput(prompt: prompt, text: text, cursorPosition: cursorPosition - 1,
                          history: history, historyIndex: historyIndex, multiline: multiline)
    }

    public func moveCursorRight() -> PromptInput {
        guard cursorPosition < text.count else { return self }
        return PromptInput(prompt: prompt, text: text, cursorPosition: cursorPosition + 1,
                          history: history, historyIndex: historyIndex, multiline: multiline)
    }

    public func moveCursorHome() -> PromptInput {
        PromptInput(prompt: prompt, text: text, cursorPosition: 0,
                   history: history, historyIndex: historyIndex, multiline: multiline)
    }

    public func moveCursorEnd() -> PromptInput {
        PromptInput(prompt: prompt, text: text, cursorPosition: text.count,
                   history: history, historyIndex: historyIndex, multiline: multiline)
    }

    public func historyUp() -> PromptInput {
        guard !history.isEmpty else { return self }
        let newIdx: Int
        if let current = historyIndex {
            newIdx = min(current + 1, history.count - 1)
        } else {
            newIdx = 0
        }
        let histText = history[newIdx]
        return PromptInput(prompt: prompt, text: histText, cursorPosition: histText.count,
                          history: history, historyIndex: newIdx, multiline: multiline)
    }

    public func historyDown() -> PromptInput {
        guard let current = historyIndex else { return self }
        if current <= 0 {
            return PromptInput(prompt: prompt, text: "", cursorPosition: 0,
                              history: history, historyIndex: nil, multiline: multiline)
        }
        let newIdx = current - 1
        let histText = history[newIdx]
        return PromptInput(prompt: prompt, text: histText, cursorPosition: histText.count,
                          history: history, historyIndex: newIdx, multiline: multiline)
    }

    public func submit() -> (text: String, updatedInput: PromptInput) {
        let submitted = text
        var newHistory = history
        if !submitted.isEmpty {
            newHistory.insert(submitted, at: 0)
        }
        let fresh = PromptInput(prompt: prompt, text: "", cursorPosition: 0,
                               history: newHistory, historyIndex: nil, multiline: multiline)
        return (submitted, fresh)
    }
}
