import Foundation
import Logging

// MARK: - ExecutionContext

/// Dependencies needed by the Executor to dispatch tool calls.
public struct ExecutionContext: Sendable {
    public let workspace: Workspace
    public let shellExecutor: ShellExecutor
    public let riskClassifier: RiskClassifier
    public let approvalGate: ApprovalGate
    public let trustStore: TrustStore
    public let config: AgentConfig
    public let logger: Logging.Logger

    public init(
        workspace: Workspace,
        shellExecutor: ShellExecutor,
        riskClassifier: RiskClassifier,
        approvalGate: ApprovalGate,
        trustStore: TrustStore,
        config: AgentConfig,
        logger: Logging.Logger = ZyquoLogger.shared
    ) {
        self.workspace = workspace
        self.shellExecutor = shellExecutor
        self.riskClassifier = riskClassifier
        self.approvalGate = approvalGate
        self.trustStore = trustStore
        self.config = config
        self.logger = logger
    }
}

// MARK: - ExecutionResult

/// Result of executing a tool call, including approval information.
public struct ExecutionResult: Sendable {
    public let observation: Observation
    public let riskAssessment: RiskAssessment?
    public let approvalSource: ApprovalSource?
    public let wasSkipped: Bool

    public init(
        observation: Observation,
        riskAssessment: RiskAssessment? = nil,
        approvalSource: ApprovalSource? = nil,
        wasSkipped: Bool = false
    ) {
        self.observation = observation
        self.riskAssessment = riskAssessment
        self.approvalSource = approvalSource
        self.wasSkipped = wasSkipped
    }
}

// MARK: - Executor

/// Dispatches tool calls to the appropriate handler with risk classification
/// and approval gating.
///
/// For V1, supports: shell.run, file.read, file.list
/// Other tool names produce a structured error observation.
///
/// Reference: CLAUDE.md §17
public struct Executor: Sendable {

    public init() {}

    /// Execute a tool call with risk classification and approval.
    ///
    /// - Parameters:
    ///   - toolCall: The tool call to execute.
    ///   - context: Execution dependencies.
    /// - Returns: An ExecutionResult with the observation and approval metadata.
    public func execute(
        toolCall: ToolCall,
        context: ExecutionContext
    ) async throws -> ExecutionResult {
        let startTime = ContinuousClock.now

        switch toolCall.toolName {
        case "shell.run":
            return try await executeShellRun(toolCall: toolCall, context: context, startTime: startTime)
        case "file.read":
            return try await executeFileRead(toolCall: toolCall, context: context, startTime: startTime)
        case "file.list":
            return try await executeFileList(toolCall: toolCall, context: context, startTime: startTime)
        default:
            let elapsed = elapsedMs(since: startTime)
            return ExecutionResult(
                observation: Observation(
                    summary: "Unknown tool '\(toolCall.toolName)'. Available tools: shell.run, file.read, file.list",
                    durationMs: elapsed,
                    isError: true
                )
            )
        }
    }

    // MARK: - shell.run

    private func executeShellRun(
        toolCall: ToolCall,
        context: ExecutionContext,
        startTime: ContinuousClock.Instant
    ) async throws -> ExecutionResult {
        guard let command = toolCall.input["command"]?.stringValue else {
            return ExecutionResult(
                observation: Observation(
                    summary: "Missing required 'command' parameter for shell.run",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                )
            )
        }

        // Risk classification
        let risk = context.riskClassifier.classify(command)

        // Approval check
        let decision = context.approvalGate.check(
            command: command,
            risk: risk,
            trustStore: context.trustStore
        )

        let approvalSource: ApprovalSource
        switch decision {
        case .autoApproved:
            approvalSource = .autoSafe
        case .requiresApproval:
            // In V1, for non-interactive mode we auto-approve SAFE+MODERATE for testing.
            // The interactive UI (Phase 10) will show a real prompt.
            if risk.tier <= .moderate && context.config.autoApproveSafe {
                approvalSource = .autoSafe
            } else {
                return ExecutionResult(
                    observation: Observation(
                        summary: "Approval required for \(risk.tier.displayName) command: \(command.prefix(80))",
                        durationMs: elapsedMs(since: startTime),
                        isError: true
                    ),
                    riskAssessment: risk,
                    approvalSource: .policyDenied,
                    wasSkipped: true
                )
            }
        case .denied(let reason):
            return ExecutionResult(
                observation: Observation(
                    summary: "Command denied: \(reason)",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                ),
                riskAssessment: risk,
                approvalSource: .policyDenied,
                wasSkipped: true
            )
        }

        // Parse optional parameters
        let workspaceRoot = await context.workspace.root
        let cwdString = toolCall.input["cwd"]?.stringValue
        let cwd: URL
        if let cwdString {
            cwd = URL(fileURLWithPath: cwdString, relativeTo: workspaceRoot)
        } else {
            cwd = workspaceRoot
        }

        let timeoutSeconds: TimeInterval
        if case .number(let t) = toolCall.input["timeout_s"] {
            timeoutSeconds = t
        } else {
            timeoutSeconds = 120
        }

        // Execute
        do {
            let result = try await context.shellExecutor.executeCollecting(
                command: command,
                cwd: cwd,
                timeout: timeoutSeconds
            )

            let summary: String
            if result.succeeded {
                let output = result.stdout.prefix(1000)
                summary = "Command succeeded (exit 0, \(result.durationMs)ms)\n\(output)"
            } else {
                let output = (result.stderr.isEmpty ? result.stdout : result.stderr).prefix(1000)
                summary = "Command failed (exit \(result.exitCode), \(result.durationMs)ms)\n\(output)"
            }

            return ExecutionResult(
                observation: Observation(
                    summary: summary,
                    payload: .object([
                        "exit_code": .number(Double(result.exitCode)),
                        "stdout": .string(String(result.stdout.prefix(4000))),
                        "stderr": .string(String(result.stderr.prefix(4000))),
                        "duration_ms": .number(Double(result.durationMs)),
                    ]),
                    durationMs: result.durationMs,
                    tokenHint: ContextAssembler.estimateStringTokens(result.stdout + result.stderr),
                    isError: !result.succeeded
                ),
                riskAssessment: risk,
                approvalSource: approvalSource
            )
        } catch {
            return ExecutionResult(
                observation: Observation(
                    summary: "Shell execution error: \(error.localizedDescription)",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                ),
                riskAssessment: risk,
                approvalSource: approvalSource
            )
        }
    }

