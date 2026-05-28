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

    private static let toolSchemas: [ToolSchema] = ZTPToolSchemas.allSchemas() + [
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

        // Set window title
        if !noColor {
            Terminal.setWindowTitle("Zyquo \u{2014} \(root.lastPathComponent)")
            Terminal.setCursorShape(.bar)
        }

        // Enable persistent status bar
        let writer = StreamWriter(theme: ThemeEngine().load(named: container.config.ui.theme), noColor: noColor)
        let statusBar = StatusBarManager(writer: writer)
        await statusBar.enable()
        await statusBar.update(StatusBarManager.Content(
            left: "\(root.lastPathComponent)",
            center: modelName,
            right: "$0.0000"
        ))

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
        let reset = noColor ? "" : "\u{1B}[0m"

        // Interactive box renderer for beautiful TUI
        let boxRenderer = InteractiveBoxRenderer(
            theme: ThemeEngine().load(named: container.config.ui.theme),
            noColor: noColor
        )

        // REPL loop
        while true {
            boxRenderer.renderPrompt()

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
                    currentModel: &currentModel,
                    boxRenderer: boxRenderer
                )
                if result == .exit { break }
                continue
            }

            // Show user input in a box
            boxRenderer.renderUserInput(trimmed)

            // Send to LLM with tools
            messageCount += 1

            guard let resolved = await router.resolveExplicit(providerId: providerName, modelId: currentModel) else {
                boxRenderer.renderError(
                    "No provider available",
                    hint: "Run: zyquo provider login \(providerName) --key YOUR_KEY"
                )
                continue
            }

            let descriptor = ModelCatalog.find(id: resolved.model) ?? ModelCatalog.claudeSonnet4_6
            conversationHistory.append(.user(trimmed))

            let currentModelDisplay = ModelCatalog.findByAlias(currentModel)?.displayName ?? currentModel

            // Trim history if over 80% of context window
            let systemPrompt = """
            You are Zyquo, a powerful native macOS AI terminal agent. You have full shell access and can interact with the entire macOS system.

            CRITICAL RULES:
            - ALWAYS use your tools to execute actions — NEVER just suggest commands for the user to run manually.
            - ALWAYS prefer ZTP tools (ztp_*) over shell scripts or workarounds when a ZTP tool exists for the task.
            - ZTP tools are the native execution layer. You reason and plan; ZTP tools produce artifacts.

            ## ZTP Tools (Zyquo Tool Protocol)
            You have access to professional document/media/system tools via ZTP:

            | Tool | Use For | Key Commands |
            |------|---------|-------------|
            | ztp_excel | Spreadsheets, XLSX reports, data tables | build, inspect, import-csv |
            | ztp_docx | Word documents, reports, proposals | build, inspect |
            | ztp_slides | PowerPoint presentations, decks | build, inspect |
            | ztp_chart | Charts/graphs as PNG/SVG/PDF (bar, line, pie, scatter, area) | build, themes |
            | ztp_mail | Email drafting and sending (SMTP + Apple Mail) | draft, send, apple-draft |
            | ztp_message | iMessage/SMS via Apple Messages | draft, send |
            | ztp_browser | Web screenshots, PDF export, scraping, link extraction | screenshot, pdf, html, text, links |
            | ztp_macos | macOS: files, clipboard, apps, screenshots, AppleScript, Shortcuts | system-info, files-*, clipboard-*, apps-*, applescript-run |

            ### How to use ZTP tools:
            1. Call the tool with `command` parameter (e.g., "build")
            2. For document generation: pass `spec` (inline JSON) or `spec_file` (path) + `output` (file path)
            3. All responses are JSON — check `ok: true` before continuing
            4. Chain tools: generate data → chart → embed in slides/docx

            ### ZTP Spec Formats:
            - Excel: `{"version":"ztp-excel/0.1","workbook":{"title":"..."},"sheets":[{"name":"...","cells":[{"address":"A1","value":"..."}]}]}`
            - Chart: `{"version":"ztp-chart/0.1","chart":{"type":"bar","title":"...","width":1000,"height":600},"data":{"values":[...]},"x":{"field":"..."},"series":[{"field":"...","label":"..."}]}`
            - Docx: `{"version":"ztp-docx/0.1","document":{"title":"..."},"sections":[{"elements":[{"type":"heading","level":1,"text":"..."},{"type":"paragraph","runs":[{"text":"..."}]}]}]}`
            - Slides: `{"version":"ztp-slides/0.1","presentation":{"title":"..."},"slides":[...]}`
            - Mail: `{"version":"ztp-mail/0.1","message":{"from":"...","to":["..."],"subject":"...","body":{"type":"markdown","content":"..."}}}`
            - Message: `{"version":"ztp-message/0.1","message":{"channel":"imessage","to":[{"name":"...","address":"..."}],"body":{"type":"plain","content":"..."}}}`

            ## Shell & macOS
            - Use shell_run for general commands (ls, cat, grep, git, etc.)
            - Use `osascript` via shell_run for Apple automation not covered by ztp_macos
            - Use `open` to launch apps and URLs
            - You can read, write, and delete files anywhere the user has permission

            Workspace: \(root.path)
            User: \(NSUserName())

            Be concise. Act decisively. Use tools proactively. ALWAYS prefer ZTP tools when they exist.
            """
            trimConversation(&conversationHistory, budget: Int(Double(descriptor.contextWindow) * 0.8), systemPrompt: systemPrompt)

            // Tool-use loop: keep calling LLM until it stops requesting tools
            var loopCount = 0
            let maxLoops = 10
            var responseStarted = false

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
                            if !responseStarted {
                                boxRenderer.renderResponseStart(model: currentModelDisplay)
                                responseStarted = true
                            }
                            fullText += text
                            boxRenderer.renderResponseDelta(text)
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
                            if responseStarted {
                                boxRenderer.renderResponseEnd()
                                responseStarted = false
                            }
                            boxRenderer.renderError(err.description)
                        default:
                            break
                        }
                    }
                } catch {
                    if responseStarted {
                        boxRenderer.renderResponseEnd()
                        responseStarted = false
                    }
                    let msg = (error as? ZyquoError)?.description ?? error.localizedDescription
                    boxRenderer.renderError(msg)
                    break
                }

                if !fullText.isEmpty && responseStarted {
                    boxRenderer.renderResponseEnd()
                    responseStarted = false
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
                    let result = await executeTool(
                        name: tc.name,
                        input: tc.input,
                        root: root,
                        shellExecutor: shellExecutor
                    )

                    let truncated = String(result.prefix(8000))
                    let isError = result.hasPrefix("Error")
                    toolResultBlocks.append(.toolResult(toolUseId: tc.id, content: truncated, isError: isError))

                    let preview = String(result.prefix(200)).replacingOccurrences(of: "\n", with: " ")
                    boxRenderer.renderToolCall(
                        name: tc.name,
                        preview: preview + (result.count > 200 ? "..." : ""),
                        isError: isError
                    )
                }

                conversationHistory.append(LLMMessage(role: .user, content: toolResultBlocks))
            }

            // Session stats footer
            boxRenderer.renderSessionStats(
                tokens: "\(totalCost.totalInputTokens) in / \(totalCost.totalOutputTokens) out",
                cost: totalCost.formattedCost,
                requests: "\(totalCost.requests)"
            )
            boxRenderer.renderSeparator()

            // Update status bar with latest cost and token info
            await statusBar.update(StatusBarManager.Content(
                left: "\(root.lastPathComponent)",
                center: "\(currentModelDisplay) \u{2022} \(totalCost.totalInputTokens + totalCost.totalOutputTokens) tok",
                right: totalCost.formattedCost
            ))
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
            if name.hasPrefix("ztp_") {
                return await executeZTPTool(name: name, params: params, root: root)
            }
            return "Unknown tool: \(name)"
        }
    }

    private func executeZTPTool(
        name: String,
        params: [String: JSONValue],
        root: URL
    ) async -> String {
        let ztpToolName = String(name.dropFirst(4))  // "ztp_excel" -> "excel"
        let ztpBinary = "/opt/homebrew/bin/ztp"

        guard FileManager.default.isExecutableFile(atPath: ztpBinary) else {
            return "Error: ZTP binary not found at \(ztpBinary). Install with: brew install ztp"
        }

        let command = params["command"]?.stringValue ?? "build"
        let specJSON = params["spec"]?.stringValue
        let specFile = params["spec_file"]?.stringValue
        let output = params["output"]?.stringValue
        let confirmed = params["confirmed"]?.asBool ?? false

        var args: [String] = [ztpToolName, command]

        if let spec = specJSON {
            let tmpPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("zyquo-ztp-\(UUID().uuidString).json")
            do {
                try spec.write(to: tmpPath, atomically: true, encoding: .utf8)
                args.append(tmpPath.path)
                defer { try? FileManager.default.removeItem(at: tmpPath) }
            } catch {
                return "Error writing temp spec: \(error.localizedDescription)"
            }
        } else if let file = specFile {
            args.append(file)
        }

        if let out = output { args += ["--output", out] }
        if confirmed { args.append("--confirmed") }

        for (key, value) in params {
            let skip: Set = ["command", "spec", "spec_file", "output", "confirmed"]
            guard !skip.contains(key) else { continue }
            let flag = "--\(key.replacingOccurrences(of: "_", with: "-"))"
            switch value {
            case .string(let s): args += [flag, s]
            case .number(let n): args += [flag, n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : "\(n)"]
            case .bool(let b): if b { args.append(flag) }
            default: break
            }
        }

        args.append("--json")

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: ztpBinary)
        process.arguments = args
        process.currentDirectoryURL = root
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Error executing ztp \(ztpToolName): \(error.localizedDescription)"
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        var result = String(data: outData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            if !errStr.isEmpty { result += "\n[stderr] \(errStr)" }
            result += "\n[exit code: \(process.terminationStatus)]"
        }

        return result.isEmpty ? "(no output)" : String(result.prefix(12000))
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
        currentModel: inout String,
        boxRenderer: InteractiveBoxRenderer
    ) -> SlashResult {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1] : nil

        let dim = noColor ? "" : "\u{1B}[2m"
        let reset = noColor ? "" : "\u{1B}[0m"

        switch cmd {
        case "/exit", "/quit", "/q":
            print("  \(dim)Goodbye.\(reset)")
            Terminal.setCursorShape(.block)
            return .exit

        case "/help", "/h", "/?":
            boxRenderer.renderListPanel(title: "Commands", entries: [
                ("/help", "Show this help"),
                ("/status", "Session info"),
                ("/cost", "Token and dollar cost"),
                ("/model [name]", "Show or switch model"),
                ("/tools", "Available tools"),
                ("/history", "Conversation info"),
                ("/reset", "Clear conversation"),
                ("/clear", "Clear screen"),
                ("/exit", "Quit"),
            ])

        case "/status":
            boxRenderer.renderCommandResult(title: "Session", items: [
                ("Provider", container.config.providers.resolvedProvider),
                ("Model", modelName),
                ("Messages", "\(messageCount)"),
                ("History", "\(conversationHistory.count) messages"),
                ("Cost", totalCost.formattedCost),
            ])

        case "/cost":
            boxRenderer.renderCommandResult(title: "Cost", items: [
                ("Input tokens", "\(totalCost.totalInputTokens)"),
                ("Output tokens", "\(totalCost.totalOutputTokens)"),
                ("Total cost", totalCost.formattedCost),
                ("Requests", "\(totalCost.requests)"),
            ])

        case "/model":
            if let alias = arg {
                if let desc = ModelCatalog.findByAlias(alias) {
                    currentModel = desc.id
                    boxRenderer.renderCommandResult(title: "Model", items: [
                        ("Switched to", desc.displayName),
                        ("Effective", "next message"),
                    ])
                } else {
                    boxRenderer.renderError("Unknown model '\(alias)'", hint: "Try: opus, sonnet, haiku")
                }
            } else {
                boxRenderer.renderCommandResult(title: "Model", items: [
                    ("Current", modelName),
                    ("Available", "opus, sonnet, haiku"),
                ])
            }

        case "/tools":
            boxRenderer.renderListPanel(title: "Tools (auto)", entries: [
                ("shell_run", "Execute shell commands"),
                ("file_read", "Read file contents"),
                ("file_write", "Write file contents"),
                ("file_list", "List directory"),
                ("ztp_excel", "Spreadsheets & XLSX"),
                ("ztp_docx", "Word documents"),
                ("ztp_slides", "Presentations"),
                ("ztp_chart", "Charts & graphs"),
                ("ztp_mail", "Email drafting"),
                ("ztp_message", "iMessage/SMS"),
                ("ztp_browser", "Web scraping"),
                ("ztp_macos", "macOS automation"),
            ])

        case "/history":
            let turns = conversationHistory.filter { $0.role == .user }.count
            let tokens = conversationHistory.reduce(0) { $0 + estimateMessageTokens($1) }
            boxRenderer.renderCommandResult(title: "History", items: [
                ("Turns", "\(turns)"),
                ("Messages", "\(conversationHistory.count)"),
                ("Tokens (est.)", "~\(tokens)"),
            ])

        case "/reset":
            let n = conversationHistory.count
            conversationHistory.removeAll()
            boxRenderer.renderCommandResult(title: "Reset", items: [
                ("Cleared", "\(n) messages removed"),
            ])

        case "/clear":
            print("\u{1B}[2J\u{1B}[H", terminator: "")
            fflush(stdout)
            return .handled

        case "/version":
            boxRenderer.renderCommandResult(title: "Version", items: [
                ("Zyquo", ZyquoInfo.versionString),
            ])

        default:
            let known = ["/help", "/status", "/exit", "/clear", "/cost", "/model",
                         "/tools", "/version", "/reset", "/history"]
            if let best = known.min(by: { levenshtein($0, cmd) < levenshtein($1, cmd) }),
               levenshtein(best, cmd) <= 2 {
                boxRenderer.renderError("Unknown command '\(cmd)'", hint: "Did you mean \(best)?")
            } else {
                boxRenderer.renderError("Unknown command '\(cmd)'", hint: "Type /help for available commands")
            }
        }

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
