import Foundation

// MARK: - WorkflowSchedule

/// Defines when a scheduled workflow should run.
///
/// Supports interval-based, daily, weekly, and file-change triggers.
/// Each variant carries the minimal data needed to compute the next
/// run time or react to filesystem events.
///
/// Reference: CLAUDE.md §30 Phase 10
public enum WorkflowSchedule: Sendable, Codable, Equatable {
    /// Run every N seconds.
    case interval(seconds: Int)
    /// Run once per day at the specified hour and minute (local time).
    case daily(hour: Int, minute: Int)
    /// Run once per week on the given day (1=Sunday..7=Saturday) at hour:minute.
    case weekly(dayOfWeek: Int, hour: Int, minute: Int)
    /// Run whenever files matching any of the given glob patterns change.
    case onFileChange(patterns: [String])

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, seconds, hour, minute, dayOfWeek, patterns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "interval":
            let seconds = try container.decode(Int.self, forKey: .seconds)
            self = .interval(seconds: seconds)
        case "daily":
            let hour = try container.decode(Int.self, forKey: .hour)
            let minute = try container.decode(Int.self, forKey: .minute)
            self = .daily(hour: hour, minute: minute)
        case "weekly":
            let dayOfWeek = try container.decode(Int.self, forKey: .dayOfWeek)
            let hour = try container.decode(Int.self, forKey: .hour)
            let minute = try container.decode(Int.self, forKey: .minute)
            self = .weekly(dayOfWeek: dayOfWeek, hour: hour, minute: minute)
        case "onFileChange":
            let patterns = try container.decode([String].self, forKey: .patterns)
            self = .onFileChange(patterns: patterns)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown schedule type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .interval(let seconds):
            try container.encode("interval", forKey: .type)
            try container.encode(seconds, forKey: .seconds)
        case .daily(let hour, let minute):
            try container.encode("daily", forKey: .type)
            try container.encode(hour, forKey: .hour)
            try container.encode(minute, forKey: .minute)
        case .weekly(let dayOfWeek, let hour, let minute):
            try container.encode("weekly", forKey: .type)
            try container.encode(dayOfWeek, forKey: .dayOfWeek)
            try container.encode(hour, forKey: .hour)
            try container.encode(minute, forKey: .minute)
        case .onFileChange(let patterns):
            try container.encode("onFileChange", forKey: .type)
            try container.encode(patterns, forKey: .patterns)
        }
    }

    // MARK: - Display

    /// Human-readable description of the schedule.
    public var displayString: String {
        switch self {
        case .interval(let seconds):
            if seconds >= 3600 {
                return "every \(seconds / 3600)h"
            } else if seconds >= 60 {
                return "every \(seconds / 60)m"
            } else {
                return "every \(seconds)s"
            }
        case .daily(let hour, let minute):
            return "daily at \(String(format: "%02d:%02d", hour, minute))"
        case .weekly(let day, let hour, let minute):
            let dayName = Self.dayName(day)
            return "\(dayName) at \(String(format: "%02d:%02d", hour, minute))"
        case .onFileChange(let patterns):
            return "on file change: \(patterns.joined(separator: ", "))"
        }
    }

    private static func dayName(_ day: Int) -> String {
        switch day {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        case 7: return "Saturday"
        default: return "day \(day)"
        }
    }
}

// MARK: - WorkflowRunStatus

/// The outcome of a single workflow run.
public enum WorkflowRunStatus: String, Sendable, Codable {
    case success
    case failure
    case timeout
    case cancelled
}

// MARK: - WorkflowRunResult

/// The result of executing a scheduled workflow once.
public struct WorkflowRunResult: Sendable, Codable, Equatable {
    /// The workflow that was run.
    public let workflowId: String
    /// Unique identifier for this particular run.
    public let runId: String
    /// When the run started.
    public let startedAt: Date
    /// When the run finished.
    public let finishedAt: Date
    /// Whether the run succeeded, failed, timed out, or was cancelled.
    public let status: WorkflowRunStatus
    /// Human-readable summary of what happened.
    public let summary: String
    /// Cumulative cost in USD for this run.
    public let cost: Double

