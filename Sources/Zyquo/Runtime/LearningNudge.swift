import Foundation

// MARK: - NudgeKind

/// The category of a learning nudge.
public enum NudgeKind: String, Sendable, Codable {
    /// A reusable session was detected; offer to save it as a skill.
    case saveSkill
    /// A skill keeps failing; offer to refine it.
    case refineSkill
    /// Project memory looks stale; offer to refresh/compact it.
    case refreshMemory
    /// The user model was enriched; informational.
    case userModelUpdated
}

// MARK: - NudgeState

/// The lifecycle state of a nudge.
public enum NudgeState: String, Sendable, Codable {
    /// Awaiting the user's attention.
    case pending
    /// The user acted on it.
    case acted
    /// The user dismissed it.
    case dismissed
}

// MARK: - LearningNudge

/// A lightweight, user-facing suggestion produced by the closed learning loop.
///
/// Nudges are how Zyquo "nudges itself to persist knowledge" (Hermes-inspired):
/// after a session, the agent surfaces calm, actionable suggestions rather than
/// silently mutating state. Each nudge names a concrete follow-up command the
/// user can run. Nudges never take action on their own — consent is required
/// (CLAUDE.md §6 "approval over autonomy").
public struct LearningNudge: Sendable, Codable, Equatable, Identifiable {
    /// Stable, deterministic identifier (dedupes repeat suggestions).
    public let id: String
    /// Which kind of nudge this is.
    public let kind: NudgeKind
    /// One-line message shown to the user.
    public let message: String
    /// The concrete command the user can run to act on it (e.g.
    /// "zyquo skills accept fix_swift_build"). Optional for informational nudges.
    public let actionCommand: String?
    /// When the nudge was created.
    public let createdAt: Date
    /// Current lifecycle state.
    public var state: NudgeState

    public init(
        id: String,
        kind: NudgeKind,
        message: String,
        actionCommand: String? = nil,
        createdAt: Date = Date(),
        state: NudgeState = .pending
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.actionCommand = actionCommand
        self.createdAt = createdAt
        self.state = state
    }

    /// Build a deterministic id from kind + a subject key so the same
    /// suggestion does not pile up across sessions.
    public static func makeId(kind: NudgeKind, subject: String) -> String {
        let normalized = subject
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(kind.rawValue):\(normalized)"
    }
}
