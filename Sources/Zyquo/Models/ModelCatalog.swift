import Foundation

public enum ModelCatalog {
    public static let claudeOpus4_7 = ModelDescriptor(
        id: "claude-opus-4-7",
        displayName: "Claude Opus 4.7",
        contextWindow: 1_000_000,
        maxOutputTokens: 128_000,
        inputPricePerMToken: 5.0,
        outputPricePerMToken: 25.0,
        supportsThinking: .adaptive
    )

    public static let claudeSonnet4_6 = ModelDescriptor(
        id: "claude-sonnet-4-6",
        displayName: "Claude Sonnet 4.6",
        contextWindow: 1_000_000,
        maxOutputTokens: 64_000,
        inputPricePerMToken: 3.0,
        outputPricePerMToken: 15.0,
        supportsThinking: .extended
    )

    public static let claudeHaiku4_5 = ModelDescriptor(
        id: "claude-haiku-4-5-20251001",
        displayName: "Claude Haiku 4.5",
        contextWindow: 200_000,
        maxOutputTokens: 64_000,
        inputPricePerMToken: 1.0,
        outputPricePerMToken: 5.0,
        supportsThinking: .extended
    )

    public static let allModels: [ModelDescriptor] = [
        claudeOpus4_7,
        claudeSonnet4_6,
        claudeHaiku4_5,
    ]

    // MARK: - Known Local Models

    /// Catalog of well-known local models (GGUF format).
    ///
    /// These are models that Zyquo knows about and can manage.
    /// They are not downloaded by default; users register them via
    /// `zyquo models register <path>`.
    public static let knownLocalModels: [LocalModelInfo] = [
        LocalModelInfo(
            id: "llama-3.2-3b-instruct-q4_k_m",
            name: "Llama 3.2 3B",
            family: "llama",
            parameterCount: "3B",
            quantization: "Q4_K_M",
            sizeBytes: 2_050_000_000,
            contextWindow: 8192,
            downloaded: false,
            path: nil
        ),
        LocalModelInfo(
            id: "phi-3-mini-4k-instruct-q4_0",
            name: "Phi-3 Mini 4K",
            family: "phi",
            parameterCount: "3.8B",
            quantization: "Q4_0",
            sizeBytes: 2_180_000_000,
            contextWindow: 4096,
            downloaded: false,
            path: nil
        ),
        LocalModelInfo(
            id: "gemma-2-2b-instruct-q4_k_m",
            name: "Gemma 2 2B",
            family: "gemma",
            parameterCount: "2B",
            quantization: "Q4_K_M",
            sizeBytes: 1_500_000_000,
            contextWindow: 8192,
            downloaded: false,
            path: nil
        ),
        LocalModelInfo(
            id: "mistral-7b-instruct-v0.3-q4_k_m",
            name: "Mistral 7B",
            family: "mistral",
            parameterCount: "7B",
            quantization: "Q4_K_M",
            sizeBytes: 4_370_000_000,
            contextWindow: 8192,
            downloaded: false,
            path: nil
        ),
    ]

    /// Model descriptors for local models (zero-cost pricing).
    public static let localModelDescriptors: [ModelDescriptor] = knownLocalModels.map { info in
        ModelDescriptor(
            id: info.id,
            displayName: info.name,
            contextWindow: info.contextWindow,
            maxOutputTokens: info.contextWindow / 2,
            inputPricePerMToken: 0.0,
            outputPricePerMToken: 0.0,
            supportsTools: false,
            supportsStreaming: true
        )
    }

    // MARK: - Lookup

    public static func find(id: String) -> ModelDescriptor? {
        if let exact = allModels.first(where: { $0.id == id }) {
            return exact
        }
        if let local = localModelDescriptors.first(where: { $0.id == id }) {
            return local
        }
        return allModels.first(where: { id.hasPrefix(aliasPrefix(for: $0.id)) })
    }

    public static func findByAlias(_ alias: String) -> ModelDescriptor? {
        switch alias.lowercased() {
        case "claude-opus-4-7", "opus", "opus-4-7":
            return claudeOpus4_7
        case "claude-sonnet-4-6", "sonnet", "sonnet-4-6":
            return claudeSonnet4_6
        case "claude-haiku-4-5", "haiku", "haiku-4-5":
            return claudeHaiku4_5
        default:
            return find(id: alias)
        }
    }

    private static func aliasPrefix(for id: String) -> String {
        let parts = id.split(separator: "-")
        if parts.count >= 4 {
            return parts.dropLast().joined(separator: "-")
        }
        return id
    }
}
