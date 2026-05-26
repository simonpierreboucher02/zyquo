import Foundation

// MARK: - MemoryCompressor

/// Compresses session memory entries by clustering and summarizing.
///
/// Decisions, errors, and user instructions are preserved verbatim.
/// Other entries are clustered by tool/intent and compressed into
/// summary entries of <= 200 tokens each (~800 chars).
///
/// Reference: CLAUDE.md S23.3
public struct MemoryCompressor: Sendable {

    /// Maximum characters per compressed summary entry (~200 tokens at 4 chars/token).
    public static let maxSummaryChars = 800

    public init() {}

    /// Compress a list of memory entries to fit within a token budget.
    ///
    /// - Parameters:
    ///   - entries: The memory entries to compress.
    ///   - maxTokens: Target maximum token count for all entries combined.
    /// - Returns: A compressed list of entries that fits within the budget.
    public func compress(entries: [MemoryEntry], maxTokens: Int) -> [MemoryEntry] {
        guard !entries.isEmpty else { return [] }

        // Separate verbatim entries (decisions, errors) from compressible ones
        var verbatim: [MemoryEntry] = []
        var compressible: [MemoryEntry] = []

        for entry in entries {
            if shouldPreserveVerbatim(entry) {
                verbatim.append(entry)
            } else {
                compressible.append(entry)
            }
        }

        // If already within budget, return as-is
        let totalTokens = estimateTokens(entries)
        if totalTokens <= maxTokens {
            return entries
        }

        // Cluster compressible entries by tool name (from metadata) or kind
        let clusters = clusterEntries(compressible)

        // Summarize each cluster
        var compressed: [MemoryEntry] = []
        for cluster in clusters {
            let summary = summarizeCluster(cluster)
            compressed.append(summary)
        }

        // Combine verbatim + compressed, sorted by timestamp
        var result = verbatim + compressed
        result.sort { $0.timestamp < $1.timestamp }

        return result
    }

    // MARK: - Internal

    /// Whether an entry should be preserved verbatim during compression.
    private func shouldPreserveVerbatim(_ entry: MemoryEntry) -> Bool {
        switch entry.kind {
        case .decision, .error:
            return true
        case .note:
            // Preserve user-issued instructions
            let lower = entry.content.lowercased()
            return lower.contains("user:") || lower.contains("instruction:")
        case .toolCall, .observation:
            return false
        }
    }

    /// Cluster entries by their tool name or kind.
    private func clusterEntries(_ entries: [MemoryEntry]) -> [[MemoryEntry]] {
        var clusters: [String: [MemoryEntry]] = [:]

        for entry in entries {
            let key: String
            if let tool = entry.metadata["tool"] {
                key = tool
            } else {
                key = entry.kind.rawValue
            }
            clusters[key, default: []].append(entry)
        }

        return Array(clusters.values)
    }

    /// Summarize a cluster of entries into a single compressed entry.
    private func summarizeCluster(_ cluster: [MemoryEntry]) -> MemoryEntry {
        guard let first = cluster.first else {
            return MemoryEntry(kind: .note, content: "[empty cluster]")
        }

        if cluster.count == 1 {
            // Single entry: just truncate if needed
            let content = String(first.content.prefix(Self.maxSummaryChars))
            return MemoryEntry(
                timestamp: first.timestamp,
                kind: first.kind,
                content: content,
                metadata: first.metadata
            )
        }

        // Multi-entry cluster: build a summary
        let tool = first.metadata["tool"] ?? first.kind.rawValue
        let count = cluster.count
        let earliest = cluster.map(\.timestamp).min() ?? first.timestamp

        // Collect unique file paths mentioned
        let files = Set(cluster.compactMap { $0.metadata["file"] })
        let filesList = files.isEmpty ? "" : " Files: \(files.sorted().joined(separator: ", "))."

        // Build compact summary
        let snippets = cluster.prefix(3).map { entry in
            String(entry.content.prefix(100))
        }
        let snippetText = snippets.joined(separator: " | ")

        let content = "[\(count)x \(tool)]\(filesList) \(snippetText)"
        let truncated = String(content.prefix(Self.maxSummaryChars))

        return MemoryEntry(
            timestamp: earliest,
            kind: .note,
            content: truncated,
            metadata: ["compressed": "true", "source_count": "\(count)"]
        )
    }

    /// Estimate token count for a list of entries (~4 chars per token).
    private func estimateTokens(_ entries: [MemoryEntry]) -> Int {
        entries.reduce(0) { total, entry in
            total + max(1, entry.content.count / 4)
        }
    }
}
