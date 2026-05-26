import Foundation
import GRDB
import Logging
import Testing

@testable import Zyquo

// MARK: - ToolResult Tests

@Suite("ToolResult")
struct ToolResultTests {

    @Test("ToolResult creation with defaults")
    func toolResultDefaults() {
        let result = ToolResult(summary: "test summary")
        #expect(result.summary == "test summary")
        #expect(result.payload == nil)
        #expect(result.artifacts.isEmpty)
        #expect(result.durationMs == 0)
        #expect(result.tokenHint == 0)
    }

    @Test("ToolResult creation with all fields")
    func toolResultAllFields() {
        let artifact = ToolArtifact(name: "output.json", path: "/tmp/output.json", mediaType: "application/json", size: 1024)
        let result = ToolResult(
            summary: "Command succeeded",
            payload: .object(["key": .string("value")]),
            artifacts: [artifact],
            durationMs: 42,
            tokenHint: 100
        )
        #expect(result.summary == "Command succeeded")
        #expect(result.durationMs == 42)
        #expect(result.tokenHint == 100)
        #expect(result.artifacts.count == 1)
        #expect(result.artifacts[0].name == "output.json")
    }

    @Test("ToolResult converts to Observation")
    func toObservation() {
        let result = ToolResult(
            summary: "test",
            payload: .string("data"),
            durationMs: 10,
            tokenHint: 5
        )
        let obs = result.toObservation(isError: false)
        #expect(obs.summary == "test")
        #expect(obs.durationMs == 10)
        #expect(obs.tokenHint == 5)
        #expect(!obs.isError)

        let errorObs = result.toObservation(isError: true)
        #expect(errorObs.isError)
    }
}

// MARK: - ToolArtifact Tests

@Suite("ToolArtifact")
struct ToolArtifactTests {

    @Test("Artifact with defaults")
    func artifactDefaults() {
        let artifact = ToolArtifact(name: "file.txt")
        #expect(artifact.name == "file.txt")
        #expect(artifact.path == nil)
        #expect(artifact.mediaType == "application/octet-stream")
        #expect(artifact.size == 0)
    }

    @Test("Artifact with all properties")
    func artifactAllProperties() {
        let artifact = ToolArtifact(
            name: "screenshot.png",
            path: "/tmp/screenshot.png",
            mediaType: "image/png",
            size: 2048
        )
        #expect(artifact.name == "screenshot.png")
        #expect(artifact.path == "/tmp/screenshot.png")
        #expect(artifact.mediaType == "image/png")
        #expect(artifact.size == 2048)
    }
}

// MARK: - ToolInputSchema Tests

@Suite("ToolInputSchema")
struct ToolInputSchemaTests {

    @Test("Schema creation")
    func schemaCreation() {
        let schema = ToolInputSchema(
            properties: [
                "query": PropertySchema(type: "string", description: "Search query"),
                "limit": PropertySchema(type: "integer", description: "Max results", defaultValue: "5"),
            ],
            required: ["query"]
        )
        #expect(schema.type == "object")
        #expect(schema.properties.count == 2)
        #expect(schema.required == ["query"])
        #expect(schema.properties["query"]?.type == "string")
        #expect(schema.properties["limit"]?.defaultValue == "5")
    }

    @Test("Empty schema")
    func emptySchema() {
        let schema = ToolInputSchema.empty
        #expect(schema.type == "object")
        #expect(schema.properties.isEmpty)
        #expect(schema.required.isEmpty)
    }

    @Test("PropertySchema with enum values")
    func propertySchemaEnum() {
        let prop = PropertySchema(
            type: "string",
            description: "Source type",
            enumValues: ["swift", "python", "mdn"]
        )
        #expect(prop.enumValues == ["swift", "python", "mdn"])
    }
}

// MARK: - ToolRegistry Tests

@Suite("ToolRegistry")
struct ToolRegistryTests {

    /// A minimal test tool for registry tests.
    struct MockTool: Tool, Sendable {
        let name: String
        let summary: String
        let documentation = "Mock tool for testing"
        let inputSchema = ToolInputSchema.empty
        let defaultRisk: RiskLevel
        let isMutating: Bool

