import Foundation

// MARK: - RemoteResult

/// The result of executing a command on a remote node.
public struct RemoteResult: Sendable {
    /// The node identifier where the command was executed.
    public let nodeId: String
    /// Process exit code.
    public let exitCode: Int32
    /// Captured standard output.
    public let stdout: String
    /// Captured standard error.
    public let stderr: String
    /// Wall-clock duration in milliseconds.
    public let durationMs: Int

    public init(
        nodeId: String,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        durationMs: Int
    ) {
        self.nodeId = nodeId
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.durationMs = durationMs
    }

    /// Whether the command succeeded (exit code 0).
    public var succeeded: Bool { exitCode == 0 }
}

// MARK: - RemoteExecutor Protocol

/// Abstraction for executing commands on remote cluster nodes.
///
/// Implementations include `SSHRemoteExecutor` for real SSH connections
/// and `MockRemoteExecutor` for testing without network access.
///
/// Reference: CLAUDE.md §30 Phase 9
public protocol RemoteExecutor: Sendable {
    /// Execute a shell command on a remote node.
    ///
    /// - Parameters:
    ///   - command: The shell command to execute.
    ///   - node: The target node.
    ///   - cwd: Optional working directory on the remote node.
    /// - Returns: The command result from the remote node.
    func execute(command: String, on node: NodeInfo, cwd: String?) async throws -> RemoteResult

    /// Check whether a node is reachable via the transport layer.
    ///
    /// - Parameter node: The node to check.
    /// - Returns: True if the node responds to a connectivity check.
    func isReachable(node: NodeInfo) async -> Bool
}

// MARK: - RemoteExecutorError

/// Errors specific to remote execution.
public enum RemoteExecutorError: Error, Sendable, CustomStringConvertible {
    /// The node was unreachable (SSH connection failed or timed out).
    case unreachable(nodeId: String, reason: String)
    /// The SSH binary was not found.
    case sshNotFound
    /// The command timed out on the remote node.
    case timeout(nodeId: String, seconds: Int)
    /// An unexpected error during remote execution.
    case executionFailed(nodeId: String, reason: String)

    public var description: String {
        switch self {
        case .unreachable(let id, let reason):
            return "Node '\(id)' unreachable: \(reason)"
        case .sshNotFound:
            return "SSH binary not found at /usr/bin/ssh"
        case .timeout(let id, let seconds):
            return "Command timed out on '\(id)' after \(seconds)s"
        case .executionFailed(let id, let reason):
            return "Execution failed on '\(id)': \(reason)"
        }
    }
}

// MARK: - SSHRemoteExecutor

/// Remote executor that uses the local `/usr/bin/ssh` binary via
/// Foundation `Process` for passwordless SSH (ed25519) environments.
///
/// Suitable for LAN clusters with pre-configured SSH keys and
/// `~/.ssh/config` aliases. Agent forwarding is assumed active.
public struct SSHRemoteExecutor: RemoteExecutor, @unchecked Sendable {

    /// Default SSH connection timeout in seconds.
    public let connectTimeoutSeconds: Int

    /// Default command execution timeout in seconds.
    public let commandTimeoutSeconds: Int

    /// Path to the SSH binary.
    public let sshPath: String

    public init(
        connectTimeoutSeconds: Int = 10,
        commandTimeoutSeconds: Int = 120,
        sshPath: String = "/usr/bin/ssh"
    ) {
        self.connectTimeoutSeconds = connectTimeoutSeconds
        self.commandTimeoutSeconds = commandTimeoutSeconds
        self.sshPath = sshPath
    }

    public func execute(command: String, on node: NodeInfo, cwd: String?) async throws -> RemoteResult {
        guard FileManager.default.isExecutableFile(atPath: sshPath) else {
            throw RemoteExecutorError.sshNotFound
        }

        let startTime = ContinuousClock.now

        // Build the remote command, optionally cd'ing first
        let remoteCommand: String
        if let cwd {
            remoteCommand = "cd \(cwd) && \(command)"
        } else {
            remoteCommand = command
        }

        // Build SSH arguments
        let sshHost = node.hostname
        let args = [
            "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=yes",
            sshHost,
            remoteCommand,
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw RemoteExecutorError.executionFailed(
                nodeId: node.id,
                reason: "Failed to launch SSH: \(error.localizedDescription)"
            )
        }

        // Schedule a timeout
        let pid = process.processIdentifier
        let timeoutItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if process.isRunning {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + .seconds(commandTimeoutSeconds),
            execute: timeoutItem
        )

        process.waitUntilExit()
        timeoutItem.cancel()

        let elapsed = ContinuousClock.now - startTime
        let durationMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        // SSH exit code 255 typically means connection failure
        if process.terminationStatus == 255 {
            throw RemoteExecutorError.unreachable(
                nodeId: node.id,
                reason: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return RemoteResult(
            nodeId: node.id,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr,
            durationMs: durationMs
        )
    }

    public func isReachable(node: NodeInfo) async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: sshPath) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = [
            "-o", "ConnectTimeout=\(connectTimeoutSeconds)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "BatchMode=yes",
            node.hostname,
            "echo ok",
        ]

        let devNull = FileHandle.nullDevice
        process.standardOutput = devNull
        process.standardError = devNull

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - MockRemoteExecutor

/// A mock remote executor that returns pre-configured results for testing.
///
/// Configure responses via `addResponse` or `setReachable` before use.
/// Unrecognized nodes return a default error response.
public final class MockRemoteExecutor: RemoteExecutor, @unchecked Sendable {

    private let lock = NSLock()

    /// Pre-configured responses keyed by node id.
    private var responses: [String: RemoteResult] = [:]

    /// Pre-configured reachability keyed by node id.
    private var reachability: [String: Bool] = [:]

    /// Records of commands executed, for verification in tests.
    private var _executionLog: [(command: String, nodeId: String)] = []

    /// Default response for nodes without a configured response.
    public let defaultResult: RemoteResult

    public init(
        defaultResult: RemoteResult = RemoteResult(
            nodeId: "mock",
            exitCode: 0,
            stdout: "mock output\n",
            stderr: "",
            durationMs: 10
        )
    ) {
        self.defaultResult = defaultResult
    }

    /// Configure the response for a specific node.
    public func addResponse(for nodeId: String, result: RemoteResult) {
        lock.lock()
        defer { lock.unlock() }
        responses[nodeId] = result
    }

    /// Configure the reachability for a specific node.
    public func setReachable(_ nodeId: String, reachable: Bool) {
        lock.lock()
        defer { lock.unlock() }
        reachability[nodeId] = reachable
    }

    /// The log of all commands executed through this mock.
    public var executionLog: [(command: String, nodeId: String)] {
        lock.lock()
        defer { lock.unlock() }
        return _executionLog
    }

    public func execute(command: String, on node: NodeInfo, cwd: String?) async throws -> RemoteResult {
        lock.lock()
        _executionLog.append((command: command, nodeId: node.id))
        let result = responses[node.id] ?? RemoteResult(
            nodeId: node.id,
            exitCode: defaultResult.exitCode,
            stdout: defaultResult.stdout,
            stderr: defaultResult.stderr,
            durationMs: defaultResult.durationMs
        )
        lock.unlock()
        return result
    }

    public func isReachable(node: NodeInfo) async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachability[node.id] ?? true
    }
}
