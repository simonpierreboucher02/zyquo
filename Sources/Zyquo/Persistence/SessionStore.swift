import Foundation

// MARK: - SessionRecord

/// A persisted record of an agent session.
public struct SessionRecord: Sendable, Codable, Equatable {
    /// The session identifier.
    public let sessionId: SessionID
    /// The user's original intent.
    public let intent: String
    /// Plan steps at time of save.
    public let planSteps: [PersistablePlanStep]
    /// Current status at time of save.
    public let status: String
    /// Model used for this session.
    public let model: String
    /// Provider used for this session.
    public let provider: String
    /// Total input tokens consumed.
    public let totalInputTokens: Int
    /// Total output tokens consumed.
    public let totalOutputTokens: Int
    /// Total cost in USD.
    public let totalCostUSD: Double
    /// When the session started.
    public let startedAt: Date
    /// When the session was last updated.
    public let updatedAt: Date
    /// Number of steps completed.
    public let stepsCompleted: Int
    /// Total number of steps in the plan.
    public let stepsTotal: Int
    /// Hash of the last checkpoint (for resume verification).
    public let checkpointHash: String?

    public init(
        sessionId: SessionID,
        intent: String,
        planSteps: [PersistablePlanStep],
        status: String,
        model: String,
        provider: String,
        totalInputTokens: Int,
        totalOutputTokens: Int,
        totalCostUSD: Double,
        startedAt: Date,
        updatedAt: Date,
        stepsCompleted: Int,
        stepsTotal: Int,
        checkpointHash: String? = nil
    ) {
        self.sessionId = sessionId
        self.intent = intent
        self.planSteps = planSteps
        self.status = status
        self.model = model
        self.provider = provider
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCostUSD = totalCostUSD
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.stepsCompleted = stepsCompleted
        self.stepsTotal = stepsTotal
        self.checkpointHash = checkpointHash
    }

    /// Short preview of the intent for listing.
    public var intentPreview: String {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60 {
            return trimmed
        }
        return String(trimmed.prefix(57)) + "..."
    }

    /// Formatted cost string.
    public var formattedCost: String {
        String(format: "$%.4f", totalCostUSD)
    }
}

// MARK: - PersistablePlanStep

/// A serializable representation of a plan step.
public struct PersistablePlanStep: Sendable, Codable, Equatable {
    public let goal: String
    public let successCriteria: String

    public init(goal: String, successCriteria: String) {
        self.goal = goal
        self.successCriteria = successCriteria
    }

    public init(from planStep: PlanStep) {
        self.goal = planStep.goal
        self.successCriteria = planStep.successCriteria
    }
}

// MARK: - SessionEvent

/// An event that occurred during a session, stored in the JSONL sidecar.
public enum SessionEvent: Sendable, Codable, Equatable {
    case stepStarted(StepStartedEvent)
    case stepCompleted(StepCompletedEvent)
    case toolExecuted(ToolExecutedEvent)
    case approvalGranted(ApprovalGrantedEvent)
    case error(ErrorEvent)

    public var timestamp: Date {
        switch self {
        case .stepStarted(let e): return e.timestamp
        case .stepCompleted(let e): return e.timestamp
        case .toolExecuted(let e): return e.timestamp
        case .approvalGranted(let e): return e.timestamp
        case .error(let e): return e.timestamp
        }
    }
}

public struct StepStartedEvent: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let stepIndex: Int
    public let goal: String

    public init(timestamp: Date = Date(), stepIndex: Int, goal: String) {
        self.timestamp = timestamp
        self.stepIndex = stepIndex
        self.goal = goal
    }
}

public struct StepCompletedEvent: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let stepIndex: Int
    public let verdict: String?
    public let durationMs: Int

    public init(timestamp: Date = Date(), stepIndex: Int, verdict: String?, durationMs: Int) {
        self.timestamp = timestamp
        self.stepIndex = stepIndex
        self.verdict = verdict
        self.durationMs = durationMs
    }
}

public struct ToolExecutedEvent: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let toolName: String
    public let summary: String
    public let isError: Bool
    public let durationMs: Int

    public init(
        timestamp: Date = Date(),
        toolName: String,
        summary: String,
        isError: Bool,
        durationMs: Int
    ) {
        self.timestamp = timestamp
        self.toolName = toolName
        self.summary = summary
        self.isError = isError
        self.durationMs = durationMs
    }
}

public struct ApprovalGrantedEvent: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let toolName: String
    public let scope: String

    public init(timestamp: Date = Date(), toolName: String, scope: String) {
        self.timestamp = timestamp
        self.toolName = toolName
        self.scope = scope
    }
}

