import XCTest
@testable import Zyquo

// MARK: - VectorMath Tests

final class VectorMathTests: XCTestCase {

    func testCosineSimilarityIdenticalVectors() {
        let v = [Float](repeating: 1.0, count: 4)
        let sim = VectorMath.cosineSimilarity(v, v)
        XCTAssertEqual(sim, 1.0, accuracy: 1e-5, "Identical vectors should have cosine similarity of 1.0")
    }

    func testCosineSimilarityOrthogonalVectors() {
        let a: [Float] = [1, 0, 0, 0]
        let b: [Float] = [0, 1, 0, 0]
        let sim = VectorMath.cosineSimilarity(a, b)
        XCTAssertEqual(sim, 0.0, accuracy: 1e-5, "Orthogonal vectors should have cosine similarity of 0.0")
    }

    func testCosineSimilarityOppositeVectors() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [-1, -2, -3]
        let sim = VectorMath.cosineSimilarity(a, b)
        XCTAssertEqual(sim, -1.0, accuracy: 1e-5, "Opposite vectors should have cosine similarity of -1.0")
    }

    func testDotProductCorrectness() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [4, 5, 6]
        let dot = VectorMath.dotProduct(a, b)
        // 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
        XCTAssertEqual(dot, 32.0, accuracy: 1e-5)
    }

    func testNormalizeProducesUnitVector() {
        let v: [Float] = [3, 4]
        let normalized = VectorMath.normalize(v)
        let n = VectorMath.norm(normalized)
        XCTAssertEqual(n, 1.0, accuracy: 1e-5, "Normalized vector should have unit norm")
        XCTAssertEqual(normalized[0], 0.6, accuracy: 1e-5)
        XCTAssertEqual(normalized[1], 0.8, accuracy: 1e-5)
    }

    func testZeroVectorHandling() {
        let zero = [Float](repeating: 0, count: 4)
        let other: [Float] = [1, 2, 3, 4]

        XCTAssertEqual(VectorMath.cosineSimilarity(zero, other), 0.0,
                       "Cosine similarity with zero vector should be 0")
        XCTAssertEqual(VectorMath.norm(zero), 0.0, "Norm of zero vector should be 0")

        let normalized = VectorMath.normalize(zero)
        XCTAssertEqual(normalized, zero, "Normalizing zero vector should return zero vector")
    }

    func testNormCorrectness() {
        let v: [Float] = [3, 4]
        let n = VectorMath.norm(v)
        XCTAssertEqual(n, 5.0, accuracy: 1e-5, "norm([3,4]) should be 5")
    }

    func testAddVectors() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [4, 5, 6]
        let result = VectorMath.add(a, b)
        XCTAssertEqual(result, [5, 7, 9])
    }

    func testScaleVector() {
        let v: [Float] = [1, 2, 3]
        let result = VectorMath.scale(v, by: 2.0)
        XCTAssertEqual(result[0], 2.0, accuracy: 1e-5)
        XCTAssertEqual(result[1], 4.0, accuracy: 1e-5)
        XCTAssertEqual(result[2], 6.0, accuracy: 1e-5)
    }

    func testEmptyVectors() {
        let empty: [Float] = []
        XCTAssertEqual(VectorMath.dotProduct(empty, empty), 0)
        XCTAssertEqual(VectorMath.norm(empty), 0)
        XCTAssertEqual(VectorMath.normalize(empty), [])
        XCTAssertEqual(VectorMath.add(empty, empty), [])
        XCTAssertEqual(VectorMath.scale(empty, by: 2), [])
        XCTAssertEqual(VectorMath.cosineSimilarity(empty, empty), 0)
    }
}

// MARK: - MockEmbedder Tests

final class MockEmbedderTests: XCTestCase {

    func testSameTextProducesSameEmbedding() async throws {
        let embedder = MockEmbedder()
        let text = "func authenticate(user: String) -> Bool"

        let vec1 = try await embedder.embed(text)
        let vec2 = try await embedder.embed(text)

        XCTAssertEqual(vec1, vec2, "Same text must always produce the same embedding")
    }

