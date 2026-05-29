import Foundation

// MARK: - ExtractedSkillCandidate

/// A candidate skill extracted from a successful session by analyzing
/// its tool-call patterns and verifying repeatability signals.
///
/// The agent (or user) can review candidates and accept or reject them
/// for promotion into the skill registry.
///
/// Reference: CLAUDE.md §30 Phase 10
public struct ExtractedSkillCandidate: Sendable, Codable, Equatable {
    /// Suggested stable identifier for the skill (e.g. "fix_swift_build").
    public let suggestedId: String
    /// Suggested human-readable title.
    public let suggestedTitle: String
    /// The set of tool names used during the analyzed session.
    public let toolsUsed: [String]
    /// Number of steps in the original session.
    public let stepsCount: Int
    /// Proportion of steps that passed verification (0.0-1.0).
    public let successRate: Double
    /// A suggested prompt derived from the session intent and tool patterns.
    public let suggestedPrompt: String
    /// Suggested resource budget based on observed usage.
    public let suggestedBudget: SkillBudget
    /// Confidence score (0.0-1.0) reflecting how suitable this session
    /// is for skill extraction.
    public let confidence: Double

    public init(
        suggestedId: String,
        suggestedTitle: String,
        toolsUsed: [String],
        stepsCount: Int,
        successRate: Double,
        suggestedPrompt: String,
        suggestedBudget: SkillBudget,
        confidence: Double
    ) {
        self.suggestedId = suggestedId
        self.suggestedTitle = suggestedTitle
        self.toolsUsed = toolsUsed
        self.stepsCount = stepsCount
        self.successRate = successRate
        self.suggestedPrompt = suggestedPrompt
        self.suggestedBudget = suggestedBudget
        self.confidence = confidence
    }

    /// Whether this candidate has enough confidence to be worth presenting.
    public var isViable: Bool {
        confidence >= 0.4
    }

    /// Build a SkillManifest from this candidate.
    public func toManifest(version: String = "0.1.0") -> SkillManifest {
        SkillManifest(
            id: suggestedId,
            version: version,
            title: suggestedTitle,
            description: "Auto-extracted skill from session analysis",
            authors: ["zyquo-extractor"],
            inputs: [],
            toolsAllowed: toolsUsed,
            promptFile: "./prompt.md",
            verify: nil,
            budget: suggestedBudget,
            riskCeiling: "MODERATE"
        )
    }
}

// MARK: - SkillExtractor

/// Analyzes successful agent sessions to identify repeatable patterns
/// that can be extracted into reusable skills.
///
/// The extractor looks for sessions that:
/// - Completed successfully (status == "done")
/// - Used a consistent set of tools
/// - Had a non-trivial number of steps (>= 3)
/// - Had a high verification pass rate
///
/// Reference: CLAUDE.md §30 Phase 10
public struct SkillExtractor: Sendable {

    /// Minimum number of steps for a session to be considered extractable.
    public static let minSteps = 3

    /// Minimum success rate for extraction consideration.
    public static let minSuccessRate = 0.6

    public init() {}

