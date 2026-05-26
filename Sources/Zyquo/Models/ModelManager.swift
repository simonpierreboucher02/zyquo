import Foundation

// MARK: - Local Model Info

/// Describes a local model, whether downloaded or available for download.
///
/// Reference: CLAUDE.md V2 Phase 8
public struct LocalModelInfo: Sendable, Codable, Equatable {
    /// Unique identifier, e.g. "llama-3.2-3b-q4_k_m"
    public let id: String

    /// Human-readable name, e.g. "Llama 3.2 3B"
    public let name: String

    /// Model family, e.g. "llama", "mistral", "phi", "gemma"
    public let family: String

    /// Parameter count as a string, e.g. "7B", "13B", "3B"
    public let parameterCount: String

    /// Quantization level, e.g. "Q4_K_M", "Q5_K_S", "Q8_0", "F16"
    public let quantization: String

    /// File size in bytes (0 if not downloaded)
    public let sizeBytes: UInt64

    /// Maximum context window in tokens
    public let contextWindow: Int

    /// Whether the model file is present on disk
    public let downloaded: Bool

    /// Path to the model file (nil if not downloaded)
    public let path: URL?

    public init(
        id: String,
        name: String,
        family: String,
        parameterCount: String,
        quantization: String,
        sizeBytes: UInt64,
        contextWindow: Int,
        downloaded: Bool,
        path: URL?
    ) {
        self.id = id
        self.name = name
        self.family = family
        self.parameterCount = parameterCount
        self.quantization = quantization
        self.sizeBytes = sizeBytes
        self.contextWindow = contextWindow
        self.downloaded = downloaded
        self.path = path
    }

