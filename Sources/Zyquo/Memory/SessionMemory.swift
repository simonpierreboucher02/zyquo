import Foundation

// MARK: - MemoryEntryKind

/// The kind of memory entry recorded during a session.
public enum MemoryEntryKind: String, Sendable, Codable, CaseIterable {
    case toolCall
    case observation
    case decision
    case note
    case error
}

// MARK: - MemoryEntry

/// A single entry in session memory, representing an event or note.
public struct MemoryEntry: Sendable, Codable, Equatable {
    /// When this entry was created.
    public let timestamp: Date
    /// The kind of entry.
    public let kind: MemoryEntryKind
    /// The content of the entry.
    public let content: String
    /// Additional structured metadata.
    public let metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        kind: MemoryEntryKind,
        content: String,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.kind = kind
        self.content = content
        self.metadata = metadata
    }
}

// MARK: - SessionMemory

/// Per-session memory: an append-only log of entries produced during
/// a single agent session. Supports recall by keyword relevance.
///
/// Reference: CLAUDE.md S23.2
public struct SessionMemory: Sendable {
    /// All entries in chronological order.
    public private(set) var entries: [MemoryEntry]

    public init(entries: [MemoryEntry] = []) {
        self.entries = entries
    }

    /// Append a new entry to the session memory.
    public mutating func append(_ entry: MemoryEntry) {
        entries.append(entry)
    }

    /// Recall entries relevant to a query, ranked by keyword overlap.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - limit: Maximum number of results to return.
    /// - Returns: Entries sorted by relevance (highest first).
    public func recall(query: String, limit: Int = 10) -> [MemoryEntry] {
        guard !query.isEmpty, !entries.isEmpty else { return [] }

        let queryTerms = Self.tokenize(query)
        guard !queryTerms.isEmpty else { return [] }

        var scored: [(entry: MemoryEntry, score: Double)] = []

        for entry in entries {
            let entryTerms = Self.tokenize(entry.content)
            guard !entryTerms.isEmpty else { continue }

            var matchCount = 0
            for term in queryTerms {
                if entryTerms.contains(term) {
                    matchCount += 1
                }
            }

            if matchCount > 0 {
                let score = Double(matchCount) / Double(queryTerms.count)
                scored.append((entry, score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.entry)
    }

    /// Simple tokenizer: lowercase, split on whitespace and punctuation.
    private static func tokenize(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        return Set(tokens)
    }
}
