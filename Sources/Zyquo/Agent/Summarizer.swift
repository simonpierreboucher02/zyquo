import Foundation

// MARK: - SessionSummary

/// A structured summary of a completed agent session.
public struct SessionSummary: Sendable {
    /// The user's original intent.
    public let intent: String
    /// How many steps were completed.
    public let stepsCompleted: Int
    /// Total planned steps.
    public let stepsTotal: Int
    /// Files that were modified during the session.
    public let filesModified: [String]
    /// Shell commands that were run.
    public let commandsRun: [String]
    /// Total token usage across all LLM calls.
    public let tokensUsed: TokenUsage
    /// Cumulative session cost.
    public let cost: SessionCost
    /// Total wall-clock duration.
    public let duration: TimeInterval
    /// Human-readable outcome description.
    public let outcome: String

    public init(
        intent: String,
        stepsCompleted: Int,
        stepsTotal: Int,
        filesModified: [String],
        commandsRun: [String],
        tokensUsed: TokenUsage,
        cost: SessionCost,
        duration: TimeInterval,
        outcome: String
    ) {
        self.intent = intent
        self.stepsCompleted = stepsCompleted
        self.stepsTotal = stepsTotal
        self.filesModified = filesModified
        self.commandsRun = commandsRun
        self.tokensUsed = tokensUsed
        self.cost = cost
        self.duration = duration
        self.outcome = outcome
    }

    /// Formatted duration string (e.g. "1m 23s").
    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Compact one-line summary.
    public var oneLiner: String {
        "\(stepsCompleted)/\(stepsTotal) steps · \(formattedDuration) · \(cost.formattedCost) · \(outcome)"
    }
}

// MARK: - Summarizer

/// Produces a SessionSummary from the final AgentState.
///
/// This is a local-only summarizer (no LLM call). It extracts structured
/// data from the step history. An LLM-backed summarizer for memory
/// compression is planned for Phase 9.
///
/// Reference: CLAUDE.md §35.4
public struct Summarizer: Sendable {

    public init() {}

    /// Summarize a completed (or terminated) agent session.
    ///
    /// - Parameter state: The final agent state.
    /// - Returns: A structured session summary.
    public func summarize(state: AgentState) -> SessionSummary {
        let completedSteps = state.steps.filter { $0.isComplete }
        let passedSteps = state.steps.filter { $0.verdict == .pass }
        let failedSteps = state.steps.filter { $0.verdict == .fail }

        // Extract files modified from file.write / file.patch tool calls
        var filesModified: [String] = []
        var commandsRun: [String] = []

        for step in state.steps {
            guard let tc = step.toolCall else { continue }
            switch tc.toolName {
            case "file.write", "file.patch", "file.move", "file.delete", "file.copy":
                if let path = tc.input["path"]?.stringValue {
                    filesModified.append(path)
                }
            case "shell.run":
                if let cmd = tc.input["command"]?.stringValue {
                    commandsRun.append(cmd)
                }
            default:
                break
            }
        }

        // Deduplicate
        filesModified = Array(Set(filesModified)).sorted()

        // Build outcome string
        let outcome: String
        switch state.status {
        case .done:
            if failedSteps.isEmpty {
                outcome = "Completed successfully"
            } else {
                outcome = "Completed with \(failedSteps.count) failed step(s)"
            }
        case .cancelled:
            outcome = "Cancelled by user"
        case .failed:
            outcome = "Failed after \(completedSteps.count) step(s)"
        case .blocked:
            outcome = "Blocked (approval required)"
        default:
            outcome = "Ended in \(state.status.rawValue) state"
        }

        // Aggregate token usage
        let totalTokens = TokenUsage(
            inputTokens: state.cost.totalInputTokens,
            outputTokens: state.cost.totalOutputTokens,
            cacheReadTokens: state.cost.totalCacheReadTokens,
            cacheWriteTokens: state.cost.totalCacheWriteTokens
        )

        return SessionSummary(
            intent: state.intent,
            stepsCompleted: completedSteps.count,
            stepsTotal: state.plan.steps.count,
            filesModified: filesModified,
            commandsRun: commandsRun,
            tokensUsed: totalTokens,
            cost: state.cost,
            duration: state.elapsed,
            outcome: outcome
        )
    }
}
