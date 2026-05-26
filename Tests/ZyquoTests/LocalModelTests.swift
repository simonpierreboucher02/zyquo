import XCTest
@testable import Zyquo

final class LocalModelTests: XCTestCase {

    // MARK: - MockLocalEngine Tests

    func testMockLocalEngineIsAvailable() {
        let engine = MockLocalEngine()
        XCTAssertTrue(engine.isAvailable)
    }

    func testMockLocalEngineUnavailable() {
        let engine = MockLocalEngine(isAvailable: false)
        XCTAssertFalse(engine.isAvailable)
    }

    func testMockLocalEngineModelId() {
        let engine = MockLocalEngine(modelId: "test-model-3b")
        XCTAssertEqual(engine.modelId, "test-model-3b")
    }

    func testMockLocalEngineContextWindow() {
        let engine = MockLocalEngine(contextWindow: 8192)
        XCTAssertEqual(engine.contextWindow, 8192)
    }

    func testMockLocalEngineGeneratesStreamingOutput() async throws {
        let engine = MockLocalEngine()
        var output = ""
        let stream = engine.generate(prompt: "Hello world", maxTokens: 100, temperature: 0.7)

        for try await chunk in stream {
            output += chunk
        }

        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains("Local model response"), "Output should contain response marker")
        XCTAssertTrue(output.contains("mock-local-7b-q4"), "Output should reference the model ID")
    }

    func testMockLocalEngineRespectsMaxTokens() async throws {
        let engine = MockLocalEngine()
        // With maxTokens = 2, only about 1-2 words should be emitted (0.75 words per token)
        var chunks: [String] = []
        let stream = engine.generate(prompt: "Hello", maxTokens: 2, temperature: 0.7)

        for try await chunk in stream {
            chunks.append(chunk)
        }

        // max 2 tokens ~= 1 word, so output should be very short
        XCTAssertTrue(chunks.count <= 2, "Should respect maxTokens limit, got \(chunks.count) chunks")
    }

    func testMockLocalEngineTokenCounting() {
        let engine = MockLocalEngine()
        // ~4 characters per token
        let count = engine.tokenCount(for: "Hello world, this is a test")
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(count, 27 / 4) // 6 tokens for 27 chars
    }

    func testMockLocalEngineTokenCountMinimumOne() {
        let engine = MockLocalEngine()
        let count = engine.tokenCount(for: "Hi")
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testMockLocalEngineTokenCountEmpty() {
        let engine = MockLocalEngine()
        let count = engine.tokenCount(for: "")
        XCTAssertGreaterThanOrEqual(count, 1, "Minimum token count should be 1")
    }

    // MARK: - LocalProvider Tests

    func testLocalProviderConformsToLLMProvider() {
        let provider: any LLMProvider = LocalProvider()
        XCTAssertEqual(provider.id, "local")
        XCTAssertEqual(provider.displayName, "Local")
    }

    func testLocalProviderSupportedModelsInitiallyEmpty() {
        let provider = LocalProvider()
        XCTAssertTrue(provider.supportedModels.isEmpty)
    }

    func testLocalProviderRegisterEngine() {
        let provider = LocalProvider()
        let engine = MockLocalEngine(modelId: "test-model")
        let descriptor = ModelDescriptor(
            id: "test-model",
            displayName: "Test Model",
            contextWindow: 4096,
            maxOutputTokens: 2048,
            inputPricePerMToken: 0.0,
            outputPricePerMToken: 0.0,
            supportsTools: false,
            supportsStreaming: true
        )

        provider.registerEngine(engine, descriptor: descriptor)

        XCTAssertEqual(provider.supportedModels.count, 1)
        XCTAssertEqual(provider.supportedModels.first?.id, "test-model")
        XCTAssertTrue(provider.hasEngine(for: "test-model"))
    }

    func testLocalProviderRemoveEngine() {
        let provider = LocalProvider()
        let engine = MockLocalEngine(modelId: "test-model")
        let descriptor = ModelDescriptor(
            id: "test-model",
            displayName: "Test",
            contextWindow: 4096,
            maxOutputTokens: 2048,
            inputPricePerMToken: 0.0,
            outputPricePerMToken: 0.0
        )

        provider.registerEngine(engine, descriptor: descriptor)
        XCTAssertTrue(provider.hasEngine(for: "test-model"))

        provider.removeEngine(modelId: "test-model")
        XCTAssertFalse(provider.hasEngine(for: "test-model"))
        XCTAssertTrue(provider.supportedModels.isEmpty)
    }

    func testLocalProviderRegisteredModelIds() {
        let provider = LocalProvider()
        let engine1 = MockLocalEngine(modelId: "model-a")
        let engine2 = MockLocalEngine(modelId: "model-b")

        let desc = ModelDescriptor(
            id: "model-a", displayName: "A", contextWindow: 4096,
            maxOutputTokens: 2048, inputPricePerMToken: 0, outputPricePerMToken: 0
        )
        let desc2 = ModelDescriptor(
            id: "model-b", displayName: "B", contextWindow: 4096,
            maxOutputTokens: 2048, inputPricePerMToken: 0, outputPricePerMToken: 0
        )

        provider.registerEngine(engine1, descriptor: desc)
        provider.registerEngine(engine2, descriptor: desc2)

        let ids = provider.registeredModelIds().sorted()
        XCTAssertEqual(ids, ["model-a", "model-b"])
    }

    func testLocalProviderStreamingWithMockEngine() async throws {
        let provider = LocalProvider()
        let engine = MockLocalEngine(modelId: "test-model")
        let descriptor = ModelDescriptor(
            id: "test-model",
            displayName: "Test",
            contextWindow: 4096,
            maxOutputTokens: 2048,
            inputPricePerMToken: 0.0,
            outputPricePerMToken: 0.0
        )
        provider.registerEngine(engine, descriptor: descriptor)

        let request = LLMRequest(
            model: "test-model",
            messages: [.user("What is 2+2?")],
            maxTokens: 100
        )

        var events: [LLMEvent] = []
        let stream = provider.send(request: request, cancellation: nil)

        for try await event in stream {
            events.append(event)
        }

        // Should have messageStart, textDelta(s), usage, messageStop
        XCTAssertFalse(events.isEmpty)

        let hasMessageStart = events.contains { if case .messageStart = $0 { return true }; return false }
        let hasTextDelta = events.contains { if case .textDelta = $0 { return true }; return false }
        let hasUsage = events.contains { if case .usage = $0 { return true }; return false }
        let hasMessageStop = events.contains { if case .messageStop = $0 { return true }; return false }

        XCTAssertTrue(hasMessageStart, "Should emit messageStart")
        XCTAssertTrue(hasTextDelta, "Should emit textDelta events")
        XCTAssertTrue(hasUsage, "Should emit usage event")
        XCTAssertTrue(hasMessageStop, "Should emit messageStop")
    }

    func testLocalProviderFailsForUnknownModel() async {
        let provider = LocalProvider()
        let request = LLMRequest(
            model: "nonexistent-model",
            messages: [.user("Hello")]
        )

        let stream = provider.send(request: request, cancellation: nil)
        do {
            for try await _ in stream {
                XCTFail("Should not produce events for unknown model")
            }
            XCTFail("Should have thrown an error")
        } catch {
            // Expected
            XCTAssertTrue(String(describing: error).contains("not loaded"))
        }
    }

    func testLocalProviderFailsForUnavailableEngine() async {
        let provider = LocalProvider()
        let engine = MockLocalEngine(modelId: "offline-model", isAvailable: false)
        let descriptor = ModelDescriptor(
            id: "offline-model", displayName: "Offline",
            contextWindow: 4096, maxOutputTokens: 2048,
            inputPricePerMToken: 0, outputPricePerMToken: 0
        )
        provider.registerEngine(engine, descriptor: descriptor)

        let request = LLMRequest(model: "offline-model", messages: [.user("Hello")])
        let stream = provider.send(request: request, cancellation: nil)

        do {
            for try await _ in stream {
                XCTFail("Should not produce events for unavailable model")
            }
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertTrue(String(describing: error).contains("not available"))
        }
    }

    // MARK: - ModelManager Tests

    func testModelManagerRegisterAndList() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a fake model file
        let modelFile = tempDir.appendingPathComponent("test-model.gguf")
        try Data("fake model data".utf8).write(to: modelFile)

        let manager = ModelManager(modelsDirectory: tempDir)
        try await manager.register(
            id: "test-model",
            path: modelFile,
            metadata: LocalModelMetadata(
                family: "llama",
                parameterCount: "3B",
                quantization: "Q4_K_M",
                contextWindow: 4096
            )
        )

        let models = await manager.listLocal()
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.id, "test-model")
        XCTAssertEqual(models.first?.family, "llama")
        XCTAssertEqual(models.first?.parameterCount, "3B")
        XCTAssertTrue(models.first?.downloaded ?? false)
    }

    func testModelManagerIsDownloaded() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelFile = tempDir.appendingPathComponent("model.gguf")
        try Data("data".utf8).write(to: modelFile)

        let manager = ModelManager(modelsDirectory: tempDir)
        try await manager.register(
            id: "my-model",
            path: modelFile,
            metadata: LocalModelMetadata(family: "phi", parameterCount: "3.8B", quantization: "Q4_0", contextWindow: 4096)
        )

        let isDownloaded = await manager.isDownloaded(id: "my-model")
        XCTAssertTrue(isDownloaded)

        let isNotDownloaded = await manager.isDownloaded(id: "nonexistent")
        XCTAssertFalse(isNotDownloaded)
    }

    func testModelManagerRemove() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelFile = tempDir.appendingPathComponent("model.gguf")
        try Data("data".utf8).write(to: modelFile)

        let manager = ModelManager(modelsDirectory: tempDir)
        try await manager.register(
            id: "removable",
            path: modelFile,
            metadata: LocalModelMetadata(family: "gemma", parameterCount: "2B", quantization: "Q4_K_M", contextWindow: 8192)
        )

        let removedExisting = try await manager.remove(id: "removable")
        XCTAssertTrue(removedExisting)

        let removedAgain = try await manager.remove(id: "removable")
        XCTAssertFalse(removedAgain)

        let models = await manager.listLocal()
        XCTAssertTrue(models.isEmpty)
    }

    func testModelManagerModelPathResolution() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let modelFile = tempDir.appendingPathComponent("model.gguf")
        try Data("data".utf8).write(to: modelFile)

        let manager = ModelManager(modelsDirectory: tempDir)
        try await manager.register(
            id: "pathed",
            path: modelFile,
            metadata: LocalModelMetadata(family: "llama", parameterCount: "7B", quantization: "Q4_K_M", contextWindow: 4096)
        )

        let path = await manager.modelPath(id: "pathed")
        XCTAssertNotNil(path)
        XCTAssertEqual(path?.lastPathComponent, "model.gguf")

        let noPath = await manager.modelPath(id: "nonexistent")
        XCTAssertNil(noPath)
    }

    func testModelManagerDirectoryCreation() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("models")
        defer { try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent().deletingLastPathComponent()) }

        let manager = ModelManager(modelsDirectory: tempDir)
        try await manager.ensureDirectory()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
    }

    func testModelManagerRegisterFailsForMissingFile() async {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ModelManager(modelsDirectory: tempDir)
        let fakePath = tempDir.appendingPathComponent("nonexistent.gguf")

        do {
            try await manager.register(
                id: "missing",
                path: fakePath,
                metadata: LocalModelMetadata(family: "llama", parameterCount: "7B", quantization: "Q4_K_M", contextWindow: 4096)
            )
            XCTFail("Should throw for missing file")
        } catch {
            XCTAssertTrue(String(describing: error).contains("not found"))
        }
    }

    // MARK: - LocalModelInfo Codable Tests

    func testLocalModelInfoEncodeDecode() throws {
        let model = LocalModelInfo(
            id: "test-model",
            name: "Test Model",
            family: "llama",
            parameterCount: "7B",
            quantization: "Q4_K_M",
            sizeBytes: 4_000_000_000,
            contextWindow: 8192,
            downloaded: true,
            path: URL(fileURLWithPath: "/tmp/model.gguf")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(model)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LocalModelInfo.self, from: data)

        XCTAssertEqual(decoded.id, model.id)
        XCTAssertEqual(decoded.name, model.name)
        XCTAssertEqual(decoded.family, model.family)
        XCTAssertEqual(decoded.parameterCount, model.parameterCount)
        XCTAssertEqual(decoded.quantization, model.quantization)
        XCTAssertEqual(decoded.sizeBytes, model.sizeBytes)
        XCTAssertEqual(decoded.contextWindow, model.contextWindow)
        XCTAssertEqual(decoded.downloaded, model.downloaded)
    }

    func testLocalModelInfoFormattedSize() {
        let gbModel = LocalModelInfo(
            id: "a", name: "A", family: "llama", parameterCount: "7B",
            quantization: "Q4", sizeBytes: 4_370_000_000, contextWindow: 4096,
            downloaded: true, path: nil
        )
        XCTAssertEqual(gbModel.formattedSize, "4.1 GB")

        let mbModel = LocalModelInfo(
            id: "b", name: "B", family: "phi", parameterCount: "3B",
            quantization: "Q4", sizeBytes: 500_000_000, contextWindow: 4096,
            downloaded: true, path: nil
        )
        XCTAssertEqual(mbModel.formattedSize, "477 MB")

        let zeroModel = LocalModelInfo(
            id: "c", name: "C", family: "gemma", parameterCount: "2B",
            quantization: "Q4", sizeBytes: 0, contextWindow: 4096,
            downloaded: false, path: nil
        )
        XCTAssertEqual(zeroModel.formattedSize, "--")
    }

    // MARK: - LocalModelMetadata Codable Tests

    func testLocalModelMetadataEncodeDecode() throws {
        let metadata = LocalModelMetadata(
            family: "mistral",
            parameterCount: "7B",
            quantization: "Q5_K_S",
            contextWindow: 8192,
            addedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LocalModelMetadata.self, from: data)

        XCTAssertEqual(decoded.family, metadata.family)
        XCTAssertEqual(decoded.parameterCount, metadata.parameterCount)
        XCTAssertEqual(decoded.quantization, metadata.quantization)
        XCTAssertEqual(decoded.contextWindow, metadata.contextWindow)
    }

    // MARK: - HybridRouter Tests

    func testHybridRouterPrefersLocalForSummarization() async {
        let router = HybridRouter()
        let localModel = LocalModelInfo(
            id: "test-model", name: "Test", family: "llama", parameterCount: "3B",
            quantization: "Q4_K_M", sizeBytes: 2_000_000_000, contextWindow: 8192,
            downloaded: true, path: URL(fileURLWithPath: "/tmp/model.gguf")
        )

        let decision = await router.shouldUseLocal(
            taskClass: .summarization,
            estimatedTokens: 2000,
            localModel: localModel
        )

        if case .useLocal(let reason) = decision {
            XCTAssertTrue(reason.contains("Summarization"), "Reason should mention summarization")
        } else {
            XCTFail("Should prefer local for small summarization tasks, got \(decision)")
        }
    }

    func testHybridRouterPrefersCloudForPlanning() async {
        let router = HybridRouter()
        let localModel = LocalModelInfo(
            id: "test-model", name: "Test", family: "llama", parameterCount: "3B",
            quantization: "Q4_K_M", sizeBytes: 2_000_000_000, contextWindow: 8192,
            downloaded: true, path: URL(fileURLWithPath: "/tmp/model.gguf")
        )

        let decision = await router.shouldUseLocal(
            taskClass: .planning,
            estimatedTokens: 2000,
            localModel: localModel
        )

        if case .useCloud(let reason) = decision {
            XCTAssertTrue(reason.contains("Planning") || reason.contains("cloud"), "Reason should explain cloud preference")
        } else {
            XCTFail("Should prefer cloud for planning tasks, got \(decision)")
        }
    }

    func testHybridRouterPrefersCloudForCoding() async {
        let router = HybridRouter()
        let localModel = LocalModelInfo(
            id: "test-model", name: "Test", family: "llama", parameterCount: "3B",
            quantization: "Q4_K_M", sizeBytes: 2_000_000_000, contextWindow: 8192,
            downloaded: true, path: URL(fileURLWithPath: "/tmp/model.gguf")
        )

        let decision = await router.shouldUseLocal(
            taskClass: .coding,
            estimatedTokens: 2000,
            localModel: localModel
        )

        if case .useCloud = decision {
            // Expected
        } else {
            XCTFail("Should prefer cloud for coding tasks, got \(decision)")
        }
    }

    func testHybridRouterReturnsUnavailableWhenNoLocalModel() async {
        let router = HybridRouter()

        let decision = await router.shouldUseLocal(
            taskClass: .summarization,
            estimatedTokens: 100,
            localModel: nil
        )

        XCTAssertEqual(decision, .localUnavailable)
    }

    func testHybridRouterReturnsUnavailableWhenNotDownloaded() async {
        let router = HybridRouter()
        let localModel = LocalModelInfo(
            id: "test-model", name: "Test", family: "llama", parameterCount: "3B",
            quantization: "Q4_K_M", sizeBytes: 0, contextWindow: 8192,
            downloaded: false, path: nil
        )

        let decision = await router.shouldUseLocal(
            taskClass: .summarization,
            estimatedTokens: 100,
            localModel: localModel
        )

        XCTAssertEqual(decision, .localUnavailable)
    }

    func testHybridRouterRespectsUserForceLocal() async {
        let router = HybridRouter()
        await router.setForceLocal(true)

        let localModel = LocalModelInfo(
            id: "test-model", name: "Test", family: "llama", parameterCount: "3B",
            quantization: "Q4_K_M", sizeBytes: 2_000_000_000, contextWindow: 8192,
            downloaded: true, path: URL(fileURLWithPath: "/tmp/model.gguf")
        )

        // Even for planning (normally cloud), force local
        let decision = await router.shouldUseLocal(
            taskClass: .planning,
            estimatedTokens: 2000,
            localModel: localModel
        )

        if case .useLocal(let reason) = decision {
            XCTAssertTrue(reason.contains("forced"), "Reason should indicate user override")
        } else {
            XCTFail("Should use local when forced, got \(decision)")
        }
    }

    func testHybridRouterForceLocalWithoutModel() async {
        let router = HybridRouter()
        await router.setForceLocal(true)

        let decision = await router.shouldUseLocal(
            taskClass: .summarization,
            estimatedTokens: 100,
            localModel: nil
        )

        XCTAssertEqual(decision, .localUnavailable)
    }

    func testHybridRouterForceCloud() async {
        let router = HybridRouter()
        await router.setForceCloud(true)

        let localModel = LocalModelInfo(
            id: "test-model", name: "Test", family: "llama", parameterCount: "3B",
            quantization: "Q4_K_M", sizeBytes: 2_000_000_000, contextWindow: 8192,
            downloaded: true, path: URL(fileURLWithPath: "/tmp/model.gguf")
        )

        let decision = await router.shouldUseLocal(
            taskClass: .summarization,
            estimatedTokens: 100,
            localModel: localModel
        )

        if case .useCloud(let reason) = decision {
            XCTAssertTrue(reason.contains("forced"), "Reason should indicate forced cloud")
        } else {
            XCTFail("Should use cloud when forced, got \(decision)")
        }
    }

    func testHybridRouterPrefersCloudWhenTokensExceedContextWindow() async {
        let router = HybridRouter()
        let localModel = LocalModelInfo(
            id: "test-model", name: "Test", family: "llama", parameterCount: "3B",
            quantization: "Q4_K_M", sizeBytes: 2_000_000_000, contextWindow: 4096,
            downloaded: true, path: URL(fileURLWithPath: "/tmp/model.gguf")
        )

        let decision = await router.shouldUseLocal(
            taskClass: .summarization,
            estimatedTokens: 5000, // Exceeds 4096 context window
            localModel: localModel
        )

        if case .useCloud(let reason) = decision {
            XCTAssertTrue(reason.contains("exceeds"), "Reason should mention exceeding context window")
        } else {
            XCTFail("Should use cloud when tokens exceed context window, got \(decision)")
        }
    }

    func testHybridRouterPrefersLocalForVerification() async {
        let router = HybridRouter()
        let localModel = LocalModelInfo(
            id: "test-model", name: "Test", family: "llama", parameterCount: "3B",
            quantization: "Q4_K_M", sizeBytes: 2_000_000_000, contextWindow: 8192,
            downloaded: true, path: URL(fileURLWithPath: "/tmp/model.gguf")
        )

        let decision = await router.shouldUseLocal(
            taskClass: .verification,
            estimatedTokens: 1000,
            localModel: localModel
        )

        if case .useLocal(let reason) = decision {
            XCTAssertTrue(reason.contains("Verification"), "Reason should mention verification")
        } else {
            XCTFail("Should prefer local for small verification tasks, got \(decision)")
        }
    }

    // MARK: - ModelCatalog Local Models Tests

    func testKnownLocalModelsCatalog() {
        let models = ModelCatalog.knownLocalModels
        XCTAssertFalse(models.isEmpty, "Should have known local models")
        XCTAssertTrue(models.count >= 4, "Should have at least 4 known local models")

        // Check that each model has valid properties
        for model in models {
            XCTAssertFalse(model.id.isEmpty, "Model ID should not be empty")
            XCTAssertFalse(model.name.isEmpty, "Model name should not be empty")
            XCTAssertFalse(model.family.isEmpty, "Model family should not be empty")
            XCTAssertFalse(model.parameterCount.isEmpty, "Parameter count should not be empty")
            XCTAssertFalse(model.quantization.isEmpty, "Quantization should not be empty")
            XCTAssertGreaterThan(model.contextWindow, 0, "Context window should be positive")
            XCTAssertFalse(model.downloaded, "Catalog models should not be marked as downloaded")
        }
    }

    func testKnownLocalModelFamilies() {
        let families = Set(ModelCatalog.knownLocalModels.map(\.family))
        XCTAssertTrue(families.contains("llama"), "Should include llama family")
        XCTAssertTrue(families.contains("phi"), "Should include phi family")
        XCTAssertTrue(families.contains("gemma"), "Should include gemma family")
        XCTAssertTrue(families.contains("mistral"), "Should include mistral family")
    }

    func testLocalModelDescriptorsHaveZeroCost() {
        for descriptor in ModelCatalog.localModelDescriptors {
            XCTAssertEqual(descriptor.inputPricePerMToken, 0.0, "Local models should have zero input cost")
            XCTAssertEqual(descriptor.outputPricePerMToken, 0.0, "Local models should have zero output cost")
        }
    }

    func testModelCatalogFindLocalModel() {
        let found = ModelCatalog.find(id: "llama-3.2-3b-instruct-q4_k_m")
        XCTAssertNotNil(found, "Should find local model by ID")
        XCTAssertEqual(found?.displayName, "Llama 3.2 3B")
    }

    // MARK: - ModelRouter Local Provider Tests

    func testModelRouterRegisterLocal() async {
        let config = ProvidersConfig(
            flags: CommandFlags(),
            env: [:],
            workspace: [:],
            user: [:]
        )
        let router = ModelRouter(config: config)
        let provider = LocalProvider()
        let engine = MockLocalEngine(modelId: "test-local")
        let descriptor = ModelDescriptor(
            id: "test-local", displayName: "Test Local", contextWindow: 4096,
            maxOutputTokens: 2048, inputPricePerMToken: 0, outputPricePerMToken: 0
        )
        provider.registerEngine(engine, descriptor: descriptor)

        await router.registerLocal(provider)

        let providers = await router.availableProviders()
        XCTAssertTrue(providers.contains("local"))
        let hasLocal = await router.hasLocalProvider()
        XCTAssertTrue(hasLocal)
    }

    func testModelRouterResolveLocal() async {
        let config = ProvidersConfig(
            flags: CommandFlags(),
            env: [:],
            workspace: [:],
            user: [:]
        )
        let router = ModelRouter(config: config)
        let provider = LocalProvider()
        let engine = MockLocalEngine(modelId: "test-local")
        let descriptor = ModelDescriptor(
            id: "test-local", displayName: "Test Local", contextWindow: 4096,
            maxOutputTokens: 2048, inputPricePerMToken: 0, outputPricePerMToken: 0
        )
        provider.registerEngine(engine, descriptor: descriptor)
        await router.registerLocal(provider)

        let result = await router.resolveLocal(modelId: "test-local")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.provider.id, "local")
        XCTAssertEqual(result?.model, "test-local")
    }

    func testModelRouterResolveLocalNonexistent() async {
        let config = ProvidersConfig(
            flags: CommandFlags(),
            env: [:],
            workspace: [:],
            user: [:]
        )
        let router = ModelRouter(config: config)
        let provider = LocalProvider()
        await router.registerLocal(provider)

        let result = await router.resolveLocal(modelId: "nonexistent")
        XCTAssertNil(result)
    }

    func testModelRouterLocalOverridePrefix() async {
        let config = ProvidersConfig(
            flags: CommandFlags(model: "local:test-local"),
            env: [:],
            workspace: [:],
            user: [:]
        )
        let router = ModelRouter(config: config)

        // Register cloud provider
        let cloudProvider = MockRouterProvider(id: "anthropic", name: "Anthropic")
        await router.register(cloudProvider)

        // Register local provider with engine
        let localProvider = LocalProvider()
        let engine = MockLocalEngine(modelId: "test-local")
        let descriptor = ModelDescriptor(
            id: "test-local", displayName: "Test Local", contextWindow: 4096,
            maxOutputTokens: 2048, inputPricePerMToken: 0, outputPricePerMToken: 0
        )
        localProvider.registerEngine(engine, descriptor: descriptor)
        await router.registerLocal(localProvider)

        let result = await router.resolve(for: .planning)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.provider.id, "local")
        XCTAssertEqual(result?.model, "test-local")
    }

    // MARK: - Filename Parsing Tests

    func testParseGGUFFilename() {
        let result = ModelManager.parseFilename("llama-3.2-3b-instruct-q4_k_m.gguf")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.metadata.family, "llama")
        XCTAssertEqual(result?.metadata.parameterCount, "3B")
    }

    func testParseGGUFFilenameMistral() {
        let result = ModelManager.parseFilename("mistral-7b-instruct-v0.3-q5_k_s.gguf")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.metadata.family, "mistral")
        XCTAssertEqual(result?.metadata.parameterCount, "7B")
    }

    func testParseGGUFFilenamePhi() {
        let result = ModelManager.parseFilename("phi-3-mini-4k-instruct-q4_0.gguf")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.metadata.family, "phi")
        XCTAssertEqual(result?.metadata.contextWindow, 4096)
    }

    func testRoutingDecisionEquatable() {
        XCTAssertEqual(RoutingDecision.localUnavailable, RoutingDecision.localUnavailable)
        XCTAssertEqual(
            RoutingDecision.useLocal(reason: "test"),
            RoutingDecision.useLocal(reason: "test")
        )
        XCTAssertEqual(
            RoutingDecision.useCloud(reason: "test"),
            RoutingDecision.useCloud(reason: "test")
        )
        XCTAssertNotEqual(
            RoutingDecision.useLocal(reason: "a"),
            RoutingDecision.useCloud(reason: "a")
        )
    }
}

// MARK: - Test Helpers

private final class MockRouterProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let supportedModels: [ModelDescriptor] = ModelCatalog.allModels

    init(id: String, name: String) {
        self.id = id
        self.displayName = name
    }

    func send(
        request: LLMRequest,
        cancellation: Task<Void, Never>?
    ) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.messageStart(MessageMeta(id: "mock-1", model: request.model)))
            continuation.yield(.textDelta("Mock response"))
            continuation.yield(.messageStop(.endTurn))
            continuation.finish()
        }
    }
}
