import Foundation

// MARK: - VectorSearchResult

/// A result from a vector similarity search.
public struct VectorSearchResult: Sendable {
    /// The chunk reference that matched.
    public let chunk: CodeChunkRef
    /// The cosine similarity score (higher = more similar).
    public let score: Float
    /// The 1-based rank in the result set.
    public let rank: Int

    public init(chunk: CodeChunkRef, score: Float, rank: Int) {
        self.chunk = chunk
        self.score = score
        self.rank = rank
    }
}

// MARK: - VectorStore

/// An in-memory vector store with JSON persistence.
///
/// Stores embedded chunks and supports cosine-similarity search.
/// Persists to a JSON file on disk for durability across sessions.
///
/// This is a pure-Swift implementation without external C extensions.
/// A native vector extension (e.g. sqlite-vec) can replace the backend later.
///
/// Reference: CLAUDE.md V2 Phase 3 - Embeddings & Local Vector Memory
public actor VectorStore {
    /// The file path for JSON persistence.
    private let path: URL

    /// All stored embedded chunks.
    private var chunks: [EmbeddedChunk] = []

    /// Index from file path to chunk indices for fast file-level operations.
    private var fileIndex: [String: [Int]] = [:]

    /// Whether the store has unsaved changes.
    private var isDirty: Bool = false

    /// Initialize a vector store.
    ///
    /// - Parameter path: The file URL for JSON persistence.
    ///   The file will be created on first `save()` if it does not exist.
    public init(path: URL) {
        self.path = path
    }

    // MARK: - Add

    /// Add a single embedded chunk to the store.
    ///
    /// - Parameter chunk: The embedded chunk to add.
    public func add(_ chunk: EmbeddedChunk) {
        let index = chunks.count
        chunks.append(chunk)
        fileIndex[chunk.chunk.filePath, default: []].append(index)
        isDirty = true
    }

    /// Add a batch of embedded chunks to the store.
    ///
    /// - Parameter newChunks: The embedded chunks to add.
    public func addBatch(_ newChunks: [EmbeddedChunk]) {
        guard !newChunks.isEmpty else { return }
        let startIndex = chunks.count
        chunks.append(contentsOf: newChunks)
        for (offset, chunk) in newChunks.enumerated() {
            fileIndex[chunk.chunk.filePath, default: []].append(startIndex + offset)
        }
        isDirty = true
    }

    // MARK: - Search

    /// Search for the most similar chunks to a query vector.
    ///
    /// Uses brute-force cosine similarity over all stored vectors.
    /// Results are sorted by score descending.
    ///
    /// - Parameters:
    ///   - query: The query vector (must match the stored vector dimensions).
    ///   - topK: Maximum number of results to return.
    /// - Returns: The top-K most similar chunks with scores and ranks.
    public func search(query: [Float], topK: Int) -> [VectorSearchResult] {
        guard !chunks.isEmpty, topK > 0 else { return [] }

        // Score all chunks against the query
        var scored: [(index: Int, score: Float)] = []
        scored.reserveCapacity(chunks.count)

        for (i, chunk) in chunks.enumerated() {
            guard chunk.vector.count == query.count else { continue }
            let score = VectorMath.cosineSimilarity(query, chunk.vector)
            scored.append((i, score))
        }

        // Sort by score descending and take top-K
        scored.sort { $0.score > $1.score }
        let topResults = scored.prefix(topK)

        return topResults.enumerated().map { rank, item in
            VectorSearchResult(
                chunk: chunks[item.index].chunk,
                score: item.score,
                rank: rank + 1
            )
        }
    }

    // MARK: - Remove

    /// Remove all chunks belonging to a file path.
    ///
    /// Used when a file is re-indexed: remove old embeddings before adding new ones.
    ///
    /// - Parameter filePath: The file path whose chunks should be removed.
    public func remove(filePath: String) {
        guard let indices = fileIndex[filePath] else { return }
        guard !indices.isEmpty else { return }

        // Remove from back to front to preserve indices
        let sortedIndices = indices.sorted(by: >)
        for index in sortedIndices {
            guard index < chunks.count else { continue }
            chunks.remove(at: index)
        }

        // Rebuild the file index (indices shifted after removal)
        rebuildFileIndex()
        isDirty = true
    }

    /// Remove all chunks from the store.
    public func clear() {
        chunks.removeAll()
        fileIndex.removeAll()
        isDirty = true
    }

    // MARK: - Persistence

    /// Save the store to disk as JSON.
    ///
    /// - Throws: If encoding or writing fails.
    public func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(StoreContainer(chunks: chunks))

        // Ensure the parent directory exists
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try data.write(to: path, options: .atomic)
        isDirty = false
    }

    /// Load the store from disk.
    ///
    /// Replaces all current in-memory data with the persisted data.
    ///
    /// - Throws: If reading or decoding fails.
    public func load() throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            chunks = []
            fileIndex = [:]
            return
        }

        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let container = try decoder.decode(StoreContainer.self, from: data)
        chunks = container.chunks
        rebuildFileIndex()
        isDirty = false
    }

    // MARK: - Info

    /// The number of chunks currently stored.
    public var count: Int {
        chunks.count
    }

    /// Whether there are unsaved changes.
    public var hasUnsavedChanges: Bool {
        isDirty
    }

    /// All unique file paths that have stored chunks.
    public var indexedFiles: Set<String> {
        Set(fileIndex.keys)
    }

    // MARK: - Internal

    /// Rebuild the file index from scratch.
    private func rebuildFileIndex() {
        fileIndex.removeAll(keepingCapacity: true)
        for (i, chunk) in chunks.enumerated() {
            fileIndex[chunk.chunk.filePath, default: []].append(i)
        }
    }
}

// MARK: - StoreContainer

/// Internal container for JSON serialization.
private struct StoreContainer: Codable {
    let chunks: [EmbeddedChunk]
}