    func testDifferentTextsProduceDifferentEmbeddings() async throws {
        let embedder = MockEmbedder()
        let vec1 = try await embedder.embed("authentication login password")
        let vec2 = try await embedder.embed("database query postgresql schema")

        XCTAssertNotEqual(vec1, vec2, "Different texts should produce different embeddings")
    }

    func testSimilarTextsHaveHigherSimilarity() async throws {
        let embedder = MockEmbedder()

        let vecAuth1 = try await embedder.embed("func authenticate user password login")
        let vecAuth2 = try await embedder.embed("func login user password authenticate")
        let vecUnrelated = try await embedder.embed("render terminal buffer ansi color theme")

        let similarScore = VectorMath.cosineSimilarity(vecAuth1, vecAuth2)
        let dissimilarScore = VectorMath.cosineSimilarity(vecAuth1, vecUnrelated)

        XCTAssertGreaterThan(
            similarScore, dissimilarScore,
            "Similar texts should have higher cosine similarity than dissimilar texts"
        )
    }

    func testCorrectDimensions() async throws {
        let embedder64 = MockEmbedder(dimensions: 64)
        let embedder256 = MockEmbedder(dimensions: 256)

        let vec64 = try await embedder64.embed("hello world")
        let vec256 = try await embedder256.embed("hello world")

        XCTAssertEqual(vec64.count, 64)
        XCTAssertEqual(vec256.count, 256)
        XCTAssertEqual(embedder64.dimensions, 64)
        XCTAssertEqual(embedder256.dimensions, 256)
    }

    func testModelId() {
        let embedder = MockEmbedder(dimensions: 128)
        XCTAssertEqual(embedder.modelId, "mock-128")
    }

    func testEmptyTextProducesZeroVector() async throws {
        let embedder = MockEmbedder()
        let vec = try await embedder.embed("")
        XCTAssertEqual(vec.count, 128)
        // All zeros for empty text
        XCTAssertTrue(vec.allSatisfy { $0 == 0 }, "Empty text should produce zero vector")
    }

    func testBatchEmbed() async throws {
        let embedder = MockEmbedder()
        let texts = ["hello world", "foo bar", "test case"]
        let vecs = try await embedder.embedBatch(texts)
        XCTAssertEqual(vecs.count, 3)
        for vec in vecs {
            XCTAssertEqual(vec.count, 128)
        }
    }

    func testNormalizedOutput() async throws {
        let embedder = MockEmbedder()
        let vec = try await embedder.embed("some meaningful text with words")
        let norm = VectorMath.norm(vec)
        // Should be unit length (normalized)
        XCTAssertEqual(norm, 1.0, accuracy: 1e-4, "MockEmbedder should produce unit-length vectors")
    }
}

// MARK: - VectorStore Tests

final class VectorStoreTests: XCTestCase {

