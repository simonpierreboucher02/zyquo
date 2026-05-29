import Foundation
import Logging

// MARK: - LearningCoordinator

/// The single integration point for Zyquo's closed learning loop.
///
/// Called once at the end of a session, it runs — best-effort, cost-bounded,
/// and behind config flags — the four learning passes:
///   1. distill the persistent user model from the session,
///   2. extract a reusable skill candidate (awaiting accept/reject),
///   3. propose refinements for underperforming skills,
///   4. surface learning nudges.
///
/// Nothing here mutates a skill or applies a refinement on its own; it only
/// records the persistent user model (agent-owned), saves candidates/proposals
/// for review, and adds nudges (CLAUDE.md §6 "approval over autonomy").
public struct LearningCoordinator: Sendable {

    /// What the post-session pass produced, for the CLI to display.
    public struct Result: Sendable {
        public let addedNudges: [LearningNudge]
        public let userModelObservationsAdded: Int
        public let candidateExtracted: String?
        public let refinedSkillIds: [String]
        public let cost: SessionCost

        public static let empty = Result(
            addedNudges: [], userModelObservationsAdded: 0,
            candidateExtracted: nil, refinedSkillIds: [], cost: SessionCost()
        )
    }

    private let logger: Logging.Logger

    public init(logger: Logging.Logger = ZyquoLogger.shared) {
        self.logger = logger
    }

    /// Run all enabled learning passes for a finished session.
    public func runPostSession(
        summary: SessionSummary,
        sessionRecord: SessionRecord,
        events: [SessionEvent],
        workspaceRoot: URL,
        router: ModelRouter,
        config: LearningConfig,
        now: Date = Date()
    ) async -> Result {
        guard config.enabled else { return .empty }

        let resolved = await router.resolve(for: .summarization)
        var cost = SessionCost()

        // 1. User-model distillation (LLM).
        var observationsAdded = 0
        if config.userModel, let (provider, model) = resolved {
            let store = UserModelStore()
            let current = await store.load()
            let outcome = await UserModelDistiller().distill(
                summary: summary,
                sessionId: sessionRecord.sessionId.value,
                current: current,
                provider: provider,
                model: model,
                maxCostUSD: config.maxDistillCostUSD,
                now: now
            )
            cost = combine(cost, outcome.cost, model: model)
            if outcome.changed {
                try? await store.save(outcome.model)
                observationsAdded = outcome.proposedCount
                logger.info("User model updated", metadata: ["added": "\(observationsAdded)"])
            }
        }

        // 2. Skill candidate extraction (rule-based).
        var candidateId: String?
        var viableCandidate: ExtractedSkillCandidate?
        if config.skillExtraction,
           let candidate = SkillExtractor().analyze(session: sessionRecord, events: events),
           candidate.isViable {
            viableCandidate = candidate
            let store = SkillCandidateStore()
            let alreadyExists = await store.exists(id: candidate.suggestedId)
            if !alreadyExists {
                try? await store.save(candidate)
                candidateId = candidate.suggestedId
                logger.info("Skill candidate extracted", metadata: ["id": "\(candidate.suggestedId)"])
            }
        }

        // 3. Skill refinement proposals (LLM, at most one per pass).
        var refinedIds: [String] = []
        if let (provider, model) = resolved {
            refinedIds = await proposeRefinements(
                workspaceRoot: workspaceRoot,
                provider: provider,
                model: model,
                config: config,
                now: now
            )
        }

        // 4. Stale-memory detection (rule-based).
        let (stale, sessionsSince) = detectStaleMemory(
            workspaceRoot: workspaceRoot,
            threshold: config.staleMemorySessions
        )

        // 5. Nudges (rule-based).
        var added: [LearningNudge] = []
        if config.nudges {
            let signals = NudgeEngine.Signals(
                skillCandidate: candidateId != nil ? viableCandidate : nil,
                refinedSkillIds: refinedIds,
                projectMemoryStale: stale,
                sessionsSinceMemoryUpdate: sessionsSince,
                userModelObservationsAdded: observationsAdded
            )
            let nudges = NudgeEngine().generate(from: signals, now: now)
            if !nudges.isEmpty {
                added = (try? await NudgeStore().add(nudges)) ?? []
            }
        }

        return Result(
            addedNudges: added,
            userModelObservationsAdded: observationsAdded,
            candidateExtracted: candidateId,
            refinedSkillIds: refinedIds,
            cost: cost
        )
    }

    // MARK: - Refinement

    private func proposeRefinements(
        workspaceRoot: URL,
        provider: any LLMProvider,
        model: String,
        config: LearningConfig,
        now: Date
    ) async -> [String] {
        let loader = SkillLoader()
        let skills = loader.discoverSkills(
            searchPaths: SkillLoader.defaultSearchPaths(workspaceRoot: workspaceRoot)
        )
        guard !skills.isEmpty else { return [] }

        let statsStore = SkillStatsStore()
        let refiner = SkillRefiner()

        // Find the single worst-performing eligible skill without a pending proposal.
        var worst: (skill: LoadedSkill, stats: SkillStats)?
        for skill in skills {
            let stats = await statsStore.load(id: skill.manifest.id)
            guard stats.warrantsRefinement(minRuns: config.skillRefineMinRuns) else { continue }
            guard SkillRefiner.load(skillDirectory: skill.sourcePath) == nil else { continue }
            if worst == nil || stats.successRate < worst!.stats.successRate {
                worst = (skill, stats)
            }
        }

        guard let target = worst else { return [] }

        guard let proposal = await refiner.propose(
            skill: target.skill,
            stats: target.stats,
            provider: provider,
            model: model,
            maxCostUSD: config.maxDistillCostUSD,
            now: now
        ) else {
            return []
        }

        try? SkillRefiner.save(proposal, skillDirectory: target.skill.sourcePath)
        logger.info("Skill refinement proposed", metadata: ["id": "\(target.skill.manifest.id)"])
        return [target.skill.manifest.id]
    }

    // MARK: - Stale Memory

    private func detectStaleMemory(
        workspaceRoot: URL,
        threshold: Int
    ) -> (stale: Bool, sessionsSince: Int) {
        let fm = FileManager.default
        let memoryDir = workspaceRoot
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("memory")
        let projectPath = memoryDir.appendingPathComponent("project.md")

        // No project memory yet → nothing to refresh.
        guard fm.fileExists(atPath: projectPath.path),
              let attrs = try? fm.attributesOfItem(atPath: projectPath.path),
              let mtime = attrs[.modificationDate] as? Date else {
            return (false, 0)
        }

        let sessionsDir = memoryDir.appendingPathComponent("sessions")
        guard let files = try? fm.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return (false, 0)
        }

        let sessionsSince = files
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.contains(".events.") }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .filter { $0 > mtime }
            .count

        return (sessionsSince >= threshold, sessionsSince)
    }

    // MARK: - Helpers

    private func combine(_ base: SessionCost, _ add: SessionCost, model: String) -> SessionCost {
        // SessionCost only exposes a `record(usage:model:)` mutator, so fold the
        // added totals back through a synthetic usage entry.
        let descriptor = ModelCatalog.find(id: model)
            ?? ModelCatalog.findByAlias(model)
            ?? ModelCatalog.claudeHaiku4_5
        var result = base
        let usage = TokenUsage(
            inputTokens: add.totalInputTokens,
            outputTokens: add.totalOutputTokens,
            cacheReadTokens: add.totalCacheReadTokens,
            cacheWriteTokens: add.totalCacheWriteTokens
        )
        result.record(usage: usage, model: descriptor)
        return result
    }
}
