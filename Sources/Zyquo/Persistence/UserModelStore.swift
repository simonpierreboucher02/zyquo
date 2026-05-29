import Foundation

// MARK: - UserModelStore

/// Persists the cross-session `UserModel` globally under `~/.zyquo/`.
///
/// Two artifacts are written on save:
/// - `user_model.json` — the canonical, machine-read model.
/// - `user_model.md` — a human-readable mirror whose
///   `## Notes (user-editable)` section is SACRED and read back on every load
///   so machine updates never clobber the user's own notes (same contract as
///   project memory, CLAUDE.md §23.5).
///
/// Mirrors the pattern of `SessionStore` / `MemoryStore` (ISO-8601 dates,
/// atomic writes, actor isolation).
public actor UserModelStore {
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

    /// - Parameter baseDir: Directory holding the model files (defaults to
    ///   `~/.zyquo`).
    public init(baseDir: URL = UserModelStore.defaultBaseDir) {
        self.baseDir = baseDir
    }

    /// Default global location: `~/.zyquo`.
    public static var defaultBaseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
    }

    private var jsonPath: URL { baseDir.appendingPathComponent("user_model.json") }
    private var markdownPath: URL { baseDir.appendingPathComponent("user_model.md") }

    // MARK: - Load

    /// Load the persisted model, or `.empty` if none exists.
    ///
    /// The user-editable notes are always taken from the markdown mirror so
    /// hand edits between runs are honoured.
    public func load() -> UserModel {
        var model = UserModel.empty
        if let data = try? Data(contentsOf: jsonPath),
           let decoded = try? decoder.decode(UserModel.self, from: data) {
            model = decoded
        }
        model.userEditedNotes = readUserNotes()
        return model
    }

    // MARK: - Save

    /// Persist the model (JSON canonical + markdown mirror).
    ///
    /// The notes block is re-read from disk first so a stale in-memory copy
    /// never overwrites edits the user made in the meantime.
    public func save(_ model: UserModel) throws {
        try ensureDir()
        var toWrite = model
        toWrite.userEditedNotes = readUserNotes(fallback: model.userEditedNotes)

        let data = try encoder.encode(toWrite)
        try data.write(to: jsonPath, options: .atomic)
        try toWrite.renderMarkdown().write(to: markdownPath, atomically: true, encoding: .utf8)
    }

    /// The path to the human-editable markdown mirror (for `$EDITOR`).
    public func markdownLocation() -> URL { markdownPath }

    // MARK: - Notes Extraction

    /// Read the user-editable notes section from the markdown mirror.
    ///
    /// Everything after the `## Notes (user-editable)` heading (minus the
    /// scaffold comment) is treated as the user's notes.
    private func readUserNotes(fallback: String = "") -> String {
        guard let content = try? String(contentsOf: markdownPath, encoding: .utf8) else {
            return fallback
        }
        guard let range = content.range(of: "## Notes (user-editable)") else {
            return fallback
        }
        let after = content[range.upperBound...]
        let body = after
            .components(separatedBy: "\n")
            .filter { !$0.contains("<!-- Add anything you want") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body
    }

    private func ensureDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDir.path) {
            try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
    }
}