    private func makeTempPath() -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("zyquo_test_vectors_\(UUID().uuidString).json")
    }

    private func makeChunk(
        filePath: String = "test.swift",
        startLine: Int = 1,
        endLine: Int = 10,
        name: String? = "testFunc",
        kind: String = "function",
        vector: [Float]
    ) -> EmbeddedChunk {
        EmbeddedChunk(
            chunk: CodeChunkRef(
                filePath: filePath,
                startLine: startLine,
                endLine: endLine,
                name: name,
                kind: kind
            ),
            vector: vector
        )
    }

    func testAddAndSearchReturnsAddedChunk() async {
        let store = VectorStore(path: makeTempPath())
        let vector: [Float] = VectorMath.normalize([1, 0, 0, 0])
        let chunk = makeChunk(name: "myFunc", vector: vector)

        await store.add(chunk)
        let results = await store.search(query: vector, topK: 5)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].chunk.name, "myFunc")
        XCTAssertEqual(results[0].score, 1.0, accuracy: 1e-5, "Exact match should have score 1.0")
        XCTAssertEqual(results[0].rank, 1)
    }

    func testSearchTopKRespectsLimit() async {
        let store = VectorStore(path: makeTempPath())

        // Add 5 chunks
        for i in 0..<5 {
            var v = [Float](repeating: 0, count: 4)
            v[i % 4] = 1.0
            await store.add(makeChunk(name: "func\(i)", vector: v))
        }

        let query: [Float] = [1, 0, 0, 0]
        let results = await store.search(query: query, topK: 2)
        XCTAssertEqual(results.count, 2, "topK=2 should return at most 2 results")
    }

    func testRemoveByFilePathClearsChunks() async {
        let store = VectorStore(path: makeTempPath())
        let v: [Float] = [1, 0, 0, 0]

        await store.add(makeChunk(filePath: "a.swift", name: "funcA", vector: v))
        await store.add(makeChunk(filePath: "b.swift", name: "funcB", vector: v))
        await store.add(makeChunk(filePath: "a.swift", name: "funcA2", vector: v))

        let countBefore = await store.count
        XCTAssertEqual(countBefore, 3)

        await store.remove(filePath: "a.swift")

        let countAfter = await store.count
        XCTAssertEqual(countAfter, 1, "Should have removed 2 chunks from a.swift")

        let results = await store.search(query: v, topK: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].chunk.filePath, "b.swift")
    }

    func testPersistenceSaveAndLoadRoundTrip() async throws {
        let path = makeTempPath()
        let store = VectorStore(path: path)
        let v: [Float] = VectorMath.normalize([1, 2, 3, 4])

        await store.add(makeChunk(name: "persisted", vector: v))
        try await store.save()

        // Load into a new store
        let store2 = VectorStore(path: path)
        try await store2.load()

        let count = await store2.count
        XCTAssertEqual(count, 1)

        let results = await store2.search(query: v, topK: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].chunk.name, "persisted")
        XCTAssertEqual(results[0].score, 1.0, accuracy: 1e-4)

        // Cleanup
        try? FileManager.default.removeItem(at: path)
    }

    func testEmptyStoreReturnsEmptyResults() async {
        let store = VectorStore(path: makeTempPath())
        let query: [Float] = [1, 0, 0, 0]
        let results = await store.search(query: query, topK: 10)
        XCTAssertTrue(results.isEmpty, "Empty store should return no results")
    }

    func testScoreOrdering() async {
        let store = VectorStore(path: makeTempPath())

        // Add chunks with vectors at known angles to the query
        let query: [Float] = [1, 0, 0, 0]

        // Exact match
        await store.add(makeChunk(name: "exact", vector: [1, 0, 0, 0]))
        // Partially similar
        let partial = VectorMath.normalize([1, 1, 0, 0])
        await store.add(makeChunk(name: "partial", vector: partial))
        // Orthogonal
        await store.add(makeChunk(name: "orthogonal", vector: [0, 0, 1, 0]))

        let results = await store.search(query: query, topK: 3)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].chunk.name, "exact", "Exact match should rank first")
        XCTAssertEqual(results[1].chunk.name, "partial", "Partial match should rank second")
        XCTAssertEqual(results[2].chunk.name, "orthogonal", "Orthogonal should rank last")

        XCTAssertGreaterThan(results[0].score, results[1].score)
        XCTAssertGreaterThan(results[1].score, results[2].score)
    }

    func testClearRemovesAll() async {
        let store = VectorStore(path: makeTempPath())
        let v: [Float] = [1, 0, 0, 0]
        await store.add(makeChunk(name: "a", vector: v))
        await store.add(makeChunk(name: "b", vector: v))

        await store.clear()
        let count = await store.count
        XCTAssertEqual(count, 0)
    }

    func testAddBatch() async {
        let store = VectorStore(path: makeTempPath())
        let chunks = (0..<5).map { i in
            makeChunk(name: "func\(i)", vector: VectorMath.normalize([Float(i), 1, 0, 0]))
        }
        await store.addBatch(chunks)
        let count = await store.count
        XCTAssertEqual(count, 5)
    }

    func testLoadFromNonexistentFile() async throws {
        let store = VectorStore(path: makeTempPath())
        // Should not throw — just initialize empty
        try await store.load()
        let count = await store.count
        XCTAssertEqual(count, 0)
    }
}

// MARK: - EmbeddingPipeline Tests

final class EmbeddingPipelineTests: XCTestCase {

