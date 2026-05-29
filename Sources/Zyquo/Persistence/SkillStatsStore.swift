import Foundation

// MARK: - SkillStatsStore

/// Persists per-skill `SkillStats` under `~/.zyquo/skills/<id>/stats.json`.
///
/// Recording a run reads the current stats, applies the pure
/// `SkillStats.recording(...)` transform, and writes the result back. The
/// `SkillRefiner` reads these to decide whether to propose improvements.
public actor SkillStatsStore {
    private let skillsDir: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// - Parameter skillsDir: Root skills directory (defaults to
    ///   `~/.zyquo/skills`). Each skill's stats live in `<skillsDir>/<id>/stats.json`.
    public init(skillsDir: URL = SkillStatsStore.defaultSkillsDir) {
        self.skillsDir = skillsDir
    }

    /// Default global location: `~/.zyquo/skills`.
    public static var defaultSkillsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("skills")
    }

    // MARK: - Load

    /// Load stats for a skill, or a fresh zeroed value if none exist.
    public func load(id: String) -> SkillStats {
        guard let data = try? Data(contentsOf: path(for: id)),
              let stats = try? decoder.decode(SkillStats.self, from: data) else {
            return SkillStats(skillId: id)
        }
        return stats
    }

    /// List stats for all skills that have recorded runs.
    public func all() -> [SkillStats] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: skillsDir, includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }
        var result: [SkillStats] = []
        for dir in dirs {
            let statsFile = dir.appendingPathComponent("stats.json")
            if let data = try? Data(contentsOf: statsFile),
               let stats = try? decoder.decode(SkillStats.self, from: data) {
                result.append(stats)
            }
        }
        return result.sorted { $0.runs > $1.runs }
    }

    // MARK: - Record

    /// Record a completed run for a skill and return the updated stats.
    @discardableResult
    public func record(
        id: String,
        succeeded: Bool,
        steps: Int,
        costUSD: Double,
        outcome: String,
        failureNote: String? = nil,
        now: Date = Date()
    ) throws -> SkillStats {
        let updated = load(id: id).recording(
            succeeded: succeeded,
            steps: steps,
            costUSD: costUSD,
            outcome: outcome,
            failureNote: failureNote,
            now: now
        )
        try save(updated)
        return updated
    }

    /// Persist stats directly.
    public func save(_ stats: SkillStats) throws {
        let dir = skillsDir.appendingPathComponent(sanitize(stats.skillId))
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(stats)
        try data.write(to: dir.appendingPathComponent("stats.json"), options: .atomic)
    }

    // MARK: - Paths

    private func path(for id: String) -> URL {
        skillsDir
            .appendingPathComponent(sanitize(id))
            .appendingPathComponent("stats.json")
    }

    private func sanitize(_ id: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
