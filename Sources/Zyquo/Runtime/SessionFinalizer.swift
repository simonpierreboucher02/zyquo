import Foundation

// MARK: - SessionFinalizer

/// Finalizes a finished agent session: persists the `SessionRecord` + event
/// log, then runs the closed learning loop. Shared by `run` and `interactive`
/// so both benefit from persistence + learning with a single call.
public enum SessionFinalizer {

    /// Persist the session and run all enabled learning passes.
    ///
    /// - Parameters:
    ///   - state: The final agent state (from `AgentRuntime.currentState()`).
    ///   - workspaceRoot: The workspace root.
    ///   - router: Model router (for distillation/refinement).
    ///   - config: Full config (provider info + learning flags).
    /// - Returns: The learning result (nudges added, model changes, etc.).
    @discardableResult
    public static func finalize(
        state: AgentState,
        workspaceRoot: URL,
        router: ModelRouter,
        config: Config,
        now: Date = Date()
    ) async -> LearningCoordinator.Result {
        // Reconstruct the persisted event log from the executed steps.
        var events: [SessionEvent] = []
        for step in state.steps {
            guard let tc = step.toolCall, let obs = step.observation else { continue }
            events.append(.toolExecuted(ToolExecutedEvent(
                timestamp: step.finishedAt ?? now,
                toolName: tc.toolName,
                summary: obs.summary,
                isError: obs.isError,
                durationMs: step.durationMs ?? obs.durationMs
            )))
        }

        let completed = state.steps.filter { $0.isComplete }.count
        let record = SessionRecord(
            sessionId: state.sessionId,
            intent: state.intent,
            planSteps: state.plan.steps.map { PersistablePlanStep(from: $0) },
            status: state.status.rawValue,
            model: config.providers.resolvedModel,
            provider: config.providers.resolvedProvider,
            totalInputTokens: state.cost.totalInputTokens,
            totalOutputTokens: state.cost.totalOutputTokens,
            totalCostUSD: state.cost.totalCostUSD,
            startedAt: state.startedAt,
            updatedAt: state.updatedAt,
            stepsCompleted: completed,
            stepsTotal: state.plan.steps.count
        )

        // Persist session record + events under the workspace memory dir.
        let sessionsDir = workspaceRoot
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("memory")
            .appendingPathComponent("sessions")
        let store = SessionStore(baseDir: sessionsDir)
        try? await store.save(record)
        for event in events {
            try? await store.appendEvent(sessionId: state.sessionId, event: event)
        }

        // Run the closed learning loop.
        let summary = Summarizer().summarize(state: state)
        return await LearningCoordinator().runPostSession(
            summary: summary,
            sessionRecord: record,
            events: events,
            workspaceRoot: workspaceRoot,
            router: router,
            config: config.learning,
            now: now
        )
    }

    // MARK: - Rendering

    /// Render a calm panel of any nudges the learning loop produced. No-op when
    /// there is nothing to show.
    public static func renderNudges(_ result: LearningCoordinator.Result, noColor: Bool) {
        guard !result.addedNudges.isEmpty else { return }

        print()
        if noColor {
            print("  Learning")
            print("  \(String(repeating: "-", count: 50))")
            for nudge in result.addedNudges {
                print("  • \(nudge.message)")
                if let cmd = nudge.actionCommand {
                    print("      \(cmd)")
                }
            }
        } else {
            print("  \u{1B}[1m\u{2728} Learning\u{1B}[0m")
            print("  \u{1B}[2m\(String(repeating: "\u{2500}", count: 50))\u{1B}[0m")
            for nudge in result.addedNudges {
                print("  \u{1B}[36m•\u{1B}[0m \(nudge.message)")
                if let cmd = nudge.actionCommand {
                    print("      \u{1B}[2m\(cmd)\u{1B}[0m")
                }
            }
        }
        print()
    }
}