        init(name: String, summary: String = "Mock tool", risk: RiskLevel = .safe, mutating: Bool = false) {
            self.name = name
            self.summary = summary
            self.defaultRisk = risk
            self.isMutating = mutating
        }

        func execute(input: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
            ToolResult(summary: "executed \(name)")
        }
    }

    @Test("Register and lookup a tool")
    func registerAndLookup() {
        let registry = ToolRegistry()
        let tool = MockTool(name: "test.tool")
        registry.register(tool)

        let found = registry.tool(named: "test.tool")
        #expect(found != nil)
        #expect(found?.name == "test.tool")
    }

    @Test("Returns nil for unknown tool")
    func unknownToolReturnsNil() {
        let registry = ToolRegistry()
        let found = registry.tool(named: "nonexistent.tool")
        #expect(found == nil)
    }

    @Test("Lists all tools sorted by name")
    func allToolsSorted() {
        let registry = ToolRegistry()
        registry.register(MockTool(name: "z.tool"))
        registry.register(MockTool(name: "a.tool"))
        registry.register(MockTool(name: "m.tool"))

        let all = registry.allTools()
        #expect(all.count == 3)
        #expect(all[0].name == "a.tool")
        #expect(all[1].name == "m.tool")
        #expect(all[2].name == "z.tool")
    }

    @Test("Count reflects registered tools")
    func countWorks() {
        let registry = ToolRegistry()
        #expect(registry.count == 0)
        registry.register(MockTool(name: "tool1"))
        #expect(registry.count == 1)
        registry.register(MockTool(name: "tool2"))
        #expect(registry.count == 2)
    }

    @Test("RegisterAll adds multiple tools")
    func registerAll() {
        let registry = ToolRegistry()
        registry.registerAll([
            MockTool(name: "alpha"),
            MockTool(name: "beta"),
            MockTool(name: "gamma"),
        ])
        #expect(registry.count == 3)
    }

    @Test("Replace tool with same name")
    func replaceExisting() {
        let registry = ToolRegistry()
        registry.register(MockTool(name: "t", summary: "v1"))
        registry.register(MockTool(name: "t", summary: "v2"))
        #expect(registry.count == 1)
        #expect(registry.tool(named: "t")?.summary == "v2")
    }

    @Test("Schemas returns all schemas sorted")
    func schemasListing() {
        let registry = ToolRegistry()
        registry.register(MockTool(name: "b.tool"))
        registry.register(MockTool(name: "a.tool"))

        let schemas = registry.schemas()
        #expect(schemas.count == 2)
        #expect(schemas[0].name == "a.tool")
        #expect(schemas[1].name == "b.tool")
    }

    @Test("Disable and enable tools")
    func disableEnable() {
        let registry = ToolRegistry()
        registry.register(MockTool(name: "tool1"))
        #expect(registry.isEnabled("tool1"))

        registry.disable("tool1")
        #expect(!registry.isEnabled("tool1"))
        #expect(registry.enabledTools().isEmpty)

        registry.enable("tool1")
        #expect(registry.isEnabled("tool1"))
        #expect(registry.enabledTools().count == 1)
    }

    @Test("Unregister removes a tool")
    func unregister() {
        let registry = ToolRegistry()
        registry.register(MockTool(name: "tool1"))
        registry.unregister("tool1")
        #expect(registry.tool(named: "tool1") == nil)
        #expect(registry.count == 0)
    }

    @Test("Formatted listing includes risk levels")
    func formattedListing() {
        let registry = ToolRegistry()
        registry.register(MockTool(name: "file.read", summary: "Read a file", risk: .safe))
        registry.register(MockTool(name: "shell.run", summary: "Run a command", risk: .moderate, mutating: true))

        let listing = registry.formattedListing()
        #expect(listing.contains("file.read"))
        #expect(listing.contains("shell.run"))
        #expect(listing.contains("SAFE"))
        #expect(listing.contains("MODERATE"))
        #expect(listing.contains("[R]"))
        #expect(listing.contains("[W]"))
    }
}

// MARK: - WebSearchTool Tests

@Suite("WebSearchTool")
struct WebSearchToolTests {

