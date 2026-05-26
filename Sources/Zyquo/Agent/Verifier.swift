import Foundation

/// LLM-backed step verification.
///
/// Given a step's goal, success criteria, and observation, the Verifier
/// asks the LLM to determine whether the step succeeded, failed, or
/// produced an unclear result.
///
/// Reference: CLAUDE.md §35.3
public struct Verifier: Sendable {

    public init() {}

    /// Verify whether a step achieved its stated goal.
    ///
    /// - Parameters:
    ///   - step: The completed agent step (must have an observation).
    ///   - context: Assembled context for verification.
    ///   - provider: The LLM provider to use.
    ///   - model: The model identifier.
    /// - Returns: A Verdict (pass/fail/unclear).
    public func verify(
        step: AgentStep,
        context: AssembledContext,
        provider: any LLMProvider,
        model: String
    ) async throws -> Verdict {
        guard step.observation != nil else {
            return .unclear
        }

        let request = LLMRequest(
            model: model,
            systemPrompt: context.systemPrompt,
            messages: context.messages,
            tools: [],
            toolChoice: .none,
            maxTokens: 256,
            temperature: 0.1
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

        return parseVerdict(from: responseText)
    }

    /// Quick local verification when an LLM call is not needed.
    ///
    /// Heuristic-based: if the observation is an error, verdict is fail.
    /// If not an error, verdict is pass. Used as a fast path before
    /// the LLM-based verification.
    public func quickVerify(step: AgentStep) -> Verdict {
        guard let observation = step.observation else {
            return .unclear
        }

        if observation.isError {
            return .fail
        }

        return .pass
    }

    // MARK: - Parsing

    /// Parse the LLM's response to extract a verdict.
    ///
    /// Looks for "pass", "fail", or "unclear" in the response text.
    internal func parseVerdict(from text: String) -> Verdict {
        let lower = text.lowercased()

        // Look for explicit verdict markers
        if lower.contains("verdict: pass") || lower.contains("verdict:pass") {
            return .pass
        }
        if lower.contains("verdict: fail") || lower.contains("verdict:fail") {
            return .fail
        }
        if lower.contains("verdict: unclear") || lower.contains("verdict:unclear") {
            return .unclear
        }

        // Fallback: check for the words themselves (prefer earliest match)
        let passRange = lower.range(of: "pass")
        let failRange = lower.range(of: "fail")

        if let pr = passRange, let fr = failRange {
            return pr.lowerBound < fr.lowerBound ? .pass : .fail
        }
        if passRange != nil { return .pass }
        if failRange != nil { return .fail }

        return .unclear
    }
}
