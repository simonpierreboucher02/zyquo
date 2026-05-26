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

    func run() async throws {
        Bootstrap.setupSignalHandlers()
        Bootstrap.ensureDirectories()

        let container = AppContainer(flags: globals.flags)
        container.logger.info("Starting interactive mode")

        let noColor = container.config.ui.noColor
        let size = Terminal.size

        // Print header
        print(renderHeader(width: size.width, config: container.config))
        print()

        // Print workspace summary
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let workspace = Workspace(root: root)
        let wsIndex = await workspace.scan()
        if !noColor {
            print("  \u{1B}[2m\(wsIndex.summaryCard.replacingOccurrences(of: "\n", with: "\n  "))\u{1B}[0m")
        } else {
            print("  \(wsIndex.summaryCard.replacingOccurrences(of: "\n", with: "\n  "))")
        }
        print()

        // Set up provider for ask-style queries
        let router = ModelRouter(config: container.config.providers)
        await router.register(AnthropicProvider())
        await router.register(OpenRouterProvider())

        // Session state
        var totalCost = SessionCost()
        var messageCount = 0
        var history: [String] = []

        // Print help hint
        if !noColor {
            print("  \u{1B}[2mType a question or command. Type /help for commands, /exit to quit.\u{1B}[0m")
        } else {
            print("  Type a question or command. Type /help for commands, /exit to quit.")
        }
        print()

        // REPL loop
        while true {
            // Print prompt
            if !noColor {
                print("\u{1B}[1;36mzyquo>\u{1B}[0m ", terminator: "")
            } else {
                print("zyquo> ", terminator: "")
            }
            fflush(stdout)

            // Read input
            guard let line = readLine(strippingNewline: true) else {
                // Ctrl-D (EOF)
                print()
                printGoodbye(noColor: noColor)
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Add to history
            history.append(trimmed)

            // Handle slash commands
            if trimmed.hasPrefix("/") {
                let handled = await handleSlashCommand(
                    trimmed,
                    container: container,
                    router: router,
                    totalCost: totalCost,
                    messageCount: messageCount,
                    noColor: noColor,
                    wsIndex: wsIndex
                )
                if handled == .exit {
                    break
                }
                continue
            }

            // Regular input: send to LLM as ask-style query
            messageCount += 1

            let providerId = container.config.providers.resolvedProvider
            guard let resolved = await router.resolveExplicit(providerId: providerId) else {
                if !noColor {
                    print("  \u{1B}[31mNo provider configured. Run `zyquo provider login \(providerId)`\u{1B}[0m")
                } else {
                    print("  No provider configured. Run `zyquo provider login \(providerId)`")
                }
                print()
                continue
            }

            let descriptor = ModelCatalog.find(id: resolved.model) ?? ModelCatalog.claudeSonnet4_6

            let request = LLMRequest(
                model: resolved.model,
                systemPrompt: "You are Zyquo, a helpful AI terminal assistant for macOS. Answer concisely and accurately. The user is working in: \(root.path)",
                messages: [.user(trimmed)],
                maxTokens: 4096
            )

            let stream = resolved.provider.send(request: request, cancellation: nil)
            print()

            var lastUsage: TokenUsage?

            do {
                for try await event in stream {
                    switch event {
                    case .textDelta(let text):
                        print(text, terminator: "")
                        fflush(stdout)
                    case .usage(let usage):
                        lastUsage = usage
                    default:
                        break
                    }
                }
            } catch {
                print()
                if let ze = error as? ZyquoError {
                    if !noColor {
                        print("  \u{1B}[31mError: \(ze.description)\u{1B}[0m")
                    } else {
                        print("  Error: \(ze.description)")
                    }
                } else {
                    if !noColor {
                        print("  \u{1B}[31mError: \(error.localizedDescription)\u{1B}[0m")
                    } else {
                        print("  Error: \(error.localizedDescription)")
                    }
                }
            }

            print()

            if let usage = lastUsage {
                totalCost.record(usage: usage, model: descriptor)
                if !noColor {
                    print("  \u{1B}[2m\(totalCost.summary)\u{1B}[0m")
                } else {
                    print("  \(totalCost.summary)")
                }
            }
            print()
        }
    }

    // MARK: - Slash Commands

    private enum SlashResult {
        case handled
        case exit
    }

    private func handleSlashCommand(
        _ command: String,
        container: AppContainer,
        router: ModelRouter,
        totalCost: SessionCost,
        messageCount: Int,
        noColor: Bool,
        wsIndex: WorkspaceIndex
    ) async -> SlashResult {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1] : nil

        switch cmd {
        case "/exit", "/quit", "/q":
            printGoodbye(noColor: noColor)
            return .exit

        case "/help", "/h", "/?":
            printHelp(noColor: noColor)

        case "/status":
            printStatus(
                container: container,
                totalCost: totalCost,
                messageCount: messageCount,
                noColor: noColor,
                wsIndex: wsIndex
            )

        case "/clear":
            // Clear screen but preserve state
            print("\u{1B}[2J\u{1B}[H", terminator: "")
            fflush(stdout)

        case "/cost":
            if !noColor {
                print("  \u{1B}[1mSession Cost\u{1B}[0m")
                print("  \(totalCost.summary)")
            } else {
                print("  Session Cost")
                print("  \(totalCost.summary)")
            }

        case "/model":
            if let newModel = arg {
                if let descriptor = ModelCatalog.findByAlias(newModel) {
                    if !noColor {
                        print("  Model switched to: \u{1B}[1m\(descriptor.displayName)\u{1B}[0m")
                    } else {
                        print("  Model switched to: \(descriptor.displayName)")
                    }
                    print("  \u{1B}[2m(Note: model override applies from next message)\u{1B}[0m")
                } else {
                    print("  Unknown model '\(newModel)'. Available: opus, sonnet, haiku")
                }
            } else {
                print("  Current model: \(container.config.providers.resolvedModel)")
                print("  Available: opus (claude-opus-4-7), sonnet (claude-sonnet-4-6), haiku (claude-haiku-4-5)")
            }

        case "/tools":
            printTools(noColor: noColor)

        case "/theme":
            let engine = ThemeEngine()
            let available = engine.availableThemes()
            if let name = arg {
                if available.contains(name) {
                    print("  Theme set to: \(name)")
                    print("  (Takes effect on next render)")
                } else {
                    print("  Unknown theme '\(name)'. Available: \(available.joined(separator: ", "))")
                }
            } else {
                print("  Current theme: \(container.config.ui.theme)")
                print("  Available: \(available.joined(separator: ", "))")
            }

        case "/version":
            print("  \(ZyquoInfo.versionString)")

        default:
            // Fuzzy match suggestion
            let known = ["/help", "/status", "/exit", "/clear", "/cost", "/model", "/tools", "/theme", "/version"]
            let suggestion = known.min(by: { levenshtein($0, cmd) < levenshtein($1, cmd) })
            if let suggestion, levenshtein(suggestion, cmd) <= 2 {
                print("  Unknown command '\(cmd)'. Did you mean '\(suggestion)'?")
            } else {
                print("  Unknown command '\(cmd)'. Type /help for available commands.")
            }
        }

        print()
        return .handled
    }

    // MARK: - Display Helpers

    private func printHelp(noColor: Bool) {
        let commands: [(String, String)] = [
            ("/help", "Show this help"),
            ("/status", "Show workspace, provider, and session info"),
            ("/cost", "Show cumulative token and dollar cost"),
            ("/model [name]", "Show or switch model (opus, sonnet, haiku)"),
            ("/tools", "List registered tools with risk levels"),
            ("/theme [name]", "Show or switch theme"),
            ("/clear", "Clear screen (preserve session state)"),
            ("/version", "Show version"),
            ("/exit", "Save session and exit"),
        ]

        if !noColor {
            print("  \u{1B}[1mCommands\u{1B}[0m")
        } else {
            print("  Commands")
        }
        for (cmd, desc) in commands {
            let padding = String(repeating: " ", count: max(1, 20 - cmd.count))
            if !noColor {
                print("  \u{1B}[36m\(cmd)\u{1B}[0m\(padding)\(desc)")
            } else {
                print("  \(cmd)\(padding)\(desc)")
            }
        }
    }

    private func printStatus(
        container: AppContainer,
        totalCost: SessionCost,
        messageCount: Int,
        noColor: Bool,
        wsIndex: WorkspaceIndex
    ) {
        if !noColor {
            print("  \u{1B}[1mSession Status\u{1B}[0m")
        } else {
            print("  Session Status")
        }
        print("  Provider: \(container.config.providers.resolvedProvider)")
        print("  Model: \(container.config.providers.resolvedModel)")
        print("  Messages: \(messageCount)")
        print("  \(totalCost.summary)")
        if let lang = wsIndex.primaryLanguage {
            print("  Primary language: \(lang.displayName)")
        }
        print("  Files indexed: \(wsIndex.fileCount)")
    }

    private func printTools(noColor: Bool) {
        let tools: [(String, String, String)] = [
            ("shell.run", "MODERATE+", "Execute shell commands"),
            ("file.read", "SAFE", "Read file contents"),
            ("file.list", "SAFE", "List directory contents"),
            ("file.search", "SAFE", "Ripgrep-backed search"),
            ("git.status", "SAFE", "Read git status"),
            ("git.diff", "SAFE", "Read git diff"),
        ]
        if !noColor {
            print("  \u{1B}[1mRegistered Tools\u{1B}[0m")
        } else {
            print("  Registered Tools")
        }
        for (name, risk, desc) in tools {
            let padding = String(repeating: " ", count: max(1, 18 - name.count))
            if !noColor {
                print("  \u{1B}[36m\(name)\u{1B}[0m\(padding)[\(risk)] \(desc)")
            } else {
                print("  \(name)\(padding)[\(risk)] \(desc)")
            }
        }
    }

    private func printGoodbye(noColor: Bool) {
        if !noColor {
            print("  \u{1B}[2mGoodbye.\u{1B}[0m")
        } else {
            print("  Goodbye.")
        }
    }

    // MARK: - Header

    private func renderHeader(width: Int, config: Config) -> String {
        let noColor = config.ui.noColor
        let border = noColor ? "-" : "\u{2500}"
        let tl = noColor ? "+" : "\u{256D}"
        let tr = noColor ? "+" : "\u{256E}"
        let bl = noColor ? "+" : "\u{2570}"
        let br = noColor ? "+" : "\u{256F}"
        let v = noColor ? "|" : "\u{2502}"

        let innerWidth = min(width - 2, 62)
        let title = " Zyquo Agent "
        let titlePad = innerWidth - title.count
        let leftPad = titlePad / 2
        let rightPad = titlePad - leftPad

        let topBorder = tl + String(repeating: border, count: leftPad) + title + String(repeating: border, count: rightPad) + tr

        let ws = "Workspace: \(FileManager.default.currentDirectoryPath)"
        let model = "Model: \(config.providers.resolvedModel)"
        let mode = "Mode: Interactive"
        let status = "Status: Ready"

        func pad(_ left: String, _ right: String) -> String {
            let content = " \(left)"
            let rightPart = "\(right) "
            let space = max(1, innerWidth - content.count - rightPart.count)
            return v + content + String(repeating: " ", count: space) + rightPart + v
        }

        let bottomBorder = bl + String(repeating: border, count: innerWidth) + br

        return [
            topBorder,
            pad(ws, model),
            pad(mode, status),
            bottomBorder,
        ].joined(separator: "\n")
    }

    // MARK: - Levenshtein Distance

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,        // deletion
                    curr[j - 1] + 1,     // insertion
                    prev[j - 1] + cost   // substitution
                )
            }
            prev = curr
        }
        return prev[n]
    }
}
