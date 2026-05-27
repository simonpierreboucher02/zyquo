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
        let noColor = container.config.ui.noColor
        let providerId = container.config.providers.resolvedProvider

        let router = ModelRouter(config: container.config.providers)
        await router.register(AnthropicProvider())
        await router.register(OpenRouterProvider())

        guard let resolved = await router.resolve(for: .planning) else {
            print("No provider configured. Run `zyquo provider login \(providerId)`.")
            throw ExitCode.failure
        }

        let descriptor = ModelCatalog.find(id: resolved.model) ?? ModelCatalog.claudeOpus4_7

        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let workspace = Workspace(root: root)
        let wsIndex = await workspace.scan()

        let dim = noColor ? "" : "\u{1B}[2m"
        let bold = noColor ? "" : "\u{1B}[1m"
        let reset = noColor ? "" : "\u{1B}[0m"

        print()
        print("  \(bold)Plan Mode\(reset)")
        print("  \(dim)Model: \(descriptor.displayName) | Provider: \(resolved.provider.displayName)\(reset)")
        print("  \(dim)Intent: \(intent)\(reset)")
        print()

        var contextInfo = "Workspace: \(root.path)"
        if let lang = wsIndex.primaryLanguage {
            contextInfo += "\nPrimary language: \(lang.displayName)"
        }
        if let framework = wsIndex.frameworks.first {
            contextInfo += "\nFramework: \(framework.displayName)"
        }
        contextInfo += "\nFiles: \(wsIndex.fileCount)"
        if let git = wsIndex.gitStatus {
            contextInfo += "\nGit: \(git.branch ?? "unknown branch")"
        }

        let systemPrompt = """
        You are Zyquo, a planning agent for macOS development. Given a user intent and workspace context, produce a clear numbered plan of small, verifiable steps.

        Rules:
        - Each step must be concrete and actionable
        - Prefer reading/understanding before writing/changing
        - Prefer narrow, surgical changes over broad rewrites
        - Include verification checks (how to confirm each step succeeded)
        - Never propose destructive actions without explicit justification
        - Keep the plan under 10 steps unless the task genuinely requires more
        - Mark each step with a risk level: [SAFE], [MODERATE], or [DANGEROUS]

        Workspace context:
        \(contextInfo)
        """

        let request = LLMRequest(
            model: resolved.model,
            systemPrompt: systemPrompt,
            messages: [.user("Plan this task: \(intent)")],
            maxTokens: min(4096, descriptor.maxOutputTokens)
        )

        var cost = SessionCost()
        var lastUsage: TokenUsage?

        let stream = resolved.provider.send(request: request, cancellation: nil)

        do {
            for try await event in stream {
                switch event {
                case .textDelta(let text):
                    print(text, terminator: "")
                    fflush(stdout)
                case .usage(let usage):
                    lastUsage = usage
                case .error(let err):
                    print("\nError: \(err.description)")
                default:
                    break
                }
            }
        } catch {
            print()
            if let ze = error as? ZyquoError {
                print("Error: \(ze.description)")
            } else {
                print("Error: \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }

        print()
        print()

        if let usage = lastUsage {
            cost.record(usage: usage, model: descriptor)
            print("  \(dim)\(cost.summary)\(reset)")
        }

        if !globals.flags.quiet {
            print()
            print("  \(dim)This is a plan only. Run `zyquo run \"\(intent)\"` to execute.\(reset)")
        }
    }
}
