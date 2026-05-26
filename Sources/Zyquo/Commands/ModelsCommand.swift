import ArgumentParser
import Foundation

// MARK: - ModelsCommand

/// Manage local and cloud models.
///
/// Provides subcommands for listing, inspecting, registering, and
/// removing local models. Cloud models are shown for reference.
///
/// Reference: CLAUDE.md V2 Phase 8
struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "Manage local and cloud models",
        subcommands: [
            ListModels.self,
            LocalModels.self,
            InfoModel.self,
            RemoveModel.self,
            RegisterModel.self,
        ],
        defaultSubcommand: ListModels.self
    )

    // MARK: - List (all models)

    struct ListModels: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all models (cloud + local)"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            // Cloud models
            let cloudModels = ModelCatalog.allModels
            printHeader("Cloud Models", count: cloudModels.count, noColor: noColor)

            for model in cloudModels {
                let ctx = formatTokens(model.contextWindow)
                let price = String(format: "$%.2f/$%.2f per MTok", model.inputPricePerMToken, model.outputPricePerMToken)
                if noColor {
                    print("  \(model.displayName.padding(toLength: 24, withPad: " ", startingAt: 0)) \(ctx)  \(price)")
                } else {
                    print("  \u{1B}[1m\(model.displayName.padding(toLength: 24, withPad: " ", startingAt: 0))\u{1B}[0m \u{1B}[2m\(ctx)  \(price)\u{1B}[0m")
                }
            }

            // Local models
            let manager = ModelManager()
            let localModels = await manager.availableModels()
            print()
            printHeader("Local Models", count: localModels.count, noColor: noColor)

            if localModels.isEmpty {
                print("  No local models registered. Use `zyquo models register <path>` to add one.")
            } else {
                for model in localModels {
                    let status = model.downloaded ? "[downloaded]" : "[not downloaded]"
                    let size = model.formattedSize
                    let ctx = formatTokens(model.contextWindow)
                    if noColor {
                        print("  \(model.name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(model.quantization.padding(toLength: 8, withPad: " ", startingAt: 0)) \(ctx)  \(size.padding(toLength: 8, withPad: " ", startingAt: 0)) \(status)")
                    } else {
                        let statusColor = model.downloaded ? "\u{1B}[32m" : "\u{1B}[33m"
                        print("  \u{1B}[1m\(model.name.padding(toLength: 24, withPad: " ", startingAt: 0))\u{1B}[0m \(model.quantization.padding(toLength: 8, withPad: " ", startingAt: 0)) \u{1B}[2m\(ctx)  \(size.padding(toLength: 8, withPad: " ", startingAt: 0))\u{1B}[0m \(statusColor)\(status)\u{1B}[0m")
                    }
                }
            }
            print()
        }
    }

    // MARK: - Local (downloaded models only)

    struct LocalModels: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "local",
            abstract: "Show only downloaded local models with sizes"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let manager = ModelManager()
            let models = await manager.listLocal()

            printHeader("Downloaded Local Models", count: models.count, noColor: noColor)

            if models.isEmpty {
                print("  No local models downloaded.")
                print("  Use `zyquo models register <path>` to register a GGUF model file.")
                print()
                return
            }

            for model in models {
                let status = model.downloaded ? "ready" : "file missing"
                let size = model.formattedSize
                if noColor {
                    print("  \(model.id.padding(toLength: 40, withPad: " ", startingAt: 0)) \(size.padding(toLength: 10, withPad: " ", startingAt: 0)) \(status)")
                } else {
                    let statusColor = model.downloaded ? "\u{1B}[32m" : "\u{1B}[31m"
                    print("  \u{1B}[1m\(model.id.padding(toLength: 40, withPad: " ", startingAt: 0))\u{1B}[0m \u{1B}[2m\(size.padding(toLength: 10, withPad: " ", startingAt: 0))\u{1B}[0m \(statusColor)\(status)\u{1B}[0m")
                }
            }
            print()
        }
    }

    // MARK: - Info

    struct InfoModel: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Show detailed model information"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Model identifier")
        var modelId: String

        func run() async throws {
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            // Check cloud models first
            if let cloud = ModelCatalog.find(id: modelId) {
                printModelInfo(cloud, noColor: noColor)
                return
            }

            // Check local models
            let manager = ModelManager()
            if let local = await manager.modelInfo(id: modelId) {
                printLocalModelInfo(local, noColor: noColor)
                return
            }

            print("Model '\(modelId)' not found.")
            print("Use `zyquo models list` to see available models.")
            throw ExitCode.failure
        }

        private func printModelInfo(_ model: ModelDescriptor, noColor: Bool) {
            print()
            if noColor {
                print("  Model: \(model.displayName)")
            } else {
                print("  \u{1B}[1mModel: \(model.displayName)\u{1B}[0m")
            }
            print("  ID:               \(model.id)")
            print("  Type:             Cloud")
            print("  Context Window:   \(formatTokens(model.contextWindow))")
            print("  Max Output:       \(formatTokens(model.maxOutputTokens))")
            print("  Input Price:      $\(String(format: "%.2f", model.inputPricePerMToken)) / MTok")
            print("  Output Price:     $\(String(format: "%.2f", model.outputPricePerMToken)) / MTok")
            print("  Supports Tools:   \(model.supportsTools ? "yes" : "no")")
            print("  Streaming:        \(model.supportsStreaming ? "yes" : "no")")
            print()
        }

        private func printLocalModelInfo(_ model: LocalModelInfo, noColor: Bool) {
            print()
            if noColor {
                print("  Model: \(model.name)")
            } else {
                print("  \u{1B}[1mModel: \(model.name)\u{1B}[0m")
            }
            print("  ID:               \(model.id)")
            print("  Type:             Local")
            print("  Family:           \(model.family)")
            print("  Parameters:       \(model.parameterCount)")
            print("  Quantization:     \(model.quantization)")
            print("  Context Window:   \(formatTokens(model.contextWindow))")
            print("  Size:             \(model.formattedSize)")
            print("  Downloaded:       \(model.downloaded ? "yes" : "no")")
            if let path = model.path {
                print("  Path:             \(path.path)")
            }
            print()
        }
    }

    // MARK: - Remove

    struct RemoveModel: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a downloaded local model from the registry"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Model identifier to remove")
        var modelId: String

        func run() async throws {
            let manager = ModelManager()
            let removed = try await manager.remove(id: modelId)
            if removed {
                print("Model '\(modelId)' removed from registry.")
            } else {
                print("Model '\(modelId)' not found in registry.")
                throw ExitCode.failure
            }
        }
    }

    // MARK: - Register

    struct RegisterModel: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "register",
            abstract: "Register a GGUF model file as a local model"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "Path to the GGUF model file")
        var path: String

        @Option(name: .long, help: "Override model ID (default: derived from filename)")
        var id: String?

        @Option(name: .long, help: "Model family (llama, mistral, phi, gemma)")
        var family: String?

        @Option(name: .long, help: "Parameter count (e.g. 7B, 3B)")
        var params: String?

        @Option(name: .long, help: "Quantization (e.g. Q4_K_M, Q8_0)")
        var quant: String?

        @Option(name: .long, help: "Context window size in tokens")
        var contextWindow: Int?

        func run() async throws {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let filename = url.lastPathComponent

            guard FileManager.default.fileExists(atPath: url.path) else {
                print("File not found: \(url.path)")
                throw ExitCode.failure
            }

            // Parse metadata from filename or flags
            let parsed = ModelManager.parseFilename(filename)

            let modelId = id ?? parsed?.id ?? filename.replacingOccurrences(of: ".gguf", with: "").lowercased()
            let metadata = LocalModelMetadata(
                family: family ?? parsed?.metadata.family ?? "unknown",
                parameterCount: params ?? parsed?.metadata.parameterCount ?? "unknown",
                quantization: quant ?? parsed?.metadata.quantization ?? "unknown",
                contextWindow: contextWindow ?? parsed?.metadata.contextWindow ?? 4096
            )

            let manager = ModelManager()
            try await manager.register(id: modelId, path: url, metadata: metadata)

            print("Registered local model '\(modelId)' from \(filename)")
            print("  Family:       \(metadata.family)")
            print("  Parameters:   \(metadata.parameterCount)")
            print("  Quantization: \(metadata.quantization)")
            print("  Context:      \(formatTokens(metadata.contextWindow))")
        }
    }
}

// MARK: - Formatting Helpers

private func formatTokens(_ count: Int) -> String {
    if count >= 1_000_000 {
        return String(format: "%.0fM ctx", Double(count) / 1_000_000)
    } else if count >= 1_000 {
        return String(format: "%.0fk ctx", Double(count) / 1_000)
    }
    return "\(count) ctx"
}

private func printHeader(_ title: String, count: Int, noColor: Bool) {
    if noColor {
        print("\(title) (\(count)):")
        print(String(repeating: "-", count: 70))
    } else {
        print("\u{1B}[1m\(title) (\(count)):\u{1B}[0m")
        print("\u{1B}[2m\(String(repeating: "-", count: 70))\u{1B}[0m")
    }
}