    // MARK: - file.read

    private func executeFileRead(
        toolCall: ToolCall,
        context: ExecutionContext,
        startTime: ContinuousClock.Instant
    ) async throws -> ExecutionResult {
        guard let pathStr = toolCall.input["path"]?.stringValue else {
            return ExecutionResult(
                observation: Observation(
                    summary: "Missing required 'path' parameter for file.read",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                )
            )
        }

        // Resolve path relative to workspace
        let workspaceRoot = await context.workspace.root
        let resolvedPath: String
        if pathStr.hasPrefix("/") {
            resolvedPath = pathStr
        } else {
            resolvedPath = workspaceRoot.appendingPathComponent(pathStr).path
        }

        // Boundary check
        let isInside = await context.workspace.isInsideBoundary(resolvedPath)
        guard isInside else {
            return ExecutionResult(
                observation: Observation(
                    summary: "Path '\(pathStr)' is outside workspace boundary",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                )
            )
        }

        // Read the file
        let url = URL(fileURLWithPath: resolvedPath)
        do {
            let maxBytes = 512 * 1024 // 512 KB
            let data = try Data(contentsOf: url)
            let truncated = data.count > maxBytes
            let readData = truncated ? data.prefix(maxBytes) : data
            let content = String(data: readData, encoding: .utf8) ?? "[binary content, \(data.count) bytes]"
            let summary = truncated
                ? "Read \(resolvedPath) (\(data.count) bytes, truncated to \(maxBytes))"
                : "Read \(resolvedPath) (\(data.count) bytes)"

            return ExecutionResult(
                observation: Observation(
                    summary: summary + "\n" + String(content.prefix(2000)),
                    payload: .object([
                        "content": .string(content),
                        "path": .string(resolvedPath),
                        "truncated": .bool(truncated),
                        "size": .number(Double(data.count)),
                    ]),
                    durationMs: elapsedMs(since: startTime),
                    tokenHint: ContextAssembler.estimateStringTokens(content)
                ),
                approvalSource: .autoSafe
            )
        } catch {
            return ExecutionResult(
                observation: Observation(
                    summary: "Failed to read '\(resolvedPath)': \(error.localizedDescription)",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                )
            )
        }
    }

    // MARK: - file.list

    private func executeFileList(
        toolCall: ToolCall,
        context: ExecutionContext,
        startTime: ContinuousClock.Instant
    ) async throws -> ExecutionResult {
        let pathStr = toolCall.input["path"]?.stringValue ?? "."
        let workspaceRoot = await context.workspace.root
        let resolvedPath: String
        if pathStr.hasPrefix("/") {
            resolvedPath = pathStr
        } else {
            resolvedPath = workspaceRoot.appendingPathComponent(pathStr).path
        }

        // Boundary check
        let isInside = await context.workspace.isInsideBoundary(resolvedPath)
        guard isInside else {
            return ExecutionResult(
                observation: Observation(
                    summary: "Path '\(pathStr)' is outside workspace boundary",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                )
            )
        }

        let depth: Int
        if case .number(let d) = toolCall.input["depth"] {
            depth = Int(d)
        } else {
            depth = 1
        }

        let fm = FileManager.default
        let url = URL(fileURLWithPath: resolvedPath)

        guard fm.fileExists(atPath: resolvedPath) else {
            return ExecutionResult(
                observation: Observation(
                    summary: "Directory '\(resolvedPath)' does not exist",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                )
            )
        }

        // List directory contents
        var entries: [String] = []
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            var currentDepth = 0
            for case let itemURL as URL in enumerator {
                if enumerator.level > depth {
                    enumerator.skipDescendants()
                    continue
                }
                currentDepth = enumerator.level
                let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let name = itemURL.lastPathComponent
                let prefix = isDir ? "[dir] " : "      "
                entries.append("\(prefix)\(name)")

                if entries.count >= 1000 { break }
            }
            _ = currentDepth // suppress unused warning
        }

        let summary = "Listed \(resolvedPath): \(entries.count) entries\n" +
            entries.prefix(100).joined(separator: "\n")

        return ExecutionResult(
            observation: Observation(
                summary: summary,
                payload: .object([
                    "path": .string(resolvedPath),
                    "count": .number(Double(entries.count)),
                    "entries": .array(entries.map { .string($0) }),
                ]),
                durationMs: elapsedMs(since: startTime),
                tokenHint: ContextAssembler.estimateStringTokens(entries.joined(separator: "\n"))
            ),
            approvalSource: .autoSafe
        )
    }

    // MARK: - Helpers

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
