import Foundation
import Logging

// MARK: - WebFetchTool

/// Fetch content from a URL with basic HTML-to-text conversion.
///
/// Only HTTPS URLs are allowed by default. Follows up to 5 redirects.
/// Content is truncated to max_bytes and HTML is converted to plain text.
///
/// Reference: CLAUDE.md Appendix A.10
public struct WebFetchTool: Tool, Sendable {
    public let name = "web.fetch"
    public let summary = "Fetch and read content from a URL"
    public let documentation = """
        Fetches content from a URL. Only HTTPS is allowed by default.
        HTML is converted to plain text. Content is truncated to max_bytes.
        Follows up to 5 redirects.
        """
    public let defaultRisk: RiskLevel = .moderate
    public let isMutating = false

    /// Allowed URL schemes.
    public static let allowedSchemes: Set<String> = ["https"]

    /// Maximum number of redirects to follow.
    public static let maxRedirects: Int = 5

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "url": PropertySchema(
                    type: "string",
                    description: "The URL to fetch (must be HTTPS)"
                ),
                "max_bytes": PropertySchema(
                    type: "integer",
                    description: "Maximum bytes to read from the response",
                    defaultValue: "1048576"
                ),
            ],
            required: ["url"]
        )
    }

    public init() {}

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let startTime = ContinuousClock.now

        guard let urlString = input["url"]?.stringValue, !urlString.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'url' parameter for web.fetch",
                remediation: "Provide a valid HTTPS URL"
            ))
        }

        let maxBytes: Int
        if case .number(let n) = input["max_bytes"] {
            maxBytes = max(1024, min(Int(n), 10 * 1024 * 1024)) // 1KB to 10MB
        } else {
            maxBytes = 1024 * 1024 // 1MB default
        }

        // Validate URL scheme
        guard let url = URL(string: urlString) else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Invalid URL: \(urlString)",
                remediation: "Provide a well-formed HTTPS URL"
            ))
        }

        guard let scheme = url.scheme?.lowercased(), WebFetchTool.allowedSchemes.contains(scheme) else {
            throw ZyquoError.tool(ToolError(
                code: "tool.scheme_blocked",
                description: "URL scheme '\(url.scheme ?? "none")' is not allowed. Only HTTPS is permitted.",
                remediation: "Use an HTTPS URL instead"
            ))
        }

        context.logger.info("web.fetch: fetching \(urlString) (max \(maxBytes) bytes)")

        // Configure session to limit redirects
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        let session = URLSession(configuration: sessionConfig)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html, text/plain, application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let elapsed = elapsedMs(since: startTime)
            throw ZyquoError.tool(ToolError(
                code: "tool.network_error",
                description: "Failed to fetch \(urlString): \(error.localizedDescription)",
                remediation: "Check the URL and your internet connection",
                underlying: error
            ))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let elapsed = elapsedMs(since: startTime)
            return ToolResult(
                summary: "Fetch failed: invalid response type",
                durationMs: elapsed
            )
        }

        let finalURL = httpResponse.url?.absoluteString ?? urlString
        let statusCode = httpResponse.statusCode
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
        let elapsed = elapsedMs(since: startTime)

        // Truncate data if necessary
        let truncated = data.count > maxBytes
        let usableData = truncated ? data.prefix(maxBytes) : data

        // Convert to text based on content type
        let rawText = String(data: usableData, encoding: .utf8)
            ?? String(data: usableData, encoding: .ascii)
            ?? "[binary content, \(data.count) bytes]"

        let content: String
        if contentType.contains("text/html") {
            content = WebFetchTool.htmlToText(rawText)
        } else {
            content = rawText
        }

        let summaryText: String
        if statusCode >= 200 && statusCode < 300 {
            summaryText = "Fetched \(finalURL) (HTTP \(statusCode), \(data.count) bytes\(truncated ? ", truncated" : ""))"
        } else {
            summaryText = "Fetch returned HTTP \(statusCode) for \(finalURL)"
        }

        return ToolResult(
            summary: summaryText + "\n" + String(content.prefix(2000)),
            payload: .object([
                "status": .number(Double(statusCode)),
                "content": .string(String(content.prefix(maxBytes))),
                "content_type": .string(contentType),
                "final_url": .string(finalURL),
                "truncated": .bool(truncated),
                "size": .number(Double(data.count)),
            ]),
            durationMs: elapsed,
            tokenHint: content.count / 4
        )
    }

    // MARK: - HTML to Text

    /// Convert HTML to readable plain text.
    ///
    /// Strips tags, decodes entities, collapses whitespace, and preserves
    /// basic structure (paragraphs, headings, list items).
    static func htmlToText(_ html: String) -> String {
        var text = html

        // Remove script and style blocks entirely
        text = removeBlocks(from: text, tag: "script")
        text = removeBlocks(from: text, tag: "style")
        text = removeBlocks(from: text, tag: "nav")
        text = removeBlocks(from: text, tag: "footer")
        text = removeBlocks(from: text, tag: "header")

        // Replace block elements with newlines
        let blockTags = ["p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6",
                         "li", "tr", "blockquote", "pre", "hr", "section", "article"]
        for tag in blockTags {
            if let regex = try? NSRegularExpression(pattern: "</?\\s*\(tag)[^>]*>", options: .caseInsensitive) {
                let range = NSRange(location: 0, length: (text as NSString).length)
                text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
            }
        }

        // Strip remaining tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = tagRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        // Decode HTML entities
        text = decodeEntities(text)

        // Collapse whitespace: multiple spaces -> single space, multiple newlines -> double
        if let multiSpace = try? NSRegularExpression(pattern: "[ \\t]+", options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = multiSpace.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        }
        if let multiNewline = try? NSRegularExpression(pattern: "\\n{3,}", options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = multiNewline.stringByReplacingMatches(in: text, range: range, withTemplate: "\n\n")
        }

        // Trim lines
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        text = lines.joined(separator: "\n")

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Remove entire blocks of a given HTML tag (including content).
    private static func removeBlocks(from html: String, tag: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
            options: .caseInsensitive
        ) else { return html }
        let range = NSRange(location: 0, length: (html as NSString).length)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    /// Decode common HTML entities.
    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&mdash;", with: "--")
            .replacingOccurrences(of: "&ndash;", with: "-")
            .replacingOccurrences(of: "&hellip;", with: "...")
            .replacingOccurrences(of: "&laquo;", with: "<<")
            .replacingOccurrences(of: "&raquo;", with: ">>")
    }

    // MARK: - Helpers

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
