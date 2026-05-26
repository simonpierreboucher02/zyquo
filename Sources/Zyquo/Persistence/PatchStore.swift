import Foundation

// MARK: - PatchStore

/// Persistent storage for patches and their reverse counterparts.
///
/// Stores patches under `.zyquo/patches/<patch-id>.patch` and reverse
/// patches alongside as `.zyquo/patches/<patch-id>.reverse.patch`.
///
/// Reference: CLAUDE.md §23.1, §29 Phase 7
public final class PatchStore: @unchecked Sendable {
    /// Root directory for patch storage (typically `.zyquo/patches/`).
    private let storageDir: URL
    /// The patch engine used for applying reverse patches.
    private let patchEngine: PatchEngine

    public init(storageDir: URL, patchEngine: PatchEngine = PatchEngine()) {
        self.storageDir = storageDir
        self.patchEngine = patchEngine
    }

    // MARK: - Record

    /// Record a changeset and its reverse diffs to disk.
    ///
    /// - Parameters:
    ///   - changeSet: The changeset to persist.
    ///   - reverseDiffs: The reverse diffs (one per file in the changeset).
    public func record(changeSet: ChangeSet, reverseDiffs: [UnifiedDiff]) throws {
        let fm = FileManager.default

        // Ensure storage directory exists
        if !fm.fileExists(atPath: storageDir.path) {
            try fm.createDirectory(at: storageDir, withIntermediateDirectories: true)
        }

        // Write the forward patch
        let forwardContent = renderChangeSet(changeSet)
        let forwardPath = patchPath(for: changeSet.id)
        try forwardContent.write(to: forwardPath, atomically: true, encoding: .utf8)

        // Write the reverse patch
        let reverseContent = renderReverseDiffs(reverseDiffs, id: changeSet.id)
        let reversePath = reversePatchPath(for: changeSet.id)
        try reverseContent.write(to: reversePath, atomically: true, encoding: .utf8)

        // Write metadata
        let metadata = PatchMetadata(
            id: changeSet.id,
            files: changeSet.files.map { PatchFileEntry(path: $0.path, preImageSHA: $0.preImageSHA, risk: $0.risk.rawValue) },
            createdAt: changeSet.createdAt,
            summary: changeSet.summary,
            totalAdded: changeSet.totalAdded,
            totalRemoved: changeSet.totalRemoved
        )
        let metadataPath = metadataPath(for: changeSet.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataPath)
    }

    // MARK: - Load

    /// Load a changeset by its ID.
    ///
    /// - Parameter id: The patch ID to load.
    /// - Returns: The parsed changeset, or nil if not found.
    public func load(id: PatchID) -> ChangeSet? {
        let forwardPath = patchPath(for: id)
        let metadataPath = metadataPath(for: id)

        guard let patchContent = try? String(contentsOf: forwardPath, encoding: .utf8) else {
            return nil
        }

        let parser = HunkParser()
        let diffs = parser.parse(patchContent)

        // Load metadata if available
        let metadata = loadMetadata(from: metadataPath)

        let files = diffs.enumerated().map { (idx, diff) -> FileChange in
            let path = diff.newPath ?? diff.oldPath ?? "unknown"
            let preImageSHA = metadata?.files.first(where: { $0.path == path })?.preImageSHA
            let riskStr = metadata?.files.first(where: { $0.path == path })?.risk
            let risk = riskStr.flatMap { RiskLevel(rawValue: $0) } ?? .moderate
            return FileChange(path: path, diff: diff, preImageSHA: preImageSHA, risk: risk)
        }

        return ChangeSet(
            id: id,
            files: files,
            createdAt: metadata?.createdAt ?? Date(),
            summary: metadata?.summary
        )
    }

    /// Load the reverse diffs for a patch ID.
    ///
    /// - Parameter id: The patch ID.
    /// - Returns: Array of reverse diffs, or nil if not found.
    public func loadReverse(id: PatchID) -> [UnifiedDiff]? {
        let path = reversePatchPath(for: id)
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return nil
        }

