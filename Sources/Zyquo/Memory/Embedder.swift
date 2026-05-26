import Foundation

// MARK: - Embedder Protocol

/// Abstraction for text embedding models.
///
/// Implementations produce fixed-dimension float vectors from text input.
/// The same text MUST always produce the same vector for a given model.
///
/// Reference: CLAUDE.md V2 Phase 3 - Embeddings & Local Vector Memory
public protocol Embedder: Sendable {
    /// The dimensionality of the embedding vectors produced by this embedder.
    var dimensions: Int { get }

    /// A stable identifier for the embedding model (e.g. "mock-128", "text-embedding-3-small").
    var modelId: String { get }

    /// Embed a single text string into a vector.
    ///
    /// - Parameter text: The input text.
    /// - Returns: A float vector of length `dimensions`.
    func embed(_ text: String) async throws -> [Float]

    /// Embed a batch of texts into vectors.
    ///
    /// Default implementation calls `embed(_:)` sequentially.
    ///
    /// - Parameter texts: The input texts.
    /// - Returns: An array of float vectors, one per input text.
    func embedBatch(_ texts: [String]) async throws -> [[Float]]
}

// Default batch implementation
extension Embedder {
    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            let vec = try await embed(text)
            results.append(vec)
        }
        return results
    }
}

// MARK: - MockEmbedder

/// A deterministic embedder that produces semantically meaningful vectors
/// using word hashing. Designed for testing and offline use.
///
/// Strategy:
/// 1. Tokenize text into lowercase words.
/// 2. Hash each word to one or more positions in the vector.
/// 3. Accumulate word contributions.
/// 4. Normalize to unit length.
///
/// This ensures:
/// - Same text always produces the same vector.
/// - Similar texts (sharing words) produce similar vectors.
/// - Different texts produce different vectors.
public final class MockEmbedder: Embedder, @unchecked Sendable {
    public let dimensions: Int
    public let modelId: String

    public init(dimensions: Int = 128) {
        self.dimensions = dimensions
        self.modelId = "mock-\(dimensions)"
    }

    public func embed(_ text: String) async throws -> [Float] {
        let words = tokenize(text)
        guard !words.isEmpty else {
            return [Float](repeating: 0, count: dimensions)
        }

        var vector = [Float](repeating: 0, count: dimensions)

        for word in words {
            // Use multiple hash functions to spread word signal across dimensions.
            // This creates richer overlap between related texts.
            let hash1 = stableHash(word, seed: 0)
            let hash2 = stableHash(word, seed: 31)
            let hash3 = stableHash(word, seed: 97)

            let pos1 = Int(hash1 % UInt64(dimensions))
            let pos2 = Int(hash2 % UInt64(dimensions))
            let pos3 = Int(hash3 % UInt64(dimensions))

            // Use hash to determine sign (+1 or -1) for richer geometry
            let sign1: Float = (hash1 / UInt64(dimensions)) % 2 == 0 ? 1.0 : -1.0
            let sign2: Float = (hash2 / UInt64(dimensions)) % 2 == 0 ? 1.0 : -1.0
            let sign3: Float = (hash3 / UInt64(dimensions)) % 2 == 0 ? 1.0 : -1.0

            vector[pos1] += sign1
            vector[pos2] += sign2 * 0.7
            vector[pos3] += sign3 * 0.5
        }

        // Normalize to unit vector
        return VectorMath.normalize(vector)
    }

    // MARK: - Internal

    /// Tokenize text into lowercase words of at least 2 characters.
    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    /// A stable hash function that produces consistent results across runs.
    /// Uses FNV-1a hashing with a configurable seed.
    private func stableHash(_ string: String, seed: UInt64) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037 &+ seed &* 6_364_136_223_846_793_005
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }
}

// MARK: - CloudEmbedder

/// An embedder that calls a cloud embedding API (e.g. OpenAI text-embedding-3-small).
///
/// This is a structural placeholder that demonstrates the API call shape.
/// In production, it reads the API key from Keychain and sends HTTPS requests.
///
/// Reference: CLAUDE.md Appendix C.2 - Embeddings
public final class CloudEmbedder: Embedder, @unchecked Sendable {
    public let dimensions: Int
    public let modelId: String

    /// The API endpoint URL.
    private let endpoint: URL

    /// The API key (in production, read from Keychain at init).
    private let apiKey: String?

    /// Initialize a cloud embedder.
    ///
    /// - Parameters:
    ///   - modelId: The model identifier (e.g. "text-embedding-3-small").
    ///   - dimensions: The output dimension count.
    ///   - endpoint: The API endpoint URL.
    ///   - apiKey: The API key (nil uses mock fallback).
    public init(
        modelId: String = "text-embedding-3-small",
        dimensions: Int = 1536,
        endpoint: URL = URL(string: "https://api.openai.com/v1/embeddings")!,
        apiKey: String? = nil
    ) {
        self.modelId = modelId
        self.dimensions = dimensions
        self.endpoint = endpoint
        self.apiKey = apiKey
    }

    public func embed(_ text: String) async throws -> [Float] {
        let results = try await embedBatch([text])
        guard let first = results.first else {
            throw EmbedderError.emptyResponse
        }
        return first
    }

    public func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard let apiKey, !apiKey.isEmpty else {
            // Fall back to mock embedder when no API key is configured
            let mock = MockEmbedder(dimensions: dimensions)
            return try await mock.embedBatch(texts)
        }

        // Build the API request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": modelId,
            "input": texts,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbedderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw EmbedderError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]]
        else {
            throw EmbedderError.invalidResponse
        }

        return dataArray.compactMap { item -> [Float]? in
            guard let embedding = item["embedding"] as? [NSNumber] else { return nil }
            return embedding.map { Float(truncating: $0) }
        }
    }
}

// MARK: - EmbedderError

/// Errors that can occur during embedding.
public enum EmbedderError: Error, Sendable, CustomStringConvertible {
    case emptyResponse
    case invalidResponse
    case apiError(statusCode: Int)
    case dimensionMismatch(expected: Int, got: Int)

    public var description: String {
        switch self {
        case .emptyResponse:
            return "Embedding API returned empty response"
        case .invalidResponse:
            return "Invalid response from embedding API"
        case .apiError(let code):
            return "Embedding API error: HTTP \(code)"
        case .dimensionMismatch(let expected, let got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)"
        }
    }
}
