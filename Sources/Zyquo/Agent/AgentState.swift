import Foundation

// MARK: - SessionID

/// Unique identifier for an agent session.
/// Format: "zq_<yyyymmdd>_<short-uuid>"
public struct SessionID: Sendable, Hashable, CustomStringConvertible, Codable {
    public let value: String

    public init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateStr = formatter.string(from: Date())
        let random = UInt32.random(in: 0...0xFFFF)
        self.value = "zq_\(dateStr)_\(String(random, radix: 16, uppercase: false))"
    }

    public init(value: String) {
        self.value = value
    }

    public var description: String { value }
}

// MARK: - AgentStatus

/// The current phase of the agent runtime.
public enum AgentStatus: String, Sendable, CaseIterable {
    case planning
    case executing
    case verifying
    case blocked
    case done
    case cancelled
    case failed
}

// MARK: - AgentState

/// The mutable state of an agent session. Owned by AgentRuntime (actor-isolated).
public struct AgentState: Sendable {
    /// The session identifier.
    public let sessionId: SessionID
    /// The user's original intent.
    public let intent: String
    /// The current plan.
    public var plan: Plan
    /// Executed steps (append-only during a session).
    public var steps: [AgentStep]
    /// Assembled context for the next LLM call.
    public var context: AssembledContext
    /// Token budget tracker.
    public var tokenBudget: TokenBudget
    /// Cumulative cost for this session.
    public var cost: SessionCost
    /// Current status.
    public var status: AgentStatus
    /// When the session started.
    public let startedAt: Date
    /// When the state was last modified.
    public var updatedAt: Date

    public init(
        sessionId: SessionID = SessionID(),
        intent: String,
        plan: Plan = Plan(),
        steps: [AgentStep] = [],
        context: AssembledContext = .empty,
        tokenBudget: TokenBudget = TokenBudget(),
        cost: SessionCost = SessionCost(),
        status: AgentStatus = .planning,
        startedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.intent = intent
        self.plan = plan
        self.steps = steps
        self.context = context
        self.tokenBudget = tokenBudget
        self.cost = cost
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    /// The number of consecutive tool failures (observations with isError=true)
    /// at the tail of the step list.
    public var consecutiveFailures: Int {
        var count = 0
        for step in steps.reversed() {
            if let obs = step.observation, obs.isError {
                count += 1
            } else if step.observation != nil {
                break
            }
        }
        return count
    }

    /// The number of consecutive "unclear" verdicts at the tail.
    public var consecutiveUnclearVerdicts: Int {
        var count = 0
        for step in steps.reversed() {
            if step.verdict == .unclear {
                count += 1
            } else if step.verdict != nil {
                break
            }
        }
        return count
    }

    /// Check for tool call loop: same contentHash appearing N times in the
    /// last `windowSize` steps.
    public func detectLoop(threshold: Int = 3, windowSize: Int = 5) -> (hash: String, count: Int)? {
        let window = steps.suffix(windowSize)
        var hashCounts: [String: Int] = [:]
        for step in window {
            guard let tc = step.toolCall else { continue }
            let hash = tc.contentHash
            hashCounts[hash, default: 0] += 1
        }
        for (hash, count) in hashCounts where count >= threshold {
            return (hash, count)
        }
        return nil
    }

    /// Total elapsed time since session start.
    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}
