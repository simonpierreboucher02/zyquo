import ArgumentParser
import Foundation
import ZyquoCore

struct InteractiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interactive",
        abstract: "Launch interactive REPL (default command)",
        aliases: ["chat"]
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    @Option(name: .long, help: "Resume a previous session")
    var resume: String?

    @Flag(name: .long, help: "Force new session")
    var new: Bool = false

    // MARK: - Tool Schemas

    private static let toolSchemas: [ToolSchema] = [
        ToolSchema(
            name: "shell_run",
            description: "Execute a shell command and return its output. Use this to run commands like ls, cat, grep, find, git, etc.",
            inputSchema: [
                "type": .string("object"),
                "required": .array([.string("command")]),
                "properties": .object([
                    "command": .object([
                        "type": .string("string"),
                        "description": .string("The shell command to execute"),
                    ]),
                    "cwd": .object([
                        "type": .string("string"),
                        "description": .string("Working directory (defaults to workspace root)"),
                    ]),
                ]),
            ]
        ),
        ToolSchema(
            name: "file_read",
            description: "Read the contents of a file. Returns the file content as text.",
            inputSchema: [
                "type": .string("object"),
                "required": .array([.string("path")]),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the file (absolute or relative to workspace)"),
                    ]),
                ]),
            ]
        ),
        ToolSchema(
            name: "file_list",
            description: "List files and directories at a given path.",
            inputSchema: [
                "type": .string("object"),
                "required": .array([.string("path")]),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Directory path to list"),
                    ]),
                ]),
            ]
        ),
        ToolSchema(
            name: "file_write",
            description: "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Creates parent directories automatically.",
            inputSchema: [
                "type": .string("object"),
                "required": .array([.string("path"), .string("content")]),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the file (absolute or relative to workspace)"),
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("Content to write to the file"),
                    ]),
                ]),
            ]
        ),
    ]

    // MARK: - Run

    func run() async throws {
        Bootstrap.setupSignalHandlers()
        Bootstrap.ensureDirectories()

        let container = AppContainer(flags: globals.flags)
        let noColor = container.config.ui.noColor
        let co = CommandOutput(noColor: noColor)

        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let providerName = container.config.providers.resolvedProvider

        // Workspace scan (skip from home dir)
        let isHomeDir = root.path == FileManager.default.homeDirectoryForCurrentUser.path
        var fileCount: Int?
        var language: String?
        if !isHomeDir {
            let workspace = Workspace(root: root)
            let wsIndex = await workspace.scan()
            fileCount = wsIndex.fileCount
            language = wsIndex.primaryLanguage?.displayName
        }

        let modelDesc = ModelCatalog.findByAlias(container.config.providers.resolvedModel)
        let modelName = modelDesc?.displayName ?? container.config.providers.resolvedModel

        // Splash screen
        let splash = SplashScreen(
            workspace: root.lastPathComponent,
            provider: providerName,
            model: modelName,
            version: ZyquoInfo.version,
            budget: String(format: "$%.2f", container.config.agent.maxCostUSD),
            fileCount: fileCount,
            language: language,
            noColor: noColor,
            animated: container.config.ui.animations && !globals.flags.quiet
        )
        splash.display()

        // Check provider key
        let hasKey = KeychainHelper.exists(service: ProviderKeychain.service, account: providerName)
        if !hasKey {
            co.failItem("No API key configured for \(providerName)")
            co.infoItem("Run: zyquo provider login \(providerName) --key YOUR_KEY")
            co.blank()
        }

        // Set up providers
        let router = ModelRouter(config: container.config.providers)
        await router.register(AnthropicProvider())
        await router.register(OpenRouterProvider())

        // Shell executor for tool use
        let shellExecutor = ShellExecutor(config: container.config.shell)

        // Session state
        var totalCost = SessionCost()
        var messageCount = 0
        var conversationHistory: [LLMMessage] = []
        var currentModel = container.config.providers.resolvedModel

        let dim = noColor ? "" : "\u{1B}[2m"
        let bold = noColor ? "" : "\u{1B}[1m"
        let cyan = noColor ? "" : "\u{1B}[36m"
        let red = noColor ? "" : "\u{1B}[31m"
        let yellow = noColor ? "" : "\u{1B}[33m"
        let reset = noColor ? "" : "\u{1B}[0m"

        // REPL loop
        while true {
            print("\(bold)\(cyan)zyquo>\(reset) ", terminator: "")
            fflush(stdout)

            guard let line = readLine(strippingNewline: true) else {
                print()
                print("  \(dim)Goodbye.\(reset)")
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("/") {
                let currentModelDisplay = ModelCatalog.findByAlias(currentModel)?.displayName ?? currentModel
                let result = handleSlashCommand(
                    trimmed, container: container, router: router,
                    totalCost: totalCost, messageCount: messageCount,
                    noColor: noColor, conversationHistory: &conversationHistory,
                    root: root, modelName: currentModelDisplay,
                    currentModel: &currentModel
                )
                if result == .exit { break }
                continue
            }

            // Send to LLM with tools
            messageCount += 1

            guard let resolved = await router.resolveExplicit(providerId: providerName, modelId: currentModel) else {
                print("  \(red)No provider available. Run: zyquo provider login \(providerName) --key YOUR_KEY\(reset)")
                print()
                continue
            }

            let descriptor = ModelCatalog.find(id: resolved.model) ?? ModelCatalog.claudeSonnet4_6
            conversationHistory.append(.user(trimmed))

            // Trim history if over 80% of context window
            let systemPrompt = """
            You are Zyquo, a powerful native macOS AI terminal agent. You have full shell access and can interact with the entire macOS system.

            CRITICAL RULES:
            - ALWAYS use your tools to execute actions — NEVER just suggest commands for the user to run manually.
            - You CAN and SHOULD use `osascript` via shell_run to control macOS apps:
              • Messages: send iMessages/SMS via `osascript -e 'tell application "Messages" ...'`
              • Finder: open files/folders, reveal in Finder
              • Calendar: create events
              • Reminders: add reminders
              • Mail: compose and send emails
              • Notes: create notes
              • Music/Spotify: play/pause/skip
              • System Preferences: change settings
              • Notifications: post alerts via `osascript -e 'display notification ...'`
              • Any scriptable macOS app
            - You can use `open` to launch apps and URLs
            - You can use `say` for text-to-speech
            - You can use `afplay` for audio playback
            - You can use `pbcopy`/`pbpaste` for clipboard
            - You can use `defaults` to read/write macOS preferences
            - You can use `networksetup`, `pmset`, `diskutil` for system management
            - You can create, read, write, and delete files anywhere the user has permission
            - When the user asks to send a message, DO IT — don't ask for permission or suggest they do it manually

            Workspace: \(root.path)
            User: \(NSUserName())

            Be concise. Act decisively. Use tools proactively.
            """
            trimConversation(&conversationHistory, budget: Int(Double(descriptor.contextWindow) * 0.8), systemPrompt: systemPrompt)

            // Tool-use loop: keep calling LLM until it stops requesting tools
            var loopCount = 0
            let maxLoops = 10

            while loopCount < maxLoops {
                loopCount += 1

                let request = LLMRequest(
                    model: resolved.model,
                    systemPrompt: systemPrompt,
                    messages: conversationHistory,
                    tools: Self.toolSchemas,
                    toolChoice: .auto,
                    maxTokens: min(4096, descriptor.maxOutputTokens)
                )

                let stream = resolved.provider.send(request: request, cancellation: nil)
                if loopCount == 1 { print() }

                var lastUsage: TokenUsage?
                var fullText = ""
                var pendingToolCalls: [(id: String, name: String, input: String)] = []
                var currentToolId = ""
                var currentToolName = ""
                var currentToolInput = ""
                var stopReason: StopReason = .endTurn

                do {
                    for try await event in stream {
                        switch event {
                        case .textDelta(let text):
                            fullText += text
                            print(text, terminator: "")
                            fflush(stdout)
                        case .toolUseStart(let meta):
                            currentToolId = meta.id
                            currentToolName = meta.name
                            currentToolInput = ""
                        case .toolUseInputDelta(let delta):
                            currentToolInput += delta
                        case .toolUseEnd:
                        if !currentToolName.isEmpty {
                            pendingToolCalls.append((id: currentToolId, name: currentToolName, input: currentToolInput))
                        }
                        case .usage(let usage):
                            lastUsage = usage
                        case .messageStop(let reason):
                            stopReason = reason
                        case .error(let err):
                            print("\n  \(red)Error: \(err.description)\(reset)")
                        default:
                            break
                        }
                    }
                } catch {
                    let msg = (error as? ZyquoError)?.description ?? error.localizedDescription
                    print("\n  \(red)Error: \(msg)\(reset)")
                    break
                }

                if !fullText.isEmpty {
                    print()
                }

                if let usage = lastUsage {
                    totalCost.record(usage: usage, model: descriptor)
                }

                // Build assistant message with text + tool_use blocks
                var assistantBlocks: [ContentBlock] = []
                if !fullText.isEmpty {
                    assistantBlocks.append(.text(fullText))
                }
                for tc in pendingToolCalls {
                    let parsedInput = parseToolInput(tc.input)
                    assistantBlocks.append(.toolUse(id: tc.id, name: tc.name, input: parsedInput))
                }
                if !assistantBlocks.isEmpty {
                    conversationHistory.append(LLMMessage(role: .assistant, content: assistantBlocks))
                }

                // If no tool calls, we're done
                if pendingToolCalls.isEmpty || stopReason != .toolUse {
                    break
                }

                // Execute tools and build results
                var toolResultBlocks: [ContentBlock] = []

                for tc in pendingToolCalls {
                    co.infoItem(tc.name, detail: nil)

                    let result = await executeTool(
                        name: tc.name,
                        input: tc.input,
                        root: root,
                        shellExecutor: shellExecutor
                    )

                    let truncated = String(result.prefix(8000))
                    toolResultBlocks.append(.toolResult(toolUseId: tc.id, content: truncated, isError: false))

                    let preview = String(result.prefix(200)).replacingOccurrences(of: "\n", with: " ")
                    print("    \(dim)\(preview)\(result.count > 200 ? "..." : "")\(reset)")
                }

                conversationHistory.append(LLMMessage(role: .user, content: toolResultBlocks))
            }

            co.blank()
            co.footer(items: [
                ("Tokens", "\(totalCost.totalInputTokens) in / \(totalCost.totalOutputTokens) out"),
                ("Cost", totalCost.formattedCost),
                ("Requests", "\(totalCost.requests)"),
            ])
            co.blank()
        }
    }

    // MARK: - Tool Execution

    private func executeTool(
        name: String,
        input: String,
        root: URL,
        shellExecutor: ShellExecutor
    ) async -> String {
        let params = parseToolInput(input)

        switch name {
        case "shell_run":
            guard let command = params["command"]?.stringValue else {
                return "Error: missing 'command' parameter"
            }
            let cwdStr = params["cwd"]?.stringValue
            let cwd = cwdStr.map { URL(fileURLWithPath: $0) } ?? root

            do {
                let result = try await shellExecutor.executeCollecting(
                    command: command,
                    cwd: cwd,
                    timeout: 60
                )
                var output = result.stdout
                if !result.stderr.isEmpty {
                    output += "\n[stderr]\n" + result.stderr
                }
                if result.exitCode != 0 {
                    output += "\n[exit code: \(result.exitCode)]"
                }
                return output.isEmpty ? "(no output)" : output
            } catch {
                return "Error executing command: \(error.localizedDescription)"
            }

        case "file_read":
            guard let path = params["path"]?.stringValue else {
                return "Error: missing 'path' parameter"
            }
            let fullPath = path.hasPrefix("/") ? path : root.appendingPathComponent(path).path
            do {
                let content = try String(contentsOfFile: fullPath, encoding: .utf8)
                return String(content.prefix(16000))
            } catch {
                return "Error reading file: \(error.localizedDescription)"
            }

        case "file_write":
            guard let path = params["path"]?.stringValue else {
                return "Error: missing 'path' parameter"
            }
            guard let content = params["content"]?.stringValue else {
                return "Error: missing 'content' parameter"
            }
            let fullPath = path.hasPrefix("/") ? path : root.appendingPathComponent(path).path
            let fileURL = URL(fileURLWithPath: fullPath)
            do {
                let dir = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
                return "File written: \(fullPath) (\(content.count) bytes)"
            } catch {
                return "Error writing file: \(error.localizedDescription)"
            }

        case "file_list":
            guard let path = params["path"]?.stringValue else {
                return "Error: missing 'path' parameter"
            }
            let fullPath = path.hasPrefix("/") ? path : root.appendingPathComponent(path).path
            do {
                let items = try FileManager.default.contentsOfDirectory(atPath: fullPath)
                return items.sorted().joined(separator: "\n")
            } catch {
                return "Error listing directory: \(error.localizedDescription)"
            }

        default:
            return "Unknown tool: \(name)"
        }
    }

    private func parseToolInput(_ raw: String) -> [String: JSONValue] {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: JSONValue] = [:]
        for (k, v) in json {
            if let s = v as? String { result[k] = .string(s) }
            else if let n = v as? Double { result[k] = .number(n) }
            else if let b = v as? Bool { result[k] = .bool(b) }
        }
        return result
    }

    // MARK: - Context Trimming

    private func trimConversation(_ history: inout [LLMMessage], budget: Int, systemPrompt: String) {
        var estimate = systemPrompt.count / 4 + 4096
        for msg in history { estimate += estimateMessageTokens(msg) }
        while estimate > budget && history.count > 2 {
            let removed = history.removeFirst()
            estimate -= estimateMessageTokens(removed)
        }
    }

    // MARK: - Slash Commands

    private enum SlashResult { case handled, exit }

    private func handleSlashCommand(
        _ command: String,
        container: AppContainer,
        router: ModelRouter,
        totalCost: SessionCost,
        messageCount: Int,
        noColor: Bool,
        conversationHistory: inout [LLMMessage],
        root: URL,
        modelName: String,
        currentModel: inout String
    ) -> SlashResult {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1] : nil

        let bold = noColor ? "" : "\u{1B}[1m"
        let dim = noColor ? "" : "\u{1B}[2m"
        let cyan = noColor ? "" : "\u{1B}[36m"
        let yellow = noColor ? "" : "\u{1B}[33m"
        let reset = noColor ? "" : "\u{1B}[0m"

        switch cmd {
        case "/exit", "/quit", "/q":
            print("  \(dim)Goodbye.\(reset)")
            return .exit

        case "/help", "/h", "/?":
            let cmds: [(String, String)] = [
                ("/help", "Show this help"),
                ("/status", "Session info"),
                ("/cost", "Token and dollar cost"),
                ("/model [name]", "Show or switch model"),
                ("/tools", "Available tools"),
                ("/history", "Conversation info"),
                ("/reset", "Clear conversation"),
                ("/clear", "Clear screen"),
                ("/exit", "Quit"),
            ]
            print()
            print("  \(bold)Commands\(reset)")
            for (c, d) in cmds {
                let pad = String(repeating: " ", count: max(1, 20 - c.count))
                print("  \(cyan)\(c)\(reset)\(pad)\(d)")
            }

        case "/status":
            print()
            print("  \(bold)Session\(reset)")
            print("  Provider:  \(container.config.providers.resolvedProvider)")
            print("  Model:     \(modelName)")
            print("  Messages:  \(messageCount)")
            print("  History:   \(conversationHistory.count) messages")
            print("  \(totalCost.summary)")

        case "/cost":
            print("  \(totalCost.summary)")

        case "/model":
            if let alias = arg {
                if let desc = ModelCatalog.findByAlias(alias) {
                    currentModel = desc.id
                    print("  Model: \(bold)\(desc.displayName)\(reset) \(dim)(next message)\(reset)")
                } else {
                    print("  Unknown model. Try: opus, sonnet, haiku")
                }
            } else {
                print("  Current: \(bold)\(modelName)\(reset)")
                print("  Available: opus, sonnet, haiku")
            }

        case "/tools":
            let tools: [(String, String)] = [
                ("shell_run", "Execute shell commands"),
                ("file_read", "Read file contents"),
                ("file_list", "List directory"),
            ]
            print()
            print("  \(bold)Tools\(reset) (agent uses these automatically)")
            for (name, desc) in tools {
                let pad = String(repeating: " ", count: max(1, 16 - name.count))
                print("  \(cyan)\(name)\(reset)\(pad)\(desc)")
            }

        case "/history":
            let turns = conversationHistory.filter { $0.role == .user }.count
            let tokens = conversationHistory.reduce(0) { $0 + estimateMessageTokens($1) }
            print("  Turns: \(turns)  Messages: \(conversationHistory.count)  Tokens: ~\(tokens)")

        case "/reset":
            let n = conversationHistory.count
            conversationHistory.removeAll()
            print("  \(yellow)History cleared\(reset) (\(n) messages removed)")

        case "/clear":
            print("\u{1B}[2J\u{1B}[H", terminator: "")
            fflush(stdout)
            return .handled

        case "/version":
            print("  \(ZyquoInfo.versionString)")

        default:
            let known = ["/help", "/status", "/exit", "/clear", "/cost", "/model",
                         "/tools", "/version", "/reset", "/history"]
            if let best = known.min(by: { levenshtein($0, cmd) < levenshtein($1, cmd) }),
               levenshtein(best, cmd) <= 2 {
                print("  Unknown '\(cmd)'. Did you mean \(cyan)\(best)\(reset)?")
            } else {
                print("  Unknown '\(cmd)'. Type \(cyan)/help\(reset) for commands.")
            }
        }

        print()
        return .handled
    }

    // MARK: - Helpers

    private func estimateMessageTokens(_ msg: LLMMessage) -> Int {
        var chars = 0
        for block in msg.content {
            switch block {
            case .text(let s): chars += s.count
            case .thinking(let s): chars += s.count
            case .toolUse(_, let n, _): chars += n.count + 50
            case .toolResult(_, let c, _): chars += c.count
            case .image: chars += 1000
            }
        }
        return max(1, chars / 4)
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let ac = Array(a), bc = Array(b)
        let m = ac.count, n = bc.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n), curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = ac[i-1] == bc[j-1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j-1] + 1, prev[j-1] + cost)
            }
            prev = curr
        }
        return prev[n]
    }
}
