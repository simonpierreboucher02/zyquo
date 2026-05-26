import Foundation

// MARK: - SessionCheckpoint

/// A snapshot of agent state at a point in time, enabling resume
/// across process restarts, sleep, and crashes.
///
/// Checkpoints are written periodically during long-lived sessions
/// (after every N steps) and on explicit save. They capture enough
/// state to reconstruct an AgentState without replaying the full
/// event log.
///
/// Reference: CLAUDE.md §30 Phase 10
public struct SessionCheckpoint: Sendable, Codable, Equatable {
    /// Unique identifier for this checkpoint.
    public let id: String
    /// The session this checkpoint belongs to.
    public let sessionId: String
    /// When this checkpoint was taken.
    public let timestamp: Date
    /// The step index at the time of checkpoint.
    public let stepIndex: Int
    /// The agent status at checkpoint time (e.g. "executing", "planning").
    public let status: String
    /// A compressed summary of the assembled context at checkpoint.
    public let contextSummary: String
    /// Total tokens used up to this checkpoint.
    public let tokensUsed: Int
    /// Cumulative cost in USD up to this checkpoint.
    public let cost: Double

    public init(
        id: String,
        sessionId: String,
        timestamp: Date = Date(),
        stepIndex: Int,
        status: String,
        contextSummary: String,
        tokensUsed: Int,
        cost: Double
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.stepIndex = stepIndex
        self.status = status
        self.contextSummary = contextSummary
        self.tokensUsed = tokensUsed
        self.cost = cost
    }

    /// Generate a unique checkpoint ID from session and step.
    public static func generateId(sessionId: String, stepIndex: Int) -> String {
        let random = UInt32.random(in: 0...0xFFFF)
        return "zcp_\(sessionId)_s\(stepIndex)_\(String(random, radix: 16, uppercase: false))"
    }
}

// MARK: - LongLivedSession

