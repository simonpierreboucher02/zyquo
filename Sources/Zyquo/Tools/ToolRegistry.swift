import Foundation
import Logging

// MARK: - ToolRegistry

/// Central registry of all available tools.
///
/// Tools are registered at boot via `AppContainer` and looked up by
/// stable name. Per-session enable/disable mutates a session-scoped
/// view, never the global registry.
///
/// Reference: CLAUDE.md §17.3
public final class ToolRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tools: [String: any Tool] = [:]
    private var disabledTools: Set<String> = []

    public init() {}

    // MARK: - Registration

    /// Register a tool. Replaces any existing tool with the same name.
    public func register(_ tool: any Tool) {
        lock.lock()
        defer { lock.unlock() }
        tools[tool.name] = tool
    }

    /// Register multiple tools at once.
    public func registerAll(_ toolList: [any Tool]) {
        lock.lock()
        defer { lock.unlock() }
        for tool in toolList {
            tools[tool.name] = tool
        }
    }

    // MARK: - Lookup

    /// Look up a tool by its stable name. Returns nil if not found.
    public func tool(named name: String) -> (any Tool)? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]
    }

    /// Returns all registered tools sorted by name.
    public func allTools() -> [any Tool] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values.sorted { $0.name < $1.name }
    }

    /// Returns the count of registered tools.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return tools.count
    }

    /// Returns schemas for all registered tools, suitable for LLM tool description.
    public func schemas() -> [(name: String, schema: ToolInputSchema)] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values
            .sorted { $0.name < $1.name }
            .map { (name: $0.name, schema: $0.inputSchema) }
    }

    // MARK: - Session-Scoped Enable/Disable

    /// Disable a tool for the current session scope.
    public func disable(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        disabledTools.insert(name)
    }

    /// Re-enable a previously disabled tool.
    public func enable(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        disabledTools.remove(name)
    }

    /// Check if a tool is currently enabled.
    public func isEnabled(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tools[name] != nil && !disabledTools.contains(name)
    }

    /// Returns all enabled tools sorted by name.
    public func enabledTools() -> [any Tool] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values
            .filter { !disabledTools.contains($0.name) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Unregister

    /// Remove a tool from the registry.
    public func unregister(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        tools.removeValue(forKey: name)
        disabledTools.remove(name)
    }

    /// Remove all tools.
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        tools.removeAll()
        disabledTools.removeAll()
    }

    // MARK: - Description

    /// Returns a formatted listing of all tools with risk levels.
    public func formattedListing() -> String {
        let allSorted = allTools()
        guard !allSorted.isEmpty else { return "No tools registered." }

        var lines: [String] = []
        lines.append("Registered Tools (\(allSorted.count)):")
        lines.append(String(repeating: "-", count: 60))

        let maxNameLen = allSorted.map(\.name.count).max() ?? 12
        for tool in allSorted {
            let enabled = isEnabled(tool.name)
            let status = enabled ? " " : "x"
            let name = tool.name.padding(toLength: maxNameLen + 2, withPad: " ", startingAt: 0)
            let risk = tool.defaultRisk.displayName.padding(toLength: 10, withPad: " ", startingAt: 0)
            let mut = tool.isMutating ? "W" : "R"
            lines.append("[\(status)] \(name) \(risk) [\(mut)] \(tool.summary)")
        }

        return lines.joined(separator: "\n")
    }
}
