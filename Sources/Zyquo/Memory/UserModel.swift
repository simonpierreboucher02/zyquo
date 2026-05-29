import Foundation

// MARK: - UserTrait

/// The category of a learned observation about the user.
///
/// These categories let Zyquo build a structured, deepening model of who the
/// user is across sessions and projects — preferences, the tools they reach
/// for, how they like to work, and what they keep coming back to.
///
/// Inspired by Hermes Agent's dialectic user modeling.
public enum UserTrait: String, Sendable, Codable, CaseIterable {
    /// A stated or inferred preference (e.g. "prefers concise output").
    case preference
    /// Tooling / stack the user works with (e.g. "Swift, GRDB, Homebrew").
    case stack
    /// How the user works (e.g. "reviews diffs carefully before applying").
    case workingStyle
    /// Communication style (e.g. "writes in French, terse").
    case communication
    /// A recurring goal or theme across sessions (e.g. "improving the TUI").
    case recurringGoal
    /// A domain the user is expert in (e.g. "macOS native engineering").
    case domainExpertise
    /// A hard constraint the user imposes (e.g. "never push without asking").
    case constraint

    /// Human-readable label for rendering.
    public var displayName: String {
        switch self {
        case .preference: return "Preference"
        case .stack: return "Stack"
        case .workingStyle: return "Working style"
        case .communication: return "Communication"
        case .recurringGoal: return "Recurring goal"
        case .domainExpertise: return "Domain expertise"
        case .constraint: return "Constraint"
        }
    }
}

// MARK: - UserObservation

/// A single durable, generalizable fact about the user, accumulated over time.
///
/// Observations carry a confidence that is reinforced each time the same fact
/// is re-observed, and which decays as a fact goes stale (not re-observed for
/// a long time). This keeps the model honest: facts the user demonstrates
/// repeatedly rise to the top; one-off guesses fade.
public struct UserObservation: Sendable, Codable, Equatable, Identifiable {
    /// Stable identifier derived from the trait + a normalized statement key.
    public let id: String
    /// Which category this observation belongs to.
    public let trait: UserTrait
    /// The fact itself, phrased as a short declarative sentence.
    public let statement: String
    /// Confidence in this fact, 0.0–1.0.
    public var confidence: Double
    /// How many independent times this fact has been observed.
    public var evidenceCount: Int
    /// When the fact was first recorded.
    public let firstSeen: Date
    /// When the fact was last reinforced.
    public var lastSeen: Date
    /// Session IDs that contributed evidence for this fact (capped).
    public var sourceSessions: [String]

    public init(
        id: String,
        trait: UserTrait,
        statement: String,
        confidence: Double,
        evidenceCount: Int = 1,
        firstSeen: Date,
        lastSeen: Date,
        sourceSessions: [String] = []
    ) {
        self.id = id
        self.trait = trait
        self.statement = statement
        self.confidence = min(1.0, max(0.0, confidence))
        self.evidenceCount = max(1, evidenceCount)
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.sourceSessions = sourceSessions
    }

    /// Build a deterministic id from a trait and statement so that the same
    /// fact merges instead of duplicating.
    public static func makeId(trait: UserTrait, statement: String) -> String {
        let normalized = statement
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(8)
            .joined(separator: "-")
        return "\(trait.rawValue):\(normalized)"
    }
}

// MARK: - UserModel

/// A persistent, cross-session model of the user.
///
/// The model is a set of `UserObservation`s plus a SACRED, user-editable
/// notes block that Zyquo never overwrites (same contract as project memory,
/// CLAUDE.md §23.5). All mutation logic here is pure and LLM-free so it can be
/// unit-tested deterministically; the LLM only proposes new observations
/// (see `UserModelDistiller`).
public struct UserModel: Sendable, Codable, Equatable {
    /// Schema version for forward migration.
    public var version: Int
    /// All accumulated observations.
    public var observations: [UserObservation]
    /// Free-form notes the user hand-edits. Never machine-overwritten.
    public var userEditedNotes: String
    /// When the model was last updated by distillation.
    public var updatedAt: Date

    public init(
        version: Int = 1,
        observations: [UserObservation] = [],
        userEditedNotes: String = "",
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.observations = observations
        self.userEditedNotes = userEditedNotes
        self.updatedAt = updatedAt
    }

    /// An empty model.
    public static let empty = UserModel()

    // MARK: - Tunables

    /// Confidence added each time an existing fact is re-observed.
    public static let reinforcement = 0.15
    /// Days after which a fact begins to decay if not re-observed.
    public static let staleAfterDays = 45.0
    /// Confidence subtracted per stale period.
    public static let decayPerPeriod = 0.1
    /// Observations below this confidence are pruned.
    public static let pruneBelow = 0.08
    /// Maximum source sessions retained per observation.
    public static let maxSources = 8

