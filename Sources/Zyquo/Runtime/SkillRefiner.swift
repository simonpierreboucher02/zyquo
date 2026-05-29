import Foundation

// MARK: - RefinementProposal

/// A proposed improvement to an underperforming skill.
///
/// Proposals are persisted next to the skill as `refinement.json` and applied
/// ONLY when the user explicitly runs `zyquo skills refine <id> --apply`. Zyquo
/// never silently rewrites a skill (CLAUDE.md §44).
public struct RefinementProposal: Sendable, Codable, Equatable {
    /// The skill this proposal targets.
    public let skillId: String
    /// One-sentence explanation of what was failing and how this helps.
    public let rationale: String
    /// A full revised prompt, or empty to keep the current prompt.
    public let newPrompt: String
    /// Suggested new step budget, or 0 to keep the current budget.
    public let suggestedMaxSteps: Int
    /// Tools to add to the allow-list.
    public let addTools: [String]
    /// Tools to remove from the allow-list.
    public let removeTools: [String]
    /// When the proposal was generated.
    public let createdAt: Date

    public init(
        skillId: String,
        rationale: String,
        newPrompt: String = "",
        suggestedMaxSteps: Int = 0,
        addTools: [String] = [],
        removeTools: [String] = [],
        createdAt: Date = Date()
    ) {
        self.skillId = skillId
        self.rationale = rationale
        self.newPrompt = newPrompt
        self.suggestedMaxSteps = suggestedMaxSteps
        self.addTools = addTools
        self.removeTools = removeTools
        self.createdAt = createdAt
    }

    /// Whether the proposal actually changes anything.
    public var hasChanges: Bool {
        !newPrompt.isEmpty || suggestedMaxSteps > 0 || !addTools.isEmpty || !removeTools.isEmpty
    }
}

// MARK: - SkillRefiner

/// Generates `RefinementProposal`s for skills whose stats show they keep
/// failing. The proposal is the "self-improving skills" half of the closed
/// learning loop; it is surfaced as a nudge and never auto-applied.
public struct SkillRefiner: Sendable {

    public init() {}

    /// Generate a refinement proposal for a skill given its stats.
    ///
    /// Returns nil if the LLM call fails or proposes no change.
    public func propose(
        skill: LoadedSkill,
        stats: SkillStats,
        provider: any LLMProvider,
        model: String,
        maxCostUSD: Double,
        now: Date = Date()
    ) async -> RefinementProposal? {
        let descriptor = ModelCatalog.find(id: model)
            ?? ModelCatalog.findByAlias(model)
            ?? ModelCatalog.claudeHaiku4_5

        let userContent = buildUserContent(skill: skill, stats: stats)

        let projectedInputTokens = ContextAssembler.estimateStringTokens(userContent)
            + ContextAssembler.estimateStringTokens(AgentPrompts.skillRefinerSystem)
        let projectedCost = Double(projectedInputTokens) * descriptor.inputPricePerMToken / 1_000_000.0
        guard projectedCost <= maxCostUSD else { return nil }

        let request = LLMRequest(
            model: model,
            systemPrompt: AgentPrompts.skillRefinerSystem,
            messages: [.user(userContent)],
            maxTokens: 1500,
            temperature: 0.2
        )

        guard let result = try? await LLMOneShot.complete(request: request, provider: provider),
              let json = LLMOneShot.extractJSONObject(from: result.text),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            return nil
        }

        let proposal = RefinementProposal(
            skillId: skill.manifest.id,
            rationale: decoded.rationale.trimmingCharacters(in: .whitespacesAndNewlines),
            newPrompt: decoded.newPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            suggestedMaxSteps: max(0, decoded.suggestedMaxSteps),
            addTools: decoded.addTools,
            removeTools: decoded.removeTools,
            createdAt: now
        )
        return proposal.hasChanges ? proposal : nil
    }

    // MARK: - Persistence helpers

    /// Path to the pending proposal file for a skill's source directory.
    public static func proposalPath(skillDirectory: URL) -> URL {
        skillDirectory.appendingPathComponent("refinement.json")
    }

    /// Persist a proposal next to its skill.
    public static func save(_ proposal: RefinementProposal, skillDirectory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(proposal)
        try data.write(to: proposalPath(skillDirectory: skillDirectory), options: .atomic)
    }

    /// Load a pending proposal from a skill's source directory, if any.
    public static func load(skillDirectory: URL) -> RefinementProposal? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: proposalPath(skillDirectory: skillDirectory)) else {
            return nil
        }
        return try? decoder.decode(RefinementProposal.self, from: data)
    }

    /// Remove a pending proposal (after apply or discard).
    public static func clear(skillDirectory: URL) {
        try? FileManager.default.removeItem(at: proposalPath(skillDirectory: skillDirectory))
    }

    // MARK: - Internal

    private struct Response: Decodable {
        let rationale: String
        let newPrompt: String
        let suggestedMaxSteps: Int
        let addTools: [String]
        let removeTools: [String]
    }

    private func buildUserContent(skill: LoadedSkill, stats: SkillStats) -> String {
        let m = skill.manifest
        var s = "Skill id: \(m.id)\n"
        s += "Risk ceiling (do not raise): \(m.riskCeiling)\n"
        s += "Current budget: \(m.budget.maxSteps) steps\n"
        s += "Allowed tools: \(m.toolsAllowed.joined(separator: ", "))\n"
        let pct = Int((stats.successRate * 100).rounded())
        s += "Runs: \(stats.runs), success rate: \(pct)%, avg steps: \(String(format: "%.1f", stats.avgSteps))\n"
        if !stats.recentFailureNotes.isEmpty {
            s += "Recent failure notes:\n"
            for note in stats.recentFailureNotes {
                s += "- \(note)\n"
            }
        }
        s += "\nCurrent prompt:\n\(skill.prompt)\n"
        s += "\nReturn the JSON described in your instructions."
        return s
    }
}
