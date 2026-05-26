import ArgumentParser
import Foundation

// MARK: - WorkflowCommand

/// Manage scheduled workflows — cron-shaped autonomous tasks that
/// run at defined intervals or in response to file changes.
///
/// Workflows are persisted in `.zyquo/workflows/` and can be listed,
/// created, inspected, deleted, and have their run history queried.
///
/// Reference: CLAUDE.md §30 Phase 10
struct WorkflowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workflows",
        abstract: "Manage scheduled workflows",
        subcommands: [
            ListWorkflows.self,
            CreateWorkflow.self,
            ShowWorkflow.self,
            DeleteWorkflow.self,
            HistoryWorkflow.self,
        ],
        defaultSubcommand: ListWorkflows.self
    )

    // MARK: - List Subcommand

    struct ListWorkflows: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all scheduled workflows"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let workflowDir = workspaceRoot
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("workflows")

            let store = WorkflowStore(path: workflowDir)
            let workflows = await store.list()

            if workflows.isEmpty {
                print("No workflows found.")
                print("")
                print("Create one with:")
                print("  zyquo workflows create <name> --schedule <spec> --intent <intent>")
                return
            }

            // Header
            if noColor {
                print("Scheduled Workflows (\(workflows.count)):")
                print(String(repeating: "-", count: 70))
            } else {
                print("\u{1B}[1mScheduled Workflows (\(workflows.count)):\u{1B}[0m")
                print("\u{1B}[2m\(String(repeating: "-", count: 70))\u{1B}[0m")
            }

            for workflow in workflows {
                let statusStr = workflow.enabled ? "enabled" : "disabled"
                let scheduleStr = workflow.schedule.displayString
                let lastRun = workflow.lastRunAt.map { formatDate($0) } ?? "never"

                if noColor {
                    print("  \(workflow.id)")
                    print("    Name:     \(workflow.name)")
                    print("    Schedule: \(scheduleStr)")
                    print("    Status:   \(statusStr)")
                    print("    Intent:   \(workflow.intentPreview)")
                    print("    Last run: \(lastRun)")
                    if let result = workflow.lastResult {
                        print("    Result:   \(result.status.rawValue)")
                    }
                    print("")
                } else {
                    let statusColor = workflow.enabled ? "\u{1B}[32m" : "\u{1B}[31m"
                    print("  \u{1B}[1m\(workflow.id)\u{1B}[0m")
                    print("    Name:     \(workflow.name)")
                    print("    Schedule: \u{1B}[36m\(scheduleStr)\u{1B}[0m")
                    print("    Status:   \(statusColor)\(statusStr)\u{1B}[0m")
                    print("    Intent:   \(workflow.intentPreview)")
                    print("    Last run: \u{1B}[2m\(lastRun)\u{1B}[0m")
                    if let result = workflow.lastResult {
                        let resultColor = result.status == .success ? "\u{1B}[32m" : "\u{1B}[31m"
                        print("    Result:   \(resultColor)\(result.status.rawValue)\u{1B}[0m")
                    }
                    print("")
                }
            }
        }

        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    // MARK: - Create Subcommand

    struct CreateWorkflow: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a scheduled workflow"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Workflow name")
        var name: String

        @Option(name: .long, help: "Schedule spec (e.g. '5m', '1h', 'daily@09:00', 'weekly@mon@09:00')")
        var schedule: String

        @Option(name: .long, help: "Intent string for the agent")
        var intent: String

        @Option(name: .long, help: "Skill ID to bind (optional)")
        var skill: String?

        @Option(name: .long, help: "Maximum cost per run in USD (default: 2.00)")
        var maxCost: Double = 2.0

        func run() async throws {
            Bootstrap.setupSignalHandlers()

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let workflowDir = workspaceRoot
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("workflows")

            let parsedSchedule = try parseSchedule(schedule)
            let id = ScheduledWorkflow.generateId(name: name)

            let workflow = ScheduledWorkflow(
                id: id,
                name: name,
                schedule: parsedSchedule,
                intent: intent,
                skillId: skill,
                maxCostPerRun: maxCost,
                enabled: true
            )

            let store = WorkflowStore(path: workflowDir)
            try await store.save(workflow)

            print("Created workflow '\(name)'")
            print("  ID:       \(id)")
            print("  Schedule: \(parsedSchedule.displayString)")
            print("  Intent:   \(workflow.intentPreview)")
            print("  Max cost: $\(String(format: "%.2f", maxCost))")
            if let skillId = skill {
                print("  Skill:    \(skillId)")
            }
        }

        private func parseSchedule(_ spec: String) throws -> WorkflowSchedule {
            // Interval formats: "5m", "30s", "2h", "1h30m"
            if let seconds = parseIntervalSeconds(spec) {
                return .interval(seconds: seconds)
            }

            // Daily format: "daily@HH:MM"
            if spec.hasPrefix("daily@") {
                let timePart = String(spec.dropFirst(6))
                let parts = timePart.split(separator: ":")
                guard parts.count == 2,
                      let hour = Int(parts[0]),
                      let minute = Int(parts[1]),
                      (0...23).contains(hour),
                      (0...59).contains(minute) else {
                    throw ValidationError("Invalid daily schedule '\(spec)'. Use format: daily@HH:MM")
                }
                return .daily(hour: hour, minute: minute)
            }

            // Weekly format: "weekly@mon@HH:MM"
            if spec.hasPrefix("weekly@") {
                let rest = String(spec.dropFirst(7))
                let parts = rest.split(separator: "@")
                guard parts.count == 2 else {
                    throw ValidationError("Invalid weekly schedule '\(spec)'. Use format: weekly@day@HH:MM")
                }
                let dayStr = String(parts[0])
                let timePart = String(parts[1])
                let timeParts = timePart.split(separator: ":")
                guard timeParts.count == 2,
                      let hour = Int(timeParts[0]),
                      let minute = Int(timeParts[1]),
                      (0...23).contains(hour),
                      (0...59).contains(minute) else {
                    throw ValidationError("Invalid time in schedule '\(spec)'. Use HH:MM")
                }
                let day = parseDayOfWeek(dayStr)
                guard day > 0 else {
                    throw ValidationError("Invalid day '\(dayStr)'. Use: sun, mon, tue, wed, thu, fri, sat")
                }
                return .weekly(dayOfWeek: day, hour: hour, minute: minute)
            }

            throw ValidationError("Unknown schedule format '\(spec)'. Use: <N>s/<N>m/<N>h, daily@HH:MM, weekly@day@HH:MM")
        }

        private func parseIntervalSeconds(_ spec: String) -> Int? {
            let lower = spec.lowercased()

            if lower.hasSuffix("s"), let n = Int(lower.dropLast()) {
                return n
            }
            if lower.hasSuffix("m"), let n = Int(lower.dropLast()) {
                return n * 60
            }
            if lower.hasSuffix("h"), let n = Int(lower.dropLast()) {
                return n * 3600
            }
            return nil
        }

        private func parseDayOfWeek(_ day: String) -> Int {
            switch day.lowercased() {
            case "sun", "sunday": return 1
            case "mon", "monday": return 2
            case "tue", "tuesday": return 3
            case "wed", "wednesday": return 4
            case "thu", "thursday": return 5
            case "fri", "friday": return 6
            case "sat", "saturday": return 7
            default: return 0
            }
        }
    }

    // MARK: - Show Subcommand

    struct ShowWorkflow: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show workflow details and recent run history"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Workflow ID")
        var id: String

        func run() async throws {
            Bootstrap.setupSignalHandlers()

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let workflowDir = workspaceRoot
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("workflows")

            let store = WorkflowStore(path: workflowDir)

            guard let workflow = await store.load(id: id) else {
                print("Workflow '\(id)' not found.")
                return
            }

            print("Workflow: \(workflow.id)")
            print("Name:     \(workflow.name)")
            print("Schedule: \(workflow.schedule.displayString)")
            print("Status:   \(workflow.enabled ? "enabled" : "disabled")")
            print("Intent:   \(workflow.intent)")
            print("Max cost: $\(String(format: "%.2f", workflow.maxCostPerRun))")
            if let skillId = workflow.skillId {
                print("Skill:    \(skillId)")
            }
            print("Created:  \(formatDate(workflow.createdAt))")
            if let lastRun = workflow.lastRunAt {
                print("Last run: \(formatDate(lastRun))")
            }
            print("")

            // Show recent history
            let history = await store.history(workflowId: id, limit: 10)
            if history.isEmpty {
                print("No run history.")
            } else {
                print("Recent runs (\(history.count)):")
                print(String(repeating: "-", count: 60))
                for result in history {
                    let statusStr = result.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
                    let costStr = String(format: "$%.4f", result.cost)
                    print("  \(formatDate(result.startedAt))  \(statusStr) \(result.formattedDuration)  \(costStr)")
                    if !result.summary.isEmpty {
                        let preview = result.summary.count <= 60
                            ? result.summary
                            : String(result.summary.prefix(57)) + "..."
                        print("    \(preview)")
                    }
                }
            }
        }

        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    // MARK: - Delete Subcommand

    struct DeleteWorkflow: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a scheduled workflow"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Workflow ID to delete")
        var id: String

        func run() async throws {
            Bootstrap.setupSignalHandlers()

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let workflowDir = workspaceRoot
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("workflows")

            let store = WorkflowStore(path: workflowDir)

            guard await store.load(id: id) != nil else {
                print("Workflow '\(id)' not found.")
                return
            }

            try await store.delete(id: id)
            print("Deleted workflow '\(id)'.")
        }
    }

    // MARK: - History Subcommand

    struct HistoryWorkflow: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "history",
            abstract: "Show run history for a workflow"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Workflow ID")
        var id: String

        @Option(name: .long, help: "Maximum number of runs to show (default: 20)")
        var limit: Int = 20

        func run() async throws {
            Bootstrap.setupSignalHandlers()

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let workflowDir = workspaceRoot
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("workflows")

            let store = WorkflowStore(path: workflowDir)
            let history = await store.history(workflowId: id, limit: limit)

            if history.isEmpty {
                print("No run history for workflow '\(id)'.")
                return
            }

            print("Run History for '\(id)' (\(history.count) runs):")
            print(String(repeating: "-", count: 70))

            for result in history {
                let statusStr = result.status.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
                let costStr = String(format: "$%.4f", result.cost)
                let durationStr = result.formattedDuration.padding(toLength: 8, withPad: " ", startingAt: 0)
                print("  \(formatDate(result.startedAt))  \(statusStr) \(durationStr) \(costStr)")
                if !result.summary.isEmpty {
                    let preview = result.summary.count <= 60
                        ? result.summary
                        : String(result.summary.prefix(57)) + "..."
                    print("    \(preview)")
                }
            }

            // Summary stats
            let successes = history.filter { $0.status == .success }.count
            let totalCost = history.reduce(0.0) { $0 + $1.cost }
            let avgDuration = history.reduce(0.0) { $0 + $1.duration } / Double(history.count)
            print("")
            print("Summary: \(successes)/\(history.count) succeeded, total cost $\(String(format: "%.4f", totalCost)), avg duration \(Int(avgDuration))s")
        }

        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}
