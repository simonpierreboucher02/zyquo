import Foundation
import Logging
import TOMLKit

// MARK: - PluginManifest

/// Describes a Zyquo plugin loaded from a `plugin.toml` file.
///
/// Plugins are signed bundles (V2: actual code signing; V2 initial:
/// manifest validation only). Each plugin declares its tools, required
/// permissions, and entry point binary.
///
/// Reference: CLAUDE.md §30 Phase 5
public struct PluginManifest: Sendable, Codable, Equatable {
    /// Unique plugin name (reverse-domain recommended).
    public let name: String
    /// Semantic version string.
    public let version: String
    /// Publisher identity.
    public let publisher: String
    /// Relative path to the plugin entry binary.
    public let entry: String
    /// Permissions this plugin requires.
    public let permissions: [String]
    /// Tools declared by this plugin.
    public let tools: [PluginToolDef]

    public init(
        name: String,
        version: String,
        publisher: String,
        entry: String,
        permissions: [String],
        tools: [PluginToolDef]
    ) {
        self.name = name
        self.version = version
        self.publisher = publisher
        self.entry = entry
        self.permissions = permissions
        self.tools = tools
    }

    /// Required fields that must be present for a manifest to be valid.
    public static let requiredFields: Set<String> = ["name", "version", "publisher", "entry"]
}

// MARK: - PluginToolDef

/// Describes a single tool declared by a plugin.
public struct PluginToolDef: Sendable, Codable, Equatable {
    /// Tool name (must be namespaced, e.g. "docker.run").
    public let name: String
    /// Default risk level as a string ("SAFE", "MODERATE", "DANGEROUS", "CRITICAL").
    public let risk: String
    /// Human-readable description.
    public let description: String

    public init(name: String, risk: String, description: String) {
        self.name = name
        self.risk = risk
        self.description = description
    }

    /// Parse the risk string into a RiskLevel.
    public var riskLevel: RiskLevel {
        RiskLevel(rawValue: risk.lowercased()) ?? .moderate
    }
}

// MARK: - PluginTool

/// A stub tool that represents a plugin's tool.
///
/// In V2, this shells out to the plugin binary. For now it serves as
/// the registration placeholder so the agent knows the tool exists.
public struct PluginTool: Tool, Sendable {
    public let name: String
    public let summary: String
    public let documentation: String
    public let inputSchema: ToolInputSchema
    public let defaultRisk: RiskLevel
    public let isMutating: Bool

    private let pluginName: String
    private let entryPath: String

    public init(def: PluginToolDef, pluginName: String, entryPath: String) {
        self.name = def.name
        self.summary = def.description
        self.documentation = "Plugin tool from \(pluginName). Delegates execution to \(entryPath)."
        self.inputSchema = ToolInputSchema(
            properties: [
                "input": PropertySchema(
                    type: "string",
                    description: "JSON-encoded input for the plugin tool"
                ),
            ],
            required: ["input"]
        )
        self.defaultRisk = def.riskLevel
        self.isMutating = def.riskLevel >= .moderate
        self.pluginName = pluginName
        self.entryPath = entryPath
    }

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        // V2 stub: would shell out to the plugin binary
        // For now, return a message indicating the plugin tool is not yet executable
        throw ZyquoError.plugin(PluginError(
            code: "plugin.not_executable",
            description: "Plugin tool '\(name)' from '\(pluginName)' is registered but not yet executable",
            remediation: "Plugin execution will be available in a future Zyquo version"
        ))
    }
}

// MARK: - PluginLoader

/// Loads and validates plugin manifests from disk.
///
/// In V2 initial, validation checks:
/// - Manifest file exists and parses correctly
/// - All required fields are present
/// - Tool definitions are well-formed
///
/// Actual code signing verification is deferred to V2 Phase 5+.
public struct PluginLoader: Sendable {

    public init() {}

    // MARK: - Manifest Loading

