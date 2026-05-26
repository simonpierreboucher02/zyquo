import Foundation

public enum TaskClass: String, Sendable {
    case planning
    case coding
    case summarization
    case verification
}

public actor ModelRouter {
    private let config: ProvidersConfig
    private var providers: [String: any LLMProvider] = [:]
    private var localProvider: LocalProvider?
    private var hybridRouter: HybridRouter?

    public init(config: ProvidersConfig) {
        self.config = config
    }

    public func register(_ provider: any LLMProvider) {
        providers[provider.id] = provider
    }

    /// Register the local provider with hybrid routing support.
    ///
    /// - Parameters:
    ///   - provider: The local model provider.
    ///   - hybridRouter: Optional hybrid router for local/cloud decisions.
    public func registerLocal(_ provider: LocalProvider, hybridRouter: HybridRouter? = nil) {
        self.localProvider = provider
        self.hybridRouter = hybridRouter
        providers[provider.id] = provider
    }

    public func resolve(for taskClass: TaskClass) -> (provider: any LLMProvider, model: String)? {
        let providerId = config.resolvedProvider
        guard let provider = providers[providerId] else { return nil }

        if let overrideModel = config.overrideModel {
            // Check for local: prefix override
            if overrideModel.hasPrefix("local:") {
                let localModelId = String(overrideModel.dropFirst(6))
                if let local = localProvider, local.hasEngine(for: localModelId) {
                    return (local, localModelId)
                }
            }
            let resolved = resolveModelId(overrideModel)
            return (provider, resolved)
        }

        let model = defaultModel(for: taskClass)
        return (provider, model)
    }

    public func resolveExplicit(providerId: String? = nil, modelId: String? = nil) -> (provider: any LLMProvider, model: String)? {
        let pid = providerId ?? config.resolvedProvider
        guard let provider = providers[pid] else { return nil }
        let model = modelId.map { resolveModelId($0) } ?? config.resolvedModel
        let resolved = resolveModelId(model)
        return (provider, resolved)
    }

    /// Resolve a specific local model by ID.
    ///
    /// - Parameter modelId: The local model identifier.
    /// - Returns: The local provider and model ID, or nil if not available.
    public func resolveLocal(modelId: String) -> (provider: any LLMProvider, model: String)? {
        guard let local = localProvider, local.hasEngine(for: modelId) else {
            return nil
        }
        return (local, modelId)
    }

    /// Resolve using hybrid routing, which may choose local or cloud.
    ///
    /// - Parameters:
    ///   - taskClass: The type of task.
    ///   - estimatedTokens: Estimated input token count.
    ///   - localModelInfo: Info about the best available local model.
    /// - Returns: The chosen provider and model ID, or nil.
    public func resolveHybrid(
        for taskClass: TaskClass,
        estimatedTokens: Int,
        localModelInfo: LocalModelInfo?
    ) async -> (provider: any LLMProvider, model: String, decision: RoutingDecision)? {
        guard let router = hybridRouter else {
            // No hybrid router configured; fall back to standard resolution
            if let result = resolve(for: taskClass) {
                return (result.provider, result.model, .useCloud(reason: "No hybrid router configured"))
            }
            return nil
        }

        let decision = await router.shouldUseLocal(
            taskClass: taskClass,
            estimatedTokens: estimatedTokens,
            localModel: localModelInfo
        )

        switch decision {
        case .useLocal:
            if let localModel = localModelInfo,
               let result = resolveLocal(modelId: localModel.id) {
                return (result.provider, result.model, decision)
            }
            // Fallback to cloud if local resolution fails
            if let result = resolve(for: taskClass) {
                return (result.provider, result.model, .useCloud(reason: "Local model resolution failed, falling back to cloud"))
            }
            return nil

        case .useCloud, .localUnavailable:
            if let result = resolve(for: taskClass) {
                return (result.provider, result.model, decision)
            }
            return nil
        }
    }

    public func availableProviders() -> [String] {
        Array(providers.keys).sorted()
    }

    /// Check if a local provider is registered and has any engines.
    public func hasLocalProvider() -> Bool {
        guard let local = localProvider else { return false }
        return !local.registeredModelIds().isEmpty
    }

    private func defaultModel(for taskClass: TaskClass) -> String {
        switch taskClass {
        case .planning: return ModelCatalog.claudeOpus4_7.id
        case .coding: return ModelCatalog.claudeSonnet4_6.id
        case .summarization: return ModelCatalog.claudeHaiku4_5.id
        case .verification: return ModelCatalog.claudeSonnet4_6.id
        }
    }

    private func resolveModelId(_ alias: String) -> String {
        if let descriptor = ModelCatalog.findByAlias(alias) {
            return descriptor.id
        }
        return alias
    }
}