    public init(
        workflowId: String,
        runId: String,
        startedAt: Date,
        finishedAt: Date,
        status: WorkflowRunStatus,
        summary: String,
        cost: Double
    ) {
        self.workflowId = workflowId
        self.runId = runId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.summary = summary
        self.cost = cost
    }

    /// Duration of the run in seconds.
    public var duration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    /// Formatted duration string.
    public var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Generate a unique run ID.
    public static func generateRunId(workflowId: String) -> String {
        let random = UInt32.random(in: 0...0xFFFFFF)
        return "zwr_\(workflowId)_\(String(random, radix: 16, uppercase: false))"
    }
}

// MARK: - ScheduledWorkflow

/// A scheduled, repeatable workflow that runs autonomously at defined
/// intervals or in response to file changes.
///
/// Workflows are persisted in `.zyquo/workflows/` and can be managed
/// via `zyquo workflows` subcommands. Each workflow defines an intent
/// (what to do), a schedule (when to do it), and optional constraints
/// (cost ceiling, skill binding).
///
/// Reference: CLAUDE.md §30 Phase 10
public struct ScheduledWorkflow: Sendable, Codable, Identifiable, Equatable {
    /// Unique identifier for this workflow.
    public let id: String
    /// Human-readable name for display and listing.
    public let name: String
    /// When and how often this workflow should run.
    public let schedule: WorkflowSchedule
    /// The intent string passed to the agent when the workflow triggers.
    public let intent: String
    /// Optional skill ID to constrain the workflow to a specific skill.
    public let skillId: String?
    /// Maximum cost in USD per individual run.
    public let maxCostPerRun: Double
    /// Whether this workflow is currently active.
    public let enabled: Bool
    /// When this workflow was created.
    public let createdAt: Date
    /// When this workflow last ran (nil if never).
    public var lastRunAt: Date?
    /// The result of the most recent run (nil if never run).
    public var lastResult: WorkflowRunResult?

    public init(
        id: String,
        name: String,
        schedule: WorkflowSchedule,
        intent: String,
        skillId: String? = nil,
        maxCostPerRun: Double = 2.0,
        enabled: Bool = true,
        createdAt: Date = Date(),
        lastRunAt: Date? = nil,
        lastResult: WorkflowRunResult? = nil
    ) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.intent = intent
        self.skillId = skillId
        self.maxCostPerRun = maxCostPerRun
        self.enabled = enabled
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.lastResult = lastResult
    }

    /// Generate a unique workflow ID from a name.
    public static func generateId(name: String) -> String {
        let sanitized = name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let random = UInt16.random(in: 0...0xFFFF)
        return "zwf_\(sanitized.prefix(20))_\(String(random, radix: 16, uppercase: false))"
    }

    /// Short preview of the intent for listing.
    public var intentPreview: String {
        let trimmed = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 50 {
            return trimmed
        }
        return String(trimmed.prefix(47)) + "..."
    }

    /// Whether this workflow should run now, given the current time.
    public func shouldRunNow(currentTime: Date = Date()) -> Bool {
        guard enabled else { return false }

        switch schedule {
        case .interval(let seconds):
            guard let lastRun = lastRunAt else { return true }
            return currentTime.timeIntervalSince(lastRun) >= Double(seconds)

        case .daily(let hour, let minute):
            let cal = Calendar.current
            let components = cal.dateComponents([.hour, .minute], from: currentTime)
            guard components.hour == hour, components.minute == minute else { return false }
            // Don't run if already ran today
            if let lastRun = lastRunAt {
                return !cal.isDate(lastRun, inSameDayAs: currentTime)
            }
            return true

        case .weekly(let dayOfWeek, let hour, let minute):
            let cal = Calendar.current
            let components = cal.dateComponents([.weekday, .hour, .minute], from: currentTime)
            guard components.weekday == dayOfWeek,
                  components.hour == hour,
                  components.minute == minute else { return false }
            if let lastRun = lastRunAt {
                let daysSince = cal.dateComponents([.day], from: lastRun, to: currentTime).day ?? 0
                return daysSince >= 7
            }
            return true

        case .onFileChange:
            // File-change triggers are event-driven, not time-driven.
            // This method returns false; the caller must use FSEvents.
            return false
        }
    }
}
