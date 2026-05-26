import Foundation

// MARK: - StopReason

/// Why the agent loop terminated.
public enum AgentStopReason: Sendable, CustomStringConvertible {
    /// Hard stop: maximum number of steps reached.
    case maxStepsReached(limit: Int)
    /// Hard stop: session cost exceeded the budget.
    case maxCostReached(cost: Double, limit: Double)
    /// Hard stop: user cancelled the operation.
    case userCancellation
    /// Hard stop: 3+ consecutive tool failures on different steps.
    case consecutiveFailures(count: Int)
    /// Soft stop: all plan steps have been completed.
    case planCompleted
    /// Soft stop: same tool call hash repeated N times in a window.
    case loopDetected(toolCallHash: String, count: Int)
    /// Soft stop: too many consecutive unclear verdicts.
    case consecutiveUnclearVerdicts(count: Int)

    public var isHard: Bool {
        switch self {
        case .maxStepsReached, .maxCostReached, .userCancellation, .consecutiveFailures:
            return true
        case .planCompleted, .loopDetected, .consecutiveUnclearVerdicts:
            return false
        }
    }

    public var description: String {
        switch self {
        case .maxStepsReached(let limit):
            return "Maximum steps reached (\(limit))"
        case .maxCostReached(let cost, let limit):
            return String(format: "Cost limit reached ($%.2f / $%.2f)", cost, limit)
        case .userCancellation:
            return "Cancelled by user"
        case .consecutiveFailures(let count):
            return "\(count) consecutive tool failures"
        case .planCompleted:
            return "Plan completed successfully"
        case .loopDetected(let hash, let count):
            return "Loop detected: tool call \(hash) repeated \(count) times"
        case .consecutiveUnclearVerdicts(let count):
            return "\(count) consecutive unclear verdicts"
        }
    }
}

// MARK: - StopConditions

/// Evaluates whether the agent loop should terminate.
///
/// Hard stops cannot be overridden; soft stops allow the agent to
/// ask the user whether to continue.
///
/// Reference: CLAUDE.md §16.3
public struct StopConditions: Sendable {

    /// Evaluate current agent state against configuration limits.
    ///
    /// - Parameters:
    ///   - state: The current agent state.
    ///   - config: Agent configuration (max steps, max cost, etc.).
    /// - Returns: A stop reason if the agent should stop, or nil to continue.
    public static func evaluate(state: AgentState, config: AgentConfig) -> AgentStopReason? {
        // Hard stop: max steps
        if state.steps.count >= config.maxSteps {
            return .maxStepsReached(limit: config.maxSteps)
        }

        // Hard stop: max cost
        if state.cost.totalCostUSD >= config.maxCostUSD {
            return .maxCostReached(cost: state.cost.totalCostUSD, limit: config.maxCostUSD)
        }

        // Hard stop: 3 consecutive tool failures
        if state.consecutiveFailures >= 3 {
            return .consecutiveFailures(count: state.consecutiveFailures)
        }

        // Soft stop: plan completed
        if state.plan.isComplete && !state.plan.steps.isEmpty {
            let completedCount = state.steps.filter { $0.isComplete }.count
            if completedCount >= state.plan.steps.count {
                return .planCompleted
            }
        }

        // Soft stop: loop detection (same tool call hash 3x in window of 5)
        if let loop = state.detectLoop(threshold: 3, windowSize: 5) {
            return .loopDetected(toolCallHash: loop.hash, count: loop.count)
        }

        // Soft stop: 5 consecutive unclear verdicts
        if state.consecutiveUnclearVerdicts >= 5 {
            return .consecutiveUnclearVerdicts(count: state.consecutiveUnclearVerdicts)
        }

        return nil
    }
}
