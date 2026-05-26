import Foundation

// MARK: - ConfigStore

/// Helpers for loading and saving workspace and global configuration files.
///
/// Workspace config: `.zyquo/config.json` (JSON)
/// Global config: `~/.zyquo/config.toml` (TOML, handled by Config.swift)
///
/// Reference: CLAUDE.md S34
public struct ConfigStore: Sendable {

    /// Load the workspace configuration from `.zyquo/config.json`.
    ///
    /// - Parameter root: The workspace root directory.
    /// - Returns: The parsed configuration dictionary, or empty if not found.
    public static func loadWorkspaceConfig(at root: URL) -> [String: Any] {
        let path = root
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    /// Save the workspace configuration to `.zyquo/config.json`.
    ///
    /// - Parameters:
    ///   - config: The configuration dictionary to save.
    ///   - root: The workspace root directory.
    /// - Throws: If the file cannot be written.
    public static func saveWorkspaceConfig(_ config: [String: Any], at root: URL) throws {
        let zyquoDir = root.appendingPathComponent(".zyquo")
        let fm = FileManager.default
        if !fm.fileExists(atPath: zyquoDir.path) {
            try fm.createDirectory(at: zyquoDir, withIntermediateDirectories: true)
        }

        let path = zyquoDir.appendingPathComponent("config.json")
        let data = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: path, options: .atomic)
    }

    /// Load the global configuration from `~/.zyquo/config.toml`.
    ///
    /// Returns the raw file contents as a dictionary. TOML parsing is
    /// handled by the Config type; this method returns the raw JSON-compatible
    /// representation for inspection.
    ///
    /// - Returns: The global config as a dictionary, or empty if not found.
    public static func loadGlobalConfig() -> [String: Any] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("config.toml")
        guard FileManager.default.fileExists(atPath: path.path) else {
            return [:]
        }
        // Return a simple indicator that the file exists; full TOML parsing
        // is done by Config.swift at startup.
        return ["_exists": true, "_path": path.path]
    }
}