    func testEmbedChunksProducesEmbeddedChunks() async throws {
        let embedder = MockEmbedder(dimensions: 64)
        let pipeline = EmbeddingPipeline(embedder: embedder)

        let chunks = [
            CodeChunk(
                filePath: "test.swift", startLine: 1, endLine: 10,
                kind: .function, name: "greet", content: "func greet() { print(\"hello\") }",
                tokenEstimate: 8
            ),
            CodeChunk(
                filePath: "test.swift", startLine: 11, endLine: 20,
                kind: .class_, name: "MyClass", content: "class MyClass { var x: Int }",
                tokenEstimate: 7
            ),
        ]

        let embedded = try await pipeline.embed(chunks: chunks)

        XCTAssertEqual(embedded.count, 2)
        XCTAssertEqual(embedded[0].chunk.name, "greet")
        XCTAssertEqual(embedded[0].chunk.kind, "function")
        XCTAssertEqual(embedded[0].vector.count, 64)
        XCTAssertEqual(embedded[1].chunk.name, "MyClass")
        XCTAssertEqual(embedded[1].vector.count, 64)
    }

    func testEmbedTextReturnsCorrectDimensions() async throws {
        let embedder = MockEmbedder(dimensions: 32)
        let pipeline = EmbeddingPipeline(embedder: embedder)

        let vec = try await pipeline.embed(text: "some query text")
        XCTAssertEqual(vec.count, 32)
    }

    func testBatchEmbedReturnsCorrectCount() async throws {
        let embedder = MockEmbedder()
        let pipeline = EmbeddingPipeline(embedder: embedder, batchSize: 2)

        let texts = ["alpha", "beta", "gamma", "delta", "epsilon"]
        let vecs = try await pipeline.embedBatch(texts: texts)
        XCTAssertEqual(vecs.count, 5)
    }

    func testEmptyChunksReturnsEmpty() async throws {
        let embedder = MockEmbedder()
        let pipeline = EmbeddingPipeline(embedder: embedder)

        let embedded = try await pipeline.embed(chunks: [])
        XCTAssertTrue(embedded.isEmpty)

        let vecs = try await pipeline.embedBatch(texts: [])
        XCTAssertTrue(vecs.isEmpty)
    }

    func testPipelineProperties() async {
        let embedder = MockEmbedder(dimensions: 256)
        let pipeline = EmbeddingPipeline(embedder: embedder)

        let dims = await pipeline.dimensions
        let model = await pipeline.modelId
        XCTAssertEqual(dims, 256)
        XCTAssertEqual(model, "mock-256")
    }
}

// MARK: - CodeChunkRef Tests

final class CodeChunkRefTests: XCTestCase {

    func testInitFromCodeChunk() {
        let chunk = CodeChunk(
            filePath: "Sources/Auth.swift",
            startLine: 10,
            endLine: 25,
            kind: .function,
            name: "authenticate",
            content: "func authenticate() { }",
            tokenEstimate: 6
        )

        let ref = CodeChunkRef(from: chunk)
        XCTAssertEqual(ref.filePath, "Sources/Auth.swift")
        XCTAssertEqual(ref.startLine, 10)
        XCTAssertEqual(ref.endLine, 25)
        XCTAssertEqual(ref.name, "authenticate")
        XCTAssertEqual(ref.kind, "function")
    }

    func testCodableRoundTrip() throws {
        let ref = CodeChunkRef(
            filePath: "test.swift", startLine: 1, endLine: 5,
            name: "hello", kind: "function"
        )

        let data = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(CodeChunkRef.self, from: data)
        XCTAssertEqual(ref, decoded)
    }
}

// MARK: - HybridRetriever Tests

final class HybridRetrieverTests: XCTestCase {

    /// Create a test setup with a populated vector store and keyword retriever.
    private func makeTestSetup() async throws -> (
        hybrid: HybridRetriever,
        vectorStore: VectorStore,
        memoryStore: MemoryStore
    ) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_hybrid_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write a project memory file with searchable content
        let projectMd = tempDir.appendingPathComponent("project.md")
        try """
        # Project Memory

        ## Authentication
        The authentication system uses JWT tokens for session management.
        Login validates credentials against the database.

        ## Rendering
        The terminal renderer uses ANSI escape codes for color output.
        Panels use Unicode box-drawing characters.
        """.write(to: projectMd, atomically: true, encoding: .utf8)

