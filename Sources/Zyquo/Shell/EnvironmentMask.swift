import Foundation

/// Filters and sanitizes environment variables for child processes.
///
/// Strips sensitive variables (tokens, secrets, keys, SSH, AWS, provider keys)
/// and sanitizes PATH to only include known-safe directories plus Homebrew prefix.
public struct EnvironmentMask: Sendable {

    /// Patterns for environment variable names that should be stripped.
    /// Matched case-insensitively against the variable name.
    private static let sensitivePatterns: [String] = [
        "_TOKEN", "_SECRET", "_KEY", "_PASSWORD", "_CREDENTIAL",
    ]

    /// Exact prefixes for environment variable names that should be stripped.
    private static let sensitivePrefixes: [String] = [
        "SSH_", "AWS_", "ANTHROPIC_", "OPENAI_", "OPENROUTER_",
        "GOOGLE_", "AZURE_",
    ]

    /// Exact variable names that should always be stripped.
    private static let sensitiveExact: Set<String> = [
        "GITHUB_TOKEN", "GITLAB_TOKEN", "NPM_TOKEN",
        "HOMEBREW_GITHUB_API_TOKEN",
    ]

    /// Directories always allowed in PATH.
    private static let pathAllowList: [String] = [
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
        "/usr/local/bin",
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
    ]

    /// Detect the Homebrew prefix for the current architecture.
    public static var homebrewPrefix: String {
        #if arch(arm64)
        return "/opt/homebrew/bin"
        #else
        return "/usr/local/bin"
        #endif
    }

    /// Check whether an environment variable name matches a sensitive pattern.
    public static func isSensitive(name: String) -> Bool {
        let upper = name.uppercased()

        if sensitiveExact.contains(upper) {
            return true
        }

        for prefix in sensitivePrefixes {
            if upper.hasPrefix(prefix) {
                return true
            }
        }

        for pattern in sensitivePatterns {
            if upper.hasSuffix(pattern) {
                return true
            }
        }

        return false
    }

    /// Filter the given environment, removing sensitive variables.
    ///
    /// - Parameters:
    ///   - environment: The source environment (e.g. ProcessInfo.processInfo.environment)
    ///   - overrides: Explicit overrides to merge (these are NOT filtered)
    /// - Returns: A sanitized environment dictionary.
    public static func sanitize(
        environment: [String: String],
        overrides: [String: String]? = nil
    ) -> [String: String] {
        var result: [String: String] = [:]

        for (key, value) in environment {
            guard !isSensitive(name: key) else { continue }

            if key == "PATH" {
                result[key] = sanitizePath(value)
            } else {
                result[key] = value
            }
        }

        // Explicit overrides are trusted and applied after filtering.
        if let overrides {
            for (key, value) in overrides {
                result[key] = value
            }
        }

        return result
    }

    /// Sanitize PATH by intersecting with the allow-list and ensuring
    /// the Homebrew prefix is present.
    public static func sanitizePath(_ path: String) -> String {
        let components = path.split(separator: ":").map(String.init)
        var allowed: [String] = []
        var seen = Set<String>()

        // Always include Homebrew prefix first
        let brewPrefix = homebrewPrefix
        if !seen.contains(brewPrefix) {
            allowed.append(brewPrefix)
            seen.insert(brewPrefix)
        }

        for component in components {
            let normalized = component.hasSuffix("/")
                ? String(component.dropLast())
                : component

            guard !seen.contains(normalized) else { continue }

            if isAllowedPathComponent(normalized) {
                allowed.append(normalized)
                seen.insert(normalized)
            }
        }

        return allowed.joined(separator: ":")
    }

    /// Check whether a PATH component is in the allow-list.
    /// Allows the standard system paths plus workspace-local bin dirs
    /// and Homebrew-managed paths.
    private static func isAllowedPathComponent(_ component: String) -> Bool {
        // Exact match against known safe paths
        if pathAllowList.contains(component) {
            return true
        }

        // Allow Homebrew-managed paths
        if component.hasPrefix("/opt/homebrew/") || component.hasPrefix("/usr/local/") {
            return true
        }

        // Allow Xcode toolchain paths
        if component.contains("/Xcode") || component.contains("/CommandLineTools") {
            return true
        }

        // Allow user-local bin directories (common for pip, cargo, go, etc.)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let localBinPaths = [
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/go/bin",
            "\(home)/.bun/bin",
        ]
        if localBinPaths.contains(component) {
            return true
        }

        return false
    }
}
