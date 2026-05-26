import XCTest
@testable import Zyquo

final class ModelRouterTests: XCTestCase {

    private func makeRouter(
        provider: String = "anthropic",
        model: String? = nil
    ) async -> ModelRouter {
        let config = ProvidersConfig(
            flags: CommandFlags(model: model, provider: provider),
            env: [:],
            workspace: [:],
            user: [:]
        )
        let router = ModelRouter(config: config)
        await router.register(MockProvider(id: "anthropic", name: "Anthropic"))
        await router.register(MockProvider(id: "openrouter", name: "OpenRouter"))
        return router
    }

    func testDefaultRoutingPlanning() async {
        let router = await makeRouter()
        let result = await router.resolve(for: .planning)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.model, ModelCatalog.claudeOpus4_7.id)
        XCTAssertEqual(result?.provider.id, "anthropic")
    }

    func testDefaultRoutingCoding() async {
        let router = await makeRouter()
        let result = await router.resolve(for: .coding)
        XCTAssertEqual(result?.model, ModelCatalog.claudeSonnet4_6.id)
    }

    func testDefaultRoutingSummarization() async {
        let router = await makeRouter()
        let result = await router.resolve(for: .summarization)
        XCTAssertEqual(result?.model, ModelCatalog.claudeHaiku4_5.id)
    }

    func testDefaultRoutingVerification() async {
        let router = await makeRouter()
        let result = await router.resolve(for: .verification)
        XCTAssertEqual(result?.model, ModelCatalog.claudeSonnet4_6.id)
    }

    func testModelOverrideTakesPrecedence() async {
        let router = await makeRouter(model: "claude-opus-4-7")
        let result = await router.resolve(for: .summarization)
        XCTAssertEqual(result?.model, ModelCatalog.claudeOpus4_7.id)
    }

    func testProviderOverride() async {
        let router = await makeRouter(provider: "openrouter")
        let result = await router.resolve(for: .coding)
        XCTAssertEqual(result?.provider.id, "openrouter")
    }

    func testUnknownProviderReturnsNil() async {
        let router = await makeRouter(provider: "nonexistent")
        let result = await router.resolve(for: .coding)
        XCTAssertNil(result)
    }

    func testResolveExplicit() async {
        let router = await makeRouter()
        let result = await router.resolveExplicit(providerId: "openrouter", modelId: "sonnet")
        XCTAssertEqual(result?.provider.id, "openrouter")
        XCTAssertEqual(result?.model, ModelCatalog.claudeSonnet4_6.id)
    }

    func testResolveExplicitUnknownModel() async {
        let router = await makeRouter()
        let result = await router.resolveExplicit(providerId: "anthropic", modelId: "my-custom-model")
        XCTAssertEqual(result?.model, "my-custom-model")
    }

    func testAvailableProviders() async {
        let router = await makeRouter()
        let providers = await router.availableProviders()
        XCTAssertTrue(providers.contains("anthropic"))
        XCTAssertTrue(providers.contains("openrouter"))
    }

    func testModelCatalogFindByAlias() {
        XCTAssertEqual(ModelCatalog.findByAlias("opus")?.id, ModelCatalog.claudeOpus4_7.id)
        XCTAssertEqual(ModelCatalog.findByAlias("sonnet")?.id, ModelCatalog.claudeSonnet4_6.id)
        XCTAssertEqual(ModelCatalog.findByAlias("haiku")?.id, ModelCatalog.claudeHaiku4_5.id)
        XCTAssertEqual(ModelCatalog.findByAlias("claude-sonnet-4-6")?.id, ModelCatalog.claudeSonnet4_6.id)
    }

    func testModelCatalogFindByExactId() {
        let model = ModelCatalog.find(id: "claude-sonnet-4-6-20250514")
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.displayName, "Claude Sonnet 4.6")
    }

    func testModelCatalogFindUnknown() {
        XCTAssertNil(ModelCatalog.find(id: "totally-unknown-model-xyz"))
    }
}

// MARK: - Mock Provider

private final class MockProvider: LLMProvider, @unchecked Sendable {
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
