import Foundation

// MARK: - PatchID

/// A unique identifier for a patch/changeset.
///
/// Format: `zp_<yyyymmdd>_<short-uuid>` (stable across session resume).
/// Reference: CLAUDE.md §20.2
public struct PatchID: Sendable, Hashable, CustomStringConvertible, Codable {
    public let value: String

    /// Create a new PatchID with today's date and a random short UUID.
    public init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateStr = formatter.string(from: Date())
        let shortUUID = UUID().uuidString.prefix(8).lowercased()
        self.value = "zp_\(dateStr)_\(shortUUID)"
    }

    /// Create a PatchID from a raw string value. Returns nil if format is invalid.
    public init?(rawValue: String) {
        guard PatchID.isValid(rawValue) else { return nil }
        self.value = rawValue
    }

    /// Internal init that trusts the value (for Codable).
    private init(trusted: String) {
        self.value = trusted
    }

    public var description: String { value }

    /// Validate that a string matches the expected PatchID format.
    public static func isValid(_ string: String) -> Bool {
        // Expected: zp_YYYYMMDD_<hex8>
        let parts = string.components(separatedBy: "_")
        guard parts.count == 3 else { return false }
        guard parts[0] == "zp" else { return false }
        guard parts[1].count == 8, Int(parts[1]) != nil else { return false }
        guard parts[2].count == 8 else { return false }
        return true
    }

    // Codable conformance
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - FileChange

/// A single file change within a changeset.
public struct FileChange: Sendable {
    /// Path to the file, relative to workspace root.
    public let path: String
    /// The computed diff for this file.
    public let diff: UnifiedDiff
    /// SHA-256 of the pre-image content (for staleness detection).
    public let preImageSHA: String?
    /// Risk classification for this file change.
    public let risk: RiskLevel

    public init(path: String, diff: UnifiedDiff, preImageSHA: String? = nil, risk: RiskLevel = .moderate) {
        self.path = path
        self.diff = diff
        self.preImageSHA = preImageSHA
        self.risk = risk
    }
}

// MARK: - ChangeSet

/// A grouped set of file changes that form a logical unit.
///
/// A single agent step MAY produce a ChangeSet covering multiple files.
/// Approval is per-changeset, but the user MAY reject individual files.
///
/// Reference: CLAUDE.md §20.3
public struct ChangeSet: Sendable {
    /// Unique identifier for this changeset.
    public let id: PatchID
    /// The individual file changes.
    public let files: [FileChange]
    /// When this changeset was created.
    public let createdAt: Date
    /// Optional description of what this changeset does.
    public let summary: String?

    public init(
        id: PatchID = PatchID(),
        files: [FileChange],
        createdAt: Date = Date(),
        summary: String? = nil
    ) {
        self.id = id
        self.files = files
        self.createdAt = createdAt
        self.summary = summary
    }

    /// Total lines added across all files.
    public var totalAdded: Int {
        files.reduce(0) { $0 + $1.diff.linesAdded }
    }

    /// Total lines removed across all files.
    public var totalRemoved: Int {
        files.reduce(0) { $0 + $1.diff.linesRemoved }
    }

    /// Number of files changed.
    public var filesChanged: Int {
        files.count
    }

    /// Highest risk level among all file changes.
    public var maxRisk: RiskLevel {
        files.map(\.risk).max() ?? .safe
    }

    /// Create a subset changeset with only the specified file paths.
    public func subset(paths: Set<String>) -> ChangeSet {
        ChangeSet(
            id: id,
            files: files.filter { paths.contains($0.path) },
            createdAt: createdAt,
            summary: summary
        )
    }

    /// Human-readable summary text suitable for display.
    public var summaryText: String {
        var parts: [String] = []
        parts.append("\(filesChanged) file\(filesChanged == 1 ? "" : "s") changed")
        parts.append("+\(totalAdded) / \u{2212}\(totalRemoved)")

        // Group risks
        var riskCounts: [RiskLevel: Int] = [:]
        for file in files {
            riskCounts[file.risk, default: 0] += 1
        }
        for (risk, count) in riskCounts.sorted(by: { $0.key > $1.key }) where risk >= .moderate {
            parts.append("\(count) \(risk.displayName)")
        }

        return parts.joined(separator: " \u{00B7} ")
    }
}
