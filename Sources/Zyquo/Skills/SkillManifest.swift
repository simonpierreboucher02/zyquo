import Foundation

// MARK: - SkillManifest

/// Definition of a Zyquo skill — a versioned, prompted workflow with
/// constrained tool access and budget enforcement.
///
/// Skills are loaded from YAML files (`skill.yaml`) that live alongside
/// a `prompt.md` file in a skill directory. The manifest declares which
/// tools the skill may invoke, what risk level it cannot exceed, and
/// resource budgets (steps, cost).
///
/// Reference: CLAUDE.md §30 Phase 6, Appendix B
public struct SkillManifest: Sendable, Codable, Equatable {
    /// Stable identifier, e.g. "fix_swift_build".
    public let id: String
    /// Semantic version string, e.g. "0.1.0".
    public let version: String
    /// Human-readable title shown in `zyquo skills list`.
    public let title: String
    /// Optional longer description of what the skill does.
    public let description: String?
    /// Authors of this skill.
    public let authors: [String]
    /// Typed input parameters the skill accepts.
    public let inputs: [SkillInput]
    /// The set of tool names this skill is permitted to invoke.
    public let toolsAllowed: [String]
    /// Relative path to the prompt markdown file (e.g. "./prompt.md").
    public let promptFile: String
    /// Optional verification step run after skill completion.
    public let verify: SkillVerification?
    /// Resource budget for this skill run.
    public let budget: SkillBudget
    /// Maximum risk tier this skill is allowed to reach (e.g. "MODERATE").
    public let riskCeiling: String

    public init(
        id: String,
        version: String,
        title: String,
        description: String? = nil,
        authors: [String] = [],
        inputs: [SkillInput] = [],
        toolsAllowed: [String] = [],
        promptFile: String = "./prompt.md",
        verify: SkillVerification? = nil,
        budget: SkillBudget = SkillBudget(),
        riskCeiling: String = "MODERATE"
    ) {
        self.id = id
        self.version = version
        self.title = title
        self.description = description
        self.authors = authors
        self.inputs = inputs
        self.toolsAllowed = toolsAllowed
        self.promptFile = promptFile
        self.verify = verify
        self.budget = budget
        self.riskCeiling = riskCeiling
    }

    /// Map the string `riskCeiling` to a typed `RiskLevel`.
    /// Falls back to `.moderate` for unrecognized values.
    public var resolvedRiskCeiling: RiskLevel {
        switch riskCeiling.lowercased() {
        case "safe": return .safe
        case "moderate": return .moderate
        case "dangerous": return .dangerous
        case "critical": return .critical
        default: return .moderate
        }
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id, version, title, description, authors, inputs
        case toolsAllowed = "tools_allowed"
        case promptFile = "prompt"
        case verify, budget
        case riskCeiling = "risk_ceiling"
    }

    // MARK: - Custom Decoder

    /// Custom decoder to handle optional fields with defaults.
    /// YAML manifests may omit `authors`, `inputs`, `description`, and `verify`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        version = try container.decode(String.self, forKey: .version)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
        inputs = try container.decodeIfPresent([SkillInput].self, forKey: .inputs) ?? []
        toolsAllowed = try container.decodeIfPresent([String].self, forKey: .toolsAllowed) ?? []
        promptFile = try container.decodeIfPresent(String.self, forKey: .promptFile) ?? "./prompt.md"
        verify = try container.decodeIfPresent(SkillVerification.self, forKey: .verify)
        budget = try container.decodeIfPresent(SkillBudget.self, forKey: .budget) ?? SkillBudget()
        riskCeiling = try container.decodeIfPresent(String.self, forKey: .riskCeiling) ?? "MODERATE"
    }
}

// MARK: - SkillInput

/// A typed input parameter for a skill.
public struct SkillInput: Sendable, Codable, Equatable {
    /// Parameter name used as the key in input dictionaries.
    public let name: String
    /// Type of the parameter: "string", "path", "bool", "int".
    public let type: String
    /// Whether this input must be provided.
    public let required: Bool
    /// Optional human-readable description.
    public let description: String?
    /// Optional default value (as a string representation).
    public let defaultValue: String?

    public init(
        name: String,
        type: String = "string",
        required: Bool = false,
        description: String? = nil,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.required = required
        self.description = description
        self.defaultValue = defaultValue
    }

    enum CodingKeys: String, CodingKey {
        case name, type, required, description
        case defaultValue = "default"
    }
}

// MARK: - SkillVerification

/// A verification command run after a skill completes to check success.
public struct SkillVerification: Sendable, Codable, Equatable {
    /// Shell command to run for verification (e.g. "swift test").
    public let command: String
    /// Expected exit code (typically 0).
    public let expectExitCode: Int

    public init(command: String, expectExitCode: Int = 0) {
        self.command = command
        self.expectExitCode = expectExitCode
    }

    enum CodingKeys: String, CodingKey {
        case command
        case expectExitCode = "expect_exit_code"
    }
}

// MARK: - SkillBudget

/// Resource budget for a skill execution.
public struct SkillBudget: Sendable, Codable, Equatable {
    /// Maximum number of agent steps allowed.
    public let maxSteps: Int
    /// Maximum cost in USD allowed.
    public let maxCostUSD: Double

    public init(maxSteps: Int = 25, maxCostUSD: Double = 2.0) {
        self.maxSteps = maxSteps
        self.maxCostUSD = maxCostUSD
    }

    enum CodingKeys: String, CodingKey {
        case maxSteps = "max_steps"
        case maxCostUSD = "max_cost_usd"
    }
}
