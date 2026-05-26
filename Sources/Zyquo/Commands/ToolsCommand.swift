import ArgumentParser
import Foundation

// MARK: - ToolsCommand

/// List and manage registered tools.
///
/// Shows all registered tools with their risk levels, mutation status,
/// and enabled/disabled state.
///
/// Reference: CLAUDE.md §10.1
struct ToolsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tools",
        abstract: "List and manage registered tools",
        subcommands: [
            ListTools.self,
        ],
        defaultSubcommand: ListTools.self
    )

    // MARK: - List Subcommand

    struct ListTools: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all registered tools with risk levels"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            // Build a registry with all known tools
            let registry = ToolRegistry()
            registerBuiltinTools(in: registry)

            let tools = registry.allTools()
            if tools.isEmpty {
                print("No tools registered.")
                return
            }

            // Header
            if noColor {
                print("Registered Tools (\(tools.count)):")
                print(String(repeating: "-", count: 70))
            } else {
                print("\u{1B}[1mRegistered Tools (\(tools.count)):\u{1B}[0m")
                print("\u{1B}[2m\(String(repeating: "-", count: 70))\u{1B}[0m")
            }

            let maxNameLen = tools.map(\.name.count).max() ?? 12

            for tool in tools {
                let name = tool.name.padding(toLength: maxNameLen + 2, withPad: " ", startingAt: 0)
                let risk = tool.defaultRisk.displayName
                let mut = tool.isMutating ? "W" : "R"

                if noColor {
                    print("  \(name) [\(risk)] [\(mut)] \(tool.summary)")
                } else {
                    let riskColor = colorForRisk(tool.defaultRisk)
                    print("  \u{1B}[1m\(name)\u{1B}[0m \(riskColor)[\(risk)]\u{1B}[0m [\(mut)] \u{1B}[2m\(tool.summary)\u{1B}[0m")
                }
            }
        }

        private func colorForRisk(_ risk: RiskLevel) -> String {
            switch risk {
            case .safe: return "\u{1B}[32m"       // green
            case .moderate: return "\u{1B}[33m"    // yellow
            case .dangerous: return "\u{1B}[31m"   // red
            case .critical: return "\u{1B}[1;31m"  // bold red
            }
        }
    }
}

// MARK: - Builtin Tool Registration

/// Register all built-in tools in the given registry.
func registerBuiltinTools(in registry: ToolRegistry) {
    registry.registerAll([
        WebSearchTool(),
        WebFetchTool(),
        HttpRequestTool(),
        DatabaseTool(),
        DocSearchTool(),
    ])
}
