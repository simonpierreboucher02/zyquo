import Foundation

// MARK: - ApprovalDecision

/// The result of checking whether a command requires user approval.
public enum ApprovalDecision: Sendable, Equatable {
    /// The command was auto-approved (no user interaction needed).
    case autoApproved(reason: String)
    /// The command requires explicit user approval before execution.
    case requiresApproval
    /// The command was denied and must not be executed.
    case denied(reason: String)

    public var isApproved: Bool {
        if case .autoApproved = self { return true }
        return false
    }

    public static func == (lhs: ApprovalDecision, rhs: ApprovalDecision) -> Bool {
        switch (lhs, rhs) {
        case (.autoApproved(let a), .autoApproved(let b)): return a == b
        case (.requiresApproval, .requiresApproval): return true
        case (.denied(let a), .denied(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - ApprovalSource

/// Records how a command was approved for audit trail purposes.
public enum ApprovalSource: String, Sendable, Codable {
    /// Auto-approved because the command was SAFE and auto_approve_safe is on.
    case autoSafe
    /// Auto-approved because a matching trust grant was found.
    case trustGrant
    /// Approved by the user during an interactive prompt.
    case userApproved
    /// Denied by the user.
    case userDenied
    /// Denied by policy (e.g., workspace boundary violation).
    case policyDenied
}

// MARK: - ApprovalGate

/// Decides whether a command can proceed without user interaction,
/// based on risk assessment, trust grants, and configuration.
///
/// The gate does NOT prompt the user itself — it returns a decision
/// that the caller (UI layer) uses to decide whether to show a prompt.
///
/// Reference: CLAUDE.md §19.4
public struct ApprovalGate: Sendable {
    /// Whether SAFE-tier commands are auto-approved.
    public let autoApproveSafe: Bool

    public init(autoApproveSafe: Bool) {
        self.autoApproveSafe = autoApproveSafe
    }

    /// Check whether a command needs approval.
    ///
    /// - Parameters:
    ///   - command: The shell command to check.
    ///   - risk: The risk assessment from RiskClassifier.
    ///   - trustStore: The trust store to check for existing grants.
    /// - Returns: An approval decision.
    public func check(
        command: String,
        risk: RiskAssessment,
        trustStore: TrustStore
    ) -> ApprovalDecision {
        // Rule 1: SAFE commands with auto-approve enabled → auto-approve
        if risk.tier == .safe && autoApproveSafe {
            return .autoApproved(reason: "SAFE tier with auto-approve enabled")
        }

        // Rule 2: Check trust grants for any tier
        if let grant = trustStore.findGrant(for: command, riskTier: risk.tier) {
            return .autoApproved(
                reason: "Trust grant [\(grant.scope.rawValue)] for '\(grant.pattern)'"
            )
        }

        // Rule 3: Everything else requires approval
        return .requiresApproval
    }

    /// Validate whether a proposed trust scope is allowed for a given risk tier.
    ///
    /// CRITICAL commands can NEVER receive workspace or global scope.
    ///
    /// - Parameters:
    ///   - scope: The proposed trust scope.
    ///   - riskTier: The risk tier of the command.
    /// - Returns: True if the scope is allowed for this risk tier.
    public static func isScopeAllowed(_ scope: TrustScope, forRisk riskTier: RiskLevel) -> Bool {
        if riskTier >= .critical && scope >= .workspace {
            return false
        }
        return true
    }

    /// The maximum trust scope allowed for a given risk tier.
    public static func maxScope(forRisk riskTier: RiskLevel) -> TrustScope {
        switch riskTier {
        case .safe, .moderate, .dangerous:
            return .global
        case .critical:
            return .session
        }
    }
}