    @Test("Tool metadata")
    func toolMetadata() {
        let tool = WebSearchTool()
        #expect(tool.name == "web.search")
        #expect(tool.defaultRisk == .safe)
        #expect(!tool.isMutating)
        #expect(tool.inputSchema.required == ["query"])
    }

    @Test("Parse results from mock HTML")
    func parseResults() {
        let mockHTML = """
        <div class="result">
            <a class="result__a" href="https://example.com/page1">Example Page One</a>
            <span class="result__snippet">This is the first result snippet.</span>
        </div>
        <div class="result">
            <a class="result__a" href="https://example.com/page2">Example Page Two</a>
            <span class="result__snippet">This is the second result snippet.</span>
        </div>
        <div class="result">
            <a class="result__a" href="https://example.com/page3">Example Page Three</a>
            <span class="result__snippet">This is the third result snippet.</span>
        </div>
        """

        let results = WebSearchTool.parseResults(from: mockHTML, limit: 5)
        #expect(results.count == 3)
        #expect(results[0].title == "Example Page One")
        #expect(results[0].url == "https://example.com/page1")
        #expect(results[0].snippet == "This is the first result snippet.")
    }

    @Test("Parse results respects limit")
    func parseResultsLimit() {
        let mockHTML = """
        <a class="result__a" href="https://a.com">A</a>
        <span class="result__snippet">Snippet A</span>
        <a class="result__a" href="https://b.com">B</a>
        <span class="result__snippet">Snippet B</span>
        <a class="result__a" href="https://c.com">C</a>
        <span class="result__snippet">Snippet C</span>
        """
        let results = WebSearchTool.parseResults(from: mockHTML, limit: 2)
        #expect(results.count == 2)
    }

    @Test("Parse results handles empty HTML")
    func parseResultsEmpty() {
        let results = WebSearchTool.parseResults(from: "", limit: 5)
        #expect(results.isEmpty)
    }

    @Test("Strip HTML removes tags and decodes entities")
    func stripHTML() {
        let html = "<b>Hello</b> &amp; <i>world</i>"
        let result = WebSearchTool.stripHTML(html)
        #expect(result == "Hello & world")
    }
}

// MARK: - WebFetchTool Tests

@Suite("WebFetchTool")
struct WebFetchToolTests {

    @Test("Tool metadata")
    func toolMetadata() {
        let tool = WebFetchTool()
        #expect(tool.name == "web.fetch")
        #expect(tool.defaultRisk == .moderate)
        #expect(!tool.isMutating)
        #expect(tool.inputSchema.required == ["url"])
    }

    @Test("Rejects http:// scheme")
    func rejectsHTTP() async throws {
        let tool = WebFetchTool()
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            sessionId: "test",
            logger: logger
        )

        do {
            _ = try await tool.execute(
                input: ["url": .string("http://example.com")],
                context: ctx
            )
            Issue.record("Expected scheme_blocked error")
        } catch let error as ZyquoError {
            if case .tool(let toolError) = error {
                #expect(toolError.code == "tool.scheme_blocked")
            } else {
                Issue.record("Expected tool error, got \(error)")
            }
        }
    }

    @Test("Rejects ftp:// scheme")
    func rejectsFTP() async throws {
        let tool = WebFetchTool()
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            sessionId: "test",
            logger: logger
        )

        do {
            _ = try await tool.execute(
                input: ["url": .string("ftp://files.example.com/file.txt")],
                context: ctx
            )
            Issue.record("Expected scheme_blocked error")
        } catch let error as ZyquoError {
            if case .tool(let toolError) = error {
                #expect(toolError.code == "tool.scheme_blocked")
            } else {
                Issue.record("Expected tool error, got \(error)")
            }
        }
    }

    @Test("Rejects empty URL")
    func rejectsEmpty() async throws {
        let tool = WebFetchTool()
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            sessionId: "test",
            logger: logger
        )

        do {
            _ = try await tool.execute(input: ["url": .string("")], context: ctx)
            Issue.record("Expected error")
        } catch let error as ZyquoError {
            if case .tool(let toolError) = error {
                #expect(toolError.code == "tool.invalid_input")
            } else {
                Issue.record("Expected tool error, got \(error)")
            }
        }
    }

    @Test("HTML to text strips script/style blocks")
    func htmlToTextStripsBlocks() {
        let html = """
        <html>
        <head><style>body { color: red; }</style></head>
        <body>
        <script>alert('hi');</script>
        <p>Hello world</p>
        <nav>Skip nav</nav>
        </body>
        </html>
        """
        let text = WebFetchTool.htmlToText(html)
        #expect(!text.contains("alert"))
        #expect(!text.contains("color: red"))
        #expect(!text.contains("Skip nav"))
        #expect(text.contains("Hello world"))
    }

    @Test("Allowed schemes is HTTPS only")
    func allowedSchemes() {
        #expect(WebFetchTool.allowedSchemes == ["https"])
    }
}

