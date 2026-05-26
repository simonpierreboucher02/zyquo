import Foundation

/// Streaming events emitted during shell command execution.
public enum ShellEvent: Sendable {
    /// A chunk of data received from stdout.
    case stdout(Data)
    /// A chunk of data received from stderr.
    case stderr(Data)
    /// The process exited with a code and optional signal number.
    case exited(code: Int32, signal: Int32?)
}

/// Execution mode for shell commands.
public enum ExecutionMode: Sendable {
    /// stdout/stderr captured via Pipe (default).
    case pipe
    /// PTY-backed execution for interactive commands (V2).
    case pty
}

/// A unique identifier for a running or completed shell job.
public struct JobID: Sendable, Hashable, CustomStringConvertible {
    public let value: String

    public init() {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random = UInt32.random(in: 0...0xFFFF)
        self.value = "job_\(timestamp)_\(String(random, radix: 16))"
    }

    public init(value: String) {
        self.value = value
    }

    public var description: String { value }
}
