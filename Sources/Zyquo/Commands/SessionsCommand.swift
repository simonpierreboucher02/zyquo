import ArgumentParser
import Foundation

struct SessionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "Manage agent sessions",
        subcommands: [
            ListSessions.self,
            ShowSession.self,
            ResumeSession.self,
        ],
        defaultSubcommand: ListSessions.self
    )

    struct ListSessions: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List recent sessions"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Option(name: .shortAndLong, help: "Maximum number of sessions to show")
        var limit: Int = 20

        func run() async throws {
            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
            let sessionsDir = root
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("memory")
                .appendingPathComponent("sessions")

            let store = SessionStore(baseDir: sessionsDir)
            let records = await store.list(limit: limit)

            if records.isEmpty {
                print("  No sessions found.")
                print("  Run \u{1B}[1mzyquo run\u{1B}[0m to start a new agent session.")
                return
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"

            print()
            print("  \u{1B}[1mRecent Sessions\u{1B}[0m")
            print("  \(String(repeating: "\u{2500}", count: 70))")

            for record in records {
                let date = formatter.string(from: record.updatedAt)
                let status = record.status.padding(toLength: 10, withPad: " ", startingAt: 0)
                let intent = record.intentPreview
                print("  \u{1B}[36m\(record.sessionId.value)\u{1B}[0m  \(date)  \(status)  \(intent)")
            }

            print("  \(String(repeating: "\u{2500}", count: 70))")
            print("  \(records.count) session(s)")
            print()
        }
    }

    struct ShowSession: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show session details"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Session ID to show")
        var sessionId: String

        func run() async throws {
            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
            let sessionsDir = root
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("memory")
                .appendingPathComponent("sessions")

            let store = SessionStore(baseDir: sessionsDir)
            let id = SessionID(value: sessionId)

            guard let record = try await store.load(id: id) else {
                print("  Session '\(sessionId)' not found.")
                return
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

            print()
            print("  \u{1B}[1mSession: \(record.sessionId.value)\u{1B}[0m")
            print("  Status:    \(record.status)")
            print("  Intent:    \(record.intent)")
            print("  Model:     \(record.model)")
            print("  Provider:  \(record.provider)")
            print("  Started:   \(formatter.string(from: record.startedAt))")
            print("  Updated:   \(formatter.string(from: record.updatedAt))")
            print("  Steps:     \(record.stepsCompleted)/\(record.stepsTotal)")
            print("  Tokens:    \(record.totalInputTokens) in / \(record.totalOutputTokens) out")
            print("  Cost:      \(record.formattedCost)")

            if !record.planSteps.isEmpty {
                print()
                print("  \u{1B}[1mPlan:\u{1B}[0m")
                for (i, step) in record.planSteps.enumerated() {
                    let marker = i < record.stepsCompleted ? "\u{2713}" : "\u{2022}"
                    print("    \(marker) \(i + 1). \(step.goal)")
                }
            }

            // Show events if available
            let events = await store.loadEvents(sessionId: id)
            if !events.isEmpty {
                print()
                print("  \u{1B}[1mEvents:\u{1B}[0m (\(events.count) total)")
                for event in events.suffix(10) {
                    let time = formatter.string(from: event.timestamp)
                    switch event {
                    case .stepStarted(let e):
                        print("    \(time)  Step \(e.stepIndex + 1) started: \(e.goal)")
                    case .stepCompleted(let e):
                        let verdict = e.verdict ?? "none"
                        print("    \(time)  Step \(e.stepIndex + 1) completed [\(verdict)] (\(e.durationMs)ms)")
                    case .toolExecuted(let e):
                        let status = e.isError ? "ERROR" : "OK"
                        print("    \(time)  \(e.toolName) [\(status)] (\(e.durationMs)ms)")
                    case .approvalGranted(let e):
                        print("    \(time)  Approved \(e.toolName) [\(e.scope)]")
                    case .error(let e):
                        print("    \(time)  Error: \(e.message)")
                    }
                }
                if events.count > 10 {
                    print("    ... and \(events.count - 10) more events")
                }
            }

            print()
        }
    }

    struct ResumeSession: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resume",
            abstract: "Resume a previous session"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Session ID to resume")
        var sessionId: String

        func run() async throws {
            let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
            let sessionsDir = root
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("memory")
                .appendingPathComponent("sessions")

            let store = SessionStore(baseDir: sessionsDir)
            let id = SessionID(value: sessionId)

            guard let record = try await store.load(id: id) else {
                print("  Session '\(sessionId)' not found.")
                return
            }

            print("  Would resume session \(record.sessionId.value)")
            print("  Intent: \(record.intent)")
            print("  Status: \(record.status)")
            print("  Steps:  \(record.stepsCompleted)/\(record.stepsTotal)")
            print()
            print("  (Session resume is not yet fully implemented.)")
        }
    }
}
