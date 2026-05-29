import Foundation

// MARK: - NudgeEngine

/// Decides, from purely local signals, which `LearningNudge`s to surface after
/// a session. Rule-based and LLM-free so it is cheap and deterministic — the
/// expensive LLM work (distillation, refinement) happens elsewhere and only its
/// *results* feed these rules.
public struct NudgeEngine: Sendable {

    /// Signals gathered at session end that the rules evaluate.
    public struct Signals: Sendable {
        /// A viable, freshly extracted skill candidate (if any).
        public let skillCandidate: ExtractedSkillCandidate?
        /// Skill ids that just received a pending refinement proposal.
        public let refinedSkillIds: [String]
        /// Whether project memory looks stale and could be refreshed.
        public let projectMemoryStale: Bool
        /// How many sessions have run since project memory last changed.
        public let sessionsSinceMemoryUpdate: Int
        /// How many user-model observations were added/reinforced this session.
        public let userModelObservationsAdded: Int

        public init(
            skillCandidate: ExtractedSkillCandidate? = nil,
            refinedSkillIds: [String] = [],
            projectMemoryStale: Bool = false,
            sessionsSinceMemoryUpdate: Int = 0,
            userModelObservationsAdded: Int = 0
        ) {
            self.skillCandidate = skillCandidate
            self.refinedSkillIds = refinedSkillIds
            self.projectMemoryStale = projectMemoryStale
            self.sessionsSinceMemoryUpdate = sessionsSinceMemoryUpdate
            self.userModelObservationsAdded = userModelObservationsAdded
        }
    }

    public init() {}

    /// Produce the set of nudges implied by the given signals.
    ///
    /// Pure: same signals + `now` always yield the same nudges (ids are
    /// deterministic, so `NudgeStore` dedupes repeats across sessions).
    public func generate(from signals: Signals, now: Date = Date()) -> [LearningNudge] {
        var nudges: [LearningNudge] = []

        // 1. Reusable session → offer to save as a skill.
        if let candidate = signals.skillCandidate, candidate.isViable {
            let id = candidate.suggestedId
            nudges.append(LearningNudge(
                id: LearningNudge.makeId(kind: .saveSkill, subject: id),
                kind: .saveSkill,
                message: "This session looks reusable — save it as the skill '\(id)'?",
                actionCommand: "zyquo skills accept \(id)",
                createdAt: now
            ))
        }

        // 2. Underperforming skills → offer to refine.
        for skillId in signals.refinedSkillIds {
            nudges.append(LearningNudge(
                id: LearningNudge.makeId(kind: .refineSkill, subject: skillId),
                kind: .refineSkill,
                message: "Skill '\(skillId)' keeps stumbling — review a proposed refinement?",
                actionCommand: "zyquo skills refine \(skillId)",
                createdAt: now
            ))
        }

        // 3. Stale project memory → offer to refresh.
        if signals.projectMemoryStale {
            nudges.append(LearningNudge(
                id: LearningNudge.makeId(kind: .refreshMemory, subject: "project"),
                kind: .refreshMemory,
                message: "Project memory hasn't changed in \(signals.sessionsSinceMemoryUpdate) sessions — refresh it?",
                actionCommand: "zyquo memory compact",
                createdAt: now
            ))
        }

        // 4. User model enriched → informational only.
        if signals.userModelObservationsAdded > 0 {
            let n = signals.userModelObservationsAdded
            nudges.append(LearningNudge(
                id: LearningNudge.makeId(kind: .userModelUpdated, subject: "session-\(now.timeIntervalSince1970)"),
                kind: .userModelUpdated,
                message: "Learned \(n) new thing\(n == 1 ? "" : "s") about how you work — see `zyquo memory user`.",
                actionCommand: "zyquo memory user",
                createdAt: now
            ))
        }

        return nudges
    }
}