public struct ErrorEvent: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let message: String
    public let code: String?

    public init(timestamp: Date = Date(), message: String, code: String? = nil) {
        self.timestamp = timestamp
        self.message = message
        self.code = code
    }
}

// MARK: - SessionStore

/// Actor-isolated store for session records and events.
///
/// Sessions are stored as JSON files under `.zyquo/memory/sessions/<id>.json`.
/// Events are stored as JSONL sidecar files: `.zyquo/memory/sessions/<id>.events.jsonl`.
///
/// Reference: CLAUDE.md S23.1, S29 Phase 9
public actor SessionStore {
    /// Base directory for session storage.
    private let baseDir: URL

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

    private let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public init(baseDir: URL) {
        self.baseDir = baseDir
    }

    // MARK: - Save

    /// Save a session record to disk.
    ///
    /// - Parameter record: The session record to persist.
    /// - Throws: If the file cannot be written.
    public func save(_ record: SessionRecord) throws {
        try ensureDir()
        let data = try encoder.encode(record)
        let path = sessionPath(for: record.sessionId)
        try data.write(to: path, options: .atomic)
    }

    // MARK: - Load

    /// Load a session record by its ID.
    ///
    /// - Parameter id: The session ID to load.
    /// - Returns: The session record, or nil if not found.
    public func load(id: SessionID) throws -> SessionRecord? {
        let path = sessionPath(for: id)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }
        let data = try Data(contentsOf: path)
        return try decoder.decode(SessionRecord.self, from: data)
    }

    // MARK: - List

    /// List session records sorted by date descending (newest first).
    ///
    /// - Parameter limit: Maximum number of records to return (default 50).
    /// - Returns: Array of session records.
    public func list(limit: Int = 50) -> [SessionRecord] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
            return []
        }

        let jsonFiles = files.filter {
            $0.pathExtension == "json" && !$0.lastPathComponent.contains(".events.")
        }

        var records: [SessionRecord] = []
        for file in jsonFiles {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(SessionRecord.self, from: data) else {
                continue
            }
            records.append(record)
        }

        records.sort { $0.updatedAt > $1.updatedAt }
        return Array(records.prefix(limit))
    }

    // MARK: - Delete

    /// Delete a session and its event sidecar.
    ///
    /// - Parameter id: The session ID to delete.
    /// - Throws: If the files cannot be removed.
    public func delete(id: SessionID) throws {
        let fm = FileManager.default
        let sessionFile = sessionPath(for: id)
        let eventsFile = eventsPath(for: id)

        if fm.fileExists(atPath: sessionFile.path) {
            try fm.removeItem(at: sessionFile)
        }
        if fm.fileExists(atPath: eventsFile.path) {
            try fm.removeItem(at: eventsFile)
        }
    }

    // MARK: - Events

    /// Append an event to the session's JSONL sidecar.
    ///
    /// - Parameters:
    ///   - sessionId: The session to append to.
    ///   - event: The event to record.
    /// - Throws: If the event cannot be written.
    public func appendEvent(sessionId: SessionID, event: SessionEvent) throws {
        try ensureDir()
        let path = eventsPath(for: sessionId)
        let data = try lineEncoder.encode(event)
        guard var line = String(data: data, encoding: .utf8) else {
            throw PersistenceError(
                code: "session.event_encode",
                description: "Failed to encode session event as UTF-8",
                remediation: "Check event data for encoding issues"
            )
        }
        line += "\n"

        if FileManager.default.fileExists(atPath: path.path) {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let lineData = line.data(using: .utf8) {
                handle.write(lineData)
            }
        } else {
            try line.write(to: path, atomically: true, encoding: .utf8)
        }
    }

    /// Load all events for a session from the JSONL sidecar.
    ///
    /// - Parameter sessionId: The session ID.
    /// - Returns: Array of events in chronological order.
    public func loadEvents(sessionId: SessionID) -> [SessionEvent] {
        let path = eventsPath(for: sessionId)
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return []
        }

        let lines = content.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var events: [SessionEvent] = []
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(SessionEvent.self, from: data) else {
                continue
            }
            events.append(event)
        }

        return events
    }

    // MARK: - Paths

    private func sessionPath(for id: SessionID) -> URL {
        baseDir.appendingPathComponent("\(id.value).json")
    }

    private func eventsPath(for id: SessionID) -> URL {
        baseDir.appendingPathComponent("\(id.value).events.jsonl")
    }

    private func ensureDir() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDir.path) {
            try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
    }
}
