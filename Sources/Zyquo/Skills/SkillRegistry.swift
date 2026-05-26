import Foundation

// MARK: - SkillRegistry

/// Central registry of available skills.
///
/// Skills are loaded at startup via `SkillLoader` and registered here.
/// The registry supports lookup by ID and fuzzy search by query string
/// (matching against ID, title, and description).
///
/// Reference: CLAUDE.md §30 Phase 6
public final class SkillRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var skills: [String: LoadedSkill] = [:]

    public init() {}

    // MARK: - Registration

    /// Register a loaded skill. Replaces any existing skill with the same ID.
    public func register(_ skill: LoadedSkill) {
        lock.lock()
        defer { lock.unlock() }
        skills[skill.manifest.id] = skill
    }

    /// Register multiple skills at once.
    public func registerAll(_ skillList: [LoadedSkill]) {
        lock.lock()
        defer { lock.unlock() }
        for skill in skillList {
            skills[skill.manifest.id] = skill
        }
    }

    // MARK: - Lookup

    /// Look up a skill by its stable ID. Returns nil if not found.
    public func skill(id: String) -> LoadedSkill? {
        lock.lock()
        defer { lock.unlock() }
        return skills[id]
    }

    /// Returns all registered skills sorted by ID.
    public func allSkills() -> [LoadedSkill] {
        lock.lock()
        defer { lock.unlock() }
        return skills.values.sorted { $0.manifest.id < $1.manifest.id }
    }

    /// Returns the count of registered skills.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return skills.count
    }

    // MARK: - Search

    /// Search for skills matching a query string.
    ///
    /// The query is matched case-insensitively against the skill's ID,
    /// title, and description. All skills that match on any field are
    /// returned, sorted by relevance (ID match first, then title, then
    /// description).
    ///
    /// - Parameter query: The search string.
    /// - Returns: Skills matching the query, sorted by relevance.
    public func search(query: String) -> [LoadedSkill] {
        lock.lock()
        defer { lock.unlock() }

        let lowered = query.lowercased()
        if lowered.isEmpty {
            return skills.values.sorted { $0.manifest.id < $1.manifest.id }
        }

        struct Scored {
            let skill: LoadedSkill
            let score: Int  // lower = better match
        }

        var results: [Scored] = []

        for skill in skills.values {
            let id = skill.manifest.id.lowercased()
            let title = skill.manifest.title.lowercased()
            let desc = (skill.manifest.description ?? "").lowercased()

            if id == lowered {
                results.append(Scored(skill: skill, score: 0))
            } else if id.contains(lowered) {
                results.append(Scored(skill: skill, score: 1))
            } else if title.contains(lowered) {
                results.append(Scored(skill: skill, score: 2))
            } else if desc.contains(lowered) {
                results.append(Scored(skill: skill, score: 3))
            }
        }

        return results
            .sorted { $0.score < $1.score }
            .map(\.skill)
    }

    // MARK: - Removal

    /// Remove a skill from the registry.
    public func unregister(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        skills.removeValue(forKey: id)
    }

    /// Remove all skills.
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        skills.removeAll()
    }
}
