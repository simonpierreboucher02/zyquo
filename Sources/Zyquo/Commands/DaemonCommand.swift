import ArgumentParser
import Foundation

// MARK: - DaemonCommand

/// Manage the Zyquo background intelligence daemon.
///
/// The daemon provides continuous workspace awareness via file watching
/// (FSEvents), incremental symbol re-indexing, and stale data cleanup.
///
/// In V1, the daemon runs in-process. In V2, it will run as a launchd
/// agent communicating via XPC.
///
/// Reference: CLAUDE.md V2 Phase 4 - Background Intelligence Runtime
struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Manage the background intelligence daemon",
        subcommands: [
            DaemonStatusCmd.self,
            DaemonStart.self,
            DaemonStop.self,
            DaemonIndex.self,
            DaemonClean.self,
        ],
        defaultSubcommand: DaemonStatusCmd.self
    )

    // MARK: - Status Subcommand

    struct DaemonStatusCmd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show daemon health report"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.ensureDirectories()
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
            let workspace = Workspace(root: root)
            let symbolIndex = SymbolIndex()
            let daemon = DaemonService(
                workspaceRoot: root,
                workspace: workspace,
                symbolIndex: symbolIndex
            )

            let report = await daemon.enrichedHealthReport()

            printHeader("Daemon Health Report", noColor: noColor)
            printField("Status", report.status.rawValue, noColor: noColor, statusColor: colorForStatus(report.status))
            printField("Uptime", formatUptime(report.uptimeSeconds), noColor: noColor)
            printField("Files indexed", "\(report.filesIndexed)", noColor: noColor)
            printField("Symbols indexed", "\(report.symbolsIndexed)", noColor: noColor)
            printField("Vectors stored", "\(report.vectorsStored)", noColor: noColor)

            if let lastIndex = report.lastIndexTime {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .medium
                printField("Last index", formatter.string(from: lastIndex), noColor: noColor)
            } else {
                printField("Last index", "never", noColor: noColor)
            }

            printField("Memory", "\(report.memoryUsageMB) MB", noColor: noColor)
            printField("CPU", String(format: "%.1f%%", report.cpuPercent), noColor: noColor)
            print()

            // Workspace info
            let wsIndex = await workspace.scan()
            printHeader("Workspace", noColor: noColor)
            printField("Root", root.path, noColor: noColor)
            printField("Files", "\(wsIndex.fileCount)", noColor: noColor)

            if let lang = wsIndex.primaryLanguage {
                printField("Language", lang.displayName, noColor: noColor)
            }

            print()
        }

        private func colorForStatus(_ status: DaemonStatus) -> String {
            switch status {
            case .running, .idle: return "\u{1B}[32m"
            case .indexing, .starting: return "\u{1B}[33m"
            case .stopped, .stopping: return "\u{1B}[2m"
            case .error: return "\u{1B}[31m"
            }
        }

        private func formatUptime(_ seconds: Int) -> String {
            if seconds == 0 { return "not running" }
            if seconds < 60 { return "\(seconds)s" }
            if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return "\(h)h \(m)m"
        }
    }

    // MARK: - Start Subcommand

    struct DaemonStart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Start background indexing (in-process)"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.ensureDirectories()
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)

            print(noColor ? "Starting daemon for \(root.path)..." : "\u{1B}[1mStarting daemon for \(root.path)...\u{1B}[0m")

            let workspace = Workspace(root: root)
            let symbolIndex = SymbolIndex()
            let daemon = DaemonService(
                workspaceRoot: root,
                workspace: workspace,
                symbolIndex: symbolIndex
            )

            await daemon.start()

            let report = await daemon.enrichedHealthReport()
            let status = report.status.rawValue

            if noColor {
                print("Daemon started. Status: \(status)")
            } else {
                print("\u{1B}[32mDaemon started.\u{1B}[0m Status: \(status)")
            }

            print("Files indexed: \(report.filesIndexed)")
            print("Symbols indexed: \(report.symbolsIndexed)")

            // In V1, the daemon runs in-process and exits after the initial index.
            // In V2, it would register as a launchd agent and stay resident.
            await daemon.stop()

            print()
            print("Note: In V1, daemon runs in-process and exits after indexing.")
            print("A persistent launchd-based daemon is planned for V2.")
        }
    }

    // MARK: - Stop Subcommand

    struct DaemonStop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stop",
            abstract: "Stop background indexing"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            // In V1, there is no persistent daemon to stop.
            // This command serves as a placeholder for V2's launchd agent.
            if noColor {
                print("No persistent daemon running (V1 runs in-process).")
            } else {
                print("\u{1B}[33mNo persistent daemon running\u{1B}[0m (V1 runs in-process).")
            }
            print("A persistent launchd-based daemon is planned for V2.")
        }
    }

    // MARK: - Index Subcommand

    struct DaemonIndex: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "index",
            abstract: "Trigger a full workspace re-index"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.ensureDirectories()
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)

            print(noColor ? "Indexing workspace: \(root.path)" : "\u{1B}[1mIndexing workspace: \(root.path)\u{1B}[0m")

            let startTime = CFAbsoluteTimeGetCurrent()

            let workspace = Workspace(root: root)
            let symbolIndex = SymbolIndex()
            let indexer = IncrementalIndexer()

            await indexer.fullIndex(workspace: workspace, symbolIndex: symbolIndex)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let stats = await indexer.stats
            let symbolCount = await symbolIndex.totalSymbols
            let fileCount = await symbolIndex.indexedFileCount

            if noColor {
                print("Index complete.")
            } else {
                print("\u{1B}[32mIndex complete.\u{1B}[0m")
            }
            print("  Files indexed: \(fileCount)")
            print("  Symbols extracted: \(symbolCount)")
            print("  Time: \(String(format: "%.2f", elapsed))s")
            print("  Avg per file: \(String(format: "%.1f", stats.averageFileTimeMs))ms")
            print()
        }
    }

    // MARK: - Clean Subcommand

    struct DaemonClean: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clean",
            abstract: "Run stale data cleanup"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Option(name: .long, help: "Snapshot retention in days (default: 30)")
        var snapshotDays: Int = 30

        @Option(name: .long, help: "Session retention in days (default: 90)")
        var sessionDays: Int = 90

        func run() async throws {
            Bootstrap.ensureDirectories()
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
            let zyquoDir = root.appendingPathComponent(".zyquo")

            print(noColor ? "Cleaning stale data..." : "\u{1B}[1mCleaning stale data...\u{1B}[0m")

            let cleaner = StaleDataCleaner()
            var totalItems = 0
            var totalBytes: UInt64 = 0

            // Clean snapshots
            let snapshotsDir = zyquoDir.appendingPathComponent("snapshots")
            if let result = try? cleaner.cleanSnapshots(olderThan: snapshotDays, at: snapshotsDir) {
                printCleanupResult("Snapshots", result, noColor: noColor)
                totalItems += result.itemsRemoved
                totalBytes += result.bytesFreed
            }

            // Clean sessions
            let sessionsDir = zyquoDir.appendingPathComponent("memory/sessions")
            if let result = try? cleaner.cleanSessions(olderThan: sessionDays, at: sessionsDir) {
                printCleanupResult("Sessions", result, noColor: noColor)
                totalItems += result.itemsRemoved
                totalBytes += result.bytesFreed
            }

            print()
            if totalItems > 0 {
                let freed = formatBytes(totalBytes)
                if noColor {
                    print("Total: removed \(totalItems) item(s), freed \(freed)")
                } else {
                    print("\u{1B}[32mTotal:\u{1B}[0m removed \(totalItems) item(s), freed \(freed)")
                }
            } else {
                print("No stale data found.")
            }
            print()
        }

        private func printCleanupResult(_ label: String, _ result: CleanupResult, noColor: Bool) {
            if result.itemsRemoved > 0 {
                let freed = formatBytes(result.bytesFreed)
                print("  \(label): removed \(result.itemsRemoved) item(s), freed \(freed)")
            } else {
                print("  \(label): clean")
            }
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
}

// MARK: - Shared Helpers

private func printHeader(_ title: String, noColor: Bool) {
    print()
    if noColor {
        print("  \(title):")
    } else {
        print("  \u{1B}[1m\(title):\u{1B}[0m")
    }
    print()
}

private func printField(_ label: String, _ value: String, noColor: Bool, statusColor: String? = nil) {
    let paddedLabel = label.padding(toLength: 20, withPad: " ", startingAt: 0)
    if noColor {
        print("  \(paddedLabel) \(value)")
    } else if let color = statusColor {
        print("  \u{1B}[2m\(paddedLabel)\u{1B}[0m \(color)\(value)\u{1B}[0m")
    } else {
        print("  \u{1B}[2m\(paddedLabel)\u{1B}[0m \(value)")
    }
}
