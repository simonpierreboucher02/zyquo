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
            MemoryUser.self,
        ],
        defaultSubcommand: MemoryOverview.self
    )

    // MARK: - User Model Subcommand

    struct MemoryUser: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "user",
            abstract: "Show the persistent cross-session user model"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Flag(name: .long, help: "Open the user model in $EDITOR")
        var edit = false

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let store = UserModelStore()

            if edit {
                // Ensure the markdown mirror exists before editing.
                let model = await store.load()
                try? await store.save(model)
                let path = await store.markdownLocation()
                let editor = ProcessInfo.processInfo.environment["EDITOR"] ?? "vi"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [editor, path.path]
                process.standardInput = FileHandle.standardInput
                process.standardOutput = FileHandle.standardOutput
                process.standardError = FileHandle.standardError
                try process.run()
                process.waitUntilExit()
                return
            }

            let model = await store.load()
            print()
            print("  \u{1B}[1mUser Model\u{1B}[0m")
            print("  \(String(repeating: "\u{2500}", count: 50))")

            if model.observations.isEmpty && model.userEditedNotes.isEmpty {
                print("  Nothing learned yet.")
                print("  Zyquo builds this as you run agentic tasks (`zyquo run ...`).")
                print()
                return
            }

            for trait in UserTrait.allCases {
                let filtered: [UserObservation] = model.observations.filter {
                    $0.trait == trait && $0.confidence >= 0.2
                }
                let group: [UserObservation] = filtered.sorted { $0.confidence > $1.confidence }
                guard !group.isEmpty else { continue }
                print("  \u{1B}[36m\(trait.displayName)\u{1B}[0m")
                for obs in group {
                    let pct = Int((obs.confidence * 100).rounded())
                    print("    • \(obs.statement) \u{1B}[2m(\(pct)%, \(obs.evidenceCount)×)\u{1B}[0m")
                }
            }

            if !model.userEditedNotes.isEmpty {
                print("  \u{1B}[36mNotes\u{1B}[0m")
                print("    \(model.userEditedNotes.replacingOccurrences(of: "\n", with: "\n    "))")
            }

            print("  \(String(repeating: "\u{2500}", count: 50))")
            print("  Edit with: zyquo memory user --edit")
            print()
        }
    }

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
                let workspace = Workspace(root: root)
                let wsIndex = await workspace.scan()
                let archContent = MemoryCommand.generateArchitectureDoc(wsIndex: wsIndex, root: root)
                let archDir = archPath.deletingLastPathComponent()
                try? fm.createDirectory(at: archDir, withIntermediateDirectories: true)
                try? archContent.write(to: archPath, atomically: true, encoding: .utf8)
                if fm.fileExists(atPath: archPath.path) {
                    print("    \u{1B}[32m\u{2713}\u{1B}[0m Generated architecture.md")
                }
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

    // MARK: - Architecture Doc Generator

    static func generateArchitectureDoc(wsIndex: WorkspaceIndex, root: URL) -> String {
        var doc = "# Architecture\n\n"
        doc += "Auto-generated by `zyquo memory`. Edit freely — Zyquo will never overwrite your changes.\n\n"

        doc += "## Project\n\n"
        doc += "- **Root:** `\(root.lastPathComponent)`\n"
        doc += "- **Files:** \(wsIndex.fileCount)\n"

        if !wsIndex.languages.isEmpty {
            let langs = wsIndex.languages.prefix(5).map { "\($0.0.displayName) (\(Int($0.1 * 100))%)" }.joined(separator: ", ")
            doc += "- **Languages:** \(langs)\n"
        }

        if !wsIndex.frameworks.isEmpty {
            doc += "- **Frameworks:** \(wsIndex.frameworks.map(\.displayName).joined(separator: ", "))\n"
        }

        if let pm = wsIndex.packageManager {
            doc += "- **Package Manager:** \(pm.displayName)\n"
        }

        if let build = wsIndex.buildCommand {
            doc += "- **Build:** `\(build)`\n"
        }

        if let test = wsIndex.testCommand {
            doc += "- **Test:** `\(test)`\n"
        }

        doc += "\n## Git\n\n"
        if let git = wsIndex.gitStatus {
            if let branch = git.branch { doc += "- **Branch:** \(branch)\n" }
            doc += "- **Clean:** \(git.isClean ? "yes" : "no")\n"
        } else {
            doc += "Not a git repository.\n"
        }

        if !wsIndex.documentation.isEmpty {
            doc += "\n## Documentation\n\n"
            for docFile in wsIndex.documentation {
                doc += "- `\(docFile)`\n"
            }
        }

        doc += "\n## Notes\n\n"
        doc += "<!-- Add architectural notes, conventions, and design decisions below -->\n"

        return doc
    }

    struct MemoryCompact: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compact",
            abstract: "Force compression pass on memory"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Option(name: .shortAndLong, help: "Target token budget for compaction")
        var maxTokens: Int = 50000

        func run() async throws {
            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
            let sessionsDir = root
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("memory")
                .appendingPathComponent("sessions")

            let store = SessionStore(baseDir: sessionsDir)
            let sessions = await store.list(limit: 1000)

            guard !sessions.isEmpty else {
                print("  No sessions to compact.")
                return
            }

            let compressor = MemoryCompressor()
            var totalBefore = 0
            var totalAfter = 0
            var sessionsCompacted = 0

            print()
            print("  \u{1B}[1mMemory Compaction\u{1B}[0m")
            print("  \(String(repeating: "\u{2500}", count: 50))")

            for session in sessions {
                let events = await store.loadEvents(sessionId: session.sessionId)
                guard !events.isEmpty else { continue }

                let entries = events.compactMap { event -> MemoryEntry? in
                    switch event {
                    case .toolExecuted(let e):
                        return MemoryEntry(
                            timestamp: e.timestamp,
                            kind: e.isError ? .error : .toolCall,
                            content: "\(e.toolName): \(e.summary)",
                            metadata: ["tool": e.toolName]
                        )
                    case .stepStarted(let e):
                        return MemoryEntry(
                            timestamp: e.timestamp,
                            kind: .note,
                            content: "Step \(e.stepIndex + 1): \(e.goal)"
                        )
                    case .stepCompleted(let e):
                        return MemoryEntry(
                            timestamp: e.timestamp,
                            kind: .observation,
                            content: "Step \(e.stepIndex + 1) completed [\(e.verdict ?? "none")] (\(e.durationMs)ms)"
                        )
                    case .error(let e):
                        return MemoryEntry(
                            timestamp: e.timestamp,
                            kind: .error,
                            content: e.message,
                            metadata: e.code.map { ["code": $0] } ?? [:]
                        )
                    case .approvalGranted(let e):
                        return MemoryEntry(
                            timestamp: e.timestamp,
                            kind: .decision,
                            content: "Approved \(e.toolName) [\(e.scope)]"
                        )
                    }
                }

                let beforeCount = entries.count
                let compressed = compressor.compress(entries: entries, maxTokens: maxTokens)
                let afterCount = compressed.count

                if afterCount < beforeCount {
                    sessionsCompacted += 1
                    totalBefore += beforeCount
                    totalAfter += afterCount
                    print("  \u{1B}[36m\(session.sessionId.value)\u{1B}[0m: \(beforeCount) -> \(afterCount) entries")
                }
            }

            print("  \(String(repeating: "\u{2500}", count: 50))")
            if sessionsCompacted > 0 {
                print("  Compacted \(sessionsCompacted) session(s): \(totalBefore) -> \(totalAfter) entries total")
            } else {
                print("  All sessions already within budget.")
            }
            print()
        }
    }
}
