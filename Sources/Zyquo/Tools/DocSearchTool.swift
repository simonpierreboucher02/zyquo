import Foundation
import Logging

// MARK: - DocSearchTool

/// Search developer documentation from common sources.
///
/// Constructs search URLs for known documentation sources and fetches
/// relevant content. Supported sources: Swift, Python, MDN, npm.
///
/// Reference: CLAUDE.md Appendix A.10
public struct DocSearchTool: Tool, Sendable {
    public let name = "docs.search"
    public let summary = "Search developer documentation"
    public let documentation = """
        Searches developer documentation from known sources:
        swift (Swift Documentation), python (Python Docs),
        mdn (MDN Web Docs), npm (npm registry).
        Returns relevant documentation excerpts.
        """
    public let defaultRisk: RiskLevel = .safe
    public let isMutating = false

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "query": PropertySchema(
                    type: "string",
                    description: "Documentation search query"
                ),
                "source": PropertySchema(
                    type: "string",
                    description: "Documentation source to search",
                    enumValues: DocSource.allCases.map(\.rawValue),
                    defaultValue: "mdn"
                ),
            ],
            required: ["query"]
        )
    }

    public init() {}

    // MARK: - Doc Sources

    /// Supported documentation sources.
    public enum DocSource: String, Sendable, CaseIterable {
        case swift
        case python
        case mdn
        case npm
    }

    /// Build the search URL for a given source and query.
    static func searchURL(source: DocSource, query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        switch source {
        case .swift:
            // Apple Developer Documentation search
            return URL(string: "https://developer.apple.com/tutorials/data/search/\(encoded).json")
        case .python:
            // Python docs search
            return URL(string: "https://docs.python.org/3/search.html?q=\(encoded)")
        case .mdn:
            // MDN search API
            return URL(string: "https://developer.mozilla.org/api/v1/search?q=\(encoded)&locale=en-US")
        case .npm:
            // npm registry search
            return URL(string: "https://registry.npmjs.org/-/v1/search?text=\(encoded)&size=5")
        }
    }

    // MARK: - Execution

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let startTime = ContinuousClock.now

        guard let query = input["query"]?.stringValue, !query.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'query' parameter for docs.search",
                remediation: "Provide a documentation search query"
            ))
        }

        let source: DocSource
        if let sourceStr = input["source"]?.stringValue,
           let parsed = DocSource(rawValue: sourceStr.lowercased()) {
            source = parsed
        } else {
            source = .mdn
        }

        context.logger.info("docs.search: '\(query)' on \(source.rawValue)")

        guard let url = DocSearchTool.searchURL(source: source, query: query) else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Failed to construct search URL for '\(query)'",
                remediation: "Simplify the search query"
            ))
        }

        // Fetch documentation
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Zyquo/0.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ZyquoError.tool(ToolError(
                code: "tool.network_error",
                description: "Documentation search failed: \(error.localizedDescription)",
                remediation: "Check your internet connection and try again",
                underlying: error
            ))
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let elapsed = elapsedMs(since: startTime)
            return ToolResult(
                summary: "Documentation search returned HTTP \(status) for '\(query)' on \(source.rawValue)",
                durationMs: elapsed
            )
        }

        let elapsed = elapsedMs(since: startTime)
        let content = String(data: data, encoding: .utf8) ?? ""

        // Parse results based on source
        let results = parseResults(source: source, content: content, query: query)
        let summaryText: String
        let payload: JSONValue

        if results.isEmpty {
            summaryText = "No documentation found for '\(query)' on \(source.rawValue)"
            payload = .array([])
        } else {
            var lines = ["Found \(results.count) result(s) for '\(query)' on \(source.rawValue):"]
            for (i, r) in results.enumerated() {
                lines.append("\(i + 1). \(r.title)")
                if !r.url.isEmpty {
                    lines.append("   \(r.url)")
                }
                if !r.excerpt.isEmpty {
                    lines.append("   \(r.excerpt.prefix(200))")
                }
            }
            summaryText = lines.joined(separator: "\n")
            payload = .array(results.map { r in
                .object([
                    "title": .string(r.title),
                    "url": .string(r.url),
                    "excerpt": .string(r.excerpt),
                ])
            })
        }

        return ToolResult(
            summary: summaryText,
            payload: payload,
            durationMs: elapsed,
            tokenHint: summaryText.count / 4
        )
    }

    // MARK: - Result Parsing

    struct DocResult {
        let title: String
        let url: String
        let excerpt: String
    }

    private func parseResults(source: DocSource, content: String, query: String) -> [DocResult] {
        switch source {
        case .mdn:
            return parseMDNResults(content)
        case .npm:
            return parseNPMResults(content)
        case .swift:
            return parseSwiftResults(content)
        case .python:
            return parsePythonResults(content, query: query)
        }
    }

    /// Parse MDN JSON API results.
    private func parseMDNResults(_ json: String) -> [DocResult] {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let documents = parsed["documents"] as? [[String: Any]]
        else { return [] }

        return documents.prefix(5).compactMap { doc in
            guard let title = doc["title"] as? String else { return nil }
            let slug = doc["mdn_url"] as? String ?? ""
            let url = slug.isEmpty ? "" : "https://developer.mozilla.org\(slug)"
            let summary = doc["summary"] as? String ?? ""
            return DocResult(title: title, url: url, excerpt: summary)
        }
    }

    /// Parse npm registry search results.
    private func parseNPMResults(_ json: String) -> [DocResult] {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objects = parsed["objects"] as? [[String: Any]]
        else { return [] }

        return objects.prefix(5).compactMap { obj in
            guard let pkg = obj["package"] as? [String: Any],
                  let name = pkg["name"] as? String
            else { return nil }
            let description = pkg["description"] as? String ?? ""
            let version = pkg["version"] as? String ?? ""
            let url = "https://www.npmjs.com/package/\(name)"
            let title = version.isEmpty ? name : "\(name)@\(version)"
            return DocResult(title: title, url: url, excerpt: description)
        }
    }

    /// Parse Swift documentation results (simplified).
    private func parseSwiftResults(_ json: String) -> [DocResult] {
        // Apple's search endpoint returns JSON with hits
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [DocResult(
                title: "Swift Documentation",
                url: "https://developer.apple.com/documentation/swift",
                excerpt: "Search Apple Developer Documentation for more details."
            )]
        }

        if let results = parsed["results"] as? [[String: Any]] {
            return results.prefix(5).compactMap { result in
                let title = result["title"] as? String ?? "Untitled"
                let path = result["path"] as? String ?? ""
                let url = path.isEmpty ? "" : "https://developer.apple.com\(path)"
                let description = result["description"] as? String ?? ""
                return DocResult(title: title, url: url, excerpt: description)
            }
        }

        return []
    }

    /// Parse Python docs results (HTML-based, simplified).
    private func parsePythonResults(_ html: String, query: String) -> [DocResult] {
        // Python docs search returns HTML; provide a useful fallback
        return [DocResult(
            title: "Python 3 Documentation: \(query)",
            url: "https://docs.python.org/3/search.html?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)",
            excerpt: "Search Python 3 documentation for '\(query)'. Visit the URL for full results."
        )]
    }

    // MARK: - Helpers

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
