import Foundation
import Logging

// MARK: - HttpRequestTool

/// General-purpose HTTP request tool.
///
/// Methods are restricted to GET and HEAD by default. POST, PUT, DELETE
/// require elevated risk and explicit approval. Only HTTPS is permitted.
///
/// Reference: CLAUDE.md Appendix A.10
public struct HttpRequestTool: Tool, Sendable {
    public let name = "http.request"
    public let summary = "Make an HTTP request to a URL"
    public let documentation = """
        Sends an HTTP request. GET/HEAD are allowed by default (MODERATE risk).
        POST, PUT, DELETE, and PATCH escalate to DANGEROUS risk.
        Only HTTPS URLs are permitted.
        """
    public let defaultRisk: RiskLevel = .moderate
    public let isMutating = false

    /// HTTP methods considered read-only (MODERATE risk).
    public static let readOnlyMethods: Set<String> = ["GET", "HEAD", "OPTIONS"]

    /// HTTP methods that mutate (DANGEROUS risk).
    public static let mutatingMethods: Set<String> = ["POST", "PUT", "DELETE", "PATCH"]

    /// All allowed HTTP methods.
    public static let allAllowedMethods: Set<String> = readOnlyMethods.union(mutatingMethods)

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "url": PropertySchema(
                    type: "string",
                    description: "The URL to request (must be HTTPS)"
                ),
                "method": PropertySchema(
                    type: "string",
                    description: "HTTP method",
                    enumValues: Array(HttpRequestTool.allAllowedMethods).sorted(),
                    defaultValue: "GET"
                ),
                "headers": PropertySchema(
                    type: "object",
                    description: "Optional HTTP headers as key-value pairs"
                ),
                "body": PropertySchema(
                    type: "string",
                    description: "Optional request body (for POST/PUT/PATCH)"
                ),
                "timeout_s": PropertySchema(
                    type: "integer",
                    description: "Request timeout in seconds",
                    defaultValue: "30"
                ),
            ],
            required: ["url"]
        )
    }

    public init() {}

    /// Determine the risk level for a specific HTTP method.
    public static func riskForMethod(_ method: String) -> RiskLevel {
        let upper = method.uppercased()
        if readOnlyMethods.contains(upper) {
            return .moderate
        } else if mutatingMethods.contains(upper) {
            return .dangerous
        } else {
            return .critical
        }
    }

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let startTime = ContinuousClock.now

        // Parse URL
        guard let urlString = input["url"]?.stringValue, !urlString.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'url' parameter for http.request",
                remediation: "Provide a valid HTTPS URL"
            ))
        }

        guard let url = URL(string: urlString) else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Invalid URL: \(urlString)",
                remediation: "Provide a well-formed URL"
            ))
        }

        // Validate scheme
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else {
            throw ZyquoError.tool(ToolError(
                code: "tool.scheme_blocked",
                description: "URL scheme '\(url.scheme ?? "none")' is not allowed. Only HTTPS is permitted.",
                remediation: "Use an HTTPS URL"
            ))
        }

        // Parse method
        let method: String
        if let m = input["method"]?.stringValue {
            method = m.uppercased()
        } else {
            method = "GET"
        }

        guard HttpRequestTool.allAllowedMethods.contains(method) else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "HTTP method '\(method)' is not allowed",
                remediation: "Use one of: \(HttpRequestTool.allAllowedMethods.sorted().joined(separator: ", "))"
            ))
        }

        // Parse timeout
        let timeoutSeconds: TimeInterval
        if case .number(let t) = input["timeout_s"] {
            timeoutSeconds = max(1, min(t, 300))
        } else {
            timeoutSeconds = 30
        }

        context.logger.info("http.request: \(method) \(urlString)")

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutSeconds
        request.setValue("Zyquo/0.1.0", forHTTPHeaderField: "User-Agent")

        // Apply custom headers
        if case .object(let headers) = input["headers"] {
            for (key, value) in headers {
                if let strValue = value.stringValue {
                    request.setValue(strValue, forHTTPHeaderField: key)
                }
            }
        }

        // Apply body for mutating methods
        if HttpRequestTool.mutatingMethods.contains(method) {
            if let bodyStr = input["body"]?.stringValue {
                request.httpBody = bodyStr.data(using: .utf8)
                // Set content type if not already set
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }

        // Execute request
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = timeoutSeconds
        let session = URLSession(configuration: sessionConfig)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ZyquoError.tool(ToolError(
                code: "tool.network_error",
                description: "HTTP request failed: \(error.localizedDescription)",
                remediation: "Check the URL and your internet connection",
                underlying: error
            ))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let elapsed = elapsedMs(since: startTime)
            return ToolResult(
                summary: "HTTP request failed: invalid response type",
                durationMs: elapsed
            )
        }

        let statusCode = httpResponse.statusCode
        let elapsed = elapsedMs(since: startTime)

        // Extract response headers
        var responseHeaders: [String: JSONValue] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                responseHeaders[k] = .string(v)
            }
        }

        // Body as string (truncated to 512KB)
        let maxBody = 512 * 1024
        let truncated = data.count > maxBody
        let bodyData = truncated ? data.prefix(maxBody) : data
        let bodyString = String(data: bodyData, encoding: .utf8)
            ?? String(data: bodyData, encoding: .ascii)
            ?? "[binary content, \(data.count) bytes]"

        let summaryText = "\(method) \(urlString) -> HTTP \(statusCode) (\(data.count) bytes, \(elapsed)ms)"

        return ToolResult(
            summary: summaryText + "\n" + String(bodyString.prefix(1000)),
            payload: .object([
                "status": .number(Double(statusCode)),
                "headers": .object(responseHeaders),
                "body": .string(bodyString),
                "size": .number(Double(data.count)),
                "truncated": .bool(truncated),
            ]),
            durationMs: elapsed,
            tokenHint: bodyString.count / 4
        )
    }

    // MARK: - Helpers

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
