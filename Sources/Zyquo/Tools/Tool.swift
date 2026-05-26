import Foundation
import Logging

// MARK: - Tool Protocol

/// The canonical protocol for all Zyquo tools (V1 + V2).
///
/// Every tool has a stable `name` (e.g. "shell.run", "web.search"),
/// a JSON Schema for input validation and LLM tool description,
/// a default risk tier, and an async execute method.
///
/// Reference: CLAUDE.md §17
public protocol Tool: Sendable {
    /// Stable identifier, e.g. "shell.run", "web.search".
    var name: String { get }

    /// Human-readable single sentence shown in /tools list.
    var summary: String { get }

    /// Longer markdown documentation shown in help and prompts.
    var documentation: String { get }

    /// JSON Schema for the input — used both to validate calls and to
    /// populate the LLM tool schema.
    var inputSchema: ToolInputSchema { get }

    /// Static default risk; per-call risk may be elevated.
    var defaultRisk: RiskLevel { get }

    /// Whether the tool mutates filesystem, network, or workspace state.
    var isMutating: Bool { get }

    /// Execute the tool. Implementations MUST be cancellable via Task.
    func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult
}

// MARK: - ToolContext

/// Dependencies injected into every tool execution.
public struct ToolContext: Sendable {
    /// The workspace root directory.
    public let workspaceRoot: URL
    /// The current session identifier.
    public let sessionId: String
    /// Logger for structured logging.
    public let logger: Logging.Logger

    public init(workspaceRoot: URL, sessionId: String, logger: Logging.Logger) {
        self.workspaceRoot = workspaceRoot
        self.sessionId = sessionId
        self.logger = logger
    }
}

// MARK: - ToolResult

/// The result of executing a tool.
public struct ToolResult: Sendable {
    /// Short summary (1-3 lines) for UI and LLM context.
    public let summary: String
    /// Structured output payload.
    public let payload: JSONValue?
    /// Produced files, diffs, or other artifacts.
    public let artifacts: [ToolArtifact]
    /// Wall-clock duration of execution in milliseconds.
    public let durationMs: Int
    /// Estimated token count if the result were echoed to the LLM.
    public let tokenHint: Int

    public init(
        summary: String,
        payload: JSONValue? = nil,
        artifacts: [ToolArtifact] = [],
        durationMs: Int = 0,
        tokenHint: Int = 0
    ) {
        self.summary = summary
        self.payload = payload
        self.artifacts = artifacts
        self.durationMs = durationMs
        self.tokenHint = tokenHint
    }

    /// Convert this ToolResult into an Observation for the agent loop.
    public func toObservation(isError: Bool = false) -> Observation {
        Observation(
            summary: summary,
            payload: payload,
            durationMs: durationMs,
            tokenHint: tokenHint,
            isError: isError
        )
    }
}

// MARK: - ToolArtifact

/// A file, diff, or other artifact produced by a tool execution.
public struct ToolArtifact: Sendable {
    /// Human-readable name of the artifact.
    public let name: String
    /// Optional file path where the artifact resides.
    public let path: String?
    /// MIME type or media type identifier.
    public let mediaType: String
    /// Size in bytes.
    public let size: Int

    public init(name: String, path: String? = nil, mediaType: String = "application/octet-stream", size: Int = 0) {
        self.name = name
        self.path = path
        self.mediaType = mediaType
        self.size = size
    }
}

// MARK: - ToolInputSchema

/// JSON Schema describing a tool's input parameters.
/// Used for both validation and LLM tool description generation.
public struct ToolInputSchema: Sendable, Codable {
    /// The schema type (always "object" for tool inputs).
    public let type: String
    /// Properties keyed by parameter name.
    public let properties: [String: PropertySchema]
    /// Names of required parameters.
    public let required: [String]

    public init(
        type: String = "object",
        properties: [String: PropertySchema],
        required: [String]
    ) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    /// An empty schema (no parameters).
    public static let empty = ToolInputSchema(type: "object", properties: [:], required: [])
}

// MARK: - PropertySchema

/// Schema for a single tool input property.
public struct PropertySchema: Sendable, Codable {
    /// The JSON type (e.g. "string", "integer", "boolean", "object", "array").
    public let type: String
    /// Human-readable description of the parameter.
    public let description: String
    /// Allowed values (for enum-style strings).
    public let enumValues: [String]?
    /// Default value as a string representation.
    public let defaultValue: String?

    public init(
        type: String,
        description: String,
        enumValues: [String]? = nil,
        defaultValue: String? = nil
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.defaultValue = defaultValue
    }

    enum CodingKeys: String, CodingKey {
        case type, description
        case enumValues = "enum"
        case defaultValue = "default"
    }
}