// MARK: - HttpRequestTool Tests

@Suite("HttpRequestTool")
struct HttpRequestToolTests {

    @Test("Tool metadata")
    func toolMetadata() {
        let tool = HttpRequestTool()
        #expect(tool.name == "http.request")
        #expect(tool.defaultRisk == .moderate)
        #expect(tool.inputSchema.required == ["url"])
    }

    @Test("GET and HEAD are read-only methods")
    func readOnlyMethods() {
        #expect(HttpRequestTool.readOnlyMethods.contains("GET"))
        #expect(HttpRequestTool.readOnlyMethods.contains("HEAD"))
        #expect(HttpRequestTool.readOnlyMethods.contains("OPTIONS"))
    }

    @Test("POST/PUT/DELETE are mutating methods")
    func mutatingMethods() {
        #expect(HttpRequestTool.mutatingMethods.contains("POST"))
        #expect(HttpRequestTool.mutatingMethods.contains("PUT"))
        #expect(HttpRequestTool.mutatingMethods.contains("DELETE"))
        #expect(HttpRequestTool.mutatingMethods.contains("PATCH"))
    }

    @Test("Risk classification by method")
    func riskByMethod() {
        #expect(HttpRequestTool.riskForMethod("GET") == .moderate)
        #expect(HttpRequestTool.riskForMethod("HEAD") == .moderate)
        #expect(HttpRequestTool.riskForMethod("POST") == .dangerous)
        #expect(HttpRequestTool.riskForMethod("PUT") == .dangerous)
        #expect(HttpRequestTool.riskForMethod("DELETE") == .dangerous)
        #expect(HttpRequestTool.riskForMethod("PATCH") == .dangerous)
        #expect(HttpRequestTool.riskForMethod("CONNECT") == .critical)
    }

    @Test("Rejects non-HTTPS schemes")
    func rejectsHTTP() async throws {
        let tool = HttpRequestTool()
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            sessionId: "test",
            logger: logger
        )

        do {
            _ = try await tool.execute(
                input: ["url": .string("http://example.com/api")],
                context: ctx
            )
            Issue.record("Expected scheme_blocked error")
        } catch let error as ZyquoError {
            if case .tool(let toolError) = error {
                #expect(toolError.code == "tool.scheme_blocked")
            } else {
                Issue.record("Expected tool error, got \(error)")
            }
        }
    }

    @Test("Rejects invalid HTTP method")
    func rejectsInvalidMethod() async throws {
        let tool = HttpRequestTool()
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            sessionId: "test",
            logger: logger
        )

        do {
            _ = try await tool.execute(
                input: [
                    "url": .string("https://example.com"),
                    "method": .string("BADMETHOD"),
                ],
                context: ctx
            )
            Issue.record("Expected invalid_input error")
        } catch let error as ZyquoError {
            if case .tool(let toolError) = error {
                #expect(toolError.code == "tool.invalid_input")
            } else {
                Issue.record("Expected tool error, got \(error)")
            }
        }
    }
}

// MARK: - DatabaseTool Tests

@Suite("DatabaseTool")
struct DatabaseToolTests {

    @Test("Tool metadata")
    func toolMetadata() {
        let tool = DatabaseTool()
        #expect(tool.name == "db.query")
        #expect(tool.defaultRisk == .moderate)
        #expect(tool.isMutating)
        #expect(tool.inputSchema.required.contains("path"))
        #expect(tool.inputSchema.required.contains("query"))
    }

