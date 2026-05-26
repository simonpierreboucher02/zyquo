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
        container.logger.info("Ask mode", metadata: ["question": "\(question)"])

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

        if !container.config.ui.noColor {
            print("\u{1B}[2mProvider: \(provider.displayName) | Model: \(descriptor.displayName)\u{1B}[0m")
            print()
        } else {
            print("Provider: \(provider.displayName) | Model: \(descriptor.displayName)")
            print()
        }

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
            print()
            if let ze = error as? ZyquoError {
                print("Error: \(ze.description)")
            } else {
                print("Error: \(error.localizedDescription)")
            }
            throw ExitCode.failure
        }

        print()

        if let usage = lastUsage {
            cost.record(usage: usage, model: descriptor)
            print()
            if !noColor {
                print("\u{1B}[2m\(cost.summary)\u{1B}[0m")
            } else {
                print(cost.summary)
            }
        }
    }
}
