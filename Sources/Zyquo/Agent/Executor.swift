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
    /// Optional registry of `Tool`s (ZTP bridges, file.write/patch, git.*, …).
    /// Tool names not handled natively are dispatched through this registry.
    public let toolRegistry: ToolRegistry?

    public init(
        workspace: Workspace,
        shellExecutor: ShellExecutor,
        riskClassifier: RiskClassifier,
        approvalGate: ApprovalGate,
        trustStore: TrustStore,
        config: AgentConfig,
        logger: Logging.Logger = ZyquoLogger.shared,
        toolRegistry: ToolRegistry? = nil
    ) {
        self.workspace = workspace
        self.shellExecutor = shellExecutor
        self.riskClassifier = riskClassifier
        self.approvalGate = approvalGate
        self.trustStore = trustStore
        self.config = config
        self.logger = logger
        self.toolRegistry = toolRegistry
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

        // Normalize the LLM-facing wire name (e.g. "ztp_excel", "shell_run")
        // back to the canonical "ns.verb" form the dispatcher and registry use.
        let canonicalName = toolCall.toolName.contains(".")
            ? toolCall.toolName
            : ToolNameWire.toCanonical(toolCall.toolName)
        let call = canonicalName == toolCall.toolName
            ? toolCall
            : ToolCall(toolName: canonicalName, input: toolCall.input, id: toolCall.id)

        switch canonicalName {
        case "shell.run":
            return try await executeShellRun(toolCall: call, context: context, startTime: startTime)
        case "file.read":
            return try await executeFileRead(toolCall: call, context: context, startTime: startTime)
        case "file.list":
            return try await executeFileList(toolCall: call, context: context, startTime: startTime)
        default:
            return try await executeRegistryTool(toolCall: call, context: context, startTime: startTime)
        }
    }

    // MARK: - Registry-backed tools (ZTP bridges, file.write/patch, git.*, …)

    /// Dispatch a tool call to a `Tool` registered in the execution context's
    /// registry. Mutating tools are gated through the same approval policy as
    /// shell commands (auto-approve SAFE/MODERATE when configured; deny
    /// DANGEROUS/CRITICAL in non-interactive mode).
    private func executeRegistryTool(
        toolCall: ToolCall,
        context: ExecutionContext,
        startTime: ContinuousClock.Instant
    ) async throws -> ExecutionResult {
        guard let registry = context.toolRegistry,
              let tool = registry.tool(named: toolCall.toolName) else {
            let available = context.toolRegistry?.allTools().map(\.name).sorted()
                ?? ["shell.run", "file.read", "file.list"]
            return ExecutionResult(
                observation: Observation(
                    summary: "Unknown tool '\(toolCall.toolName)'. Available: \(available.joined(separator: ", "))",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                )
            )
        }

        // Per-call risk: a tool flagged `confirmed`/destructive escalates.
        let confirmed = toolCall.input["confirmed"]?.asBool ?? false
        let tier = (tool.isMutating && confirmed) ? max(tool.defaultRisk, .dangerous) : tool.defaultRisk
        let risk = RiskAssessment(tier: tier, rationale: "Registered tool '\(tool.name)' (\(tier.displayName))")

        // Approval gating (trust grants keyed by tool name).
        let decision = context.approvalGate.check(
            command: tool.name,
            risk: risk,
            trustStore: context.trustStore
        )
        let approvalSource: ApprovalSource
        switch decision {
        case .autoApproved:
            approvalSource = .autoSafe
        case .requiresApproval:
            if tier <= .moderate && context.config.autoApproveSafe {
                approvalSource = .autoSafe
            } else {
                return ExecutionResult(
                    observation: Observation(
                        summary: "Approval required for \(tier.displayName) tool '\(tool.name)'",
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
                    summary: "Tool '\(tool.name)' denied: \(reason)",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                ),
                riskAssessment: risk,
                approvalSource: .policyDenied,
                wasSkipped: true
            )
        }

        let toolContext = ToolContext(
            workspaceRoot: await context.workspace.root,
            sessionId: "",
            logger: context.logger
        )

        do {
            let result = try await tool.execute(input: toolCall.input, context: toolContext)
            // A ZTP/registry tool reports failure inside its payload; treat a
            // summary starting with "FAILED"/"Error" as an error observation.
            let lower = result.summary.lowercased()
            let isError = lower.contains("failed") || lower.hasPrefix("error")
            return ExecutionResult(
                observation: result.toObservation(isError: isError),
                riskAssessment: risk,
                approvalSource: approvalSource
            )
        } catch {
            return ExecutionResult(
                observation: Observation(
                    summary: "Tool '\(tool.name)' error: \(error.localizedDescription)",
                    durationMs: elapsedMs(since: startTime),
                    isError: true
                ),
                riskAssessment: risk,
                approvalSource: approvalSource
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
