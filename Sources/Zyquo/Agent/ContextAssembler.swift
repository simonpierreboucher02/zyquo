import Foundation

// MARK: - AssembledContext

/// The fully assembled context ready to send to an LLM provider.
public struct AssembledContext: Sendable {
    /// The system prompt for the LLM.
    public let systemPrompt: String
    /// The conversation messages (user turns, assistant turns, tool results).
    public let messages: [LLMMessage]
    /// Tool schemas available to the LLM.
    public let tools: [ToolSchema]
    /// Estimated total token count for this context.
    public let totalTokenEstimate: Int

    public init(
        systemPrompt: String,
        messages: [LLMMessage],
        tools: [ToolSchema],
        totalTokenEstimate: Int
    ) {
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
        self.totalTokenEstimate = totalTokenEstimate
    }

    /// An empty context with no content.
    public static let empty = AssembledContext(
        systemPrompt: "",
        messages: [],
        tools: [],
        totalTokenEstimate: 0
    )
}

// MARK: - ContextAssembler

/// Builds the LLM context from intent, plan, step history, workspace info,
/// and project memory. Manages token budget by truncating older observations.
///
/// Reference: CLAUDE.md §16.1
public struct ContextAssembler: Sendable {

    /// Rough token estimation: ~4 characters per token.
    public static let charsPerToken = 4

    public init() {}

    /// Assemble context for the planning phase.
    ///
    /// - Parameters:
    ///   - intent: The user's original request.
    ///   - workspaceSummary: Summary of the workspace (from WorkspaceIndex).
    ///   - projectMemory: Project memory content (if any).
    ///   - tools: Available tool schemas.
    ///   - budget: Current token budget.
    /// - Returns: Assembled context and updated token budget.
    public func assembleForPlanning(
        intent: String,
        workspaceSummary: String?,
        projectMemory: String?,
        userModel: String? = nil,
        toolGuidance: String? = nil,
        tools: [ToolSchema],
        budget: TokenBudget
    ) -> (context: AssembledContext, updatedBudget: TokenBudget) {
        var systemPrompt = AgentPrompts.plannerSystem
        if let guidance = toolGuidance, !guidance.isEmpty {
            systemPrompt += "\n" + guidance
        }

        var userContent = "User intent: \(intent)\n"
        if let ws = workspaceSummary {
            userContent += "\nWorkspace:\n\(ws)\n"
        }
        if let pm = projectMemory {
            userContent += "\nProject memory:\n\(pm)\n"
        }
        if let um = userModel, !um.isEmpty {
            userContent += "\nAbout the user (apply their preferences and style):\n\(um)\n"
        }

        let messages: [LLMMessage] = [.user(userContent)]

        let estimate = estimateTokens(
            systemPrompt: systemPrompt,
            messages: messages,
            tools: tools
        )

        var updatedBudget = budget
        updatedBudget.record(tokens: estimate)

        let context = AssembledContext(
            systemPrompt: systemPrompt,
            messages: messages,
            tools: tools,
            totalTokenEstimate: estimate
        )

        return (context, updatedBudget)
    }

