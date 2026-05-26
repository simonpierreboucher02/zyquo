import Foundation

// MARK: - SearchResult

/// A result from a semantic search query.
///
/// May contain a matched symbol, a matched code chunk, or both.
/// Results are ranked by relevance score (higher is better).
public struct SearchResult: Sendable, Equatable {
    /// The symbol that matched, if any.
    public let symbol: Symbol?
    /// The code chunk that matched, if any.
    public let chunk: CodeChunk?
    /// The file path where the match was found.
    public let filePath: String
    /// The relevance score (0.0 to 1.0, higher is better).
    public let score: Float
    /// A snippet of code showing the match in context.
    public let snippet: String

    public init(
        symbol: Symbol? = nil,
        chunk: CodeChunk? = nil,
        filePath: String,
        score: Float,
        snippet: String
    ) {
        self.symbol = symbol
        self.chunk = chunk
        self.filePath = filePath
        self.score = score
        self.snippet = snippet
    }
}

// MARK: - SemanticSearch

/// Performs semantic search across a symbol index and optional code chunks.
///
/// Combines multiple search signals:
/// 1. **Exact name match** -- symbol name exactly equals the query (score: 1.0)
/// 2. **Prefix match** -- symbol name starts with the query (score: 0.8)
/// 3. **Contains match** -- symbol name contains the query (score: 0.6)
/// 4. **File path match** -- file path contains the query (score: 0.4)
/// 5. **Content match** -- code content contains the query keywords (score: 0.3)
///
/// Results are deduplicated by file path + line and sorted by score descending.
///
/// Reference: CLAUDE.md V2 Phase 2 - Semantic Repository Intelligence
public struct SemanticSearch: Sendable {
    public init() {}

    /// Search the symbol index for results matching the query.
    ///
    /// - Parameters:
    ///   - query: The search query (natural language or symbol name).
    ///   - index: The symbol index to search.
    ///   - limit: Maximum number of results to return.
    /// - Returns: Ranked search results, up to `limit` entries.
    public func search(
        query: String,
        index: SymbolIndex,
        limit: Int = 20
    ) async -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var results: [SearchResult] = []
        let lowerQuery = trimmedQuery.lowercased()
        let queryWords = lowerQuery.split(separator: " ").map(String.init)

        // 1. Search by symbol name
        let symbolResults = await searchSymbols(
            query: trimmedQuery,
            lowerQuery: lowerQuery,
            index: index
        )
        results.append(contentsOf: symbolResults)

        // 2. Search by file path
        let pathResults = await searchFilePaths(
            lowerQuery: lowerQuery,
            queryWords: queryWords,
            index: index
        )
        results.append(contentsOf: pathResults)

        // Deduplicate by (filePath, line)
        var seen: Set<String> = []
        var deduplicated: [SearchResult] = []
        for result in results.sorted(by: { $0.score > $1.score }) {
            let key: String
            if let symbol = result.symbol {
                key = "\(result.filePath):\(symbol.line)"
            } else {
                key = "\(result.filePath):\(result.snippet.prefix(50))"
            }
            if seen.insert(key).inserted {
                deduplicated.append(result)
            }
        }

        return Array(deduplicated.prefix(limit))
    }

    /// Search with additional code chunks for content-level matching.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - index: The symbol index to search.
    ///   - chunks: Code chunks to search for content matches.
    ///   - limit: Maximum number of results.
    /// - Returns: Ranked search results.
    public func search(
        query: String,
        index: SymbolIndex,
        chunks: [CodeChunk],
        limit: Int = 20
    ) async -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        var results = await search(query: trimmedQuery, index: index, limit: limit * 2)

        // Add chunk-level content matches
        let lowerQuery = trimmedQuery.lowercased()
        let queryWords = lowerQuery.split(separator: " ").map(String.init)
        let chunkResults = searchChunks(
            lowerQuery: lowerQuery,
            queryWords: queryWords,
            chunks: chunks
        )
        results.append(contentsOf: chunkResults)

        // Deduplicate and sort
        var seen: Set<String> = []
        var deduplicated: [SearchResult] = []
        for result in results.sorted(by: { $0.score > $1.score }) {
            let key: String
            if let symbol = result.symbol {
                key = "\(result.filePath):\(symbol.line)"
            } else if let chunk = result.chunk {
                key = "\(result.filePath):\(chunk.startLine)"
            } else {
                key = "\(result.filePath):\(result.snippet.prefix(50))"
            }
            if seen.insert(key).inserted {
                deduplicated.append(result)
            }
        }

        return Array(deduplicated.prefix(limit))
    }

    // MARK: - Private Search Methods

    /// Search symbols by name matching.
    private func searchSymbols(
        query: String,
        lowerQuery: String,
        index: SymbolIndex
    ) async -> [SearchResult] {
        var results: [SearchResult] = []

        // Use the index's fuzzy search which returns exact > prefix > contains
        let matches = await index.find(query: query)

        for symbol in matches {
            let lowerName = symbol.name.lowercased()
            let score: Float
            if lowerName == lowerQuery {
                score = 1.0
            } else if lowerName.hasPrefix(lowerQuery) {
                score = 0.8
            } else {
                score = 0.6
            }

            let snippet = symbol.signature ?? symbol.name
            results.append(SearchResult(
                symbol: symbol,
                chunk: nil,
                filePath: symbol.filePath,
                score: score,
                snippet: snippet
            ))
        }

        return results
    }

    /// Search by file path matching.
    private func searchFilePaths(
        lowerQuery: String,
        queryWords: [String],
        index: SymbolIndex
    ) async -> [SearchResult] {
        var results: [SearchResult] = []

        // Get all symbol names and check their file paths
        let allNames = await index.allSymbolNames
        var seenPaths: Set<String> = []

        for name in allNames {
            let symbols = await index.find(name: name, kind: nil)
            for symbol in symbols {
                let path = symbol.filePath.lowercased()
                guard !seenPaths.contains(symbol.filePath) else { continue }

                let pathMatches = queryWords.allSatisfy { path.contains($0) }
                    || path.contains(lowerQuery)

                if pathMatches {
                    seenPaths.insert(symbol.filePath)
                    results.append(SearchResult(
                        symbol: nil,
                        chunk: nil,
                        filePath: symbol.filePath,
                        score: 0.4,
                        snippet: symbol.filePath
                    ))
                }
            }
        }

        return results
    }

    /// Search code chunks for content-level matches.
    private func searchChunks(
        lowerQuery: String,
        queryWords: [String],
        chunks: [CodeChunk]
    ) -> [SearchResult] {
        var results: [SearchResult] = []

        for chunk in chunks {
            let lowerContent = chunk.content.lowercased()

            // Check if all query words appear in the content
            let matchCount = queryWords.filter { lowerContent.contains($0) }.count
            guard matchCount > 0 else { continue }

            let wordRatio = Float(matchCount) / Float(max(1, queryWords.count))
            let score: Float = 0.3 * wordRatio

            // Extract a relevant snippet (first line containing a query word)
            let snippetLine = chunk.content.components(separatedBy: .newlines)
                .first { line in
                    let lower = line.lowercased()
                    return queryWords.contains { lower.contains($0) }
                }
                ?? chunk.content.components(separatedBy: .newlines).first
                ?? ""

            results.append(SearchResult(
                symbol: nil,
                chunk: chunk,
                filePath: chunk.filePath,
                score: score,
                snippet: snippetLine.trimmingCharacters(in: .whitespaces)
            ))
        }

        return results
    }
}
