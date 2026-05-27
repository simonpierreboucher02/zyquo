import Foundation

/// A single danger-detection rule mapping a regex pattern to a risk tier.
public struct DangerRule: Sendable, Equatable, CustomStringConvertible {
    /// The risk tier this rule classifies to.
    public let tier: RiskLevel
    /// Human-readable label describing what the rule detects.
    public let label: String
    /// The regex pattern string (stored for diagnostics).
    public let pattern: String
    /// Compiled regex for matching.
    internal let regex: NSRegularExpression

    public init(tier: RiskLevel, label: String, pattern: String) {
        self.tier = tier
        self.label = label
        self.pattern = pattern
        // Force-unwrap is acceptable here: these are compile-time constants.
        // A bad pattern is a programmer error that must fail immediately.
        // swiftlint:disable:next force_try
        self.regex = try! NSRegularExpression(pattern: pattern, options: [])
    }

    /// Test whether the rule matches the given command string.
    public func matches(_ command: String) -> Bool {
        let range = NSRange(command.startIndex..., in: command)
        return regex.firstMatch(in: command, range: range) != nil
    }

    public var description: String {
        "[\(tier.rawValue.uppercased())] \(label)"
    }

    public static func == (lhs: DangerRule, rhs: DangerRule) -> Bool {
        lhs.tier == rhs.tier && lhs.label == rhs.label && lhs.pattern == rhs.pattern
    }
}

// MARK: - Canonical Rule Catalog

/// The complete catalog of danger-detection rules, organized by tier.
///
/// Rules are evaluated highest-tier-first (CRITICAL > DANGEROUS > MODERATE).
/// If no rule matches, the command is classified as SAFE.
///
/// Reference: CLAUDE.md §19.2
public enum DangerRuleCatalog {

    // MARK: CRITICAL

