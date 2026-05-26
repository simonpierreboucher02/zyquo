import ArgumentParser
import Foundation

struct PlanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Plan-only mode (no execution)"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    @Argument(help: "Intent to plan")
    var intent: String

    func run() async throws {
        Bootstrap.setupSignalHandlers()
        let container = AppContainer(flags: globals.flags)
        container.logger.info("Plan mode", metadata: ["intent": "\(intent)"])

        print("Plan mode is not yet implemented. Agent runtime (Phase 8) required.")
    }
}