    /// Human-readable file size string.
    public var formattedSize: String {
        if sizeBytes == 0 { return "--" }
        let gb = Double(sizeBytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(sizeBytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Local Model Metadata

/// Metadata stored alongside a registered local model.
public struct LocalModelMetadata: Sendable, Codable, Equatable {
    public let family: String
    public let parameterCount: String
    public let quantization: String
    public let contextWindow: Int
    public let addedAt: Date

    public init(
        family: String,
        parameterCount: String,
        quantization: String,
        contextWindow: Int,
        addedAt: Date = Date()
    ) {
        self.family = family
        self.parameterCount = parameterCount
        self.quantization = quantization
        self.contextWindow = contextWindow
        self.addedAt = addedAt
    }
}

// MARK: - Model Registry Entry (internal persistence)

/// Persisted entry in the model registry JSON file.
struct ModelRegistryEntry: Codable, Equatable {
    let id: String
    let name: String
    let path: String
    let metadata: LocalModelMetadata
}

// MARK: - Model Manager

/// Manages the lifecycle of local models: registration, listing, removal.
///
/// Models are stored under `~/Library/Application Support/Zyquo/models/`
/// with a registry JSON file tracking metadata.
///
/// Reference: CLAUDE.md V2 Phase 8
public actor ModelManager {
    /// Root directory for local model storage.
    public let modelsDirectory: URL

    /// Path to the registry JSON file.
    private var registryPath: URL {
        modelsDirectory.appendingPathComponent("registry.json")
    }

    /// In-memory cache of the registry.
    private var entries: [String: ModelRegistryEntry] = [:]

    /// Whether the registry has been loaded from disk.
    private var loaded = false

    public init(modelsDirectory: URL? = nil) {
        self.modelsDirectory = modelsDirectory ?? Self.defaultModelsDirectory
    }

    /// Default models directory: ~/Library/Application Support/Zyquo/models/
    public static var defaultModelsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Zyquo")
            .appendingPathComponent("models")
    }

    // MARK: - Directory Setup

    /// Ensure the models directory exists.
    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Registry Operations

    /// Load the registry from disk if not already loaded.
    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        guard let data = try? Data(contentsOf: registryPath),
              let decoded = try? JSONDecoder().decode([ModelRegistryEntry].self, from: data) else {
            entries = [:]
            return
        }

        entries = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    /// Persist the registry to disk.
    private func save() throws {
        let sorted = entries.values.sorted { $0.id < $1.id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sorted)
        try data.write(to: registryPath, options: .atomic)
    }

    // MARK: - Public API

    /// Register a model file with metadata.
    ///
    /// - Parameters:
    ///   - id: Unique model identifier.
    ///   - path: Path to the GGUF (or other format) model file.
    ///   - metadata: Model metadata (family, params, quantization, etc.).
    /// - Throws: If the file does not exist or registry cannot be saved.
    public func register(id: String, path: URL, metadata: LocalModelMetadata) throws {
        ensureLoaded()

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ZyquoError.config(ConfigError(
                code: "model.file_not_found",
                description: "Model file not found at '\(path.path)'",
                remediation: "Verify the path points to a valid model file"
            ))
        }

        let name = Self.humanName(id: id, family: metadata.family, params: metadata.parameterCount)
        let entry = ModelRegistryEntry(
            id: id,
            name: name,
            path: path.path,
            metadata: metadata
        )

        entries[id] = entry

        try ensureDirectory()
        try save()
    }

    /// Remove a registered model.
    ///
    /// - Parameter id: The model identifier to remove.
    /// - Returns: `true` if the model was found and removed.
    @discardableResult
    public func remove(id: String) throws -> Bool {
        ensureLoaded()

        guard entries.removeValue(forKey: id) != nil else {
            return false
        }

        try save()
        return true
    }

    /// Check if a model with the given ID is registered and its file exists.
    public func isDownloaded(id: String) -> Bool {
        ensureLoaded()
        guard let entry = entries[id] else { return false }
        return FileManager.default.fileExists(atPath: entry.path)
    }

    /// Return the file path for a registered model, if it exists.
    public func modelPath(id: String) -> URL? {
        ensureLoaded()
        guard let entry = entries[id] else { return nil }
        let url = URL(fileURLWithPath: entry.path)
        return FileManager.default.fileExists(atPath: entry.path) ? url : nil
    }

    /// List all registered local models with their current download status.
    public func listLocal() -> [LocalModelInfo] {
        ensureLoaded()
        return entries.values.sorted(by: { $0.id < $1.id }).map { entry in
            let path = URL(fileURLWithPath: entry.path)
            let exists = FileManager.default.fileExists(atPath: entry.path)
            let size: UInt64
            if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: entry.path) {
                size = attrs[.size] as? UInt64 ?? 0
            } else {
                size = 0
            }
            return LocalModelInfo(
                id: entry.id,
                name: entry.name,
                family: entry.metadata.family,
                parameterCount: entry.metadata.parameterCount,
                quantization: entry.metadata.quantization,
                sizeBytes: size,
                contextWindow: entry.metadata.contextWindow,
                downloaded: exists,
                path: exists ? path : nil
            )
        }
    }

    /// Return the full catalog of known downloadable local models,
    /// merged with download status from the local registry.
    public func availableModels() -> [LocalModelInfo] {
        ensureLoaded()
        var result: [LocalModelInfo] = []

        // Include all known models from catalog, enriched with local state
        for catalogModel in ModelCatalog.knownLocalModels {
            if let entry = entries[catalogModel.id] {
                let path = URL(fileURLWithPath: entry.path)
                let exists = FileManager.default.fileExists(atPath: entry.path)
                let size: UInt64
                if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: entry.path) {
                    size = attrs[.size] as? UInt64 ?? 0
                } else {
                    size = catalogModel.sizeBytes
                }
                result.append(LocalModelInfo(
                    id: catalogModel.id,
                    name: catalogModel.name,
                    family: catalogModel.family,
                    parameterCount: catalogModel.parameterCount,
                    quantization: catalogModel.quantization,
                    sizeBytes: size,
                    contextWindow: catalogModel.contextWindow,
                    downloaded: exists,
                    path: exists ? path : nil
                ))
            } else {
                result.append(catalogModel)
            }
        }

        // Include any locally-registered models not in the catalog
        for entry in entries.values.sorted(by: { $0.id < $1.id }) {
            if !ModelCatalog.knownLocalModels.contains(where: { $0.id == entry.id }) {
                let path = URL(fileURLWithPath: entry.path)
                let exists = FileManager.default.fileExists(atPath: entry.path)
                let size: UInt64
                if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: entry.path) {
                    size = attrs[.size] as? UInt64 ?? 0
                } else {
                    size = 0
                }
                result.append(LocalModelInfo(
                    id: entry.id,
                    name: entry.name,
                    family: entry.metadata.family,
                    parameterCount: entry.metadata.parameterCount,
                    quantization: entry.metadata.quantization,
                    sizeBytes: size,
                    contextWindow: entry.metadata.contextWindow,
                    downloaded: exists,
                    path: exists ? path : nil
                ))
            }
        }