    public static let critical: [DangerRule] = [
        DangerRule(tier: .critical, label: "sudo invocation",
                   pattern: #"(?:^|\s|;|&&|\|\|)\s*sudo\b"#),
        DangerRule(tier: .critical, label: "curl pipe to shell",
                   pattern: #"\bcurl\s+[^|]*\|\s*(sh|bash|zsh)\b"#),
        DangerRule(tier: .critical, label: "wget pipe to shell",
                   pattern: #"\bwget\s+[^|]*\|\s*(sh|bash|zsh)\b"#),
        DangerRule(tier: .critical, label: "git push",
                   pattern: #"\bgit\s+push\b"#),
        DangerRule(tier: .critical, label: "git reset --hard",
                   pattern: #"\bgit\s+reset\s+--hard\b"#),
        DangerRule(tier: .critical, label: "diskutil invocation",
                   pattern: #"\bdiskutil\b"#),
        DangerRule(tier: .critical, label: "launchctl invocation",
                   pattern: #"\blaunchctl\b"#),
        DangerRule(tier: .critical, label: "npm global install",
                   pattern: #"\bnpm\s+install\s+-g\b"#),
        DangerRule(tier: .critical, label: "npm global install (alt)",
                   pattern: #"\bnpm\s+i\s+-g\b"#),
        DangerRule(tier: .critical, label: "yarn global add",
                   pattern: #"\byarn\s+global\s+add\b"#),
        DangerRule(tier: .critical, label: "pnpm global add",
                   pattern: #"\bpnpm\s+add\s+-g\b"#),
        DangerRule(tier: .critical, label: "brew install",
                   pattern: #"\bbrew\s+install\b"#),
        DangerRule(tier: .critical, label: "brew uninstall",
                   pattern: #"\bbrew\s+uninstall\b"#),
        DangerRule(tier: .critical, label: "brew remove",
                   pattern: #"\bbrew\s+remove\b"#),
        DangerRule(tier: .critical, label: "pip global install",
                   pattern: #"\bpip3?\s+install\b(?!.*--user)(?!.*-t\s)(?!.*--target)"#),
        DangerRule(tier: .critical, label: "eval of shell content",
                   pattern: #"\beval\s+"#),
        DangerRule(tier: .critical, label: "osascript with shell script",
                   pattern: #"\bosascript\b.*do shell script"#),
        DangerRule(tier: .critical, label: "osascript with sudo/admin",
                   pattern: #"\bosascript\b.*(?:sudo|administrator privileges)"#),
        DangerRule(tier: .critical, label: "osascript shutdown/restart",
                   pattern: #"\bosascript\b.*(?:shut down|restart|sleep)"#),
    ]

    // MARK: DANGEROUS

    public static let dangerous: [DangerRule] = [
        DangerRule(tier: .dangerous, label: "recursive remove",
                   pattern: #"\brm\s+(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)\b"#),
        DangerRule(tier: .dangerous, label: "recursive chmod",
                   pattern: #"\bchmod\s+(-[a-zA-Z]*R[a-zA-Z]*|--recursive)\b"#),
        DangerRule(tier: .dangerous, label: "recursive chown",
                   pattern: #"\bchown\s+(-[a-zA-Z]*R[a-zA-Z]*|--recursive)\b"#),
        DangerRule(tier: .dangerous, label: "cross-root mv",
                   pattern: #"\bmv\s+/[^ ]+\s+/[^ ]+"#),
        DangerRule(tier: .dangerous, label: "find with -delete",
                   pattern: #"\bfind\b.*-delete\b"#),
        DangerRule(tier: .dangerous, label: "write to raw disk",
                   pattern: #">\s*/dev/(disk|rdisk)"#),
        DangerRule(tier: .dangerous, label: "dd command",
                   pattern: #"\bdd\s+if="#),
        DangerRule(tier: .dangerous, label: "mkfs/format",
                   pattern: #"\b(mkfs|newfs)\b"#),
        DangerRule(tier: .dangerous, label: "git force push",
                   pattern: #"\bgit\s+push\s+.*(-f|--force)\b"#),
        DangerRule(tier: .dangerous, label: "git clean -f",
                   pattern: #"\bgit\s+clean\s+.*-[a-zA-Z]*f"#),
        DangerRule(tier: .dangerous, label: "kill all processes",
                   pattern: #"\bkillall\b"#),
    ]

    // MARK: MODERATE

    public static let moderate: [DangerRule] = [
        DangerRule(tier: .moderate, label: "git commit",
                   pattern: #"\bgit\s+commit\b"#),
        DangerRule(tier: .moderate, label: "git checkout/switch/branch",
                   pattern: #"\bgit\s+(checkout|switch|branch)\b"#),
        DangerRule(tier: .moderate, label: "npm install (local)",
                   pattern: #"\bnpm\s+(install|i|ci)\b"#),
        DangerRule(tier: .moderate, label: "yarn install",
                   pattern: #"\byarn\s+(install|add)\b"#),
        DangerRule(tier: .moderate, label: "pnpm install",
                   pattern: #"\bpnpm\s+(install|add|i)\b"#),
        DangerRule(tier: .moderate, label: "cargo install",
                   pattern: #"\bcargo\s+install\b"#),
        DangerRule(tier: .moderate, label: "pip install (user/venv)",
                   pattern: #"\bpip3?\s+install\s+.*(--user|-t\s|--target)"#),
        DangerRule(tier: .moderate, label: "redirect write (overwrite)",
                   pattern: #"(?<![>12])>\s*[^ &|>]+"#),
        DangerRule(tier: .moderate, label: "redirect write (append)",
                   pattern: #">>\s*[^ &|]+"#),
        DangerRule(tier: .moderate, label: "git stash",
                   pattern: #"\bgit\s+stash\b"#),
        DangerRule(tier: .moderate, label: "git merge",
                   pattern: #"\bgit\s+merge\b"#),
        DangerRule(tier: .moderate, label: "git rebase",
                   pattern: #"\bgit\s+rebase\b"#),
        DangerRule(tier: .moderate, label: "git tag",
                   pattern: #"\bgit\s+tag\b"#),
        DangerRule(tier: .moderate, label: "git fetch",
                   pattern: #"\bgit\s+fetch\b"#),
        DangerRule(tier: .moderate, label: "git pull",
                   pattern: #"\bgit\s+pull\b"#),
        DangerRule(tier: .moderate, label: "touch command",
                   pattern: #"\btouch\b"#),
        DangerRule(tier: .moderate, label: "mkdir command",
                   pattern: #"\bmkdir\b"#),
        DangerRule(tier: .moderate, label: "cp command",
                   pattern: #"\bcp\b"#),
        DangerRule(tier: .moderate, label: "osascript execution",
                   pattern: #"\bosascript\b"#),
    ]

    // MARK: All Rules

    /// All rules ordered from highest tier to lowest.
    /// The classifier evaluates them in this order and takes the highest match.
    public static let allRules: [DangerRule] = critical + dangerous + moderate

    // MARK: Sensitive Paths

    /// Path prefixes that, when touched by a command, escalate to CRITICAL regardless.
    /// Reference: CLAUDE.md §19.3
    public static let sensitivePaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            home + "/.ssh",
            home + "/.aws",
            home + "/.config",
            home + "/Library",
            "/System",
            "/Library",
            "/private",
            "/usr/bin",
            "/usr/sbin",
            "/usr/lib",
        ]
    }()

    /// Path prefixes where `/usr/local` is excluded from the `/usr` catch-all.
    public static let sensitivePathExceptions: [String] = [
        "/usr/local",
    ]
}