    /// Analyze a session and its events to determine if a reusable
    /// skill can be extracted.
    ///
    /// - Parameters:
    ///   - session: The session record to analyze.
    ///   - events: The session's event log.
    /// - Returns: A skill candidate if the session is suitable, nil otherwise.
    public func analyze(
        session: SessionRecord,
        events: [SessionEvent]
    ) -> ExtractedSkillCandidate? {
        // Only extract from successful sessions
        guard session.status == "done" else { return nil }

        // Need enough steps to form a meaningful pattern
        guard session.stepsCompleted >= Self.minSteps else { return nil }

        // Extract tool usage from events
        let toolEvents = events.compactMap { event -> ToolExecutedEvent? in
            if case .toolExecuted(let e) = event { return e }
            return nil
        }

        guard !toolEvents.isEmpty else { return nil }

        // Compute tool usage patterns
        let toolNames = Array(Set(toolEvents.map(\.toolName))).sorted()
        let errorCount = toolEvents.filter(\.isError).count
        let successRate = toolEvents.isEmpty ? 0.0 :
            Double(toolEvents.count - errorCount) / Double(toolEvents.count)

        // Require minimum success rate
        guard successRate >= Self.minSuccessRate else { return nil }

        // Compute confidence based on multiple factors
        let confidence = computeConfidence(
            session: session,
            toolNames: toolNames,
            toolEvents: toolEvents,
            successRate: successRate
        )

        // Generate suggested ID from intent
        let suggestedId = generateId(from: session.intent)
        let suggestedTitle = generateTitle(from: session.intent)

        // Build suggested prompt
        let suggestedPrompt = buildPrompt(
            intent: session.intent,
            toolNames: toolNames,
            stepsCompleted: session.stepsCompleted
        )

        // Suggest budget based on observed usage (with 50% headroom)
        let suggestedBudget = SkillBudget(
            maxSteps: max(Self.minSteps, Int(Double(session.stepsCompleted) * 1.5)),
            maxCostUSD: max(0.50, session.totalCostUSD * 2.0)
        )

        return ExtractedSkillCandidate(
            suggestedId: suggestedId,
            suggestedTitle: suggestedTitle,
            toolsUsed: toolNames,
            stepsCount: session.stepsCompleted,
            successRate: successRate,
            suggestedPrompt: suggestedPrompt,
            suggestedBudget: suggestedBudget,
            confidence: confidence
        )
    }

    // MARK: - Internal

    private func computeConfidence(
        session: SessionRecord,
        toolNames: [String],
        toolEvents: [ToolExecutedEvent],
        successRate: Double
    ) -> Double {
        var score = 0.0

        // Factor 1: Success rate (weight: 0.35)
        score += successRate * 0.35

        // Factor 2: Completion ratio (weight: 0.25)
        let completionRatio = session.stepsTotal > 0
            ? Double(session.stepsCompleted) / Double(session.stepsTotal)
            : 0.0
        score += completionRatio * 0.25

        // Factor 3: Tool consistency — fewer distinct tools = more focused = higher
        // confidence (weight: 0.20)
        let toolConsistency: Double
        if toolNames.count <= 3 {
            toolConsistency = 1.0
        } else if toolNames.count <= 6 {
            toolConsistency = 0.7
        } else {
            toolConsistency = 0.4
        }
        score += toolConsistency * 0.20

        // Factor 4: Non-triviality — must have enough steps to be interesting
        // (weight: 0.20)
        let nonTriviality: Double
        if session.stepsCompleted >= 5 {
            nonTriviality = 1.0
        } else if session.stepsCompleted >= Self.minSteps {
            nonTriviality = 0.6
        } else {
            nonTriviality = 0.2
        }
        score += nonTriviality * 0.20

        return min(1.0, max(0.0, score))
    }

    private func generateId(from intent: String) -> String {
        let words = intent.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .prefix(4)
        let base = words.joined(separator: "_")
        return base.isEmpty ? "extracted_skill" : base
    }

    private func generateTitle(from intent: String) -> String {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60 {
            return trimmed
        }
        return String(trimmed.prefix(57)) + "..."
    }

    private func buildPrompt(
        intent: String,
        toolNames: [String],
        stepsCompleted: Int
    ) -> String {
        var lines: [String] = []
        lines.append("You are a focused agent executing a learned workflow.")
        lines.append("")
        lines.append("Original intent: \(intent)")
        lines.append("")
        lines.append("This workflow typically completes in ~\(stepsCompleted) steps using:")
        for tool in toolNames {
            lines.append("- \(tool)")
        }
        lines.append("")
        lines.append("Follow the established pattern. Prefer reading before writing.")
        lines.append("Verify each step before proceeding to the next.")
        return lines.joined(separator: "\n")
    }
}