    /// Load and parse a plugin manifest from a `plugin.toml` file.
    ///
    /// - Parameter path: URL to the `plugin.toml` file.
    /// - Returns: The parsed PluginManifest.
    /// - Throws: `ZyquoError.plugin` if the file cannot be read or parsed.
    public func loadManifest(at path: URL) throws -> PluginManifest {
        let content: String
        do {
            content = try String(contentsOf: path, encoding: .utf8)
        } catch {
            throw ZyquoError.plugin(PluginError(
                code: "plugin.manifest_not_found",
                description: "Cannot read plugin manifest at \(path.path)",
                remediation: "Ensure the plugin.toml file exists and is readable",
                underlying: error
            ))
        }

        return try parseManifest(content, at: path)
    }

    /// Parse a TOML string into a PluginManifest.
    public func parseManifest(_ toml: String, at path: URL? = nil) throws -> PluginManifest {
        let table: TOMLTable
        do {
            table = try TOMLTable(string: toml)
        } catch {
            throw ZyquoError.plugin(PluginError(
                code: "plugin.manifest_invalid",
                description: "Failed to parse plugin TOML: \(error.localizedDescription)",
                remediation: "Fix the TOML syntax in the plugin manifest",
                underlying: error
            ))
        }

        // Validate required fields
        for field in PluginManifest.requiredFields {
            guard table[field] != nil else {
                throw ZyquoError.plugin(PluginError(
                    code: "plugin.manifest_missing_field",
                    description: "Plugin manifest is missing required field '\(field)'",
                    remediation: "Add the '\(field)' field to the plugin.toml"
                ))
            }
        }

        let name = table["name"]?.string ?? ""
        let version = table["version"]?.string ?? ""
        let publisher = table["publisher"]?.string ?? ""
        let entry = table["entry"]?.string ?? ""

        // Parse permissions
        var permissions: [String] = []
        if let perms = table["permissions"]?.array {
            for i in 0..<perms.count {
                if let s = perms[i].string {
                    permissions.append(s)
                }
            }
        }

        // Parse tools
        var tools: [PluginToolDef] = []
        if let toolsArray = table["tools"]?.array {
            for i in 0..<toolsArray.count {
                if let toolTable = toolsArray[i].table {
                    let toolName = toolTable["name"]?.string ?? ""
                    let toolRisk = toolTable["risk"]?.string ?? "MODERATE"
                    let toolDesc = toolTable["description"]?.string ?? ""
                    if !toolName.isEmpty {
                        tools.append(PluginToolDef(name: toolName, risk: toolRisk, description: toolDesc))
                    }
                }
            }
        }

        return PluginManifest(
            name: name,
            version: version,
            publisher: publisher,
            entry: entry,
            permissions: permissions,
            tools: tools
        )
    }

    // MARK: - Signature Validation

    /// Validate a plugin's signature.
    ///
    /// V2 initial: checks that the manifest has all required fields and the
    /// entry binary exists. Actual code signing verification is deferred.
    ///
    /// - Parameters:
    ///   - manifest: The parsed manifest.
    ///   - pluginDir: Directory containing the plugin.
    /// - Returns: `true` if the plugin passes validation.
    public func validateSignature(manifest: PluginManifest, at pluginDir: URL) -> Bool {
        // Basic field validation
        guard !manifest.name.isEmpty,
              !manifest.version.isEmpty,
              !manifest.publisher.isEmpty,
              !manifest.entry.isEmpty
        else {
            return false
        }

        // Check that the entry binary exists
        let entryURL = pluginDir.appendingPathComponent(manifest.entry)
        guard FileManager.default.fileExists(atPath: entryURL.path) else {
            return false
        }

        // V2 TODO: actual code signature verification via Security.framework
        return true
    }

    // MARK: - Tool Loading

    /// Create Tool instances from a plugin manifest.
    ///
    /// Returns stub tools that register in the ToolRegistry. Actual
    /// execution delegates to the plugin binary.
    ///
    /// - Parameters:
    ///   - manifest: The parsed manifest.
    ///   - pluginDir: Directory containing the plugin.
    /// - Returns: Array of tools declared by the plugin.
    public func loadTools(from manifest: PluginManifest, at pluginDir: URL) -> [any Tool] {
        let entryPath = pluginDir.appendingPathComponent(manifest.entry).path

        return manifest.tools.map { def in
            PluginTool(def: def, pluginName: manifest.name, entryPath: entryPath)
        }
    }
}
