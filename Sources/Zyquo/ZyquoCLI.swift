import ArgumentParser
import Foundation
import ZyquoCore

@main
struct ZyquoCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zyquo",
        abstract: "Native macOS AI terminal agent runtime",
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
