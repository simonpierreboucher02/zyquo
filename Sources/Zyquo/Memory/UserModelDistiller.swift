import Foundation

// MARK: - UserModelDistiller

/// Distills durable facts about the user from a finished session and merges
/// them into the persistent `UserModel`.
///
/// This is the learning half of the dialectic user model: after a session, a
/// cheap LLM pass (Haiku by default) proposes generalizable observations about
/// the person — never about the project — which are merged with confidence
/// reinforcement. The pass is cost-bounded and entirely best-effort: any
/// failure leaves the existing model untouched.
public struct UserModelDistiller: Sendable {

    /// Outcome of a distillation pass.
    public struct Outcome: Sendable {
        /// The updated model (== input model if nothing changed).
        public let model: UserModel
        /// How many observations were proposed this pass.
        public let proposedCount: Int
        /// Cost incurred by the distillation LLM call.
        public let cost: SessionCost
        /// Whether the model actually changed.
        public var changed: Bool { proposedCount > 0 }
    }

    public init() {}

    /// Run a distillation pass.
    ///
    /// - Parameters:
    ///   - summary: The finished session summary.
    ///   - sessionId: The session's id (recorded as evidence source).
    ///   - current: The current persisted user model.
    ///   - provider: LLM provider.
    ///   - model: Model id to use (a cheap model is recommended).
    ///   - maxCostUSD: Hard cap; if the projected input cost exceeds this, the
    ///     pass is skipped and the model returned unchanged.
    ///   - now: Injectable clock for deterministic tests.
    /// - Returns: An `Outcome` with the (possibly unchanged) model.
    public func distill(
        summary: SessionSummary,
        sessionId: String,
        current: UserModel,
        provider: any LLMProvider,
        model: String,
        maxCostUSD: Double,
        now: Date = Date()
    ) async -> Outcome {
        let unchanged = Outcome(model: current, proposedCount: 0, cost: SessionCost())

        let userContent = buildUserContent(summary: summary, current: current)
        let descriptor = ModelCatalog.find(id: model)
            ?? ModelCatalog.findByAlias(model)
            ?? ModelCatalog.claudeHaiku4_5

        // Cheap projected-cost guard: don't even call if the input alone would
        // blow the cap (output is small and bounded by maxTokens).
        let projectedInputTokens = ContextAssembler.estimateStringTokens(userContent)
            + ContextAssembler.estimateStringTokens(AgentPrompts.userModelDistillerSystem)
        let projectedCost = Double(projectedInputTokens) * descriptor.inputPricePerMToken / 1_000_000.0
        guard projectedCost <= maxCostUSD else { return unchanged }

        let request = LLMRequest(
            model: model,
            systemPrompt: AgentPrompts.userModelDistillerSystem,
            messages: [.user(userContent)],
            maxTokens: 700,
            temperature: 0.2
        )

        guard let result = try? await LLMOneShot.complete(request: request, provider: provider) else {
            return unchanged
        }

        var cost = SessionCost()
        if let usage = result.usage {
            cost.record(usage: usage, model: descriptor)
        }

        let proposed = parseObservations(from: result.text, sessionId: sessionId, now: now)
        guard !proposed.isEmpty else {
            return Outcome(model: current, proposedCount: 0, cost: cost)
        }

        let merged = current.merging(proposed, now: now).decayed(now: now)
        return Outcome(model: merged, proposedCount: proposed.count, cost: cost)
    }

    // MARK: - Prompt Construction

    private func buildUserContent(summary: SessionSummary, current: UserModel) -> String {
        var s = "Existing user model:\n"
        if let rendered = current.renderForContext(maxTokens: 300, minConfidence: 0.0) {
            s += rendered + "\n"
        } else {
            s += "(empty)\n"
        }
        s += "\nFinished session to learn from:\n"
        s += "- Intent: \(summary.intent)\n"
        s += "- Outcome: \(summary.outcome)\n"
        if !summary.commandsRun.isEmpty {
            let cmds = summary.commandsRun.prefix(12).joined(separator: "; ")
            s += "- Commands run: \(cmds)\n"
        }
        if !summary.filesModified.isEmpty {
            let files = summary.filesModified.prefix(15).joined(separator: ", ")
            s += "- Files touched: \(files)\n"
        }
        s += "\nReturn the JSON described in your instructions."
        return s
    }

    // MARK: - Parsing

    private struct DistillResponse: Decodable {
        struct Obs: Decodable {
            let trait: String
            let statement: String
            let confidence: Double
        }
        let observations: [Obs]
    }

    private func parseObservations(
        from text: String,
        sessionId: String,
        now: Date
    ) -> [UserObservation] {
        guard let json = LLMOneShot.extractJSONObject(from: text),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DistillResponse.self, from: data) else {
            return []
        }

        var result: [UserObservation] = []
        for obs in decoded.observations {
            let statement = obs.statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !statement.isEmpty,
                  let trait = UserTrait(rawValue: obs.trait) else {
                continue
            }
            result.append(UserObservation(
                id: UserObservation.makeId(trait: trait, statement: statement),
                trait: trait,
                statement: statement,
                confidence: obs.confidence,
                evidenceCount: 1,
                firstSeen: now,
                lastSeen: now,
                sourceSessions: [sessionId]
            ))
        }
        return result
    }
}
