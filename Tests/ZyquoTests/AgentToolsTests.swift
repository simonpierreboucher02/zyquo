import XCTest
@testable import Zyquo

/// Verifies that the agent's plan-execute loop can advertise and execute
/// registry-backed tools (ZTP bridges, file.write/patch, git.*) — i.e. that the
/// closed wiring done for "version B" actually reaches the Executor.
final class AgentToolsTests: XCTestCase {

    private func makeContext(workspaceRoot: URL, registry: ToolRegistry) -> ExecutionContext {
        let config = Config(flags: .init())
        return ExecutionContext(
            workspace: Workspace(root: workspaceRoot),
            shellExecutor: ShellExecutor(config: config.shell),
            riskClassifier: RiskClassifier(workspaceRoot: workspaceRoot),
            approvalGate: ApprovalGate(autoApproveSafe: true),
            trustStore: TrustStore(workspaceRoot: workspaceRoot),
            config: config.agent,
            toolRegistry: registry
        )
    }

    // MARK: - Registry execution path

    func testExecutorRunsRegistryFileWriteTool() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-agenttool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let registry = ToolRegistry()
        registry.register(FileWriteTool())
        let ctx = makeContext(workspaceRoot: dir, registry: registry)

        let call = ToolCall(
            toolName: "file.write",
            input: ["path": .string("hello.txt"), "content": .string("hi from agent")],
            id: "t1"
        )
        let result = try await Executor().execute(toolCall: call, context: ctx)

        XCTAssertFalse(result.observation.isError, "file.write should succeed via the registry path")
        let written = dir.appendingPathComponent("hello.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
        XCTAssertEqual(try String(contentsOf: written, encoding: .utf8), "hi from agent")
    }

    func testExecutorRejectsPathOutsideWorkspace() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-agenttool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let registry = ToolRegistry()
        registry.register(FileWriteTool())
        let ctx = makeContext(workspaceRoot: dir, registry: registry)

        let call = ToolCall(
            toolName: "file.write",
            input: ["path": .string("/etc/zyquo-should-not-write"), "content": .string("x")],
            id: "t2"
        )
        let result = try await Executor().execute(toolCall: call, context: ctx)
        XCTAssertTrue(result.observation.isError, "Writing outside the workspace must fail")
    }

    func testExecutorUnknownToolStillErrors() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-agenttool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ctx = makeContext(workspaceRoot: dir, registry: ToolRegistry())
        let call = ToolCall(toolName: "does.not.exist", input: [:], id: "t3")
        let result = try await Executor().execute(toolCall: call, context: ctx)
        XCTAssertTrue(result.observation.isError)
        XCTAssertTrue(result.observation.summary.contains("Unknown tool"))
    }

    // MARK: - Schema conversion

    func testToolInputSchemaConvertsToJSONValueSchema() {
        let schema = FileWriteTool().inputSchema.toJSONValueSchema()
        XCTAssertEqual(schema["type"]?.stringValue, "object")
        guard case .array(let required)? = schema["required"] else {
            return XCTFail("required should be an array")
        }
        let names = required.compactMap { $0.stringValue }
        XCTAssertTrue(names.contains("path"))
        XCTAssertTrue(names.contains("content"))
        guard case .object(let props)? = schema["properties"] else {
            return XCTFail("properties should be an object")
        }
        XCTAssertNotNil(props["path"])
        XCTAssertNotNil(props["content"])
    }

    // MARK: - ZTP integration with the agent

    func testZTPBinaryResolves() throws {
        // ZTP is installed via Homebrew on this machine; if absent, skip.
        guard let path = ZTPDiscovery.resolveBinaryPath() else {
            throw XCTSkip("ztp binary not installed")
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path))
    }

    func testZTPBootstrapRegistersToolsForAgent() async throws {
        guard ZTPDiscovery.resolveBinaryPath() != nil else {
            throw XCTSkip("ztp binary not installed")
        }
        let registry = ToolRegistry()
        await ZTPIntegration.shared.bootstrap(registry: registry)
        let ztpTools = registry.allTools().map(\.name).filter { $0.hasPrefix("ztp.") }
        XCTAssertFalse(ztpTools.isEmpty, "Agent registry should contain ztp.* tools after bootstrap")
        // Each bridge must expose a valid LLM schema (so buildToolSchemas works).
        for tool in registry.allTools() where tool.name.hasPrefix("ztp.") {
            let schema = tool.inputSchema.toJSONValueSchema()
            XCTAssertEqual(schema["type"]?.stringValue, "object")
        }
    }
}