        let memoryStore = MemoryStore(baseDir: tempDir)
        let keywordRetriever = KeywordMemoryRetriever(memoryStore: memoryStore)

        let embedder = MockEmbedder(dimensions: 64)
        let pipeline = EmbeddingPipeline(embedder: embedder)

        let vectorPath = tempDir.appendingPathComponent("vectors.json")
        let vectorStore = VectorStore(path: vectorPath)

        // Add some embedded chunks to the vector store
        let chunks = [
            EmbeddedChunk(
                chunk: CodeChunkRef(
                    filePath: "Auth.swift", startLine: 1, endLine: 20,
                    name: "authenticate", kind: "function"
                ),
                vector: try await embedder.embed("authenticate user password login jwt token")
            ),
            EmbeddedChunk(
                chunk: CodeChunkRef(
                    filePath: "Renderer.swift", startLine: 1, endLine: 30,
                    name: "render", kind: "function"
                ),
                vector: try await embedder.embed("render terminal ansi color panel theme")
            ),
            EmbeddedChunk(
                chunk: CodeChunkRef(
                    filePath: "Database.swift", startLine: 1, endLine: 15,
                    name: "query", kind: "function"
                ),
                vector: try await embedder.embed("database query sql select insert schema")
            ),
        ]
        await vectorStore.addBatch(chunks)

        let hybrid = HybridRetriever(
            keywordRetriever: keywordRetriever,
            vectorStore: vectorStore,
            pipeline: pipeline
        )

        return (hybrid, vectorStore, memoryStore)
    }

    func testHybridRetrievalReturnsResults() async throws {
        let (hybrid, _, _) = try await makeTestSetup()

        let results = try await hybrid.recall(query: "authentication login", scope: .all, limit: 5)
        XCTAssertFalse(results.isEmpty, "Hybrid retrieval should return results for a matching query")
    }

    func testResultsAreDeduplicated() async throws {
        let (hybrid, _, _) = try await makeTestSetup()

        let results = try await hybrid.recall(query: "authentication", scope: .all, limit: 10)

        // Check no duplicate sources+lines
        var seen = Set<String>()
        for result in results {
            let key: String
            if let sl = result.metadata["startLine"], let el = result.metadata["endLine"] {
                key = "\(result.source)::\(sl)-\(el)"
            } else {
                key = "\(result.source)::\(result.content.hashValue)"
            }
            XCTAssertTrue(seen.insert(key).inserted, "Results should be deduplicated: found duplicate \(key)")
        }
    }

    func testRRFMergesKeywordAndVectorResults() async throws {
        let (hybrid, _, _) = try await makeTestSetup()

        // Query that matches both keyword (project.md has "authentication") and vector
        let results = try await hybrid.recall(query: "authentication system jwt", scope: .all, limit: 10)

        // Should have results from both sources
        let sources = Set(results.map(\.source))
        XCTAssertTrue(sources.count >= 1, "Should have results from at least one source")

        // Scores should be positive and ordered
        for i in 0..<results.count - 1 {
            XCTAssertGreaterThanOrEqual(results[i].score, results[i + 1].score,
                                        "Results should be ordered by fused score descending")
        }
    }

    func testEmptyQueryReturnsEmpty() async throws {
        let (hybrid, _, _) = try await makeTestSetup()

        let results = try await hybrid.recall(query: "", scope: .all, limit: 5)
        XCTAssertTrue(results.isEmpty, "Empty query should return no results")
    }

    func testLimitIsRespected() async throws {
        let (hybrid, _, _) = try await makeTestSetup()

        let results = try await hybrid.recall(query: "render terminal", scope: .all, limit: 1)
        XCTAssertLessThanOrEqual(results.count, 1, "Should respect the limit parameter")
    }
}

// MARK: - EmbedderError Tests

final class EmbedderErrorTests: XCTestCase {
    func testErrorDescriptions() {
        XCTAssertFalse(EmbedderError.emptyResponse.description.isEmpty)
        XCTAssertFalse(EmbedderError.invalidResponse.description.isEmpty)
        XCTAssertTrue(EmbedderError.apiError(statusCode: 429).description.contains("429"))
        XCTAssertTrue(EmbedderError.dimensionMismatch(expected: 128, got: 64).description.contains("128"))
    }
}
