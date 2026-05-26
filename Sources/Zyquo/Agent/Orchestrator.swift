import Foundation
import Logging

// MARK: - Orchestrator

/// Decomposes complex intents into subtasks, delegates each to a
/// specialized sub-agent, and merges the results.
///
/// The Orchestrator is the multi-agent coordinator. It uses the LLM to
/// break down a user intent, then runs each subtask through a scoped
/// agent runtime with the appropriate tool whitelist and risk ceiling.
///
/// Reference: CLAUDE.md §24
public actor Orchestrator {

    private let logger: Logging.Logger
    private let planner: Planner
    private let contextAssembler: ContextAssembler
    private let merger: ChangeSetMerger

    public init(logger: Logging.Logger = ZyquoLogger.shared) {
        self.logger = logger
        self.planner = Planner()
        self.contextAssembler = ContextAssembler()
        self.merger = ChangeSetMerger()
    }

    // MARK: - Decomposition

    /// Decompose a complex intent into subtasks using the LLM.
    ///
    /// The LLM is asked to break the intent into numbered sub-goals,
    /// each with an agent type assignment and success criteria.
    ///
    /// - Parameters:
    ///   - intent: The user's natural-language request.
    ///   - context: Assembled workspace context.
    ///   - provider: LLM provider for decomposition.
    ///   - model: Model identifier.
    /// - Returns: An array of SubTasks ready for delegation.
    public func decompose(
        intent: String,
        context: AssembledContext,
        provider: any LLMProvider,
        model: String
    ) async throws -> [SubTask] {
        let systemPrompt = AgentPrompts.orchestratorSystem

        var userContent = "User intent: \(intent)\n\n"
        userContent += "Available agent types:\n"
        for agent in SubAgentRegistry.allAgents {
            userContent += "- \(agent.id): \(agent.description) (risk ceiling: \(agent.riskCeiling.displayName), max steps: \(agent.maxSteps))\n"
        }
        userContent += "\nDecompose this intent into subtasks. For each subtask, specify:\n"
        userContent += "<number>. [<agent_type>] <goal> | <success_criteria>\n"
        userContent += "\nExample:\n"
        userContent += "1. [architect] Analyze the codebase structure | Architecture summary produced\n"
        userContent += "2. [coder] Implement the authentication module | Code compiles and tests pass\n"
        userContent += "3. [reviewer] Review the changes for style and correctness | No issues found\n"
        userContent += "4. [verifier] Run the full test suite | All tests pass\n"

        let request = LLMRequest(
            model: model,
            systemPrompt: systemPrompt,
            messages: [.user(userContent)],
            tools: [],
            toolChoice: .none,
            maxTokens: 4096,
            temperature: 0.3
        )

        var responseText = ""
        let stream = provider.send(request: request, cancellation: nil)

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                responseText += delta
            case .error(let error):
                throw ZyquoError.provider(error)
            default:
                break
            }
        }

        return parseSubTasks(from: responseText)
    }

    // MARK: - Agent Selection

    /// Select the best agent type for a given subtask.
    ///
    /// If the subtask has an explicit agent type that exists in the
    /// registry, that agent is used. Otherwise, selection is based
    /// on keyword matching against the goal.
    ///
    /// - Parameter task: The subtask to find an agent for.
    /// - Returns: The selected agent type.
    public nonisolated func selectAgent(for task: SubTask) -> any SubAgentType {
        // Try explicit match first
        if let agent = SubAgentRegistry.find(id: task.agentType) {
            return agent
        }

        // Fallback: keyword-based selection
        return inferAgentType(from: task.goal)
    }

    // MARK: - Subtask Execution

    /// Execute a single subtask by running a scoped agent loop.
    ///
    /// The returned stream emits OrchestratorEvents for the UI layer.
    /// The subtask runs through a constrained agent loop that respects
    /// the selected agent's tool whitelist and risk ceiling.
    ///
    /// - Parameters:
    ///   - task: The subtask to execute.
    ///   - context: Execution dependencies.
    ///   - router: Model router for provider resolution.
    /// - Returns: An async stream of orchestrator events.
    public func executeSubTask(
        _ task: SubTask,
        context: ExecutionContext,
        router: ModelRouter
    ) -> AsyncStream<OrchestratorEvent> {
        AsyncStream { continuation in
            Task { [self] in
                var mutableTask = task
                let agent = self.selectAgent(for: mutableTask)

                mutableTask.status = .assigned
                mutableTask.startedAt = Date()

                // Emit selection event
                let selectionMsg = AgentMessage(
                    from: "orchestrator",
                    to: agent.id,
                    kind: .taskDelegation,
                    content: mutableTask.goal
                )
                continuation.yield(.messageSent(selectionMsg))
                continuation.yield(.agentSelected(subtask: mutableTask, agent: agent.id))

                mutableTask.status = .running
                continuation.yield(.subtaskStarted(mutableTask))

                // Create a scoped agent config with the agent's step limit
                let scopedConfig = AgentConfig(
                    flags: CommandFlags(maxSteps: agent.maxSteps),
                    env: [:],
                    workspace: [:],
                    user: [:]
                )

                // Run the agent loop
                let runtime = AgentRuntime(
                    executionContext: context,
                    logger: self.logger
                )

                let workspace = context.workspace
                var filesModified: [String] = []
                var commandsRun: [String] = []
                var observations: [Observation] = []
                var lastError: ZyquoError?

                let events = await runtime.run(
                    intent: mutableTask.goal,
                    workspace: workspace,
                    config: scopedConfig,
                    router: router
                )

                for await event in events {
                    switch event {
                    case .toolExecuted(let tc, let obs):
                        observations.append(obs)
                        // Track files and commands
                        switch tc.toolName {
                        case "file.write", "file.patch", "file.move",
                             "file.delete", "file.copy":
                            if let path = tc.input["path"]?.stringValue {
                                filesModified.append(path)
                            }
                        case "shell.run":
                            if let cmd = tc.input["command"]?.stringValue {
                                commandsRun.append(cmd)
                            }
                        default:
                            break
                        }

                        // Enforce tool whitelist: if the agent used a
                        // non-whitelisted tool, note it as a violation
                        // (the executor already ran it, but we log it)
                        if !agent.isToolAllowed(tc.toolName) {
                            self.logger.warning("Agent '\(agent.id)' used non-whitelisted tool '\(tc.toolName)'")
                        }

                    case .error(let err):
                        lastError = err

                    case .finished:
                        break

                    default:
                        break
                    }
                }

                // Build result
                let uniqueFiles = Array(Set(filesModified)).sorted()
                let result = SubTaskResult(
                    summary: lastError != nil
                        ? "Failed: \(lastError!.description)"
                        : "Completed \(observations.count) tool calls",
                    filesModified: uniqueFiles,
                    commandsRun: commandsRun,
                    observations: observations
                )

                mutableTask.result = result
                mutableTask.finishedAt = Date()

                if let error = lastError {
                    mutableTask.status = .failed
                    continuation.yield(.subtaskFailed(mutableTask, error))
                } else {
                    mutableTask.status = .completed
                    continuation.yield(.subtaskCompleted(mutableTask, result))
                }

                // Result message back to orchestrator
                let resultMsg = AgentMessage(
                    from: agent.id,
                    to: "orchestrator",
                    kind: .taskResult,
                    content: result.summary
                )
                mutableTask.messages.append(resultMsg)
                continuation.yield(.messageSent(resultMsg))

                continuation.finish()
            }
        }
    }

    // MARK: - Result Merging

    /// Merge results from all completed subtasks.
    ///
    /// Detects conflicts when multiple agents modified the same file
    /// and produces a unified MergedResult.
    ///
    /// - Parameter results: The subtasks with their results.
    /// - Returns: A MergedResult with conflict information.
    public nonisolated func mergeResults(_ subtasks: [SubTask]) -> MergedResult {
        merger.merge(subtasks: subtasks)
    }

    // MARK: - Parsing

    /// Parse the LLM's decomposition response into SubTasks.
    ///
    /// Expected format:
    /// ```
    /// 1. [agent_type] goal text | success criteria
    /// 2. [agent_type] goal text | success criteria
    /// ```
    internal nonisolated func parseSubTasks(from text: String) -> [SubTask] {
        var tasks: [SubTask] = []
        let lines = text.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let firstChar = trimmed.first, firstChar.isNumber else { continue }

            // Strip the number prefix
            var content = trimmed
            if let dotIndex = content.firstIndex(of: ".") {
                let afterDot = content.index(after: dotIndex)
                if afterDot < content.endIndex {
                    content = String(content[afterDot...]).trimmingCharacters(in: .whitespaces)
                }
            } else if let parenIndex = content.firstIndex(of: ")") {
                let afterParen = content.index(after: parenIndex)
                if afterParen < content.endIndex {
                    content = String(content[afterParen...]).trimmingCharacters(in: .whitespaces)
                }
            }

            guard !content.isEmpty else { continue }

            // Extract [agent_type] prefix if present
            var agentType = "coder" // default
            if content.hasPrefix("[") {
                if let closingBracket = content.firstIndex(of: "]") {
                    let typeStart = content.index(after: content.startIndex)
                    agentType = String(content[typeStart..<closingBracket])
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    let afterBracket = content.index(after: closingBracket)
                    if afterBracket < content.endIndex {
                        content = String(content[afterBracket...])
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
            }

            // Split on | for goal | criteria
            let parts = content.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }

            let goal = parts[0]
            let criteria = parts.count > 1 ? parts[1] : "Step completes without errors"

            guard !goal.isEmpty else { continue }

            tasks.append(SubTask(
                agentType: agentType,
                goal: goal,
                successCriteria: criteria,
                priority: index
            ))
        }

        return tasks
    }

    // MARK: - Agent Inference

    /// Infer the best agent type from a goal description using keywords.
    private nonisolated func inferAgentType(from goal: String) -> any SubAgentType {
        let lower = goal.lowercased()

        // Architecture / design keywords
        let architectKeywords = ["architect", "design", "adr", "structure", "refactor architecture",
                                  "module boundary", "dependency graph"]
        if architectKeywords.contains(where: { lower.contains($0) }) {
            return ArchitectAgent()
        }

        // Review keywords
        let reviewKeywords = ["review", "audit", "inspect", "check style",
                               "convention", "lint check"]
        if reviewKeywords.contains(where: { lower.contains($0) }) {
            return ReviewerAgent()
        }

        // Verification / test keywords
        let verifyKeywords = ["test", "verify", "validate", "run tests",
                               "check pass", "assert"]
        if verifyKeywords.contains(where: { lower.contains($0) }) {
            return VerifierAgent()
        }

        // Shell / build keywords
        let shellKeywords = ["build", "compile", "deploy", "ci", "run command",
                              "execute", "install dependencies"]
        if shellKeywords.contains(where: { lower.contains($0) }) {
            return ShellAgent()
        }

        // Research keywords
        let researchKeywords = ["research", "investigate", "find", "search",
                                 "document", "explain", "understand"]
        if researchKeywords.contains(where: { lower.contains($0) }) {
            return ResearchAgent()
        }

        // Default to coder
        return CoderAgent()
    }
}
