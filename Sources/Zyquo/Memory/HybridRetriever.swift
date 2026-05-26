import Foundation

// MARK: - HybridRetriever

/// Hybrid retriever combining keyword-based (BM25-ish) and vector-based retrieval.
///
/// Queries both a `KeywordMemoryRetriever` (V1) and a `VectorStore`, then
/// merges results using Reciprocal Rank Fusion (RRF):
///
///     score = sum(1 / (k + rank_i))
///
/// where k = 60 (standard RRF constant). Results are deduplicated by
/// file path + line range before returning.
///
/// Reference: CLAUDE.md V2 Phase 3 - Embeddings & Local Vector Memory
public actor HybridRetriever: MemoryRetriever {
    /// The keyword-based retriever (V1).
    private let keywordRetriever: KeywordMemoryRetriever

    /// The vector store for semantic search.
    private let vectorStore: VectorStore

    /// The embedding pipeline for query vectorization.
    private let pipeline: EmbeddingPipeline

    /// RRF constant (standard value from the literature).
    private static let rrfK: Double = 60.0

    /// How many results to fetch from each source before fusion.
    private let fetchMultiplier: Int

    /// Initialize a hybrid retriever.
    ///
    /// - Parameters:
    ///   - keywordRetriever: The keyword-based memory retriever.
    ///   - vectorStore: The vector store for semantic search.
    ///   - pipeline: The embedding pipeline for vectorizing queries.
    ///   - fetchMultiplier: Multiplier for how many results to fetch from each
    ///     source relative to the requested limit (default 3).
    public init(
        keywordRetriever: KeywordMemoryRetriever,
        vectorStore: VectorStore,
        pipeline: EmbeddingPipeline,
        fetchMultiplier: Int = 3
    ) {
        self.keywordRetriever = keywordRetriever
        self.vectorStore = vectorStore
        self.pipeline = pipeline
        self.fetchMultiplier = fetchMultiplier
    }

    /// Recall memory chunks using hybrid keyword + vector retrieval.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - scope: Which memory layers to search.
    ///   - limit: Maximum number of results.
    /// - Returns: Merged and ranked memory chunks.
    public nonisolated func recall(
        query: String,
        scope: MemoryScope,
        limit: Int
    ) async throws -> [MemoryChunk] {
        guard !query.isEmpty else { return [] }

        let fetchLimit = limit * fetchMultiplier

        // Fetch keyword results
        let keywordResults = try await keywordRetriever.recall(
            query: query, scope: scope, limit: fetchLimit
        )

        // Fetch vector results
        let vectorResults = await vectorSearch(query: query, limit: fetchLimit)

        // Merge using RRF
        let fused = fuseResults(
            keywordResults: keywordResults,
            vectorResults: vectorResults
        )

        // Deduplicate and limit
        let deduped = deduplicate(fused)
        return Array(deduped.prefix(limit))
    }

    // MARK: - Vector Search

    /// Perform a vector similarity search for the query.
    private func vectorSearch(query: String, limit: Int) async -> [VectorSearchResult] {
        do {
            let queryVector = try await pipeline.embed(text: query)
            return await vectorStore.search(query: queryVector, topK: limit)
        } catch {
            // If embedding fails, return empty — keyword results will still work
            return []
        }
    }

    // MARK: - Reciprocal Rank Fusion

    /// Merge keyword and vector results using Reciprocal Rank Fusion.
    private nonisolated func fuseResults(
        keywordResults: [MemoryChunk],
        vectorResults: [VectorSearchResult]
    ) -> [MemoryChunk] {
        // Build a map of dedup key → RRF score + best chunk
        var scoreMap: [String: (score: Double, chunk: MemoryChunk)] = [:]

        // Score keyword results
        for (rank, chunk) in keywordResults.enumerated() {
            let key = deduplicationKey(source: chunk.source, content: chunk.content)
            let rrfScore = 1.0 / (Self.rrfK + Double(rank + 1))

            if let existing = scoreMap[key] {
                scoreMap[key] = (existing.score + rrfScore, existing.chunk)
            } else {
                scoreMap[key] = (rrfScore, chunk)
            }
        }

        // Score vector results, converting them to MemoryChunks
        for result in vectorResults {
            let key = deduplicationKey(
                source: result.chunk.filePath,
                startLine: result.chunk.startLine,
                endLine: result.chunk.endLine
            )
            let rrfScore = 1.0 / (Self.rrfK + Double(result.rank))

            if let existing = scoreMap[key] {
                scoreMap[key] = (existing.score + rrfScore, existing.chunk)
            } else {
                let chunk = MemoryChunk(
                    content: formatVectorResult(result),
                    source: result.chunk.filePath,
                    score: Double(result.score),
                    metadata: [
                        "startLine": "\(result.chunk.startLine)",
                        "endLine": "\(result.chunk.endLine)",
                        "kind": result.chunk.kind,
                        "name": result.chunk.name ?? "",
                        "retrieval": "vector",
                    ]
                )
                scoreMap[key] = (rrfScore, chunk)
            }
        }

        // Sort by fused RRF score descending
        return scoreMap.values
            .sorted { $0.score > $1.score }
            .map { item in
                MemoryChunk(
                    content: item.chunk.content,
                    source: item.chunk.source,
                    score: item.score,
                    metadata: item.chunk.metadata
                )
            }
    }

    // MARK: - Deduplication

    /// Generate a deduplication key for a memory chunk.
    private nonisolated func deduplicationKey(source: String, content: String) -> String {
        // For keyword results, use source + content hash
        let contentHash = content.hashValue
        return "\(source)::\(contentHash)"
    }

    /// Generate a deduplication key for a vector result.
    private nonisolated func deduplicationKey(source: String, startLine: Int, endLine: Int) -> String {
        return "\(source)::\(startLine)-\(endLine)"
    }

    /// Deduplicate chunks that overlap in file path and line range.
    private nonisolated func deduplicate(_ chunks: [MemoryChunk]) -> [MemoryChunk] {
        var seen = Set<String>()
        var result: [MemoryChunk] = []

        for chunk in chunks {
            let key: String
            if let startLine = chunk.metadata["startLine"],
               let endLine = chunk.metadata["endLine"] {
                key = "\(chunk.source)::\(startLine)-\(endLine)"
            } else {
                key = "\(chunk.source)::\(chunk.content.hashValue)"
            }

            if seen.insert(key).inserted {
                result.append(chunk)
            }
        }

        return result
    }

    /// Format a vector search result into a readable content string.
    private nonisolated func formatVectorResult(_ result: VectorSearchResult) -> String {
        let name = result.chunk.name.map { " (\($0))" } ?? ""
        return "[\(result.chunk.kind)\(name)] \(result.chunk.filePath):\(result.chunk.startLine)-\(result.chunk.endLine)"
    }
}