    @Test("SELECT is SAFE")
    func selectIsSafe() {
        #expect(DatabaseTool.classifyQueryRisk("SELECT * FROM users") == .safe)
        #expect(DatabaseTool.classifyQueryRisk("  SELECT id FROM t") == .safe)
        #expect(DatabaseTool.classifyQueryRisk("select name from t") == .safe)
    }

    @Test("PRAGMA is SAFE")
    func pragmaIsSafe() {
        #expect(DatabaseTool.classifyQueryRisk("PRAGMA table_info(users)") == .safe)
    }

    @Test("EXPLAIN is SAFE")
    func explainIsSafe() {
        #expect(DatabaseTool.classifyQueryRisk("EXPLAIN QUERY PLAN SELECT * FROM t") == .safe)
    }

    @Test("WITH (CTE) is SAFE")
    func withIsSafe() {
        #expect(DatabaseTool.classifyQueryRisk("WITH cte AS (SELECT 1) SELECT * FROM cte") == .safe)
    }

    @Test("INSERT is DANGEROUS")
    func insertIsDangerous() {
        #expect(DatabaseTool.classifyQueryRisk("INSERT INTO users (name) VALUES ('test')") == .dangerous)
    }

    @Test("UPDATE is DANGEROUS")
    func updateIsDangerous() {
        #expect(DatabaseTool.classifyQueryRisk("UPDATE users SET name = 'new' WHERE id = 1") == .dangerous)
    }

    @Test("DELETE is DANGEROUS")
    func deleteIsDangerous() {
        #expect(DatabaseTool.classifyQueryRisk("DELETE FROM users WHERE id = 1") == .dangerous)
    }

    @Test("REPLACE is DANGEROUS")
    func replaceIsDangerous() {
        #expect(DatabaseTool.classifyQueryRisk("REPLACE INTO users (id, name) VALUES (1, 'x')") == .dangerous)
    }

    @Test("CREATE is CRITICAL")
    func createIsCritical() {
        #expect(DatabaseTool.classifyQueryRisk("CREATE TABLE users (id INTEGER)") == .critical)
    }

    @Test("DROP is CRITICAL")
    func dropIsCritical() {
        #expect(DatabaseTool.classifyQueryRisk("DROP TABLE users") == .critical)
    }

    @Test("ALTER is CRITICAL")
    func alterIsCritical() {
        #expect(DatabaseTool.classifyQueryRisk("ALTER TABLE users ADD COLUMN email TEXT") == .critical)
    }

    @Test("Unknown SQL is DANGEROUS by default")
    func unknownIsDangerous() {
        #expect(DatabaseTool.classifyQueryRisk("VACUUM") == .dangerous)
        #expect(DatabaseTool.classifyQueryRisk("REINDEX") == .dangerous)
    }

    @Test("Workspace boundary check rejects outside paths")
    func boundaryCheck() async throws {
        let tool = DatabaseTool()
        let workspaceRoot = URL(fileURLWithPath: "/tmp/test-workspace")
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: workspaceRoot,
            sessionId: "test",
            logger: logger
        )

