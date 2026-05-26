import Foundation

// MARK: - MemoryScope

/// The scope of a memory query.
public enum MemoryScope: String, Sendable, CaseIterable {
    case session
    case project
    case architecture
    case decisions
    case all
}

// MARK: - MemoryChunk

/// A ranked chunk of memory content returned from retrieval.
public struct MemoryChunk: Sendable, Equatable {
    /// The text content of this chunk.
    public let content: String
    /// Where this chunk came from (e.g. "project.md", "session zq_...").
    public let source: String
    /// Relevance score (higher is more relevant).
    public let score: Double
    /// Additional metadata about the chunk.
    public let metadata: [String: String]

    public init(
        content: String,
        source: String,
        score: Double,
        metadata: [String: String] = [:]
    ) {
        self.content = content
        self.source = source
        self.score = score
        self.metadata = metadata
    }
}

// MARK: - MemoryRetriever Protocol

/// Protocol for retrieving relevant memory chunks.
///
/// V1 implementation uses keyword-based scoring (BM25-ish term frequency).
/// V2 will add hybrid retrieval with local embeddings.
///
/// Reference: CLAUDE.md S23.4
public protocol MemoryRetriever: Sendable {
    /// Recall memory chunks relevant to a query.
    ///
    /// - Parameters:
    ///   - query: The search query.
    ///   - scope: Which memory layers to search.
    ///   - limit: Maximum number of results.
    /// - Returns: Ranked chunks ready for context injection.
    func recall(query: String, scope: MemoryScope, limit: Int) async throws -> [MemoryChunk]
}

// MARK: - KeywordMemoryRetriever

/// V1 implementation of MemoryRetriever using keyword-based scoring.
///
/// Searches across session memory, project memory, and decisions
/// using term frequency ranking.
public struct KeywordMemoryRetriever: MemoryRetriever, Sendable {
    private let memoryStore: MemoryStore

    public init(memoryStore: MemoryStore) {
        self.memoryStore = memoryStore
    }

    public func recall(query: String, scope: MemoryScope, limit: Int) async throws -> [MemoryChunk] {
        return await memoryStore.search(query: query, scope: scope, limit: limit)
    }
}
