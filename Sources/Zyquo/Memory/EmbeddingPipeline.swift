import Foundation

// MARK: - CodeChunkRef

/// A lightweight, serializable reference to a code chunk.
///
/// Unlike `CodeChunk`, this does not carry the full source content.
/// Used in `EmbeddedChunk` to avoid storing large source texts alongside vectors.
public struct CodeChunkRef: Sendable, Codable, Equatable, Hashable {
    /// The file path this chunk belongs to.
    public let filePath: String
    /// The start line (1-based) of the chunk.
    public let startLine: Int
    /// The end line (1-based, inclusive) of the chunk.
    public let endLine: Int
    /// The name of the symbol (function, class, etc.) or nil for anonymous chunks.
    public let name: String?
    /// The structural kind of the chunk (e.g. "function", "class_", "block").
    public let kind: String

    public init(filePath: String, startLine: Int, endLine: Int, name: String?, kind: String) {
        self.filePath = filePath
        self.startLine = startLine
        self.endLine = endLine
        self.name = name
        self.kind = kind
    }

    /// Create a ref from a full CodeChunk.
    public init(from chunk: CodeChunk) {
        self.filePath = chunk.filePath
        self.startLine = chunk.startLine
        self.endLine = chunk.endLine
        self.name = chunk.name
        self.kind = chunk.kind.rawValue
    }
}

// MARK: - EmbeddedChunk

/// A code chunk paired with its embedding vector.
///
/// Persisted to disk as part of the vector store.
public struct EmbeddedChunk: Sendable, Codable {
    /// Lightweight reference to the source chunk.
    public let chunk: CodeChunkRef
    /// The embedding vector.
    public let vector: [Float]
    /// When this chunk was embedded.
    public let embeddedAt: Date

    public init(chunk: CodeChunkRef, vector: [Float], embeddedAt: Date = Date()) {
        self.chunk = chunk
        self.vector = vector
        self.embeddedAt = embeddedAt
    }
}

// MARK: - EmbeddingPipeline

/// The chunk-to-vector pipeline: takes code chunks and produces embedded chunks.
///
/// Manages the embedding process, including batching and rate limiting.
/// Uses an `Embedder` implementation to produce the actual vectors.
///
/// Reference: CLAUDE.md V2 Phase 3 - Embeddings & Local Vector Memory
public actor EmbeddingPipeline {
    /// The embedder used to produce vectors.
    private let embedder: any Embedder

    /// Maximum batch size for embedding requests.
    private let batchSize: Int

    /// Initialize the embedding pipeline.
    ///
    /// - Parameters:
    ///   - embedder: The embedder implementation to use.
    ///   - batchSize: Maximum texts to embed in a single batch call.
    public init(embedder: any Embedder, batchSize: Int = 64) {
        self.embedder = embedder
        self.batchSize = batchSize
    }

    /// Embed a list of code chunks, producing embedded chunks with vectors.
    ///
    /// Chunks are batched for efficiency. Each chunk's content is embedded
    /// using the configured embedder.
    ///
    /// - Parameter chunks: The code chunks to embed.
    /// - Returns: Embedded chunks with their vectors.
    public func embed(chunks: [CodeChunk]) async throws -> [EmbeddedChunk] {
        guard !chunks.isEmpty else { return [] }

        var results: [EmbeddedChunk] = []
        results.reserveCapacity(chunks.count)

        // Process in batches
        for batchStart in stride(from: 0, to: chunks.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, chunks.count)
            let batch = Array(chunks[batchStart..<batchEnd])

            let texts = batch.map { $0.content }
            let vectors = try await embedder.embedBatch(texts)

            let now = Date()
            for (chunk, vector) in zip(batch, vectors) {
                let ref = CodeChunkRef(from: chunk)
                results.append(EmbeddedChunk(chunk: ref, vector: vector, embeddedAt: now))
            }
        }

        return results
    }

    /// Embed a single text string into a vector.
    ///
    /// - Parameter text: The input text.
    /// - Returns: The embedding vector.
    public func embed(text: String) async throws -> [Float] {
        try await embedder.embed(text)
    }

    /// Embed a batch of texts into vectors.
    ///
    /// - Parameter texts: The input texts.
    /// - Returns: An array of embedding vectors.
    public func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }

        var results: [[Float]] = []
        results.reserveCapacity(texts.count)

        for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, texts.count)
            let batch = Array(texts[batchStart..<batchEnd])
            let vectors = try await embedder.embedBatch(batch)
            results.append(contentsOf: vectors)
        }

        return results
    }

    /// The dimensionality of the embedding vectors.
    public var dimensions: Int {
        embedder.dimensions
    }

    /// The model identifier of the underlying embedder.
    public var modelId: String {
        embedder.modelId
    }
}
