import Foundation

/// LLM-backed plan generation and tool call proposal.
///
/// The Planner talks to the LLM twice during the loop:
/// 1. `plan()` — at the start, to decompose the intent into numbered steps.
/// 2. `propose()` — per step, to produce a concrete tool call.
///
/// Reference: CLAUDE.md §16.1, §35.1, §35.2
public struct Planner: Sendable {

    public init() {}

    // MARK: - Plan Generation

    /// Ask the LLM to produce a plan of small, verifiable steps.
    ///
    /// - Parameters:
    ///   - intent: The user's request.
    ///   - context: Assembled context including workspace info and tools.
    ///   - provider: The LLM provider to use.
    ///   - model: The model identifier.
    /// - Returns: A parsed Plan with ordered steps.
    public func plan(
        intent: String,
        context: AssembledContext,
        provider: any LLMProvider,
        model: String
    ) async throws -> Plan {
        let request = LLMRequest(
            model: model,
            systemPrompt: context.systemPrompt,
            messages: context.messages,
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

        return parsePlan(from: responseText)
    }

    // MARK: - Tool Call Proposal

    /// Ask the LLM to propose a single tool call for the current step.
    ///
    /// - Parameters:
    ///   - step: The plan step to execute.
    ///   - state: Current agent state (for context).
    ///   - context: Assembled context with step history.
    ///   - provider: The LLM provider.
    ///   - model: The model identifier.
    /// - Returns: A ToolCall, or nil if the LLM decided no tool call is needed.
    public func propose(
        step: PlanStep,
        state: AgentState,
        context: AssembledContext,
        provider: any LLMProvider,
        model: String
    ) async throws -> ToolCall? {
        let request = LLMRequest(
            model: model,
            systemPrompt: context.systemPrompt,
            messages: context.messages,
            tools: context.tools,
            toolChoice: .any,
            maxTokens: 4096,
            temperature: 0.2
        )

        var toolName: String?
        var toolId: String?
        var inputBuffer = ""

        let stream = provider.send(request: request, cancellation: nil)

        for try await event in stream {
            switch event {
            case .toolUseStart(let meta):
                toolName = meta.name
                toolId = meta.id
                inputBuffer = ""
            case .toolUseInputDelta(let delta):
                inputBuffer += delta
            case .toolUseEnd:
                break
            case .error(let error):
                throw ZyquoError.provider(error)
            default:
                break
            }
        }

        guard let name = toolName, let id = toolId else {
            return nil
        }

        let input = parseToolInput(inputBuffer)
        return ToolCall(toolName: name, input: input, id: id)
    }

    // MARK: - Parsing

    /// Parse the LLM's response into a structured Plan.
    ///
    /// Expects numbered lines like:
    /// ```
    /// 1. Goal text | Success criteria text
    /// 2. Goal text | Success criteria text
    /// ```
    /// Falls back to treating each numbered line as a goal with generic criteria.
    internal func parsePlan(from text: String) -> Plan {
        var steps: [PlanStep] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match lines starting with a number followed by . or )
            guard let firstChar = trimmed.first, firstChar.isNumber else { continue }

            // Strip the number prefix (e.g. "1. " or "1) ")
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

            // Split on | for goal | criteria
            let parts = content.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }

            let goal = parts[0]
            let criteria = parts.count > 1 ? parts[1] : "Step completes without errors"

            steps.append(PlanStep(goal: goal, successCriteria: criteria))
        }

        // If parsing found nothing, create a single-step plan
        if steps.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            steps.append(PlanStep(
                goal: text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200).description,
                successCriteria: "Step completes without errors"
            ))
        }

        return Plan(steps: steps, isComplete: false)
    }

    /// Parse the tool input JSON string into a dictionary.
    internal func parseToolInput(_ jsonString: String) -> [String: JSONValue] {
        guard !jsonString.isEmpty,
              let data = jsonString.data(using: .utf8) else {
            return [:]
        }

        do {
            let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)
            return decoded
        } catch {
            // If JSON parsing fails, wrap the raw string as the "command" field
            return ["raw_input": .string(jsonString)]
        }
    }
}