    // MARK: - Merge

    /// Merge newly distilled observations into the model.
    ///
    /// For each incoming observation:
    /// - if a matching fact (same id) already exists, reinforce it (bump
    ///   confidence, increment evidence, refresh `lastSeen`, merge sources);
    /// - otherwise, insert it.
    ///
    /// Pure and deterministic given `now`.
    ///
    /// - Parameters:
    ///   - incoming: Freshly proposed observations.
    ///   - now: Current time (injectable for testing).
    /// - Returns: A new model with the merge applied (sources capped, sorted).
    public func merging(_ incoming: [UserObservation], now: Date = Date()) -> UserModel {
        var byId: [String: UserObservation] = [:]
        for obs in observations {
            byId[obs.id] = obs
        }

        for new in incoming {
            if var existing = byId[new.id] {
                existing.confidence = min(1.0, existing.confidence + Self.reinforcement)
                existing.evidenceCount += 1
                existing.lastSeen = max(existing.lastSeen, new.lastSeen)
                var sources = existing.sourceSessions
                for s in new.sourceSessions where !sources.contains(s) {
                    sources.append(s)
                }
                existing.sourceSessions = Array(sources.suffix(Self.maxSources))
                byId[new.id] = existing
            } else {
                var inserted = new
                inserted.sourceSessions = Array(new.sourceSessions.suffix(Self.maxSources))
                byId[new.id] = inserted
            }
        }

        let merged = byId.values.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.id < $1.id
        }

        return UserModel(
            version: version,
            observations: merged,
            userEditedNotes: userEditedNotes,
            updatedAt: now
        )
    }

    /// Apply confidence decay to facts that have gone stale and prune those
    /// that fall below the floor. Pure and deterministic given `now`.
    public func decayed(now: Date = Date()) -> UserModel {
        var result: [UserObservation] = []
        for var obs in observations {
            let ageDays = now.timeIntervalSince(obs.lastSeen) / 86_400.0
            if ageDays > Self.staleAfterDays {
                let periods = (ageDays - Self.staleAfterDays) / Self.staleAfterDays
                obs.confidence = max(0.0, obs.confidence - Self.decayPerPeriod * (1.0 + periods))
            }
            if obs.confidence >= Self.pruneBelow {
                result.append(obs)
            }
        }
        result.sort {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.id < $1.id
        }
        return UserModel(
            version: version,
            observations: result,
            userEditedNotes: userEditedNotes,
            updatedAt: now
        )
    }

    // MARK: - Rendering

    /// Render a compact view for injection into the planner context.
    ///
    /// Only sufficiently-confident facts are included, grouped by trait, and
    /// the total is capped to roughly `maxTokens` (≈4 chars/token).
    public func renderForContext(maxTokens: Int = 400, minConfidence: Double = 0.3) -> String? {
        let relevant = observations
            .filter { $0.confidence >= minConfidence }
            .sorted { $0.confidence > $1.confidence }
        guard !relevant.isEmpty || !userEditedNotes.isEmpty else { return nil }

        let charBudget = maxTokens * 4
        var lines: [String] = []
        var used = 0

        if !userEditedNotes.isEmpty {
            let note = userEditedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                let block = "User-provided notes: \(note)"
                lines.append(block)
                used += block.count
            }
        }

        for obs in relevant {
            let line = "- [\(obs.trait.displayName)] \(obs.statement)"
            if used + line.count > charBudget { break }
            lines.append(line)
            used += line.count
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Render the full human-readable markdown view (for the `.md` mirror and
    /// `zyquo memory user`). The user-editable notes section is always last so
    /// it is easy to find and edit.
    public func renderMarkdown() -> String {
        var out = "# User Model\n\n"
        out += "<!-- auto-generated by zyquo; edit only the Notes section below -->\n\n"

        if observations.isEmpty {
            out += "_No observations yet. Zyquo learns about you as you work._\n\n"
        } else {
            for trait in UserTrait.allCases {
                let group = observations
                    .filter { $0.trait == trait }
                    .sorted { $0.confidence > $1.confidence }
                guard !group.isEmpty else { continue }
                out += "## \(trait.displayName)\n\n"
                for obs in group {
                    let pct = Int((obs.confidence * 100).rounded())
                    out += "- \(obs.statement) "
                    out += "_(confidence \(pct)%, seen \(obs.evidenceCount)×)_\n"
                }
                out += "\n"
            }
        }

        out += "## Notes (user-editable)\n\n"
        if userEditedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "<!-- Add anything you want Zyquo to always know about you here. -->\n"
        } else {
            out += userEditedNotes
            if !userEditedNotes.hasSuffix("\n") { out += "\n" }
        }

        return out
    }
}
