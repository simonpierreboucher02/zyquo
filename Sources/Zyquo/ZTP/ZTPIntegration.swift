import Foundation
import Logging

public actor ZTPIntegration {
    public static let shared = ZTPIntegration()

    private let discovery = ZTPDiscovery()
    private var bridges: [String: ZTPToolBridge] = [:]
    private var initialized = false

    private init() {}

    public func bootstrap(registry: ToolRegistry, logger: Logging.Logger = ZyquoLogger.shared) async {
        guard !initialized else { return }
        initialized = true

        guard discovery.isAvailable() else {
            logger.info("ZTP binary not found — ZTP tools will not be available")
            return
        }

        let manifests = await discovery.discoverTools()
        logger.info("ZTP discovery found \(manifests.count) tools")

        let ztpPath = "/opt/homebrew/bin/ztp"
        for manifest in manifests {
            let bridge = ZTPToolBridge(manifest: manifest, ztpBinary: ztpPath)
            bridges[bridge.name] = bridge
            registry.register(bridge)
            logger.debug("Registered ZTP tool: \(bridge.name) (\(manifest.commands.count) commands)")
        }
    }

    public func availableTools() -> [String] {
        Array(bridges.keys).sorted()
    }

    public func bridge(for toolName: String) -> ZTPToolBridge? {
        bridges[toolName]
    }

    public func manifest(for toolName: String) async -> ZTPToolManifest? {
        await discovery.manifest(for: toolName)
    }

    public func createWorkflowEngine(logger: Logging.Logger = ZyquoLogger.shared) -> ZTPWorkflowEngine {
        ZTPWorkflowEngine(discovery: discovery, logger: logger)
    }

    public func systemPromptFragment() async -> String {
        let manifests = await discovery.discoverTools()
        guard !manifests.isEmpty else { return "" }

        var fragment = "\n\n## ZTP Tools Available\n\n"
        fragment += "You have access to the Zyquo Tool Protocol (ZTP) tools. "
        fragment += "ALWAYS prefer ZTP tools over writing scripts or workarounds.\n\n"
        fragment += "Use ZTP tools via the `ztp.*` tool functions. Each takes a `command` parameter "
        fragment += "and optionally `spec` (inline JSON), `spec_file` (path), and `output` (path).\n\n"

        fragment += "| Tool | Commands | Use For |\n"
        fragment += "|------|----------|--------|\n"

        let toolDescriptions: [String: String] = [
            "ztp-excel": "XLSX spreadsheets, reports, data tables",
            "ztp-docx": "Word documents, reports, proposals",
            "ztp-slides": "PowerPoint presentations, decks",
            "ztp-chart": "Charts, graphs, visualizations (PNG/SVG/PDF)",
            "ztp-mail": "Email drafting and sending (SMTP/Apple Mail)",
            "ztp-message": "iMessage and SMS via Apple Messages",
            "ztp-browser": "Web screenshots, scraping, PDF export",
            "ztp-macos": "macOS automation, files, apps, clipboard, screenshots",
        ]

        for manifest in manifests.sorted(by: { $0.name < $1.name }) {
            let cmds = manifest.commands.map(\.name).joined(separator: ", ")
            let desc = toolDescriptions[manifest.name] ?? manifest.capabilities.prefix(3).joined(separator: ", ")
            fragment += "| `\(manifest.name)` | \(cmds) | \(desc) |\n"
        }

        fragment += "\n### Spec Format\n"
        fragment += "Each document-generating tool (excel, docx, slides, chart) accepts a JSON spec.\n"
        fragment += "Pass specs inline via `spec` parameter or save to a file and use `spec_file`.\n"
        fragment += "All commands must use `--json` output (handled automatically).\n"
        fragment += "Verify `ok: true` in the response before proceeding.\n\n"

        fragment += "### Workflow Chaining\n"
        fragment += "ZTP tools can be chained: generate data → create chart → embed in slides.\n"
        fragment += "Use output paths from one tool as inputs to the next.\n"

        return fragment
    }
}

// MARK: - LLM Tool Schemas for Interactive Mode

public enum ZTPToolSchemas {
    public static func allSchemas() -> [ToolSchema] {
        [
            excelSchema,
            docxSchema,
            slidesSchema,
            chartSchema,
            mailSchema,
            messageSchema,
            browserSchema,
            macosSchema,
        ]
    }

    public static let excelSchema = ToolSchema(
        name: "ztp_excel",
        description: "Generate Excel XLSX files from JSON specs. Commands: build, validate-spec, inspect, import-csv. Use for spreadsheets, reports, and data tables.",
        inputSchema: toolInputSchema(commands: ["build", "validate-spec", "inspect", "import-csv", "sheets", "preview"])
    )

    public static let docxSchema = ToolSchema(
        name: "ztp_docx",
        description: "Generate Word DOCX files from JSON specs. Commands: build, validate-spec, inspect. Use for documents, reports, and proposals.",
        inputSchema: toolInputSchema(commands: ["build", "validate-spec", "inspect"])
    )

