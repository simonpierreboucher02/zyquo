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

        let co = CommandOutput(noColor: noColor)
        co.header(title: "Workspace", subtitle: root.path)
        co.blank()

        if !index.languages.isEmpty {
            let langStr = index.languages.prefix(3).map { "\($0.0.displayName) (\(Int($0.1 * 100))%)" }.joined(separator: ", ")
            co.keyValue("Languages", langStr)
        }

        if !index.frameworks.isEmpty {
            co.keyValue("Frameworks", index.frameworks.map(\.displayName).joined(separator: ", "))
        }

        if let pm = index.packageManager {
            co.keyValue("Package Manager", pm.displayName)
        }

        if let test = index.testCommand {
            co.keyValue("Test", test)
        }

        if let build = index.buildCommand {
            co.keyValue("Build", build)
        }

        if let git = index.gitStatus {
            var gitParts = [String]()
            if let branch = git.branch { gitParts.append(branch) }
            if git.isClean {
                gitParts.append("clean")
            } else {
                var changes = [String]()
                if git.stagedCount > 0 { changes.append("\(git.stagedCount) staged") }
                if git.unstagedCount > 0 { changes.append("\(git.unstagedCount) modified") }
                if git.untrackedCount > 0 { changes.append("\(git.untrackedCount) untracked") }
                gitParts.append(changes.joined(separator: ", "))
            }
            if git.ahead > 0 { gitParts.append("\u{2191}\(git.ahead)") }
            if git.behind > 0 { gitParts.append("\u{2193}\(git.behind)") }
            co.keyValue("Git", gitParts.joined(separator: " \u{00B7} "))
        }

        co.keyValue("Files", "\(index.fileCount)")
        co.keyValue("Size", formatBytes(index.totalSize))

        if !index.documentation.isEmpty {
            co.keyValue("Docs", index.documentation.joined(separator: ", "))
        }

        co.blank()
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(bytes) B" }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