        let parser = HunkParser()
        return parser.parse(content)
    }

    // MARK: - List

    /// List all stored patch IDs, sorted by creation date (newest first).
    public func listAll() -> [PatchID] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "patch" && !$0.lastPathComponent.contains(".reverse.") }
            .compactMap { url -> PatchID? in
                let name = url.deletingPathExtension().lastPathComponent
                return PatchID(rawValue: name)
            }
            .sorted { $0.value > $1.value } // newest first (date is embedded in ID)
    }

    // MARK: - Rollback

    /// Roll back a patch by applying its reverse diffs to the workspace.
    ///
    /// - Parameters:
    ///   - id: The patch ID to roll back.
    ///   - workspaceRoot: The workspace root directory for resolving file paths.
    /// - Throws: If the reverse patches cannot be loaded or applied.
    public func rollback(id: PatchID, workspaceRoot: URL) throws {
        guard let reverseDiffs = loadReverse(id: id) else {
            throw PatchStoreError.reverseNotFound(id: id)
        }

        for diff in reverseDiffs {
            guard let filePath = diff.newPath ?? diff.oldPath else { continue }

            let fileURL: URL
            if filePath.hasPrefix("/") {
                fileURL = URL(fileURLWithPath: filePath)
            } else {
                fileURL = workspaceRoot.appendingPathComponent(filePath)
            }

            try patchEngine.applyToFile(diff: diff, path: fileURL)
        }
    }

    // MARK: - Delete

    /// Remove a patch and its reverse from storage.
    public func remove(id: PatchID) throws {
        let fm = FileManager.default
        let paths = [
            patchPath(for: id),
            reversePatchPath(for: id),
            metadataPath(for: id),
        ]
        for path in paths {
            if fm.fileExists(atPath: path.path) {
                try fm.removeItem(at: path)
            }
        }
    }

    // MARK: - Paths

    private func patchPath(for id: PatchID) -> URL {
        storageDir.appendingPathComponent("\(id.value).patch")
    }

    private func reversePatchPath(for id: PatchID) -> URL {
        storageDir.appendingPathComponent("\(id.value).reverse.patch")
    }

    private func metadataPath(for id: PatchID) -> URL {
        storageDir.appendingPathComponent("\(id.value).meta.json")
    }

    // MARK: - Rendering

    /// Render a changeset to unified diff text.
    private func renderChangeSet(_ changeSet: ChangeSet) -> String {
        changeSet.files.map { $0.diff.render() }.joined(separator: "\n")
    }

    /// Render reverse diffs to unified diff text.
    private func renderReverseDiffs(_ diffs: [UnifiedDiff], id: PatchID) -> String {
        diffs.map { $0.render() }.joined(separator: "\n")
    }

    /// Load metadata from a JSON file.
    private func loadMetadata(from path: URL) -> PatchMetadata? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PatchMetadata.self, from: data)
    }
}

// MARK: - PatchMetadata

/// JSON-serializable metadata about a stored patch.
private struct PatchMetadata: Codable {
    let id: PatchID
    let files: [PatchFileEntry]
    let createdAt: Date
    let summary: String?
    let totalAdded: Int
    let totalRemoved: Int
}

/// Entry for a single file in the patch metadata.
private struct PatchFileEntry: Codable {
    let path: String
    let preImageSHA: String?
    let risk: String
}

// MARK: - PatchStoreError

public enum PatchStoreError: Error, Sendable, CustomStringConvertible {
    case reverseNotFound(id: PatchID)
    case patchNotFound(id: PatchID)
    case applyFailed(id: PatchID, reason: String)

    public var description: String {
        switch self {
        case .reverseNotFound(let id):
            return "Reverse patch not found for \(id.value)"
        case .patchNotFound(let id):
            return "Patch not found: \(id.value)"
        case .applyFailed(let id, let reason):
            return "Failed to apply patch \(id.value): \(reason)"
        }
    }
}