    /// Assemble context for the execution phase (proposing the next tool call).
    ///
    /// Includes step history with truncation of older observations when
    /// the budget is tight.
    ///
    /// - Parameters:
    ///   - intent: The user's original request.
    ///   - plan: The current plan.
    ///   - steps: Completed steps so far.
    ///   - currentStepIndex: The index of the step being proposed.
    ///   - workspaceSummary: Workspace summary.
    ///   - tools: Available tool schemas.
    ///   - budget: Current token budget.
    /// - Returns: Assembled context and updated token budget.
    public func assembleForExecution(
        intent: String,
        plan: Plan,
        steps: [AgentStep],
        currentStepIndex: Int,
        workspaceSummary: String?,
        toolGuidance: String? = nil,
        tools: [ToolSchema],
        budget: TokenBudget
    ) -> (context: AssembledContext, updatedBudget: TokenBudget) {
        var systemPrompt = AgentPrompts.executorSystem
        if let guidance = toolGuidance, !guidance.isEmpty {
            systemPrompt += "\n" + guidance
        }

        var messages: [LLMMessage] = []

        // Build the initial user message with intent + plan
        var userContent = "Intent: \(intent)\n\nPlan:\n"
        for (i, step) in plan.steps.enumerated() {
            let status: String
            if i < currentStepIndex {
                status = "done"
            } else if i == currentStepIndex {
                status = "current"
            } else {
                status = "pending"
            }
            userContent += "\(i + 1). \(step.goal) [\(status)]\n"
        }
        if let ws = workspaceSummary {
            userContent += "\nWorkspace: \(ws)\n"
        }

        messages.append(.user(userContent))

        // Add step history as alternating assistant/tool messages
        let availableTokens = budget.remaining
        var historyTokens = 0
        let maxHistoryTokens = max(availableTokens / 2, 1000) // Reserve half for new output

        // Process steps newest-first for truncation, but add in order
        var stepMessages: [(LLMMessage, LLMMessage?)] = []
        for step in steps {
            guard let tc = step.toolCall else { continue }

            // Assistant message: the tool call
            let assistantMsg = LLMMessage(
                role: .assistant,
                content: [.toolUse(
                    id: tc.id,
                    name: tc.toolName,
                    input: tc.input
                )]
            )

            // Tool result message
            var toolMsg: LLMMessage?
            if let obs = step.observation {
                let resultContent: String
                if historyTokens < maxHistoryTokens {
                    resultContent = obs.summary
                    historyTokens += Self.estimateStringTokens(resultContent)
                } else {
                    // Truncate: just show a short marker
                    resultContent = "[truncated] \(obs.summary.prefix(100))"
                }
                toolMsg = LLMMessage(
                    role: .tool,
                    content: [.toolResult(
                        toolUseId: tc.id,
                        content: resultContent,
                        isError: obs.isError
                    )]
                )
            }

            stepMessages.append((assistantMsg, toolMsg))
        }

        for (assistantMsg, toolMsg) in stepMessages {
            messages.append(assistantMsg)
            if let toolMsg {
                messages.append(toolMsg)
            }
        }

        // Final user message: ask for next tool call
        let currentGoal = currentStepIndex < plan.steps.count
            ? plan.steps[currentStepIndex].goal
            : "Complete the task"
        messages.append(.user(
            "Now execute step \(currentStepIndex + 1): \(currentGoal). " +
            "Propose a single tool call."
        ))

        let estimate = estimateTokens(
            systemPrompt: systemPrompt,
            messages: messages,
            tools: tools
        )

        var updatedBudget = budget
        updatedBudget.record(tokens: estimate)

        let context = AssembledContext(
            systemPrompt: systemPrompt,
            messages: messages,
            tools: tools,
            totalTokenEstimate: estimate
        )

        return (context, updatedBudget)
    }

    /// Assemble context for the verification phase.
    public func assembleForVerification(
        step: AgentStep
    ) -> AssembledContext {
        let systemPrompt = AgentPrompts.verifierSystem

        var content = "Step goal: \(step.goal)\n"
        content += "Success criteria: \(step.successCriteria)\n"
        if let obs = step.observation {
            content += "\nObservation:\n\(obs.summary)\n"
            if obs.isError {
                content += "(The tool returned an error)\n"
            }
        }

        let messages: [LLMMessage] = [.user(content)]
        let estimate = estimateTokens(systemPrompt: systemPrompt, messages: messages, tools: [])

        return AssembledContext(
            systemPrompt: systemPrompt,
            messages: messages,
            tools: [],
            totalTokenEstimate: estimate
        )
    }

    // MARK: - Token Estimation

    /// Estimate the total tokens for a full request.
    public func estimateTokens(
        systemPrompt: String,
        messages: [LLMMessage],
        tools: [ToolSchema]
    ) -> Int {
        var total = Self.estimateStringTokens(systemPrompt)

        for message in messages {
            total += 4 // message overhead
            for block in message.content {
                switch block {
                case .text(let s):
                    total += Self.estimateStringTokens(s)
                case .thinking(let s):
                    total += Self.estimateStringTokens(s)
                case .toolUse(_, let name, let input):
                    total += Self.estimateStringTokens(name)
                    total += Self.estimateStringTokens(String(describing: input))
                case .toolResult(_, let content, _):
                    total += Self.estimateStringTokens(content)
                case .image(_, let data):
                    total += max(85, data.count / 750)
                }
            }
        }

        for tool in tools {
            total += Self.estimateStringTokens(tool.name)
            total += Self.estimateStringTokens(tool.description)
            total += Self.estimateStringTokens(String(describing: tool.inputSchema))
        }

        return total
    }

    /// Estimate tokens for a single string (~4 chars per token).
    public static func estimateStringTokens(_ string: String) -> Int {
        max(1, string.count / charsPerToken)
    }
}
