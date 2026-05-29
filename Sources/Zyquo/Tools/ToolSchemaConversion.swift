import Foundation

// MARK: - Tool name wire form

/// Maps between canonical tool names (`ns.verb`, e.g. `ztp.excel`, `shell.run`)
/// and the "wire" form required by LLM providers, whose tool-name pattern is
/// `^[a-zA-Z0-9_-]+$` (no dots). Canonical names never contain underscores, so
/// `.`↔`_` round-trips unambiguously. Used only on the agent path; the
/// interactive chat uses underscore names natively.
public enum ToolNameWire {
    /// Canonical → wire (`ztp.excel` → `ztp_excel`).
    public static func toWire(_ canonical: String) -> String {
        canonical.replacingOccurrences(of: ".", with: "_")
    }

    /// Wire → canonical (`ztp_excel` → `ztp.excel`).
    public static func toCanonical(_ wire: String) -> String {
        wire.replacingOccurrences(of: "_", with: ".")
    }
}

// MARK: - ToolInputSchema → LLM JSON Schema

extension ToolInputSchema {
    /// Convert this typed schema into the `[String: JSONValue]` JSON-Schema
    /// shape expected by `ToolSchema` (the LLM-facing tool description used by
    /// providers). This lets registry `Tool`s (ZTP bridges, file.write, git.*)
    /// be advertised to the planner/executor exactly like the native tools.
    public func toJSONValueSchema() -> [String: JSONValue] {
        var props: [String: JSONValue] = [:]
        for (key, prop) in properties {
            var entry: [String: JSONValue] = [
                "type": .string(prop.type),
                "description": .string(prop.description),
            ]
            if let enumValues = prop.enumValues, !enumValues.isEmpty {
                entry["enum"] = .array(enumValues.map { .string($0) })
            }
            if let def = prop.defaultValue {
                entry["default"] = .string(def)
            }
            props[key] = .object(entry)
        }
        return [
            "type": .string("object"),
            "required": .array(required.map { .string($0) }),
            "properties": .object(props),
        ]
    }
}
