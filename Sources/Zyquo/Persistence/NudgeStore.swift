import Foundation

// MARK: - NudgeStore

/// Persists `LearningNudge`s as a single JSON array at `~/.zyquo/nudges.json`.
///
/// Adding a nudge is idempotent by id: a pending nudge with the same id is not
/// duplicated. Acting on or dismissing a nudge updates its state in place. A
/// bounded number of resolved nudges is retained for history.
public actor NudgeStore {
    private let fileURL: URL

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

    /// Maximum resolved (acted/dismissed) nudges kept for history.
    public static let maxResolved = 50

    /// - Parameter fileURL: Location of the nudges file (defaults to
    ///   `~/.zyquo/nudges.json`).
    public init(fileURL: URL = NudgeStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// Default global location: `~/.zyquo/nudges.json`.
    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("nudges.json")
    }

    // MARK: - Read

    /// Load all stored nudges (any state), newest first.
    public func all() -> [LearningNudge] {
        guard let data = try? Data(contentsOf: fileURL),
              let nudges = try? decoder.decode([LearningNudge].self, from: data) else {
            return []
        }
        return nudges.sorted { $0.createdAt > $1.createdAt }
    }

    /// Load only pending nudges, newest first.
    public func pending() -> [LearningNudge] {
        all().filter { $0.state == .pending }
    }

    // MARK: - Mutate

    /// Add new nudges, skipping any whose id already exists as pending.
    /// Returns the nudges that were actually added.
    @discardableResult
    public func add(_ incoming: [LearningNudge]) throws -> [LearningNudge] {
        var current = all()
        let pendingIds = Set(current.filter { $0.state == .pending }.map(\.id))

        var added: [LearningNudge] = []
        for nudge in incoming where !pendingIds.contains(nudge.id) {
            current.append(nudge)
            added.append(nudge)
        }
        if !added.isEmpty {
            try persist(current)
        }
        return added
    }

    /// Mark a nudge as acted-upon.
    public func markActed(id: String) throws {
        try updateState(id: id, to: .acted)
    }

    /// Mark a nudge as dismissed.
    public func markDismissed(id: String) throws {
        try updateState(id: id, to: .dismissed)
    }

    private func updateState(id: String, to state: NudgeState) throws {
        var current = all()
        guard let idx = current.firstIndex(where: { $0.id == id }) else { return }
        current[idx].state = state
        try persist(current)
    }

    // MARK: - Persist

    private func persist(_ nudges: [LearningNudge]) throws {
        // Keep all pending + a bounded tail of resolved ones.
        let pending = nudges.filter { $0.state == .pending }
        let resolved = nudges
            .filter { $0.state != .pending }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(Self.maxResolved)
        let toWrite = pending + Array(resolved)

        let dir = fileURL.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(toWrite)
        try data.write(to: fileURL, options: .atomic)
    }
}
