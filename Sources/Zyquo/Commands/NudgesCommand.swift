import ArgumentParser
import Foundation

// MARK: - NudgesCommand

/// List and resolve learning nudges produced by the closed learning loop.
///
/// Nudges are calm, actionable suggestions ("save this as a skill", "refine
/// skill X", "refresh project memory"). They never act on their own — the user
/// runs the suggested command, or dismisses the nudge here.
struct NudgesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nudges",
        abstract: "Show and resolve learning suggestions",
        subcommands: [
            ListNudges.self,
            DismissNudge.self,
        ],
        defaultSubcommand: ListNudges.self
    )

    // MARK: - List

    struct ListNudges: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List pending nudges"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Flag(name: .long, help: "Include resolved (acted/dismissed) nudges")
        var all = false

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let store = NudgeStore()
            let nudges = all ? await store.all() : await store.pending()

            guard !nudges.isEmpty else {
                print("No \(all ? "" : "pending ")nudges.")
                return
            }

            print("\u{1B}[1m\(all ? "All" : "Pending") Nudges (\(nudges.count)):\u{1B}[0m")
            print("\u{1B}[2m\(String(repeating: "-", count: 70))\u{1B}[0m")
            for nudge in nudges {
                let stateTag = nudge.state == .pending ? "" : " \u{1B}[2m[\(nudge.state.rawValue)]\u{1B}[0m"
                print("  \u{1B}[36m•\u{1B}[0m \(nudge.message)\(stateTag)")
                if let cmd = nudge.actionCommand {
                    print("      \u{1B}[2m\(cmd)\u{1B}[0m")
                }
                print("      \u{1B}[2mdismiss: zyquo nudges dismiss \(nudge.id)\u{1B}[0m")
            }
        }
    }

    // MARK: - Dismiss

    struct DismissNudge: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dismiss",
            abstract: "Dismiss a nudge by id"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "The nudge id to dismiss (or 'all')")
        var id: String

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let store = NudgeStore()
            if id == "all" {
                let pending = await store.pending()
                for nudge in pending {
                    try? await store.markDismissed(id: nudge.id)
                }
                print("Dismissed \(pending.count) nudge(s).")
            } else {
                try await store.markDismissed(id: id)
                print("Dismissed '\(id)'.")
            }
        }
    }
}
