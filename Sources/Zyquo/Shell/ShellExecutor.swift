import Foundation
import Logging

/// Core shell execution engine. Manages subprocess lifecycle with streaming
/// output, cancellation, and timeout enforcement.
///
/// All executions are tracked by `JobID` and can be cancelled via `cancel(jobId:)`.
/// Uses Foundation `Process` with stdout/stderr `Pipe` for output capture.
public actor ShellExecutor {

    /// Maximum bytes to retain in the captured output tail.
    public static let defaultMaxOutputBytes = 256 * 1024 // 256 KB

    /// Active jobs keyed by their identifier.
    private var activeJobs: [JobID: Process] = [:]

    /// The shell configuration to use.
    private let shellConfig: ShellConfig

    /// Logger for structured logging.
    private let logger: Logger

    public init(config: ShellConfig, logger: Logger = ZyquoLogger.shared) {
        self.shellConfig = config
        self.logger = logger
    }

    /// Execute a shell command, streaming output events.
    ///
    /// - Parameters:
    ///   - command: The shell command string to execute via `zsh -c` (or bash fallback).
    ///   - cwd: Working directory for the child process.
    ///   - env: Optional environment overrides (merged after masking).
    ///   - timeout: Maximum wall-clock duration. Default from config.
    ///   - mode: Execution mode (pipe or pty). Only `.pipe` is supported in V1.
    ///   - maxOutputBytes: Maximum bytes to retain per stream in the result.
    /// - Returns: An `AsyncThrowingStream` of `ShellEvent`s ending with `.exited`.
    public func execute(
        command: String,
        cwd: URL,
        env: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        mode: ExecutionMode = .pipe,
        maxOutputBytes: Int = defaultMaxOutputBytes
    ) -> (jobId: JobID, stream: AsyncThrowingStream<ShellEvent, Error>) {
        let jobId = JobID()
        let effectiveTimeout = timeout ?? TimeInterval(shellConfig.timeoutSeconds)

        let stream = AsyncThrowingStream<ShellEvent, Error> { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: ShellError(
                        code: "shell.internal",
                        description: "ShellExecutor was deallocated",
                        remediation: "This is a bug; please report it"
                    ))
                    return
                }

                do {
                    try await self.runProcess(
                        command: command,
                        cwd: cwd,
                        env: env,
                        timeout: effectiveTimeout,
                        jobId: jobId,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return (jobId, stream)
    }

    /// Execute a command and collect the full result (non-streaming convenience).
    ///
    /// - Returns: A `CommandResult` with captured stdout/stderr and exit code.
    public func executeCollecting(
        command: String,
        cwd: URL,
        env: [String: String]? = nil,
        timeout: TimeInterval? = nil,
        maxOutputBytes: Int = defaultMaxOutputBytes
    ) async throws -> CommandResult {
        let (jobId, stream) = execute(
            command: command,
            cwd: cwd,
            env: env,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes
        )

        let startTime = ContinuousClock.now
        var stdoutData = Data()
        var stderrData = Data()
        var exitCode: Int32 = -1
        var exitSignal: Int32?

        for try await event in stream {
            switch event {
            case .stdout(let data):
                stdoutData.append(data)
                // Cap the retained data
                if stdoutData.count > maxOutputBytes {
                    let excess = stdoutData.count - maxOutputBytes
                    stdoutData.removeFirst(excess)
                }
            case .stderr(let data):
                stderrData.append(data)
                if stderrData.count > maxOutputBytes {
                    let excess = stderrData.count - maxOutputBytes
                    stderrData.removeFirst(excess)
                }
            case .exited(let code, let sig):
                exitCode = code
                exitSignal = sig
            }
        }

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        return CommandResult(
            command: command,
            exitCode: exitCode,
            signal: exitSignal,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            durationMs: durationMs,
            bytesOut: stdoutData.count,
            bytesErr: stderrData.count,
            jobId: jobId
        )
    }

    /// Cancel a running job. Sends SIGTERM, then SIGKILL after 5 seconds.
    public func cancel(jobId: JobID) {
        guard let process = activeJobs[jobId], process.isRunning else { return }

        logger.info("Cancelling job \(jobId.value)")
        process.terminate() // SIGTERM

        // Schedule SIGKILL after 5 seconds if still running
        Task {
            try? await Task.sleep(for: .seconds(5))
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    /// Cancel all active jobs.
    public func cancelAll() {
        for (jobId, _) in activeJobs {
            cancel(jobId: jobId)
        }
    }

    /// Number of currently active jobs.
    public var activeJobCount: Int {
        activeJobs.count
    }

    // MARK: - Internal

    private func runProcess(
        command: String,
        cwd: URL,
        env: [String: String]?,
        timeout: TimeInterval,
        jobId: JobID,
        continuation: AsyncThrowingStream<ShellEvent, Error>.Continuation
    ) async throws {
        let shellPath = resolveShellPath()
        let args = buildShellArguments(command: command)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = args
        process.currentDirectoryURL = cwd

        // Sanitize environment
        let sanitizedEnv = EnvironmentMask.sanitize(
            environment: ProcessInfo.processInfo.environment,
            overrides: env
        )
        process.environment = sanitizedEnv

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Register the job
        activeJobs[jobId] = process

        // Setup cleanup
        defer {
            activeJobs.removeValue(forKey: jobId)
        }

        logger.debug("Executing command", metadata: [
            "jobId": "\(jobId.value)",
            "command": "\(command.prefix(120))",
            "shell": "\(shellPath)",
            "cwd": "\(cwd.path)",
        ])

        // Launch the process
        do {
            try process.run()
        } catch {
            continuation.finish(throwing: ShellError(
                code: "shell.launch_failed",
                description: "Failed to launch shell: \(error.localizedDescription)",
                remediation: "Check that \(shellPath) exists and is executable"
            ))
            return
        }

        let pid = process.processIdentifier

        // Schedule timeout on a GCD timer (does not depend on actor scheduling)
        let timedOut = _TimedOutFlag()
        let timeoutItem = DispatchWorkItem {
            timedOut.set()
            if process.isRunning {
                process.terminate()
                // Schedule SIGKILL as a backstop
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if process.isRunning {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        // Read stdout and stderr concurrently
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        await withTaskGroup(of: Void.self) { group in
            // stdout reader
            group.addTask {
                while true {
                    let data = stdoutHandle.availableData
                    if data.isEmpty { break }
                    continuation.yield(.stdout(data))
                }
            }

            // stderr reader
            group.addTask {
                while true {
                    let data = stderrHandle.availableData
                    if data.isEmpty { break }
                    continuation.yield(.stderr(data))
                }
            }

            // Waiter task -- uses DispatchSemaphore to avoid blocking actor
            group.addTask {
                process.waitUntilExit()
            }

            // Wait for all tasks (readers complete when pipes close after exit)
            await group.waitForAll()
        }

        // Cancel the timeout timer if process exited normally
        timeoutItem.cancel()

        // Determine exit info
        let exitCode = process.terminationStatus
        let exitSignal: Int32?

        switch process.terminationReason {
        case .uncaughtSignal:
            exitSignal = exitCode
        default:
            exitSignal = nil
        }

        // Check if this was a timeout
        if timedOut.value {
            continuation.yield(.exited(code: exitCode, signal: exitSignal))
            continuation.finish(throwing: ShellError.timeout(
                command: command,
                seconds: Int(timeout)
            ))
            return
        }

        continuation.yield(.exited(code: exitCode, signal: exitSignal))
        continuation.finish()
    }

    /// Resolve the shell binary path. Prefers configured shell, falls back to /bin/bash.
    private func resolveShellPath() -> String {
        let preferred = shellConfig.defaultShell
        if FileManager.default.isExecutableFile(atPath: preferred) {
            return preferred
        }

        let fallback = "/bin/bash"
        if FileManager.default.isExecutableFile(atPath: fallback) {
            logger.warning("Configured shell '\(preferred)' not found, falling back to \(fallback)")
            return fallback
        }

        // Last resort
        return "/bin/sh"
    }

    /// Build the arguments for the shell invocation.
    private func buildShellArguments(command: String) -> [String] {
        if shellConfig.loadProfile {
            return ["-l", "-c", command]
        }
        return ["-c", command]
    }
}

// MARK: - Internal Helpers

/// Thread-safe boolean flag used to communicate timeout status between
/// GCD and actor-isolated code.
private final class _TimedOutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        _value = true
    }
}