/// Actor managing multi-day session persistence with periodic
/// checkpointing and resume support.
///
/// Long-lived sessions survive process restarts, machine sleep,
/// and even crashes by checkpointing state after every N steps.
/// Resume reconstructs the agent state from the most recent
/// checkpoint plus any trailing events.
///
/// Reference: CLAUDE.md §30 Phase 10
public actor LongLivedSession {
    /// The session identifier.
    public let sessionId: SessionID
    /// Ordered list of checkpoints taken during this session.
    public private(set) var checkpoints: [SessionCheckpoint]
    /// How many times this session has been resumed.
    public private(set) var resumeCount: Int
    /// When this long-lived session was first created.
    public let createdAt: Date
    /// When this session was last resumed (nil if never resumed).
    public private(set) var lastResumedAt: Date?

    /// Directory where checkpoint files are stored.
    private let storageDir: URL
    /// Number of steps between automatic checkpoints.
    private let checkpointInterval: Int

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Maximum age in days before a session is considered stale.
    public static let staleDays: Int = 30

    public init(
        sessionId: SessionID,
        storageDir: URL,
        checkpointInterval: Int = 5,
        checkpoints: [SessionCheckpoint] = [],
        resumeCount: Int = 0,
        createdAt: Date = Date(),
        lastResumedAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.storageDir = storageDir
        self.checkpointInterval = checkpointInterval
        self.checkpoints = checkpoints
        self.resumeCount = resumeCount
        self.createdAt = createdAt
        self.lastResumedAt = lastResumedAt
    }

    // MARK: - Checkpoint

    /// Take a checkpoint of the current agent state.
    ///
    /// - Parameter state: The agent state to snapshot.
    /// - Throws: If the checkpoint cannot be persisted to disk.
    public func checkpoint(state: AgentState) throws {
        let cp = SessionCheckpoint(
            id: SessionCheckpoint.generateId(
                sessionId: sessionId.value,
                stepIndex: state.steps.count
            ),
            sessionId: sessionId.value,
            timestamp: Date(),
            stepIndex: state.steps.count,
            status: state.status.rawValue,
            contextSummary: buildContextSummary(state: state),
            tokensUsed: state.tokenBudget.tokensUsed,
            cost: state.cost.totalCostUSD
        )

        // Persist to disk
        try ensureDir()
        let data = try encoder.encode(cp)
        let path = checkpointPath(for: cp.id)
        try data.write(to: path, options: .atomic)

        checkpoints.append(cp)
    }

    /// Whether a checkpoint should be taken based on the current step index.
    ///
    /// - Parameter stepIndex: The current step index.
    /// - Returns: True if a checkpoint is due.
    public func shouldCheckpoint(stepIndex: Int) -> Bool {
        guard checkpointInterval > 0 else { return false }
        return stepIndex > 0 && stepIndex % checkpointInterval == 0
    }

    // MARK: - Resume

    /// Resume this session, incrementing the resume count and
    /// reconstructing state from the latest checkpoint.
    ///
    /// - Returns: The agent state reconstructed from the latest checkpoint.
    /// - Throws: If no checkpoints exist or state cannot be reconstructed.
    public func resume() async throws -> AgentState {
        guard let latest = checkpoints.last else {
            throw PersistenceError(
                code: "session.no_checkpoint",
                description: "No checkpoints found for session '\(sessionId.value)'",
                remediation: "This session has no checkpoints to resume from"
            )
        }

        resumeCount += 1
        lastResumedAt = Date()

        // Reconstruct a minimal AgentState from the checkpoint
        let state = AgentState(
            sessionId: sessionId,
            intent: latest.contextSummary,
            plan: Plan(),
            steps: [],
            context: .empty,
            tokenBudget: TokenBudget(tokensUsed: latest.tokensUsed),
            cost: SessionCost(),
            status: AgentStatus(rawValue: latest.status) ?? .planning,
            startedAt: createdAt,
            updatedAt: Date()
        )

        return state
    }

    // MARK: - History

    /// Get all checkpoints for this session in chronological order.
    ///
    /// - Returns: Array of checkpoints sorted by timestamp.
    public func history() -> [SessionCheckpoint] {
        checkpoints.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Staleness

    /// Whether this session is stale (no resume in the last 30 days).
    public var isStale: Bool {
        let referenceDate = lastResumedAt ?? createdAt
        let daysSince = Calendar.current.dateComponents(
            [.day],
            from: referenceDate,
            to: Date()
        ).day ?? 0
        return daysSince > Self.staleDays
    }

    /// The number of days since last activity.
    public var daysSinceActivity: Int {
        let referenceDate = lastResumedAt ?? createdAt
        return Calendar.current.dateComponents(
            [.day],
            from: referenceDate,
            to: Date()
        ).day ?? 0
    }

    // MARK: - Load from disk

    /// Load all checkpoints for this session from disk.
    ///
    /// - Throws: If checkpoint files cannot be read.
    public func loadCheckpoints() throws {
        try ensureDir()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDir, includingPropertiesForKeys: nil) else {
            return
        }

        let cpFiles = files.filter {
            $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("zcp_")
        }

        var loaded: [SessionCheckpoint] = []
        for file in cpFiles {
            guard let data = try? Data(contentsOf: file),
                  let cp = try? decoder.decode(SessionCheckpoint.self, from: data),
                  cp.sessionId == sessionId.value else {
                continue
            }
            loaded.append(cp)
        }

        loaded.sort { $0.timestamp < $1.timestamp }
        self.checkpoints = loaded
    }

    // MARK: - Internal

    private func buildContextSummary(state: AgentState) -> String {
        var parts: [String] = []
        parts.append("Intent: \(state.intent)")
        parts.append("Steps: \(state.steps.count)/\(state.plan.steps.count)")
        parts.append("Status: \(state.status.rawValue)")

        let completedSteps = state.steps.filter { $0.isComplete }
        if !completedSteps.isEmpty {
            let lastGoals = completedSteps.suffix(3).map(\.goal)
            parts.append("Recent: \(lastGoals.joined(separator: "; "))")
        }

        return parts.joined(separator: " | ")
    }

    private func checkpointPath(for id: String) -> URL {
        storageDir.appendingPathComponent("\(id).json")
    }

    private func ensureDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDir.path) {
            try fm.createDirectory(at: storageDir, withIntermediateDirectories: true)
        }
    }
}
