import Foundation

// MARK: - SkillStats

/// Accumulated usage statistics for a single skill.
///
/// These power the "self-improving skills" half of the closed learning loop:
/// once a skill has run enough times, the `SkillRefiner` inspects its stats to
/// decide whether to propose a refinement (prompt tweak, budget adjustment,
/// tool changes). Stats are persisted per skill at
/// `~/.zyquo/skills/<id>/stats.json`.
public struct SkillStats: Sendable, Codable, Equatable {
    /// The skill these stats belong to.
    public let skillId: String
    /// Total number of runs recorded.
    public var runs: Int
    /// Runs that completed successfully (verification passed or no failure).
    public var successes: Int
    /// Runs that failed.
    public var failures: Int
    /// Running average of steps used per run.
    public var avgSteps: Double
    /// Running average of cost (USD) per run.
    public var avgCostUSD: Double
    /// When the skill was last run.
    public var lastUsed: Date?
    /// One-line outcome of the most recent run.
    public var lastOutcome: String?
    /// Recent failure notes, newest last (capped).
    public var recentFailureNotes: [String]

    public init(
        skillId: String,
        runs: Int = 0,
        successes: Int = 0,
        failures: Int = 0,
        avgSteps: Double = 0,
        avgCostUSD: Double = 0,
        lastUsed: Date? = nil,
        lastOutcome: String? = nil,
        recentFailureNotes: [String] = []
    ) {
        self.skillId = skillId
        self.runs = runs
        self.successes = successes
        self.failures = failures
        self.avgSteps = avgSteps
        self.avgCostUSD = avgCostUSD
        self.lastUsed = lastUsed
        self.lastOutcome = lastOutcome
        self.recentFailureNotes = recentFailureNotes
    }

    /// Maximum failure notes retained.
    public static let maxFailureNotes = 5

    /// Success rate across all runs, 0.0–1.0 (0 when no runs).
    public var successRate: Double {
        runs == 0 ? 0 : Double(successes) / Double(runs)
    }

    /// Record a completed run, returning a new updated value.
    ///
    /// Pure and deterministic. Averages are updated incrementally so old runs
    /// are not stored. `failureNote` is only retained on failures.
    public func recording(
        succeeded: Bool,
        steps: Int,
        costUSD: Double,
        outcome: String,
        failureNote: String? = nil,
        now: Date = Date()
    ) -> SkillStats {
        let newRuns = runs + 1
        let newAvgSteps = (avgSteps * Double(runs) + Double(steps)) / Double(newRuns)
        let newAvgCost = (avgCostUSD * Double(runs) + costUSD) / Double(newRuns)

        var notes = recentFailureNotes
        if !succeeded, let note = failureNote, !note.isEmpty {
            notes.append(note)
            notes = Array(notes.suffix(Self.maxFailureNotes))
        }

        return SkillStats(
            skillId: skillId,
            runs: newRuns,
            successes: successes + (succeeded ? 1 : 0),
            failures: failures + (succeeded ? 0 : 1),
            avgSteps: newAvgSteps,
            avgCostUSD: newAvgCost,
            lastUsed: now,
            lastOutcome: outcome,
            recentFailureNotes: notes
        )
    }

    /// Whether these stats warrant a refinement proposal.
    ///
    /// Triggers when the skill has been run at least `minRuns` times AND its
    /// success rate is below `successFloor` (i.e. it keeps stumbling and is a
    /// candidate for improvement).
    public func warrantsRefinement(minRuns: Int, successFloor: Double = 0.6) -> Bool {
        runs >= minRuns && successRate < successFloor
    }
}
