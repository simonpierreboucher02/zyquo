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
            StatusProvider.self,
        ],
        defaultSubcommand: ListProviders.self
    )

    // MARK: - Known Providers

    static let knownProviders: [(id: String, name: String, required: Bool, envVar: String)] = [
        ("anthropic", "Anthropic", true, "ANTHROPIC_API_KEY"),
        ("openrouter", "OpenRouter", false, "OPENROUTER_API_KEY"),
        ("openai", "OpenAI", false, "OPENAI_API_KEY"),
    ]

    static let validProviderIds: [String] = knownProviders.map(\.id)

    // MARK: - Key Format Validation

    /// Returns nil if the key looks plausible, or an error message if it clearly does not.
    static func validateKeyFormat(providerId: String, key: String) -> String? {
        switch providerId {
        case "anthropic":
            if key.hasPrefix("sk-ant-") { return nil }
            // Some older keys may not have the prefix; allow if long enough
            if key.count >= 32 { return nil }
            return "Anthropic keys typically start with 'sk-ant-' and are at least 32 characters."
        case "openrouter":
            if key.hasPrefix("sk-or-") { return nil }
            if key.count >= 32 { return nil }
            return "OpenRouter keys typically start with 'sk-or-' and are at least 32 characters."
        case "openai":
            if key.hasPrefix("sk-") { return nil }
            if key.count >= 32 { return nil }
            return "OpenAI keys typically start with 'sk-' and are at least 32 characters."
        default:
            if key.count >= 16 { return nil }
            return "Key appears too short (expected at least 16 characters)."
        }
    }

    /// Mask a key for display: first 8 chars + "..." + last 4 chars.
    /// If the key is too short, show just the first few chars.
    static func maskedKey(_ key: String) -> String {
        if key.count <= 16 {
            let prefix = String(key.prefix(4))
            return "\(prefix)..."
        }
        let prefix = String(key.prefix(8))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    /// Models associated with each provider for display purposes.
    static func modelsForProvider(_ providerId: String) -> [ModelDescriptor] {
        switch providerId {
        case "anthropic":
            return ModelCatalog.allModels
        case "openrouter":
            // OpenRouter routes to the same Anthropic models
            return ModelCatalog.allModels
        case "openai":
            // Placeholder; we don't have OpenAI model descriptors in catalog yet
            return []
        default:
            return []
        }
    }

    /// Default model for a provider.
    static func defaultModelForProvider(_ providerId: String) -> String {
        switch providerId {
        case "anthropic": return "claude-sonnet-4-6"
        case "openrouter": return "claude-sonnet-4-6"
        case "openai": return "gpt-4o"
        default: return "unknown"
        }
    }

    /// Format a context window size for display (e.g. 1000000 -> "1M").
    static func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let m = Double(tokens) / 1_000_000.0
            if m == m.rounded() {
                return "\(Int(m))M"
            }
            return String(format: "%.1fM", m)
        } else if tokens >= 1_000 {
            let k = Double(tokens) / 1_000.0
            if k == k.rounded() {
                return "\(Int(k))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(tokens)"
    }

    /// Format price per million tokens for display.
    static func formatPrice(_ pricePerMToken: Double) -> String {
        if pricePerMToken == 0 {
            return "free"
        }
        if pricePerMToken == pricePerMToken.rounded() {
            return "$\(Int(pricePerMToken))/M"
        }
        return String(format: "$%.2f/M", pricePerMToken)
    }

    // MARK: - List Subcommand

    struct ListProviders: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List configured providers with auth status and model info"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let bold = noColor ? "" : "\u{1B}[1m"
            let dim = noColor ? "" : "\u{1B}[2m"
            let reset = noColor ? "" : "\u{1B}[0m"
            let green = noColor ? "" : "\u{1B}[32m"
            let yellow = noColor ? "" : "\u{1B}[33m"
            let cyan = noColor ? "" : "\u{1B}[36m"

            let check = noColor ? "[OK]" : "\(green)\u{2713}\(reset)"
            let miss = noColor ? "[--]" : "\(yellow)-\(reset)"

            let activeProvider = container.config.providers.resolvedProvider
            let activeModel = container.config.providers.resolvedModel

            print()
            print("  \(bold)LLM Providers\(reset)")
            print()

            for p in ProviderCommand.knownProviders {
                let hasKey = KeychainHelper.exists(service: ProviderKeychain.service, account: p.id)
                let badge = hasKey ? check : miss
                let active = p.id == activeProvider ? " (active)" : ""
                let status = hasKey ? "key stored" : (p.required ? "not configured" : "optional")
                print("  \(badge) \(bold)\(p.name)\(reset)\(active) -- \(status)")

                // Show model and pricing info for this provider
                let models = ProviderCommand.modelsForProvider(p.id)
                let defaultModelId = p.id == activeProvider ? activeModel : ProviderCommand.defaultModelForProvider(p.id)

                if !models.isEmpty {
                    // Find the default model descriptor
                    let defaultDesc = models.first(where: { $0.id == defaultModelId }) ?? models.first
                    if let desc = defaultDesc {
                        let ctx = ProviderCommand.formatContextWindow(desc.contextWindow)
                        let inPrice = ProviderCommand.formatPrice(desc.inputPricePerMToken)
                        let outPrice = ProviderCommand.formatPrice(desc.outputPricePerMToken)
                        print("      \(dim)Default: \(desc.displayName)  |  Context: \(ctx)  |  In: \(inPrice)  Out: \(outPrice)\(reset)")
                    }

                    // List other available models briefly
                    let others = models.filter { $0.id != (defaultDesc?.id ?? "") }
                    if !others.isEmpty {
                        let otherNames = others.map(\.displayName).joined(separator: ", ")
                        print("      \(dim)Also: \(otherNames)\(reset)")
                    }
                } else if p.id == "openai" {
                    print("      \(dim)Default: gpt-4o  |  Context: 128k  |  In: $2.50/M  Out: $10/M\(reset)")
                }

                print()
            }

            let resolvedDesc = ModelCatalog.find(id: activeModel)
            let activeDisplayName = resolvedDesc?.displayName ?? activeModel
            print("  \(cyan)Active:\(reset) \(activeProvider) / \(activeDisplayName)")
            print()
            print("  Use `zyquo provider login <id>` to add a provider API key.")
            print("  Use `zyquo provider status <id>` to test connectivity.")
            print()
        }
    }

    // MARK: - Login Subcommand

    struct LoginProvider: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "login",
            abstract: "Store API key in Keychain"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Provider identifier (anthropic, openrouter, openai)")
        var providerId: String

        @Option(name: .long, help: "API key value (skips interactive prompt)")
        var key: String?

        @Flag(name: .long, help: "Read key from standard environment variable (e.g. ANTHROPIC_API_KEY)")
        var allowEnv: Bool = false

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let dim = noColor ? "" : "\u{1B}[2m"
            let reset = noColor ? "" : "\u{1B}[0m"
            let green = noColor ? "" : "\u{1B}[32m"
            let red = noColor ? "" : "\u{1B}[31m"
            let yellow = noColor ? "" : "\u{1B}[33m"

            guard ProviderCommand.validProviderIds.contains(providerId) else {
                print("\(red)Unknown provider '\(providerId)'.\(reset) Valid providers: \(ProviderCommand.validProviderIds.joined(separator: ", "))")
                throw ExitCode.failure
            }

            guard let providerInfo = ProviderCommand.knownProviders.first(where: { $0.id == providerId }) else {
                print("\(red)Internal error: provider '\(providerId)' passed validation but not found in registry.\(reset)")
                throw ExitCode.failure
            }

            // Resolve the key from the three possible sources
            let resolvedKey: String

            if let flagKey = key {
                // Source: --key flag (non-interactive)
                let trimmed = flagKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    print("\(red)Empty key provided via --key flag.\(reset)")
                    throw ExitCode.failure
                }
                resolvedKey = trimmed
            } else if allowEnv {
                // Source: environment variable
                let envVar = providerInfo.envVar
                guard let envValue = ProcessInfo.processInfo.environment[envVar] else {
                    print("\(red)Environment variable \(envVar) is not set.\(reset)")
                    print("Set it before running: export \(envVar)=<your-key>")
                    throw ExitCode.failure
                }
                let trimmed = envValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    print("\(red)Environment variable \(envVar) is set but empty.\(reset)")
                    throw ExitCode.failure
                }
                resolvedKey = trimmed
                print("Read API key from \(dim)\(envVar)\(reset).")
            } else {
                // Source: interactive prompt
                resolvedKey = try readKeyInteractively(
                    providerId: providerId,
                    providerName: providerInfo.name,
                    noColor: noColor
                )
            }

            // Validate key format
            if let warning = ProviderCommand.validateKeyFormat(providerId: providerId, key: resolvedKey) {
                print("\(yellow)Warning: \(warning)\(reset)")
                // Not a hard failure -- the user may have a valid key with an unusual format
            }

            // Store in Keychain
            let success = KeychainHelper.save(
                service: ProviderKeychain.service,
                account: providerId,
                string: resolvedKey
            )

            if success {
                let masked = ProviderCommand.maskedKey(resolvedKey)
                print("\(green)API key for \(providerInfo.name) stored in Keychain.\(reset) [\(dim)\(masked)\(reset)]")
            } else {
                print("\(red)Failed to store API key in Keychain.\(reset)")
                print("Check that Zyquo has Keychain access. Run `zyquo doctor` for diagnostics.")
                throw ExitCode.failure
            }
        }

        /// Interactive key entry with prompt, masking, and confirmation.
        private func readKeyInteractively(
            providerId: String,
            providerName: String,
            noColor: Bool
        ) throws -> String {
            let bold = noColor ? "" : "\u{1B}[1m"
            let dim = noColor ? "" : "\u{1B}[2m"
            let reset = noColor ? "" : "\u{1B}[0m"
            let red = noColor ? "" : "\u{1B}[31m"
            let cyan = noColor ? "" : "\u{1B}[36m"

            print()
            print("  \(bold)Login: \(providerName)\(reset)")
            print("  \(dim)Paste your API key below. Input will not be echoed.\(reset)")
            print()

            // Check if stdin is a terminal
            guard isatty(STDIN_FILENO) != 0 else {
                // Non-interactive: just read a line
                guard let line = readLine() else {
                    print("\(red)No input received.\(reset)")
                    throw ExitCode.failure
                }
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    print("\(red)Empty key provided.\(reset)")
                    throw ExitCode.failure
                }
                return trimmed
            }

            // Interactive: show prompt, read with echo disabled
            print("  \(cyan)>\(reset) ", terminator: "")
            fflush(stdout)

            guard let rawKey = readSecureInput() else {
                print()
                print("\(red)No input received.\(reset)")
                throw ExitCode.failure
            }
            // Move to next line after hidden input
            print()

            let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                print("\(red)Empty key provided. Aborted.\(reset)")
                throw ExitCode.failure
            }

            // Show masked key and ask for confirmation
            let masked = ProviderCommand.maskedKey(trimmed)
            print("  Key: \(dim)\(masked)\(reset)")
            print()
            print("  Save this key to Keychain? [y]es / [n]o")
            print("  \(cyan)>\(reset) ", terminator: "")
            fflush(stdout)

            guard let confirmation = readLine() else {
                print("\(red)No confirmation received. Aborted.\(reset)")
                throw ExitCode.failure
            }

            let answer = confirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard answer == "y" || answer == "yes" || answer.isEmpty else {
                print("Aborted. Key was not stored.")
                throw ExitCode.failure
            }

            return trimmed
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

    // MARK: - Logout Subcommand

    struct LogoutProvider: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logout",
            abstract: "Remove API key from Keychain"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Provider identifier")
        var providerId: String

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor
            let green = noColor ? "" : "\u{1B}[32m"
            let yellow = noColor ? "" : "\u{1B}[33m"
            let reset = noColor ? "" : "\u{1B}[0m"

            let deleted = KeychainHelper.delete(
                service: ProviderKeychain.service,
                account: providerId
            )

            if deleted {
                print("\(green)API key for \(providerId) removed from Keychain.\(reset)")
            } else {
                print("\(yellow)No API key found for \(providerId).\(reset)")
            }
        }
    }

    // MARK: - Status Subcommand

    struct StatusProvider: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Test provider connectivity and validate key format"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Provider identifier (anthropic, openrouter, openai). Omit to check all.")
        var providerId: String?

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let bold = noColor ? "" : "\u{1B}[1m"
            let dim = noColor ? "" : "\u{1B}[2m"
            let reset = noColor ? "" : "\u{1B}[0m"
            let green = noColor ? "" : "\u{1B}[32m"
            let red = noColor ? "" : "\u{1B}[31m"
            let yellow = noColor ? "" : "\u{1B}[33m"

            let check = noColor ? "[OK]" : "\(green)\u{2713}\(reset)"
            let fail = noColor ? "[FAIL]" : "\(red)\u{2717}\(reset)"
            let warn = noColor ? "[WARN]" : "\(yellow)!\(reset)"

            let providersToCheck: [(id: String, name: String, required: Bool, envVar: String)]

            if let specific = providerId {
                guard ProviderCommand.validProviderIds.contains(specific) else {
                    print("\(red)Unknown provider '\(specific)'.\(reset) Valid providers: \(ProviderCommand.validProviderIds.joined(separator: ", "))")
                    throw ExitCode.failure
                }
                providersToCheck = ProviderCommand.knownProviders.filter { $0.id == specific }
            } else {
                providersToCheck = ProviderCommand.knownProviders
            }

            print()
            print("  \(bold)Provider Status\(reset)")
            print()

            var anyFailed = false

            for p in providersToCheck {
                print("  \(bold)\(p.name)\(reset) (\(p.id))")

                // Step 1: Check if key exists in Keychain
                guard let storedKey = KeychainHelper.read(service: ProviderKeychain.service, account: p.id) else {
                    print("    \(fail) No API key in Keychain")
                    if p.required {
                        print("    \(dim)Run: zyquo provider login \(p.id)\(reset)")
                        anyFailed = true
                    } else {
                        print("    \(dim)Optional provider. Run: zyquo provider login \(p.id)\(reset)")
                    }
                    print()
                    continue
                }

                let masked = ProviderCommand.maskedKey(storedKey)
                print("    \(check) Key in Keychain: \(dim)\(masked)\(reset)")

                // Step 2: Validate key format
                if let formatWarning = ProviderCommand.validateKeyFormat(providerId: p.id, key: storedKey) {
                    print("    \(warn) Format: \(formatWarning)")
                } else {
                    print("    \(check) Key format looks valid")
                }

                // Step 3: Test connectivity with a lightweight request
                let connectResult = await testConnectivity(providerId: p.id, apiKey: storedKey)
                switch connectResult {
                case .success:
                    print("    \(check) Connectivity: OK")
                case .authError:
                    print("    \(fail) Connectivity: authentication failed (invalid key?)")
                    anyFailed = true
                case .networkError(let message):
                    print("    \(fail) Connectivity: \(message)")
                    anyFailed = true
                case .rateLimited:
                    print("    \(warn) Connectivity: rate limited (key is valid but throttled)")
                case .skipped:
                    print("    \(dim)Connectivity test not available for this provider.\(reset)")
                }

                print()
            }

            if anyFailed {
                print("  \(dim)Some checks failed. Run `zyquo doctor` for full diagnostics.\(reset)")
                print()
            }
        }

        private enum ConnectivityResult {
            case success
            case authError
            case networkError(String)
            case rateLimited
            case skipped
        }

        private func testConnectivity(providerId: String, apiKey: String) async -> ConnectivityResult {
            switch providerId {
            case "anthropic":
                return await testAnthropicConnectivity(apiKey: apiKey)
            case "openrouter":
                return await testOpenRouterConnectivity(apiKey: apiKey)
            case "openai":
                return await testOpenAIConnectivity(apiKey: apiKey)
            default:
                return .skipped
            }
        }

        /// Test Anthropic by sending a minimal request to the messages endpoint.
        /// We send a tiny prompt with max_tokens=1 to minimize cost.
        private func testAnthropicConnectivity(apiKey: String) async -> ConnectivityResult {
            guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
                return .networkError("invalid URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.timeoutInterval = 15

            let body: [String: Any] = [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 1,
                "messages": [
                    ["role": "user", "content": "hi"]
                ]
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                return .networkError("failed to build request")
            }

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .networkError("unexpected response type")
                }

                switch httpResponse.statusCode {
                case 200:
                    return .success
                case 401:
                    return .authError
                case 429:
                    return .rateLimited
                default:
                    return .networkError("HTTP \(httpResponse.statusCode)")
                }
            } catch {
                return .networkError(error.localizedDescription)
            }
        }

        /// Test OpenRouter by hitting their /auth/key endpoint.
        private func testOpenRouterConnectivity(apiKey: String) async -> ConnectivityResult {
            guard let url = URL(string: "https://openrouter.ai/api/v1/auth/key") else {
                return .networkError("invalid URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .networkError("unexpected response type")
                }

                switch httpResponse.statusCode {
                case 200:
                    return .success
                case 401, 403:
                    return .authError
                case 429:
                    return .rateLimited
                default:
                    return .networkError("HTTP \(httpResponse.statusCode)")
                }
            } catch {
                return .networkError(error.localizedDescription)
            }
        }

        /// Test OpenAI by hitting their /models endpoint.
        private func testOpenAIConnectivity(apiKey: String) async -> ConnectivityResult {
            guard let url = URL(string: "https://api.openai.com/v1/models") else {
                return .networkError("invalid URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .networkError("unexpected response type")
                }

                switch httpResponse.statusCode {
                case 200:
                    return .success
                case 401:
                    return .authError
                case 429:
                    return .rateLimited
                default:
                    return .networkError("HTTP \(httpResponse.statusCode)")
                }
            } catch {
                return .networkError(error.localizedDescription)
            }
        }
    }
}
