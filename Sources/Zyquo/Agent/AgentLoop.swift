import Foundation
import Logging

// MARK: - AgentEvent

/// Events emitted by the agent runtime for every state transition.
/// The UI layer observes these to render the interactive display.
public enum AgentEvent: Sendable {
    /// Agent status changed (planning, executing, verifying, etc.).
    case statusChanged(AgentStatus)
    /// A plan was produced or updated.
    case planProduced(Plan)
    /// A step began execution.
    case stepStarted(AgentStep)
    /// A tool call was proposed with its risk level.
    case toolProposed(ToolCall, RiskLevel)
    /// A tool call requires interactive user approval.
    case approvalRequired(ToolCall, RiskAssessment)
    /// A tool call completed execution.
    case toolExecuted(ToolCall, Observation)
    /// A step's verification completed.
    case verificationCompleted(StepID, Verdict)
    /// Context was compacted due to token budget pressure.
    case contextCompacted(tokensBefore: Int, tokensAfter: Int)
    /// The agent loop finished (success, failure, or cancellation).
    case finished(SessionSummary)
    /// An error occurred during the loop.
    case error(ZyquoError)
}

// MARK: - AgentRuntime

/// The main agent loop actor. Owns the mutable AgentState and drives
/// the plan-execute-verify cycle.
///
/// Usage:
/// ```swift
/// let runtime = AgentRuntime(executionContext: ctx)
/// let events = runtime.run(intent: "fix tests", workspace: ws, config: cfg, router: router)
/// for await event in events {
///     // render event in UI
/// }
/// ```
///
/// Reference: CLAUDE.md §16
public actor AgentRuntime {

    /// The mutable agent state. Actor-isolated.
    private var state: AgentState?

    /// Whether the runtime has been cancelled.
    private var isCancelled = false

    /// Execution dependencies.
    private let executionContext: ExecutionContext

    /// Logger.
    private let logger: Logging.Logger

    /// Components.
    private let planner = Planner()
    private let executor = Executor()
    private let verifier = Verifier()
    private let summarizer = Summarizer()
    private let contextAssembler = ContextAssembler()

    public init(
        executionContext: ExecutionContext,
        logger: Logging.Logger = ZyquoLogger.shared
    ) {
        self.executionContext = executionContext
        self.logger = logger
    }

    // MARK: - Public Interface

    /// Run the agent loop for a given intent.
    ///
    /// Returns an AsyncStream of AgentEvents. The stream completes when
    /// the agent finishes (success, failure, or cancellation).
    ///
    /// - Parameters:
    ///   - intent: The user's natural-language request.
    ///   - workspace: The workspace to operate in.
    ///   - config: Agent configuration (max steps, cost, etc.).
    ///   - router: Model router for LLM provider resolution.
    /// - Returns: An async stream of agent events.
    public func run(
        intent: String,
        workspace: Workspace,
        config: AgentConfig,
        router: ModelRouter
    ) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.executeLoop(
                    intent: intent,
                    workspace: workspace,
                    config: config,
                    router: router,
                    continuation: continuation
                )
            }
        }
    }

    /// Cancel the running agent loop.
    public func cancel() {
        isCancelled = true
    }

    /// Get the current agent state (for inspection).
    public func currentState() -> AgentState? {
        state
    }

    // MARK: - Main Loop

    private func executeLoop(
        intent: String,
        workspace: Workspace,
        config: AgentConfig,
        router: ModelRouter,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async {
        // Initialize state
        let sessionId = SessionID()
        let modelDescriptor = ModelCatalog.claudeSonnet4_6
        let tokenBudget = TokenBudget(
            modelContextWindow: modelDescriptor.contextWindow,
            reserveForOutput: modelDescriptor.maxOutputTokens
        )

        state = AgentState(
            sessionId: sessionId,
            intent: intent,
            tokenBudget: tokenBudget,
            status: .planning
        )

        logger.info("Agent session started", metadata: [
            "sessionId": "\(sessionId.value)",
            "intent": "\(intent.prefix(100))",
        ])

        emit(.statusChanged(.planning), to: continuation)

        // Phase 1: Planning
        do {
            let plan = try await generatePlan(
                intent: intent,
                workspace: workspace,
                config: config,
                router: router
            )

            guard !isCancelled else {
                await finishCancelled(continuation: continuation)
                return
            }

            state?.plan = plan
            state?.updatedAt = Date()
            emit(.planProduced(plan), to: continuation)

            logger.info("Plan produced", metadata: [
                "steps": "\(plan.steps.count)",
            ])

            // Phase 2: Execute each step
            for (index, planStep) in plan.steps.enumerated() {
                guard !isCancelled else {
                    await finishCancelled(continuation: continuation)
                    return
                }

                // Check stop conditions before each step
                if let stopReason = StopConditions.evaluate(state: state!, config: config) {
                    logger.info("Stop condition met", metadata: [
                        "reason": "\(stopReason.description)",
                    ])

                    if stopReason.isHard {
                        await finishWithReason(stopReason, continuation: continuation)
                        return
                    } else {
                        // For soft stops, complete normally
                        await finishWithReason(stopReason, continuation: continuation)
                        return
                    }
                }

                // Execute this step
                let result = try await executeStep(
                    planStep: planStep,
                    index: index,
                    workspace: workspace,
                    config: config,
                    router: router,
                    continuation: continuation
                )

                if result == .blocked {
                    state?.status = .blocked
                    emit(.statusChanged(.blocked), to: continuation)
                    await finishWithReason(
                        .consecutiveFailures(count: state?.consecutiveFailures ?? 0),
                        continuation: continuation
                    )
                    return
                }
            }

            // All steps done
            state?.plan.isComplete = true
            state?.status = .done
            state?.updatedAt = Date()
            emit(.statusChanged(.done), to: continuation)

            let summary = summarizer.summarize(state: state!)
            emit(.finished(summary), to: continuation)

        } catch {
            logger.error("Agent loop error", metadata: [
                "error": "\(error.localizedDescription)",
            ])

            state?.status = .failed
            state?.updatedAt = Date()
            emit(.statusChanged(.failed), to: continuation)

            let zyquoError: ZyquoError
            if let ze = error as? ZyquoError {
                zyquoError = ze
            } else {
                zyquoError = .provider(ProviderError(
                    code: "agent.loop_error",
                    description: error.localizedDescription,
                    remediation: "Check provider configuration and try again"
                ))
            }
            emit(.error(zyquoError), to: continuation)

            let summary = summarizer.summarize(state: state!)
            emit(.finished(summary), to: continuation)
        }

        continuation.finish()
    }

    // MARK: - Step Execution Result

    private enum StepResult {
        case completed
        case blocked
    }

    // MARK: - Step Execution

    private func executeStep(
        planStep: PlanStep,
        index: Int,
        workspace: Workspace,
        config: AgentConfig,
        router: ModelRouter,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async throws -> StepResult {
        var step = AgentStep(
            index: index,
            goal: planStep.goal,
            successCriteria: planStep.successCriteria
        )
        step.startedAt = Date()

        state?.status = .executing
        state?.updatedAt = Date()
        emit(.statusChanged(.executing), to: continuation)
        emit(.stepStarted(step), to: continuation)

        // Propose tool call
        let toolCall = try await proposeToolCall(
            planStep: planStep,
            workspace: workspace,
            config: config,
            router: router
        )

        guard !isCancelled else {
            return .blocked
        }

        guard let toolCall else {
            // No tool call proposed — mark as complete with unclear verdict
            step.verdict = .unclear
            step.finishedAt = Date()
            state?.steps.append(step)
            state?.updatedAt = Date()
            return .completed
        }

        step.toolCall = toolCall

        // Classify risk for shell commands
        let riskLevel: RiskLevel
        if toolCall.toolName == "shell.run", let cmd = toolCall.input["command"]?.stringValue {
            let assessment = executionContext.riskClassifier.classify(cmd)
            riskLevel = assessment.tier
            step.risk = riskLevel
            emit(.toolProposed(toolCall, riskLevel), to: continuation)

            // Check if approval is needed
            if riskLevel >= .dangerous {
                emit(.approvalRequired(toolCall, assessment), to: continuation)
            }
        } else {
            // Non-shell tools have a default risk
            riskLevel = toolCall.toolName.hasPrefix("file.read") || toolCall.toolName.hasPrefix("file.list")
                ? .safe : .moderate
            step.risk = riskLevel
            emit(.toolProposed(toolCall, riskLevel), to: continuation)
        }

        // Execute the tool
        let executionResult = try await executor.execute(
            toolCall: toolCall,
            context: executionContext
        )

        step.observation = executionResult.observation
        step.approvedBy = executionResult.approvalSource

        emit(.toolExecuted(toolCall, executionResult.observation), to: continuation)

        // Check if execution was skipped (e.g., approval denied)
        if executionResult.wasSkipped {
            step.verdict = .fail
            step.finishedAt = Date()
            state?.steps.append(step)
            state?.updatedAt = Date()
            return .blocked
        }

        // Verify the step
        state?.status = .verifying
        emit(.statusChanged(.verifying), to: continuation)

        // Use quick (local) verification for V1; LLM verification is available but
        // not used by default to save tokens.
        let verdict = verifier.quickVerify(step: step)
        step.verdict = verdict
        step.finishedAt = Date()

        emit(.verificationCompleted(step.id, verdict), to: continuation)

        // Append completed step to state
        state?.steps.append(step)
        state?.updatedAt = Date()

        logger.debug("Step completed", metadata: [
            "index": "\(index)",
            "goal": "\(planStep.goal.prefix(60))",
            "verdict": "\(verdict.rawValue)",
            "durationMs": "\(step.durationMs ?? 0)",
        ])

        return .completed
    }

    // MARK: - Plan Generation

    private func generatePlan(
        intent: String,
        workspace: Workspace,
        config: AgentConfig,
        router: ModelRouter
    ) async throws -> Plan {
        // Get workspace summary
        let wsIndex = await workspace.scan()
        let workspaceSummary = wsIndex.summaryCard

        // Read project memory if available
        let wsRoot = await workspace.root
        let projectMemoryPath = wsRoot
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("memory")
            .appendingPathComponent("project.md")
        let projectMemory = try? String(contentsOf: projectMemoryPath, encoding: .utf8)

        // Assemble context for planning
        let tools = buildToolSchemas()
        let (context, updatedBudget) = contextAssembler.assembleForPlanning(
            intent: intent,
            workspaceSummary: workspaceSummary,
            projectMemory: projectMemory,
            tools: tools,
            budget: state?.tokenBudget ?? TokenBudget()
        )

        state?.context = context
        state?.tokenBudget = updatedBudget

        // Resolve provider for planning
        guard let resolved = await router.resolve(for: .planning) else {
            throw ZyquoError.provider(ProviderError(
                code: "provider.not_found",
                description: "No provider available for planning",
                remediation: "Run `zyquo provider login anthropic` to configure a provider"
            ))
        }

        // Generate plan via LLM
        return try await planner.plan(
            intent: intent,
            context: context,
            provider: resolved.provider,
            model: resolved.model
        )
    }

    // MARK: - Tool Call Proposal

    private func proposeToolCall(
        planStep: PlanStep,
        workspace: Workspace,
        config: AgentConfig,
        router: ModelRouter
    ) async throws -> ToolCall? {
        guard let currentState = state else { return nil }

        let wsIndex = await workspace.scan()
        let tools = buildToolSchemas()

        let (context, updatedBudget) = contextAssembler.assembleForExecution(
            intent: currentState.intent,
            plan: currentState.plan,
            steps: currentState.steps,
            currentStepIndex: currentState.steps.count,
            workspaceSummary: wsIndex.summaryCard,
            tools: tools,
            budget: currentState.tokenBudget
        )

        state?.context = context
        state?.tokenBudget = updatedBudget

        // Check for compaction
        if updatedBudget.needsCompaction {
            // In V1, we just note it — actual compaction is Phase 9
            logger.warning("Token budget needs compaction", metadata: [
                "utilization": "\(String(format: "%.0f", updatedBudget.utilizationPercent * 100))%",
            ])
            // Emit event for UI
        }

        guard let resolved = await router.resolve(for: .coding) else {
            throw ZyquoError.provider(ProviderError(
                code: "provider.not_found",
                description: "No provider available for coding",
                remediation: "Run `zyquo provider login anthropic` to configure a provider"
            ))
        }

        return try await planner.propose(
            step: planStep,
            state: currentState,
            context: context,
            provider: resolved.provider,
            model: resolved.model
        )
    }

    // MARK: - Finish Helpers

    private func finishCancelled(continuation: AsyncStream<AgentEvent>.Continuation) async {
        state?.status = .cancelled
        state?.updatedAt = Date()
        emit(.statusChanged(.cancelled), to: continuation)

        if let state {
            let summary = summarizer.summarize(state: state)
            emit(.finished(summary), to: continuation)
        }
        continuation.finish()
    }

    private func finishWithReason(
        _ reason: AgentStopReason,
        continuation: AsyncStream<AgentEvent>.Continuation
    ) async {
        let finalStatus: AgentStatus
        switch reason {
        case .planCompleted:
            finalStatus = .done
        case .userCancellation:
            finalStatus = .cancelled
        default:
            finalStatus = .failed
        }

        state?.status = finalStatus
        state?.updatedAt = Date()
        if case .planCompleted = reason {
            state?.plan.isComplete = true
        }
        emit(.statusChanged(finalStatus), to: continuation)

        if let state {
            let summary = summarizer.summarize(state: state)
            emit(.finished(summary), to: continuation)
        }
        continuation.finish()
    }

    // MARK: - Event Emission

    private func emit(_ event: AgentEvent, to continuation: AsyncStream<AgentEvent>.Continuation) {
        continuation.yield(event)
    }

    // MARK: - Tool Schemas

    /// Build the tool schemas available in V1.
    private func buildToolSchemas() -> [ToolSchema] {
        [
            ToolSchema(
                name: "shell.run",
                description: "Execute a shell command via zsh -c. Returns stdout, stderr, and exit code.",
                inputSchema: [
                    "type": .string("object"),
                    "required": .array([.string("command")]),
                    "properties": .object([
                        "command": .object([
                            "type": .string("string"),
                            "description": .string("Shell command to execute via zsh -c"),
                        ]),
                        "cwd": .object([
                            "type": .string("string"),
                            "description": .string("Working directory; must be inside workspace"),
                        ]),
                        "timeout_s": .object([
                            "type": .string("integer"),
                            "description": .string("Timeout in seconds (default 120)"),
                        ]),
                    ]),
                ]
            ),
            ToolSchema(
                name: "file.read",
                description: "Read a file's contents. Returns the text content and metadata.",
                inputSchema: [
                    "type": .string("object"),
                    "required": .array([.string("path")]),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("File path (relative to workspace or absolute within workspace)"),
                        ]),
                    ]),
                ]
            ),
            ToolSchema(
                name: "file.list",
                description: "List directory contents. Returns names, types, and sizes.",
                inputSchema: [
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Directory path (default: workspace root)"),
                        ]),
                        "depth": .object([
                            "type": .string("integer"),
                            "description": .string("How many levels deep to list (default: 1)"),
                        ]),
                    ]),
                ]
            ),
        ]
    }
}
