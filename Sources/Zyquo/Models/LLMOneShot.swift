import Foundation

// MARK: - LLMOneShot

/// A small helper for non-streaming, single-shot LLM calls: send a request,
/// drain the event stream, and return the full assistant text plus token usage.
///
/// Used by background learning passes (user-model distillation, skill
/// refinement) that need a complete response rather than a live stream.
public enum LLMOneShot {

    /// Result of a one-shot call.
    public struct Result: Sendable {
        public let text: String
        public let usage: TokenUsage?
    }

    /// Send a request and collect the full text response.
    ///
    /// - Parameters:
    ///   - request: The fully-formed LLM request.
    ///   - provider: The provider to send through.
    /// - Returns: The concatenated assistant text and final usage (if reported).
    /// - Throws: Any error surfaced by the provider stream.
    public static func complete(
        request: LLMRequest,
        provider: any LLMProvider
    ) async throws -> Result {
        var text = ""
        var usage: TokenUsage?

        let stream = provider.send(request: request, cancellation: nil)
        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                text += delta
            case .usage(let u):
                usage = u
            case .error(let err):
                throw err
            default:
                break
            }
        }

        return Result(text: text, usage: usage)
    }

    /// Extract the first top-level JSON object substring from a text blob.
    ///
    /// LLMs occasionally wrap JSON in prose or code fences; this pulls out the
    /// `{ ... }` span by brace matching so it can be decoded.
    public static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...idx])
                    }
                default:
                    break
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }
}
