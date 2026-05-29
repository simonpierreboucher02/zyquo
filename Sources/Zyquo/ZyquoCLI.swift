import ArgumentParser
import Foundation
import ZyquoCore

@main
struct ZyquoCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zyquo",
        abstract: "Native macOS AI terminal agent runtime",
        discussion: """
        GLOBAL OPTIONS (available on all subcommands):
          --workspace <path>    Override workspace root
          --no-color            Disable ANSI color output
          --json                Machine-readable JSON output
          -y, --yes             Auto-approve SAFE-tier actions
          --dry-run             Plan but never execute
          --model <model>       Override session model (opus, sonnet, haiku)
          --provider <id>       Override session provider (anthropic, openrouter)
          --max-steps <n>       Hard cap on agent steps
          --max-cost <usd>      Hard cap on session cost (USD)
          -v, --verbose         Increase log verbosity
          -q, --quiet           Suppress non-essential output
          --log-file <path>     Mirror logs to file

        QUICK START:
          zyquo provider login anthropic    Store your API key
          zyquo doctor                      Check setup
          zyquo ask "explain this repo"     Single-shot question
          zyquo run "fix failing tests"     Agentic run with tools
          zyquo                             Interactive REPL
        """,
        version: ZyquoInfo.versionString,
        subcommands: [
            InteractiveCommand.self,
            AskCommand.self,
            RunCommand.self,
            PlanCommand.self,
            InitCommand.self,
            DoctorCommand.self,
            ConfigCommand.self,
            ProviderCommand.self,
            ModelsCommand.self,
            StatusCommand.self,
            SessionsCommand.self,
            MemoryCommand.self,
            ToolsCommand.self,
            SkillCommand.self,
            NudgesCommand.self,
            WorkflowCommand.self,
            ClusterCommand.self,
            DaemonCommand.self,
            VersionCommand.self,
        ],
        defaultSubcommand: InteractiveCommand.self
    )

    struct GlobalOptions: ParsableArguments {
        @Option(name: .long, help: "Override workspace root")
        var workspace: String?

        @Flag(name: .long, help: "Disable ANSI color output")
        var noColor: Bool = false

        @Flag(name: .long, help: "Machine-readable JSON output")
        var json: Bool = false

        @Flag(name: .shortAndLong, help: "Auto-approve SAFE-tier actions")
        var yes: Bool = false

        @Flag(name: .long, help: "Plan but never execute")
        var dryRun: Bool = false

        @Option(name: .long, help: "Override session model")
        var model: String?

        @Option(name: .long, help: "Override session provider")
        var provider: String?

        @Option(name: .long, help: "Hard cap on agent steps")
        var maxSteps: Int?

        @Option(name: .long, help: "Hard cap on session cost (USD)")
        var maxCost: Double?

        @Flag(name: .shortAndLong, help: "Increase log verbosity")
        var verbose: Bool = false

        @Flag(name: .shortAndLong, help: "Suppress non-essential output")
        var quiet: Bool = false

        @Option(name: .long, help: "Mirror logs to file")
        var logFile: String?

        var flags: CommandFlags {
            CommandFlags(
                workspace: workspace,
                noColor: noColor,
                json: json,
                yes: yes,
                dryRun: dryRun,
                model: model,
                provider: provider,
                maxSteps: maxSteps,
                maxCost: maxCost,
                verbose: verbose,
                quiet: quiet,
                logFile: logFile
            )
        }
    }
}
