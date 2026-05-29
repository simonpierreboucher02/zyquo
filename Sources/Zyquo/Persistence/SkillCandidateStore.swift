import Foundation

// MARK: - SkillCandidateStore

/// Persists `ExtractedSkillCandidate`s awaiting the user's accept/reject
/// decision under `~/.zyquo/skills/_candidates/<id>.json`.
///
/// Candidates are produced automatically by `SkillExtractor` at session end,
/// but are NEVER auto-promoted into runnable skills — promotion is an explicit
/// user action (`zyquo skills accept <id>`), honouring "approval over
/// autonomy" (CLAUDE.md §6).
public actor SkillCandidateStore {
    private let baseDir: URL

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

    /// - Parameter baseDir: Candidates directory (defaults to
    ///   `~/.zyquo/skills/_candidates`).
    public init(baseDir: URL = SkillCandidateStore.defaultBaseDir) {
        self.baseDir = baseDir
    }

    /// Default global location: `~/.zyquo/skills/_candidates`.
    public static var defaultBaseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("skills")
            .appendingPathComponent("_candidates")
    }

    // MARK: - Save

    /// Persist a candidate (overwrites any existing one with the same id).
    public func save(_ candidate: ExtractedSkillCandidate) throws {
        try ensureDir()
        let data = try encoder.encode(candidate)
        try data.write(to: path(for: candidate.suggestedId), options: .atomic)
    }

    // MARK: - Load / List

    /// Load a candidate by its suggested id.
    public func load(id: String) -> ExtractedSkillCandidate? {
        guard let data = try? Data(contentsOf: path(for: id)) else { return nil }
        return try? decoder.decode(ExtractedSkillCandidate.self, from: data)
    }

    /// List all candidates, highest confidence first.
    public func list() -> [ExtractedSkillCandidate] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: baseDir, includingPropertiesForKeys: nil
        ) else {
            return []
        }
        var result: [ExtractedSkillCandidate] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let c = try? decoder.decode(ExtractedSkillCandidate.self, from: data) {
                result.append(c)
            }
        }
        return result.sorted { $0.confidence > $1.confidence }
    }

    /// Whether a candidate with this id already exists on disk.
    public func exists(id: String) -> Bool {
        FileManager.default.fileExists(atPath: path(for: id).path)
    }

    // MARK: - Delete

    /// Remove a candidate (after accept or reject).
    public func delete(id: String) throws {
        let p = path(for: id)
        if FileManager.default.fileExists(atPath: p.path) {
            try FileManager.default.removeItem(at: p)
        }
    }

    // MARK: - Paths

    private func path(for id: String) -> URL {
        baseDir.appendingPathComponent("\(sanitize(id)).json")
    }

    private func sanitize(_ id: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private func ensureDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDir.path) {
            try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
    }
}
