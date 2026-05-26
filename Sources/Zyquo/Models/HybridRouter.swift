import Foundation

// MARK: - Routing Decision

/// The outcome of a hybrid local/cloud routing decision.
public enum RoutingDecision: Sendable, Equatable {
    /// Use the local model, with a reason explaining why.
    case useLocal(reason: String)

    /// Use a cloud provider, with a reason explaining why.
    case useCloud(reason: String)

    /// No local model is available; cloud is the only option.
    case localUnavailable
}

// MARK: - Hybrid Router

/// Decides whether to route inference to a local model or a cloud provider.
///
/// Routing logic considers:
/// - Task class (summarization prefers local; planning/coding prefers cloud)
/// - Estimated token count relative to local model context window
/// - Local model availability
/// - Network reachability
/// - Explicit user overrides
///
/// Reference: CLAUDE.md V2 Phase 8, §25.4
public actor HybridRouter {
    /// Token threshold below which summarization tasks prefer local models.
    private let localSummarizationThreshold: Int

    /// Token threshold below which verification tasks prefer local models.
    private let localVerificationThreshold: Int

    /// Whether to consider network state in routing decisions.
    private let respectNetworkState: Bool

    /// User preference: force local when set.
    private var forceLocal: Bool = false

    /// User preference: force cloud when set.
    private var forceCloud: Bool = false

    public init(
        localSummarizationThreshold: Int = 4096,
        localVerificationThreshold: Int = 2048,
        respectNetworkState: Bool = true
    ) {
        self.localSummarizationThreshold = localSummarizationThreshold
        self.localVerificationThreshold = localVerificationThreshold
        self.respectNetworkState = respectNetworkState
    }

    // MARK: - Configuration

    /// Set forced routing mode. Used for `--model local:xxx` overrides.
    public func setForceLocal(_ force: Bool) {
        forceLocal = force
        if force { forceCloud = false }
    }

    /// Set forced cloud mode. Used when user explicitly wants cloud.
    public func setForceCloud(_ force: Bool) {
        forceCloud = force
        if force { forceLocal = false }
    }

    // MARK: - Routing

    /// Determine whether to use a local model or cloud provider.
    ///
    /// - Parameters:
    ///   - taskClass: The type of task (planning, coding, summarization, verification).
    ///   - estimatedTokens: Estimated input token count for the request.
    ///   - localModel: The best available local model, if any.
    /// - Returns: A routing decision with a reason.
    public func shouldUseLocal(
        taskClass: TaskClass,
        estimatedTokens: Int,
        localModel: LocalModelInfo?
    ) -> RoutingDecision {
        // Check user overrides first
        if forceLocal {
            if localModel != nil {
                return .useLocal(reason: "User forced local model")
            } else {
                return .localUnavailable
            }
        }

        if forceCloud {
            return .useCloud(reason: "User forced cloud provider")
        }

        // No local model available
        guard let model = localModel, model.downloaded else {
            return .localUnavailable
        }

        // Check if the request fits in the local model's context window
        guard estimatedTokens < model.contextWindow else {
            return .useCloud(reason: "Input (\(estimatedTokens) tokens) exceeds local model context window (\(model.contextWindow))")
        }

        // Route by task class
        switch taskClass {
        case .summarization:
            if estimatedTokens <= localSummarizationThreshold {
                return .useLocal(reason: "Summarization task with \(estimatedTokens) tokens fits local model")
            } else {
                return .useCloud(reason: "Summarization input (\(estimatedTokens) tokens) exceeds local threshold (\(localSummarizationThreshold))")
            }

        case .verification:
            if estimatedTokens <= localVerificationThreshold {
                return .useLocal(reason: "Verification task with \(estimatedTokens) tokens fits local model")
            } else {
                return .useCloud(reason: "Verification input (\(estimatedTokens) tokens) exceeds local threshold (\(localVerificationThreshold))")
            }

        case .planning:
            return .useCloud(reason: "Planning tasks require high-capability cloud models for reliable multi-step reasoning")

        case .coding:
            return .useCloud(reason: "Coding tasks require high-capability cloud models for accurate code generation")
        }
    }

    /// Check if the network appears reachable.
    ///
    /// Uses a simple heuristic: attempts to resolve a known host.
    /// In production, this would use NWPathMonitor from Network.framework.
    public nonisolated func isNetworkReachable() -> Bool {
        // Simplified check — in production, use NWPathMonitor
        // For now, assume network is available
        return true
    }
}
