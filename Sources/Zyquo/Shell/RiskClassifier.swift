import Foundation

// MARK: - RiskLevel

/// Risk classification tiers for shell commands and tool invocations.
/// Ordered from lowest to highest risk.
///
/// Reference: CLAUDE.md §19.1
public enum RiskLevel: String, Sendable, Comparable, CaseIterable, Codable {
    case safe
    case moderate
    case dangerous
    case critical

    private var ordinal: Int {
        switch self {
        case .safe: return 0
        case .moderate: return 1
        case .dangerous: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.ordinal < rhs.ordinal
    }

    /// Escalate by one tier (SAFE -> MODERATE, etc.). CRITICAL stays CRITICAL.
    public func escalated() -> RiskLevel {
        switch self {
        case .safe: return .moderate
        case .moderate: return .dangerous
        case .dangerous: return .critical
        case .critical: return .critical
        }
    }

    /// Display name with consistent width for UI alignment.
    public var displayName: String {
        rawValue.uppercased()
    }
}

// MARK: - RiskAssessment

/// The result of classifying a command's risk.
public struct RiskAssessment: Sendable {
    /// The final risk tier after all escalations.
    public let tier: RiskLevel
    /// Human-readable explanation of why this tier was assigned.
    public let rationale: String
    /// The specific rules that matched (may be empty for SAFE).
    public let matchedRules: [DangerRule]
    /// Reasons the tier was escalated beyond the base rule match.
    public let escalationReasons: [String]

    public init(
        tier: RiskLevel,
        rationale: String,
        matchedRules: [DangerRule] = [],
        escalationReasons: [String] = []
    ) {
        self.tier = tier
        self.rationale = rationale
        self.matchedRules = matchedRules
        self.escalationReasons = escalationReasons
    }
}

// MARK: - RiskClassifier

/// Deterministic, rule-based risk classifier for shell commands.
///
/// Classification is regex-based and runs in < 1ms per command.
/// The classifier is a pure function over the command string and workspace root.
/// It is NOT LLM-based — this is a critical safety system.
///
/// Reference: CLAUDE.md §19
public struct RiskClassifier: Sendable {
    public let workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
    }

    /// Classify a shell command string and return a full risk assessment.
    public func classify(_ command: String) -> RiskAssessment {
        // 1. Find all matching rules, grouped by tier
        var matchedRules: [DangerRule] = []
        var baseTier: RiskLevel = .safe

        for rule in DangerRuleCatalog.allRules where rule.matches(command) {
            matchedRules.append(rule)
            if rule.tier > baseTier {
                baseTier = rule.tier
            }
        }

        // 2. Path-based escalation
        var escalationReasons: [String] = []
        var finalTier = baseTier

        let pathEscalation = checkPathEscalation(command)
        if let (reason, forcedTier) = pathEscalation.sensitiveHit {
            escalationReasons.append(reason)
            if forcedTier > finalTier {
                finalTier = forcedTier
            }
        }
        if pathEscalation.outsideWorkspace {
            let reason = "Command references path outside workspace"
            escalationReasons.append(reason)
            let escalated = finalTier.escalated()
            if escalated > finalTier {
                finalTier = escalated
            }
        }

        // 3. Build rationale
        let rationale = buildRationale(
            command: command,
            finalTier: finalTier,
            matchedRules: matchedRules,
            escalationReasons: escalationReasons
        )

        return RiskAssessment(
            tier: finalTier,
            rationale: rationale,
            matchedRules: matchedRules,
            escalationReasons: escalationReasons
        )
    }

    // MARK: - Path Analysis

    /// Result of scanning a command for path references.
    private struct PathEscalationResult {
        /// Whether any referenced path is outside the workspace.
        var outsideWorkspace: Bool = false
        /// If a sensitive path was found: (reason, forced tier).
        var sensitiveHit: (String, RiskLevel)? = nil
    }

    /// Extract paths from a command and check for escalation conditions.
    private func checkPathEscalation(_ command: String) -> PathEscalationResult {
        var result = PathEscalationResult()
        let paths = extractPaths(from: command)
        let workspacePath = workspaceRoot.path

        for path in paths {
            // Check sensitive paths first (these force CRITICAL)
            if isSensitivePath(path) {
                result.sensitiveHit = (
                    "Path '\(path)' touches sensitive system location",
                    .critical
                )
                // Sensitive is always also outside workspace, but the reason
                // "sensitive" is more specific, so we don't double-count.
                return result
            }

            // Check if outside workspace (escalate by one tier)
            if path.hasPrefix("/") && !path.hasPrefix(workspacePath) {
                result.outsideWorkspace = true
            }
        }

        return result
    }

    /// Check if a path matches any sensitive location.
    ///
    /// Reference: CLAUDE.md §19.3
    private func isSensitivePath(_ path: String) -> Bool {
        for sensitive in DangerRuleCatalog.sensitivePaths {
            // Handle /usr exception: /usr/local is OK
            if sensitive.hasPrefix("/usr") {
                for exception in DangerRuleCatalog.sensitivePathExceptions {
                    if path.hasPrefix(exception) {
                        return false
                    }
                }
            }
            if path.hasPrefix(sensitive) {
                return true
            }
        }
        return false
    }

    /// Extract file paths referenced in a shell command.
    ///
    /// Heuristic: looks for tokens that start with `/`, `~/`, or `./`
    /// and resolves `~` to the home directory.
    internal func extractPaths(from command: String) -> [String] {
        var paths: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Tokenize by whitespace, respecting basic quoting
        let tokens = tokenize(command)

        for token in tokens {
            var resolved = token

            // Expand ~ to home dir
            if resolved.hasPrefix("~/") {
                resolved = home + String(resolved.dropFirst(1))
            } else if resolved == "~" {
                resolved = home
            }

            // Recognize absolute paths
            if resolved.hasPrefix("/") {
                paths.append(resolved)
                continue
            }

            // Recognize relative paths and resolve against workspace
            if resolved.hasPrefix("./") || resolved.hasPrefix("../") {
                let url = workspaceRoot.appendingPathComponent(resolved).standardizedFileURL
                paths.append(url.path)
            }
        }

        return paths
    }

    /// Simple tokenizer that splits on whitespace but respects single/double quotes.
    private func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaped = false

        for char in command {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            if char == "\\" && !inSingle {
                escaped = true
                continue
            }
            if char == "'" && !inDouble {
                inSingle.toggle()
                continue
            }
            if char == "\"" && !inSingle {
                inDouble.toggle()
                continue
            }
            if char.isWhitespace && !inSingle && !inDouble {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(char)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    // MARK: - Rationale

    private func buildRationale(
        command: String,
        finalTier: RiskLevel,
        matchedRules: [DangerRule],
        escalationReasons: [String]
    ) -> String {
        if matchedRules.isEmpty && escalationReasons.isEmpty {
            return "No dangerous patterns detected; classified as SAFE"
        }

        var parts: [String] = []

        if !matchedRules.isEmpty {
            let ruleDescriptions = matchedRules.map { $0.label }
            parts.append("Matched: \(ruleDescriptions.joined(separator: ", "))")
        }

        if !escalationReasons.isEmpty {
            parts.append("Escalated: \(escalationReasons.joined(separator: "; "))")
        }

        parts.append("Final classification: \(finalTier.displayName)")
        return parts.joined(separator: ". ")
    }
}
