import Foundation
import Logging

/// Per-session shell state. Tracks the working directory, environment
/// overrides, and command history for a single Zyquo session.
///
/// Provides a scoped `execute` method that applies session defaults
/// (cwd, env) to each invocation.
public final class ShellSession: @unchecked Sendable {

    /// The underlying shell executor.
    private let executor: ShellExecutor

    /// Current working directory for this session.
    private let lock = NSLock()
    private var _cwd: URL
    private var _envOverrides: [String: String]

    /// Command history for this session.
    public let history: CommandHistory

    /// Logger.
    private let logger: Logger

    public init(
        executor: ShellExecutor,
        cwd: URL,
        envOverrides: [String: String] = [:],
        logger: Logger = ZyquoLogger.shared
    ) {
        self.executor = executor
        self._cwd = cwd
        self._envOverrides = envOverrides
        self.history = CommandHistory()
        self.logger = logger
    }

    /// The current working directory for this session.
    public var cwd: URL {
        lock.lock()
        defer { lock.unlock() }
        return _cwd
    }

    /// Update the session working directory.
    public func setCwd(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        _cwd = url
    }

    /// Current environment overrides.
    public var envOverrides: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return _envOverrides
    }

    /// Set an environment override for this session.
    public func setEnv(key: String, value: String) {
        lock.lock()
        defer { lock.unlock() }
        _envOverrides[key] = value
    }

    /// Remove an environment override.
    public func removeEnv(key: String) {
        lock.lock()
        defer { lock.unlock() }
        _envOverrides.removeValue(forKey: key)
    }

    /// Execute a command in this session's context (cwd + env).
    ///
    /// Returns the streaming result. The command is also recorded in history
    /// when it completes (use `executeCollecting` for automatic recording).
    public func execute(
        command: String,
        cwd: URL? = nil,
        env: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async -> (jobId: JobID, stream: AsyncThrowingStream<ShellEvent, Error>) {
        let effectiveCwd = cwd ?? self.cwd
        let effectiveEnv = mergedEnv(with: env)

        return await executor.execute(
            command: command,
            cwd: effectiveCwd,
            env: effectiveEnv,
            timeout: timeout
        )
    }

    /// Execute a command and collect the full result. Records in history.
    public func executeCollecting(
        command: String,
        cwd: URL? = nil,
        env: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> CommandResult {
        let effectiveCwd = cwd ?? self.cwd
        let effectiveEnv = mergedEnv(with: env)
        let startedAt = Date()

        let result = try await executor.executeCollecting(
            command: command,
            cwd: effectiveCwd,
            env: effectiveEnv,
            timeout: timeout
        )

        history.record(from: result, startedAt: startedAt)
        return result
    }

    /// Cancel a running job.
    public func cancel(jobId: JobID) async {
        await executor.cancel(jobId: jobId)
    }

    // MARK: - Private

    private func mergedEnv(with overrides: [String: String]?) -> [String: String] {
        lock.lock()
        let sessionEnv = _envOverrides
        lock.unlock()

        var merged = sessionEnv
        if let overrides {
            for (key, value) in overrides {
                merged[key] = value
            }
        }
        return merged
    }
}