        do {
            _ = try await tool.execute(
                input: [
                    "path": .string("/etc/shadow.db"),
                    "query": .string("SELECT 1"),
                ],
                context: ctx
            )
            Issue.record("Expected boundary violation")
        } catch let error as ZyquoError {
            if case .workspace(let wsError) = error {
                #expect(wsError.code == "workspace.boundary")
            } else {
                Issue.record("Expected workspace error, got \(error)")
            }
        }
    }

    @Test("Rejects missing path")
    func rejectsMissingPath() async throws {
        let tool = DatabaseTool()
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            sessionId: "test",
            logger: logger
        )

        do {
            _ = try await tool.execute(
                input: ["query": .string("SELECT 1")],
                context: ctx
            )
            Issue.record("Expected invalid_input error")
        } catch let error as ZyquoError {
            if case .tool(let toolError) = error {
                #expect(toolError.code == "tool.invalid_input")
            } else {
                Issue.record("Expected tool error, got \(error)")
            }
        }
    }

    @Test("Rejects missing query")
    func rejectsMissingQuery() async throws {
        let tool = DatabaseTool()
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: URL(fileURLWithPath: "/tmp"),
            sessionId: "test",
            logger: logger
        )

        do {
            _ = try await tool.execute(
                input: ["path": .string("test.db")],
                context: ctx
            )
            Issue.record("Expected invalid_input error")
        } catch let error as ZyquoError {
            if case .tool(let toolError) = error {
                #expect(toolError.code == "tool.invalid_input")
            } else {
                Issue.record("Expected tool error, got \(error)")
            }
        }
    }

    @Test("Executes SELECT on a real SQLite database")
    func executeSelectOnRealDB() async throws {
        // Create a temporary SQLite database
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let dbPath = tmpDir.appendingPathComponent("test.db")

        // Create and populate the database using GRDB
        let dbQueue = try DatabaseQueue(path: dbPath.path)
        try await dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)")
            try db.execute(sql: "INSERT INTO items (name) VALUES ('alpha')")
            try db.execute(sql: "INSERT INTO items (name) VALUES ('beta')")
        }

        let tool = DatabaseTool()
        let logger = Logger(label: "test")
        let ctx = ToolContext(
            workspaceRoot: tmpDir,
            sessionId: "test",
            logger: logger
        )

        let result = try await tool.execute(
            input: [
                "path": .string(dbPath.path),
                "query": .string("SELECT * FROM items ORDER BY id"),
            ],
            context: ctx
        )

        #expect(result.summary.contains("2 row"))
        #expect(result.durationMs >= 0)
        if case .array(let rows) = result.payload {
            #expect(rows.count == 2)
        } else {
            Issue.record("Expected array payload")
        }
    }
}

// MARK: - DocSearchTool Tests

@Suite("DocSearchTool")
struct DocSearchToolTests {

    @Test("Tool metadata")
    func toolMetadata() {
        let tool = DocSearchTool()
        #expect(tool.name == "docs.search")
        #expect(tool.defaultRisk == .safe)
        #expect(!tool.isMutating)
        #expect(tool.inputSchema.required == ["query"])
    }

    @Test("Search URLs are constructed correctly")
    func searchURLs() {
        let mdnURL = DocSearchTool.searchURL(source: .mdn, query: "Array.map")
        #expect(mdnURL != nil)
        #expect(mdnURL?.absoluteString.contains("developer.mozilla.org") == true)

        let npmURL = DocSearchTool.searchURL(source: .npm, query: "express")
        #expect(npmURL != nil)
        #expect(npmURL?.absoluteString.contains("registry.npmjs.org") == true)

        let swiftURL = DocSearchTool.searchURL(source: .swift, query: "Optional")
        #expect(swiftURL != nil)
        #expect(swiftURL?.absoluteString.contains("developer.apple.com") == true)

        let pythonURL = DocSearchTool.searchURL(source: .python, query: "asyncio")
        #expect(pythonURL != nil)
        #expect(pythonURL?.absoluteString.contains("docs.python.org") == true)
    }

    @Test("DocSource covers all expected values")
    func docSourceCases() {
        let all = DocSearchTool.DocSource.allCases
        #expect(all.count == 4)
        #expect(all.contains(.swift))
        #expect(all.contains(.python))
        #expect(all.contains(.mdn))
        #expect(all.contains(.npm))
    }
}

// MARK: - PluginManifest Tests

@Suite("PluginManifest")
struct PluginManifestTests {

    @Test("Manifest creation")
    func manifestCreation() {
        let manifest = PluginManifest(
            name: "docker",
            version: "0.1.0",
            publisher: "zyquo",
            entry: "./bin/zyquo-docker",
            permissions: ["network:local", "shell:limited"],
            tools: [
                PluginToolDef(name: "docker.run", risk: "MODERATE", description: "Run a Docker container"),
            ]
        )
        #expect(manifest.name == "docker")
        #expect(manifest.version == "0.1.0")
        #expect(manifest.publisher == "zyquo")
        #expect(manifest.entry == "./bin/zyquo-docker")
        #expect(manifest.permissions.count == 2)
        #expect(manifest.tools.count == 1)
        #expect(manifest.tools[0].name == "docker.run")
    }

