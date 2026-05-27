import ArgumentParser
import Foundation

struct AskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ask",
        abstract: "Single-shot Q&A (no tools)"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    @Argument(help: "Your question")
    var question: String

    func run() async throws {
        Bootstrap.setupSignalHandlers()
        let container = AppContainer(flags: globals.flags)

        let noColor = container.config.ui.noColor
        let providerId = container.config.providers.resolvedProvider
        let modelAlias = container.config.providers.resolvedModel

        let router = ModelRouter(config: container.config.providers)
        await router.register(AnthropicProvider())
        await router.register(OpenRouterProvider())

        guard let resolved = await router.resolveExplicit(providerId: providerId, modelId: modelAlias) else {
            print("No provider configured for '\(providerId)'. Run `zyquo provider login \(providerId)`.")
            throw ExitCode.failure
        }

        let provider = resolved.provider
        let modelId = resolved.model

        let descriptor = ModelCatalog.find(id: modelId) ?? ModelCatalog.claudeSonnet4_6

        let co = CommandOutput(noColor: noColor)
        co.header(title: "Zyquo Ask", subtitle: question)
        co.blank()

        let request = LLMRequest(
            model: modelId,
            systemPrompt: "You are a helpful assistant. Answer concisely and accurately.",
            messages: [.user(question)],
            maxTokens: 4096
        )

        var cost = SessionCost()
        var fullText = ""
        var lastUsage: TokenUsage?

        let stream = provider.send(request: request, cancellation: nil)

        co.streamStart()
        do {
            for try await event in stream {
                switch event {
                case .messageStart:
                    break
                case .textDelta(let text):
                    print(text, terminator: "")
                    fflush(stdout)
                    fullText += text
                case .usage(let usage):
                    lastUsage = usage
                case .messageStop:
                    break
                case .error(let err):
                    print("\nError: \(err.description)")
                default:
                    break
                }
            }
        } catch {
            co.streamEnd()
            if let ze = error as? ZyquoError {
                print("Error: \(ze.description)")
            } else {
                print("Error: \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }
        co.streamEnd()

        if let usage = lastUsage {
            cost.record(usage: usage, model: descriptor)
            co.footer(items: [
                ("Model", descriptor.displayName),
                ("Tokens", "\(usage.inputTokens) in \u{00B7} \(usage.outputTokens) out"),
                ("Cost", cost.formattedCost),
            ])
        }
    }
}
