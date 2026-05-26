import Foundation

// MARK: - AuditEntry

/// A single entry in the append-only audit log.
///
/// Tracks every command classification, approval decision, and trust grant
/// for accountability and forensics.
public struct AuditEntry: Sendable, Codable {
    /// ISO 8601 timestamp of the event.
    public let timestamp: Date
    /// The session this entry belongs to.
    public let sessionId: String
    /// The type of audit event.
    public let event: AuditEvent
    /// The shell command involved (may be redacted for display).
    public let command: String
    /// The risk tier assigned by the classifier.
    public let riskTier: RiskLevel
    /// The approval decision.
    public let decision: String
    /// How the approval was sourced.
    public let source: ApprovalSource
    /// Trust scope if a grant was created.
    public let trustScope: TrustScope?
    /// Additional context (e.g., matched rules, escalation reasons).
    public let context: [String: String]?

    public init(
        timestamp: Date = Date(),
        sessionId: String,
        event: AuditEvent,
        command: String,
        riskTier: RiskLevel,
        decision: String,
        source: ApprovalSource,
        trustScope: TrustScope? = nil,
        context: [String: String]? = nil
    ) {
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.event = event
        self.command = command
        self.riskTier = riskTier
        self.decision = decision
        self.source = source
        self.trustScope = trustScope
        self.context = context
    }
}

/// Types of audit events.
public enum AuditEvent: String, Sendable, Codable {
    /// A command was classified and an approval decision was made.
    case commandApproval = "command_approval"
    /// A trust grant was created.
    case trustGranted = "trust_granted"
    /// A trust grant was revoked.
    case trustRevoked = "trust_revoked"
    /// All session trust was cleared (/untrust).
    case trustCleared = "trust_cleared"
    /// A command was executed after approval.
    case commandExecuted = "command_executed"
    /// A command was blocked (denied).
    case commandBlocked = "command_blocked"
}

// MARK: - AuditLog

/// Append-only JSONL audit log for command approvals and trust decisions.
///
/// Each session gets its own log file at `.zyquo/logs/<session-id>.audit.jsonl`.
/// The log is never cleared by the agent — only manual deletion removes entries.
///
/// Reference: CLAUDE.md §33
public final class AuditLog: @unchecked Sendable {
    private let logDirectory: URL
    private let sessionId: String
    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private let encoder: JSONEncoder

    public init(workspaceRoot: URL, sessionId: String) {
        self.logDirectory = workspaceRoot
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("logs")
        self.sessionId = sessionId
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = .sortedKeys
    }

    /// Create an AuditLog for testing with a specific log directory.
    internal init(logDirectory: URL, sessionId: String) {
        self.logDirectory = logDirectory
        self.sessionId = sessionId
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = .sortedKeys
    }

    deinit {
        try? fileHandle?.close()
    }

    /// The path to this session's audit log file.
    public var logPath: URL {
        logDirectory.appendingPathComponent("\(sessionId).audit.jsonl")
    }

    // MARK: - Writing

    /// Append an audit entry to the log.
    public func record(_ entry: AuditEntry) {
        lock.lock()
        defer { lock.unlock() }

        guard let data = try? encoder.encode(entry) else { return }
        guard var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"

        guard let lineData = line.data(using: .utf8) else { return }

        if fileHandle == nil {
            openFileHandle()
        }

        fileHandle?.write(lineData)
    }

    /// Record a command approval event.
    public func recordApproval(
        command: String,
        riskTier: RiskLevel,
        decision: ApprovalDecision,
        source: ApprovalSource,
        matchedRules: [DangerRule] = [],
        escalationReasons: [String] = []
    ) {
        var context: [String: String] = [:]
        if !matchedRules.isEmpty {
            context["matched_rules"] = matchedRules.map(\.label).joined(separator: ", ")
        }
        if !escalationReasons.isEmpty {
            context["escalation"] = escalationReasons.joined(separator: "; ")
        }

        let decisionString: String
        switch decision {
        case .autoApproved(let reason):
            decisionString = "auto_approved: \(reason)"
        case .requiresApproval:
            decisionString = "requires_approval"
        case .denied(let reason):
            decisionString = "denied: \(reason)"
        }

        record(AuditEntry(
            sessionId: sessionId,
            event: .commandApproval,
            command: Redaction.redact(command),
            riskTier: riskTier,
            decision: decisionString,
            source: source,
            context: context.isEmpty ? nil : context
        ))
    }

    /// Record a trust grant event.
    public func recordTrustGrant(_ grant: TrustGrant) {
        record(AuditEntry(
            sessionId: sessionId,
            event: .trustGranted,
            command: grant.pattern,
            riskTier: grant.riskTier,
            decision: "granted",
            source: .userApproved,
            trustScope: grant.scope
        ))
    }

    /// Record that all session trust was cleared.
    public func recordTrustCleared() {
        record(AuditEntry(
            sessionId: sessionId,
            event: .trustCleared,
            command: "*",
            riskTier: .safe,
            decision: "cleared",
            source: .userApproved
        ))
    }

    // MARK: - Reading

    /// Read all entries from the audit log for this session.
    public func readEntries() -> [AuditEntry] {
        guard let data = try? Data(contentsOf: logPath),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(AuditEntry.self, from: lineData)
            }
    }

    // MARK: - File Management

    private func openFileHandle() {
        let manager = FileManager.default
        try? manager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let path = logPath.path
        if !manager.fileExists(atPath: path) {
            manager.createFile(atPath: path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logPath)
        fileHandle?.seekToEndOfFile()
    }
}

// MARK: - Redaction import

/// Re-export Redaction for use in AuditLog without adding a separate import.
/// The actual implementation lives in Observability/Logger.swift.
// Note: Redaction is already in scope since both are in the Zyquo target.