    public static let slidesSchema = ToolSchema(
        name: "ztp_slides",
        description: "Generate PowerPoint PPTX files from JSON specs. Commands: build, validate-spec, inspect. Use for presentations and pitch decks.",
        inputSchema: toolInputSchema(commands: ["build", "validate-spec", "inspect"])
    )

    public static let chartSchema = ToolSchema(
        name: "ztp_chart",
        description: "Generate charts as PNG/SVG/PDF from JSON specs. Types: bar, line, scatter, pie, area, histogram. Commands: build, validate-spec, data-summary, themes.",
        inputSchema: chartInputSchema()
    )

    public static let mailSchema = ToolSchema(
        name: "ztp_mail",
        description: "Draft and send emails. Commands: validate, preview, draft, send, apple-draft. Supports SMTP and Apple Mail.",
        inputSchema: toolInputSchema(commands: ["validate", "preview", "draft", "send", "apple-draft", "inspect"])
    )

    public static let messageSchema = ToolSchema(
        name: "ztp_message",
        description: "Send iMessages and SMS via Apple Messages. Commands: validate, preview, draft, send, templates.",
        inputSchema: toolInputSchema(commands: ["validate", "preview", "draft", "send", "apple-draft", "inspect", "templates"])
    )

    public static let browserSchema = ToolSchema(
        name: "ztp_browser",
        description: "Web automation: screenshots, PDF export, HTML/text extraction, link harvesting, metadata inspection. Commands: screenshot, pdf, html, text, links, metadata, open.",
        inputSchema: browserInputSchema()
    )

    public static let macosSchema = ToolSchema(
        name: "ztp_macos",
        description: "macOS automation: system-info, files (read/write/copy/move/delete), clipboard, notifications, screenshots, apps (open/list/quit), windows, processes, AppleScript, Shortcuts. Use for all macOS system interactions.",
        inputSchema: macosInputSchema()
    )

    private static func toolInputSchema(commands: [String]) -> [String: JSONValue] {
        [
            "type": .string("object"),
            "required": .array([.string("command")]),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "description": .string("ZTP subcommand: \(commands.joined(separator: ", "))"),
                    "enum": .array(commands.map { .string($0) }),
                ]),
                "spec": .object([
                    "type": .string("string"),
                    "description": .string("Inline JSON spec content for the tool"),
                ]),
                "spec_file": .object([
                    "type": .string("string"),
                    "description": .string("Path to JSON spec file"),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Output file path"),
                ]),
                "confirmed": .object([
                    "type": .string("boolean"),
                    "description": .string("Confirm destructive operations (send, delete)"),
                ]),
            ]),
        ]
    }

    private static func chartInputSchema() -> [String: JSONValue] {
        [
            "type": .string("object"),
            "required": .array([.string("command")]),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "description": .string("ZTP subcommand: build, validate-spec, data-summary, themes"),
                    "enum": .array([.string("build"), .string("validate-spec"), .string("data-summary"), .string("themes")]),
                ]),
                "spec": .object([
                    "type": .string("string"),
                    "description": .string("Inline JSON chart spec"),
                ]),
                "spec_file": .object([
                    "type": .string("string"),
                    "description": .string("Path to JSON spec file"),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Output file path (chart.png, chart.svg, etc.)"),
                ]),
                "format": .object([
                    "type": .string("string"),
                    "description": .string("Output format: png, svg, pdf"),
                    "enum": .array([.string("png"), .string("svg"), .string("pdf")]),
                ]),
            ]),
        ]
    }

    private static func browserInputSchema() -> [String: JSONValue] {
        [
            "type": .string("object"),
            "required": .array([.string("command")]),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "description": .string("ZTP subcommand: screenshot, pdf, html, text, links, metadata, open"),
                ]),
                "url": .object([
                    "type": .string("string"),
                    "description": .string("URL to process"),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Output file path for screenshot/pdf"),
                ]),
                "viewport_width": .object([
                    "type": .string("integer"),
                    "description": .string("Viewport width in pixels"),
                ]),
                "viewport_height": .object([
                    "type": .string("integer"),
                    "description": .string("Viewport height in pixels"),
                ]),
            ]),
        ]
    }

    private static func macosInputSchema() -> [String: JSONValue] {
        [
            "type": .string("object"),
            "required": .array([.string("command")]),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "description": .string("macOS subcommand: system-info, files-read, files-write, files-copy, files-move, files-delete, clipboard-get, clipboard-set, notify, screenshot-full, screenshot-window, apps-open, apps-list, apps-running, apps-quit, windows-list, processes-list, applescript-run, shortcuts-list, shortcuts-run"),
                ]),
                "path": .object([
                    "type": .string("string"),
                    "description": .string("File/directory path for file operations"),
                ]),
                "content": .object([
                    "type": .string("string"),
                    "description": .string("Content for write operations or AppleScript code"),
                ]),
                "output": .object([
                    "type": .string("string"),
                    "description": .string("Output path for screenshots"),
                ]),
                "app": .object([
                    "type": .string("string"),
                    "description": .string("Application name for app operations"),
                ]),
            ]),
        ]
    }
}
