import Foundation

// MARK: - DecisionEntry

/// A structured decision record (ADR-like).
public struct DecisionEntry: Sendable, Codable, Equatable {
    /// Title of the decision.
    public let title: String
    /// Context that led to the decision.
    public let context: String
    /// The decision that was made.
    public let decision: String
    /// Expected consequences.
    public let consequences: String
    /// Alternatives that were considered.
    public let alternatives: String
    /// Current status (e.g. "accepted", "superseded", "deprecated").
    public let status: String
    /// When the decision was recorded.
    public let date: Date

    public init(
        title: String,
        context: String,
        decision: String,
        consequences: String,
        alternatives: String,
        status: String = "accepted",
        date: Date = Date()
    ) {
        self.title = title
        self.context = context
        self.decision = decision
        self.consequences = consequences
        self.alternatives = alternatives
        self.status = status
        self.date = date
    }

    /// Render this entry as a markdown section for appending to decisions.md.
    public func renderMarkdown() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = formatter.string(from: date)

        return """

        ## \(title)

        **Date:** \(dateStr)
        **Status:** \(status)

        **Context:** \(context)

        **Decision:** \(decision)

        **Consequences:** \(consequences)

        **Alternatives considered:** \(alternatives)

        """
    }
}

// MARK: - MemoryStore

/// Actor-isolated store for project memory, architecture, and decisions.
///
/// Memory files live under `.zyquo/memory/`:
/// - `project.md` — hand-editable project memory (SACRED, never overwritten)
/// - `architecture.md` — auto-generated on first scan, hand-editable
/// - `decisions.md` — append-only decision log
///
/// Reference: CLAUDE.md S23.1, S23.2
public actor MemoryStore {
    /// Base directory for memory files.
    private let baseDir: URL

    public init(baseDir: URL) {
        self.baseDir = baseDir
    }

    // MARK: - Read

    /// Read the project memory file.
    ///
    /// - Returns: The contents of `project.md`, or nil if not found.
    public func readProject() -> String? {
        readFile(named: "project.md")
    }

    /// Read the architecture memory file.
    ///
    /// - Returns: The contents of `architecture.md`, or nil if not found.
    public func readArchitecture() -> String? {
        readFile(named: "architecture.md")
    }

    /// Read the decisions file.
    ///
    /// - Returns: The contents of `decisions.md`, or nil if not found.
    public func readDecisions() -> String? {
        readFile(named: "decisions.md")
    }

    // MARK: - Write

    /// Append a decision entry to the decisions log.
    ///
    /// Creates `decisions.md` with a header if it does not exist.
    ///
    /// - Parameter entry: The decision to append.
    /// - Throws: If the file cannot be written.
    public func appendDecision(_ entry: DecisionEntry) throws {
        try ensureDir()
        let path = baseDir.appendingPathComponent("decisions.md")
        let fm = FileManager.default

        let markdown = entry.renderMarkdown()

        if fm.fileExists(atPath: path.path) {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = markdown.data(using: .utf8) {
                handle.write(data)
            }
        } else {
            let header = "# Decisions\n\n<!-- Append-only decision log. Each entry is an ADR-like record. -->\n"
            let content = header + markdown
            try content.write(to: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Search

    /// Search memory for chunks matching a query.
    ///
    /// Uses keyword-based scoring (term frequency). Searches across
    /// the requested scope(s).
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - scope: Which memory layers to search.
    ///   - limit: Maximum number of results.
    /// - Returns: Ranked memory chunks.
    public func search(query: String, scope: MemoryScope, limit: Int = 10) -> [MemoryChunk] {
        guard !query.isEmpty else { return [] }

        let queryTerms = tokenize(query)
        guard !queryTerms.isEmpty else { return [] }

        var chunks: [MemoryChunk] = []

        // Determine which files to search
        let filesToSearch: [(name: String, source: String)] = {
            switch scope {
            case .project:
                return [("project.md", "project")]
            case .architecture:
                return [("architecture.md", "architecture")]
            case .decisions:
                return [("decisions.md", "decisions")]
            case .session:
                return [] // Session memory is in-memory, not file-based here
            case .all:
                return [
                    ("project.md", "project"),
                    ("architecture.md", "architecture"),
                    ("decisions.md", "decisions"),
                ]
            }
        }()

        for (fileName, source) in filesToSearch {
            guard let content = readFile(named: fileName) else { continue }

            // Split content into chunks by sections (headings)
            let sections = splitIntoChunks(content)
            for section in sections {
                let score = scoreChunk(section, queryTerms: queryTerms)
                if score > 0 {
                    chunks.append(MemoryChunk(
                        content: section,
                        source: source,
                        score: score
                    ))
                }
            }
        }

        // Sort by score descending and limit
        chunks.sort { $0.score > $1.score }
        return Array(chunks.prefix(limit))
    }

    // MARK: - Internal

    private func readFile(named name: String) -> String? {
        let path = baseDir.appendingPathComponent(name)
        return try? String(contentsOf: path, encoding: .utf8)
    }

    private func ensureDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDir.path) {
            try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
    }

    /// Split content into chunks by markdown headings.
    private func splitIntoChunks(_ content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        var chunks: [String] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") && !current.isEmpty {
                let chunk = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    chunks.append(chunk)
                }
                current = [line]
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            let chunk = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
        }

        return chunks
    }

    /// Tokenize a string into lowercase terms.
    private func tokenize(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        return Set(tokens)
    }

    /// Score a chunk against query terms using term frequency.
    private func scoreChunk(_ chunk: String, queryTerms: Set<String>) -> Double {
        let chunkTerms = tokenize(chunk)
        guard !chunkTerms.isEmpty else { return 0 }

        var matchCount = 0
        for term in queryTerms {
            if chunkTerms.contains(term) {
                matchCount += 1
            }
        }

        guard matchCount > 0 else { return 0 }

        // Score: proportion of query terms matched, weighted by inverse chunk length
        let termCoverage = Double(matchCount) / Double(queryTerms.count)
        let lengthPenalty = 1.0 / (1.0 + log(Double(max(1, chunkTerms.count))))
        return termCoverage * (1.0 + lengthPenalty)
    }
}