    @Test("Required fields list")
    func requiredFields() {
        let required = PluginManifest.requiredFields
        #expect(required.contains("name"))
        #expect(required.contains("version"))
        #expect(required.contains("publisher"))
        #expect(required.contains("entry"))
    }

    @Test("PluginToolDef risk level parsing")
    func toolDefRiskParsing() {
        let safe = PluginToolDef(name: "t", risk: "safe", description: "")
        #expect(safe.riskLevel == .safe)

        let moderate = PluginToolDef(name: "t", risk: "moderate", description: "")
        #expect(moderate.riskLevel == .moderate)

        let dangerous = PluginToolDef(name: "t", risk: "dangerous", description: "")
        #expect(dangerous.riskLevel == .dangerous)

        let critical = PluginToolDef(name: "t", risk: "critical", description: "")
        #expect(critical.riskLevel == .critical)

        let unknown = PluginToolDef(name: "t", risk: "UNKNOWN", description: "")
        #expect(unknown.riskLevel == .moderate) // default fallback
    }
}

// MARK: - PluginLoader Tests

@Suite("PluginLoader")
struct PluginLoaderTests {

    @Test("Parse valid TOML manifest")
    func parseValidManifest() throws {
        let toml = """
        name = "docker"
        version = "0.1.0"
        publisher = "zyquo"
        entry = "./bin/zyquo-docker"
        permissions = ["network:local", "shell:limited"]

        [[tools]]
        name = "docker.run"
        risk = "MODERATE"
        description = "Run a Docker container"

        [[tools]]
        name = "docker.ps"
        risk = "SAFE"
        description = "List Docker containers"
        """

        let loader = PluginLoader()
        let manifest = try loader.parseManifest(toml)

        #expect(manifest.name == "docker")
        #expect(manifest.version == "0.1.0")
        #expect(manifest.publisher == "zyquo")
        #expect(manifest.entry == "./bin/zyquo-docker")
        #expect(manifest.permissions == ["network:local", "shell:limited"])
        #expect(manifest.tools.count == 2)
        #expect(manifest.tools[0].name == "docker.run")
        #expect(manifest.tools[0].risk == "MODERATE")
        #expect(manifest.tools[1].name == "docker.ps")
        #expect(manifest.tools[1].risk == "SAFE")
    }

