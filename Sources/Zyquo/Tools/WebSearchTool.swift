import Foundation
import Logging

// MARK: - WebSearchTool

/// Search the web using DuckDuckGo HTML API.
///
/// This tool performs a web search and returns titles, URLs, and snippets.
/// No API key is required — it uses the DuckDuckGo HTML endpoint.
///
/// Reference: CLAUDE.md Appendix A.10
public struct WebSearchTool: Tool, Sendable {
    public let name = "web.search"
    public let summary = "Search the web via DuckDuckGo"
    public let documentation = """
        Performs a web search using DuckDuckGo's HTML endpoint.
        Returns a list of results with title, URL, and snippet.
        No API key required.
        """
    public let defaultRisk: RiskLevel = .safe
    public let isMutating = false

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "query": PropertySchema(
                    type: "string",
                    description: "Search query string"
                ),
                "limit": PropertySchema(
                    type: "integer",
                    description: "Maximum number of results to return",
                    defaultValue: "5"
                ),
            ],
            required: ["query"]
        )
    }

    public init() {}

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let startTime = ContinuousClock.now

        guard let query = input["query"]?.stringValue, !query.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'query' parameter for web.search",
                remediation: "Provide a non-empty search query string"
            ))
        }

        let limit: Int
        if case .number(let n) = input["limit"] {
            limit = max(1, min(Int(n), 20))
        } else {
            limit = 5
        }

        context.logger.info("web.search: querying '\(query)' (limit \(limit))")

        // Build DuckDuckGo HTML search URL
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)")
        else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Failed to encode search query",
                remediation: "Simplify the search query"
            ))
        }

        // Fetch HTML
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let elapsed = elapsedMs(since: startTime)
            throw ZyquoError.tool(ToolError(
                code: "tool.network_error",
                description: "Web search failed: \(error.localizedDescription)",
                remediation: "Check your internet connection and try again",
                underlying: error
            ))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let elapsed = elapsedMs(since: startTime)
            return ToolResult(
                summary: "Web search failed: invalid response",
                durationMs: elapsed
            )
        }

        guard httpResponse.statusCode == 200 else {
            let elapsed = elapsedMs(since: startTime)
            return ToolResult(
                summary: "Web search returned HTTP \(httpResponse.statusCode)",
                durationMs: elapsed
            )
        }

        let html = String(data: data, encoding: .utf8) ?? ""
        let results = WebSearchTool.parseResults(from: html, limit: limit)
        let elapsed = elapsedMs(since: startTime)

        if results.isEmpty {
            return ToolResult(
                summary: "No results found for '\(query)'",
                payload: .array([]),
                durationMs: elapsed
            )
        }

        // Build summary
        var summaryLines = ["Found \(results.count) result(s) for '\(query)':"]
        for (i, r) in results.enumerated() {
            summaryLines.append("\(i + 1). \(r.title)")
            summaryLines.append("   \(r.url)")
            if !r.snippet.isEmpty {
                summaryLines.append("   \(r.snippet.prefix(120))")
            }
        }

        let payloadArray: [JSONValue] = results.map { result in
            .object([
                "title": .string(result.title),
                "url": .string(result.url),
                "snippet": .string(result.snippet),
            ])
        }

        let summaryText = summaryLines.joined(separator: "\n")
        return ToolResult(
            summary: summaryText,
            payload: .array(payloadArray),
            durationMs: elapsed,
            tokenHint: summaryText.count / 4
        )
    }

    // MARK: - HTML Parsing

    /// A single search result.
    struct SearchResult {
        let title: String
        let url: String
        let snippet: String
    }

    /// Parse DuckDuckGo HTML results using pattern matching.
    ///
    /// The DuckDuckGo HTML page contains result blocks with class "result".
    /// Each block has a link with class "result__a" and a snippet with class "result__snippet".
    static func parseResults(from html: String, limit: Int) -> [SearchResult] {
        var results: [SearchResult] = []

        // Extract result blocks — each contains class="result__a" for title/link
        // and class="result__snippet" for snippet text.
        let resultPattern = #"class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*(?:<[^/][^>]*>[^<]*)*)</a>"#
        let snippetPattern = #"class="result__snippet"[^>]*>([^<]*(?:<[^/][^>]*>[^<]*)*)</[^>]*>"#

        guard let resultRegex = try? NSRegularExpression(pattern: resultPattern, options: []),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [])
        else {
            return results
        }

        let nsHtml = html as NSString
        let range = NSRange(location: 0, length: nsHtml.length)

        let resultMatches = resultRegex.matches(in: html, range: range)
        let snippetMatches = snippetRegex.matches(in: html, range: range)

        for (i, match) in resultMatches.enumerated() {
            if results.count >= limit { break }

            guard match.numberOfRanges >= 3 else { continue }

            let urlRange = match.range(at: 1)
            let titleRange = match.range(at: 2)
            guard urlRange.location != NSNotFound, titleRange.location != NSNotFound else { continue }

            var rawUrl = nsHtml.substring(with: urlRange)
            let rawTitle = nsHtml.substring(with: titleRange)

            // DuckDuckGo wraps URLs in a redirect; try to extract the actual URL
            if let actual = extractActualURL(from: rawUrl) {
                rawUrl = actual
            }

            let title = stripHTML(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty, !url.isEmpty else { continue }

            // Find corresponding snippet
            var snippet = ""
            if i < snippetMatches.count {
                let snippetMatch = snippetMatches[i]
                if snippetMatch.numberOfRanges >= 2 {
                    let snippetRange = snippetMatch.range(at: 1)
                    if snippetRange.location != NSNotFound {
                        snippet = stripHTML(nsHtml.substring(with: snippetRange))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            results.append(SearchResult(title: title, url: url, snippet: snippet))
        }

        return results
    }

    /// Extract the actual URL from a DuckDuckGo redirect URL.
    private static func extractActualURL(from ddgURL: String) -> String? {
        guard ddgURL.contains("uddg=") else { return nil }
        guard let components = URLComponents(string: ddgURL),
              let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value
        else { return nil }
        return uddg
    }

    /// Strip HTML tags and decode common entities.
    static func stripHTML(_ html: String) -> String {
        var result = html
        // Remove tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = tagRegex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // Decode entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
        return result
    }

    // MARK: - Helpers

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
