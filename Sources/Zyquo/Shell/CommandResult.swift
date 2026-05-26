import Foundation

/// Structured output from a completed shell command.
public struct CommandResult: Sendable {
    /// The command that was executed.
    public let command: String
    /// Process exit code.
    public let exitCode: Int32
    /// Signal number if the process was terminated by a signal.
    public let signal: Int32?
    /// Captured stdout (tail-capped by maxOutputBytes).
    public let stdout: String
    /// Captured stderr (tail-capped by maxOutputBytes).
    public let stderr: String
    /// Wall-clock duration in milliseconds.
    public let durationMs: Int
    /// Total bytes received on stdout.
    public let bytesOut: Int
    /// Total bytes received on stderr.
    public let bytesErr: Int
    /// The job identifier for this execution.
    public let jobId: JobID

    public init(
        command: String,
        exitCode: Int32,
        signal: Int32? = nil,
        stdout: String,
        stderr: String,
        durationMs: Int,
        bytesOut: Int,
        bytesErr: Int,
        jobId: JobID
    ) {
        self.command = command
        self.exitCode = exitCode
        self.signal = signal
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
        self.bytesOut = bytesOut
        self.bytesErr = bytesErr
        self.jobId = jobId
    }

    /// Whether the command succeeded (exit code 0).
    public var succeeded: Bool { exitCode == 0 }
}