        return result
    }

    /// Get info for a single model by ID.
    public func modelInfo(id: String) -> LocalModelInfo? {
        ensureLoaded()

        // Check local registry first
        if let entry = entries[id] {
            let path = URL(fileURLWithPath: entry.path)
            let exists = FileManager.default.fileExists(atPath: entry.path)
            let size: UInt64
            if exists, let attrs = try? FileManager.default.attributesOfItem(atPath: entry.path) {
                size = attrs[.size] as? UInt64 ?? 0
            } else {
                size = 0
            }
            return LocalModelInfo(
                id: entry.id,
                name: entry.name,
                family: entry.metadata.family,
                parameterCount: entry.metadata.parameterCount,
                quantization: entry.metadata.quantization,
                sizeBytes: size,
                contextWindow: entry.metadata.contextWindow,
                downloaded: exists,
                path: exists ? path : nil
            )
        }

        // Check known catalog
        return ModelCatalog.knownLocalModels.first { $0.id == id }
    }

    // MARK: - Filename Parsing

    /// Parse a GGUF filename into model metadata.
    ///
    /// Common patterns:
    /// - `llama-3.2-3b-instruct-q4_k_m.gguf`
    /// - `mistral-7b-instruct-v0.3-q5_k_s.gguf`
    /// - `phi-3-mini-4k-instruct-q4_0.gguf`
    public static func parseFilename(_ filename: String) -> (id: String, metadata: LocalModelMetadata)? {
        let name = filename
            .replacingOccurrences(of: ".gguf", with: "")
            .lowercased()

        let parts = name.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return nil }

        // Detect family
        let family: String
        if name.contains("llama") { family = "llama" }
        else if name.contains("mistral") { family = "mistral" }
        else if name.contains("phi") { family = "phi" }
        else if name.contains("gemma") { family = "gemma" }
        else if name.contains("qwen") { family = "qwen" }
        else { family = parts[0] }

        // Detect parameter count
        let paramPattern = parts.first { $0.hasSuffix("b") && $0.dropLast().allSatisfy({ $0.isNumber || $0 == "." }) }
        let parameterCount = paramPattern?.uppercased() ?? "unknown"

        // Detect quantization
        let quantPattern = parts.first { $0.hasPrefix("q") && $0.count >= 2 && $0.dropFirst().first?.isNumber == true }
        let quantization = quantPattern?.uppercased() ?? "Q4_K_M"

        // Estimate context window from name
        let contextWindow: Int
        if name.contains("4k") { contextWindow = 4096 }
        else if name.contains("8k") { contextWindow = 8192 }
        else if name.contains("16k") { contextWindow = 16384 }
        else if name.contains("32k") { contextWindow = 32768 }
        else if name.contains("128k") { contextWindow = 131072 }
        else { contextWindow = 4096 }

        let metadata = LocalModelMetadata(
            family: family,
            parameterCount: parameterCount,
            quantization: quantization,
            contextWindow: contextWindow
        )

        return (id: name, metadata: metadata)
    }

    // MARK: - Helpers

    private static func humanName(id: String, family: String, params: String) -> String {
        let familyName = family.prefix(1).uppercased() + family.dropFirst()
        return "\(familyName) \(params)"
    }
}
