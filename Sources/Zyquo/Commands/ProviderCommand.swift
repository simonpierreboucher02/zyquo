import ArgumentParser
import Foundation

struct ProviderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "provider",
        abstract: "Manage LLM providers",
        subcommands: [
            ListProviders.self,
            LoginProvider.self,
            LogoutProvider.self,
        ],
        defaultSubcommand: ListProviders.self
    )

    struct ListProviders: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List configured providers with auth status"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor
            let check = noColor ? "[OK]" : "\u{1B}[32m✓\u{1B}[0m"
            let miss = noColor ? "[--]" : "\u{1B}[33m-\u{1B}[0m"

            let knownProviders: [(id: String, name: String, required: Bool)] = [
                ("anthropic", "Anthropic", true),
                ("openrouter", "OpenRouter", false),
                ("openai", "OpenAI", false),
            ]

            print()
            print(noColor ? "  LLM Providers" : "  \u{1B}[1mLLM Providers\u{1B}[0m")
            print()

            let activeProvider = container.config.providers.resolvedProvider
            let activeModel = container.config.providers.resolvedModel

            for p in knownProviders {
                let hasKey = KeychainHelper.exists(service: ProviderKeychain.service, account: p.id)
                let badge = hasKey ? check : miss
                let active = p.id == activeProvider ? " (active)" : ""
                let status = hasKey ? "key stored" : (p.required ? "not configured" : "optional")
                print("  \(badge) \(p.name)\(active) -- \(status)")
            }

            print()
            print("  Active: \(activeProvider) / \(activeModel)")
            print()
            print("  Use `zyquo provider login <id>` to add a provider API key.")
            print()
        }
    }

    struct LoginProvider: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "login",
            abstract: "Store API key in Keychain"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Provider identifier (anthropic, openrouter, openai)")
        var providerId: String

        func run() async throws {
            let validProviders = ["anthropic", "openrouter", "openai"]
            guard validProviders.contains(providerId) else {
                print("Unknown provider '\(providerId)'. Valid providers: \(validProviders.joined(separator: ", "))")
                throw ExitCode.failure
            }

            print("Enter API key for \(providerId):")
            print("(input will not be echoed)")

            guard let key = readSecureInput() else {
                print("No input received.")
                throw ExitCode.failure
            }

            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                print("Empty key provided.")
                throw ExitCode.failure
            }

            let success = KeychainHelper.save(
                service: ProviderKeychain.service,
                account: providerId,
                string: trimmed
            )

            if success {
                print("API key for \(providerId) stored in Keychain.")
            } else {
                print("Failed to store API key in Keychain.")
                throw ExitCode.failure
            }
        }

        private func readSecureInput() -> String? {
            var oldTermios = termios()
            tcgetattr(STDIN_FILENO, &oldTermios)
            var newTermios = oldTermios
            newTermios.c_lflag &= ~UInt(ECHO)
            tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)
            defer { tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios) }
            return readLine()
        }
    }

    struct LogoutProvider: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logout",
            abstract: "Remove API key from Keychain"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Provider identifier")
        var providerId: String

        func run() async throws {
            let deleted = KeychainHelper.delete(
                service: ProviderKeychain.service,
                account: providerId
            )

            if deleted {
                print("API key for \(providerId) removed from Keychain.")
            } else {
                print("No API key found for \(providerId).")
            }
        }
    }
}
