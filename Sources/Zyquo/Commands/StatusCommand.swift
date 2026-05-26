import ArgumentParser
import Foundation

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show workspace analysis and agent state"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    func run() async throws {
        Bootstrap.setupSignalHandlers()
        let container = AppContainer(flags: globals.flags)
        let noColor = container.config.ui.noColor
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)

        let workspace = Workspace(root: root)
        let index = await workspace.scan()

        if noColor {
            print(index.summaryCard)
        } else {
            let lines = index.summaryCard.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("Workspace:") {
                    print("\u{1B}[1m\(line)\u{1B}[0m")
                } else if line.hasPrefix("Git:") {
                    print("\u{1B}[36m\(line)\u{1B}[0m")
                } else {
                    print("\u{1B}[2m\(line)\u{1B}[0m")
                }
            }
        }
    }
}
