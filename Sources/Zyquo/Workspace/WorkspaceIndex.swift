import Foundation

public struct WorkspaceIndex: Sendable {
    public let root: URL
    public let languages: [(Language, Float)]
    public let frameworks: [Framework]
    public let packageManager: PackageManager?
    public let testCommand: String?
    public let buildCommand: String?
    public let gitStatus: GitStatus?
    public let fileCount: Int
    public let totalSize: UInt64
    public let lastFullScan: Date
    public let documentation: [String]

    public var primaryLanguage: Language? { languages.first?.0 }

    public var summaryCard: String {
        var lines: [String] = []
        lines.append("Workspace: \(root.lastPathComponent)")

        if !languages.isEmpty {
            let langStr = languages.prefix(3).map { "\($0.0.displayName) (\(Int($0.1 * 100))%)" }.joined(separator: ", ")
            lines.append("Languages: \(langStr)")
        }

        if !frameworks.isEmpty {
            lines.append("Frameworks: \(frameworks.map(\.displayName).joined(separator: ", "))")
        }

        if let pm = packageManager {
            lines.append("Package Manager: \(pm.displayName)")
        }

        if let test = testCommand {
            lines.append("Test: \(test)")
        }

        if let build = buildCommand {
            lines.append("Build: \(build)")
        }

        if let git = gitStatus {
            var gitParts = [String]()
            if let branch = git.branch { gitParts.append(branch) }
            if git.isClean { gitParts.append("clean") }
            else {
                var changes = [String]()
                if git.stagedCount > 0 { changes.append("\(git.stagedCount) staged") }
                if git.unstagedCount > 0 { changes.append("\(git.unstagedCount) modified") }
                if git.untrackedCount > 0 { changes.append("\(git.untrackedCount) untracked") }
                gitParts.append(changes.joined(separator: ", "))
            }
            if git.ahead > 0 { gitParts.append("↑\(git.ahead)") }
            if git.behind > 0 { gitParts.append("↓\(git.behind)") }
            lines.append("Git: \(gitParts.joined(separator: " · "))")
        }

        lines.append("Files: \(fileCount) · Size: \(formatBytes(totalSize))")

        if !documentation.isEmpty {
            lines.append("Docs: \(documentation.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
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
