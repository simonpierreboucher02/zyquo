import ArgumentParser
import Foundation

struct MemoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "memory",
        abstract: "Inspect and manage project memory",
        subcommands: [
            MemoryOverview.self,
            MemoryEdit.self,
            MemoryCompact.self,
        ],
        defaultSubcommand: MemoryOverview.self
    )

    struct MemoryOverview: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "overview",
            abstract: "Show memory overview"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
            let memoryDir = root
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("memory")
            let sessionsDir = memoryDir.appendingPathComponent("sessions")

            let fm = FileManager.default

            print()
            print("  \u{1B}[1mMemory Overview\u{1B}[0m")
            print("  \(String(repeating: "\u{2500}", count: 50))")

            // Project memory
            let projectPath = memoryDir.appendingPathComponent("project.md")
            if fm.fileExists(atPath: projectPath.path),
               let content = try? String(contentsOf: projectPath, encoding: .utf8) {
                let pm = ProjectMemory(content: content)
                let sectionNames = pm.sections.map(\.title).joined(separator: ", ")
                print("  Project Memory:   \(pm.sections.count) section(s)")
                if !sectionNames.isEmpty {
                    print("    Sections: \(sectionNames)")
                }
            } else {
                print("  Project Memory:   not found")
                print("    Run \u{1B}[1mzyquo init\u{1B}[0m to create project memory.")
            }

            // Architecture
            let archPath = memoryDir.appendingPathComponent("architecture.md")
            if fm.fileExists(atPath: archPath.path) {
                let attrs = try? fm.attributesOfItem(atPath: archPath.path)
                let size = (attrs?[.size] as? Int) ?? 0
                print("  Architecture:     present (\(size) bytes)")
            } else {
                print("  Architecture:     not yet generated")
            }

            // Decisions
            let decisionsPath = memoryDir.appendingPathComponent("decisions.md")
            if fm.fileExists(atPath: decisionsPath.path),
               let content = try? String(contentsOf: decisionsPath, encoding: .utf8) {
                // Count decision entries by counting ## headings (excluding the first # heading)
                let decisionCount = content.components(separatedBy: "\n")
                    .filter { $0.hasPrefix("## ") }
                    .count
                print("  Decisions:        \(decisionCount) recorded")
            } else {
                print("  Decisions:        none recorded")
            }

            // Sessions
            if fm.fileExists(atPath: sessionsDir.path) {
                let store = SessionStore(baseDir: sessionsDir)
                let sessions = await store.list(limit: 1000)
                print("  Sessions:         \(sessions.count) stored")
            } else {
                print("  Sessions:         none")
            }

            print("  \(String(repeating: "\u{2500}", count: 50))")
            print("  Memory dir: \(memoryDir.path)")
            print()
        }
    }

    struct MemoryEdit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "edit",
            abstract: "Open project memory in $EDITOR"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
            let projectPath = root
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("memory")
                .appendingPathComponent("project.md")

            let fm = FileManager.default
            guard fm.fileExists(atPath: projectPath.path) else {
                print("  Project memory not found at \(projectPath.path)")
                print("  Run \u{1B}[1mzyquo init\u{1B}[0m first.")
                return
            }

            let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [editor, projectPath.path]
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            try process.run()
            process.waitUntilExit()
        }
    }

    struct MemoryCompact: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compact",
            abstract: "Force compression pass on memory"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            print("  Memory compaction is not yet fully implemented.")
            print("  This will compress session memory to reduce token usage.")
        }
    }
}