    @Test("Rejects manifest missing 'name'")
    func rejectsMissingName() {
        let toml = """
        version = "0.1.0"
        publisher = "zyquo"
        entry = "./bin/plugin"
        """

        let loader = PluginLoader()
        do {
            _ = try loader.parseManifest(toml)
            Issue.record("Expected error for missing 'name'")
        } catch let error as ZyquoError {
            if case .plugin(let pluginError) = error {
                #expect(pluginError.code == "plugin.manifest_missing_field")
                #expect(pluginError.description.contains("name"))
            } else {
                Issue.record("Expected plugin error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Rejects manifest missing 'version'")
    func rejectsMissingVersion() {
        let toml = """
        name = "myplugin"
        publisher = "zyquo"
        entry = "./bin/plugin"
        """

        let loader = PluginLoader()
        do {
            _ = try loader.parseManifest(toml)
            Issue.record("Expected error for missing 'version'")
        } catch let error as ZyquoError {
            if case .plugin(let pluginError) = error {
                #expect(pluginError.code == "plugin.manifest_missing_field")
            } else {
                Issue.record("Expected plugin error")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Rejects manifest missing 'publisher'")
    func rejectsMissingPublisher() {
        let toml = """
        name = "myplugin"
        version = "1.0.0"
        entry = "./bin/plugin"
        """

        let loader = PluginLoader()
        do {
            _ = try loader.parseManifest(toml)
            Issue.record("Expected error for missing 'publisher'")
        } catch let error as ZyquoError {
            if case .plugin(let pluginError) = error {
                #expect(pluginError.code == "plugin.manifest_missing_field")
            } else {
                Issue.record("Expected plugin error")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Rejects manifest missing 'entry'")
    func rejectsMissingEntry() {
        let toml = """
        name = "myplugin"
        version = "1.0.0"
        publisher = "zyquo"
        """

        let loader = PluginLoader()
        do {
            _ = try loader.parseManifest(toml)
            Issue.record("Expected error for missing 'entry'")
        } catch let error as ZyquoError {
            if case .plugin(let pluginError) = error {
                #expect(pluginError.code == "plugin.manifest_missing_field")
            } else {
                Issue.record("Expected plugin error")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Rejects invalid TOML syntax")
    func rejectsInvalidTOML() {
        let toml = "{{invalid toml}}"

        let loader = PluginLoader()
        do {
            _ = try loader.parseManifest(toml)
            Issue.record("Expected error for invalid TOML")
        } catch let error as ZyquoError {
            if case .plugin(let pluginError) = error {
                #expect(pluginError.code == "plugin.manifest_invalid")
            } else {
                Issue.record("Expected plugin error")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Validate signature with valid manifest and entry")
    func validateSignatureValid() throws {
        // Create a temp directory with a mock binary
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-plugin-test-\(UUID().uuidString)")
        let binDir = tmpDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let entryPath = binDir.appendingPathComponent("plugin")
        FileManager.default.createFile(atPath: entryPath.path, contents: "#!/bin/sh".data(using: .utf8))

        let manifest = PluginManifest(
            name: "test",
            version: "0.1.0",
            publisher: "zyquo",
            entry: "bin/plugin",
            permissions: [],
            tools: []
        )

        let loader = PluginLoader()
        #expect(loader.validateSignature(manifest: manifest, at: tmpDir))
    }

    @Test("Validate signature fails with missing entry binary")
    func validateSignatureMissingEntry() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-plugin-test-\(UUID().uuidString)")

        let manifest = PluginManifest(
            name: "test",
            version: "0.1.0",
            publisher: "zyquo",
            entry: "bin/nonexistent",
            permissions: [],
            tools: []
        )

        let loader = PluginLoader()
        #expect(!loader.validateSignature(manifest: manifest, at: tmpDir))
    }

    @Test("Validate signature fails with empty fields")
    func validateSignatureEmptyFields() {
        let manifest = PluginManifest(
            name: "",
            version: "0.1.0",
            publisher: "zyquo",
            entry: "bin/plugin",
            permissions: [],
            tools: []
        )

        let loader = PluginLoader()
        #expect(!loader.validateSignature(manifest: manifest, at: URL(fileURLWithPath: "/tmp")))
    }

    @Test("Load tools from manifest creates PluginTool instances")
    func loadTools() {
        let manifest = PluginManifest(
            name: "docker",
            version: "0.1.0",
            publisher: "zyquo",
            entry: "./bin/zyquo-docker",
            permissions: ["network:local"],
            tools: [
                PluginToolDef(name: "docker.run", risk: "MODERATE", description: "Run a container"),
                PluginToolDef(name: "docker.ps", risk: "SAFE", description: "List containers"),
            ]
        )

        let loader = PluginLoader()
        let tools = loader.loadTools(from: manifest, at: URL(fileURLWithPath: "/tmp/plugins/docker"))
        #expect(tools.count == 2)
        #expect(tools[0].name == "docker.run")
        #expect(tools[0].defaultRisk == .moderate)
        #expect(tools[1].name == "docker.ps")
        #expect(tools[1].defaultRisk == .safe)
    }
}

// MARK: - Builtin Registration Tests

@Suite("BuiltinRegistration")
struct BuiltinRegistrationTests {

    @Test("registerBuiltinTools registers all V2 tools")
    func registersAll() {
        let registry = ToolRegistry()
        registerBuiltinTools(in: registry)

        #expect(registry.count == 5)
        #expect(registry.tool(named: "web.search") != nil)
        #expect(registry.tool(named: "web.fetch") != nil)
        #expect(registry.tool(named: "http.request") != nil)
        #expect(registry.tool(named: "db.query") != nil)
        #expect(registry.tool(named: "docs.search") != nil)
    }
}
