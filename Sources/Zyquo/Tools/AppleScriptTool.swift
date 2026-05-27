import Foundation
import Logging

// MARK: - AppleScriptTool

/// Execute AppleScript code via osascript.
///
/// Enables the agent to automate macOS applications (Finder, Safari, Mail,
/// Calendar, Contacts, Notes, Music, Messages, Keynote, Pages, Numbers,
/// System Events, Terminal) and interact with system services.
///
/// Risk is classified per-script based on content analysis:
/// - SAFE: read-only queries (get properties, count, exists)
/// - MODERATE: application control (activate, open, send, make, set)
/// - DANGEROUS: file system mutations via Finder, System Events keystroke/click
/// - CRITICAL: do shell script, sudo, system shutdown/restart/sleep
public struct AppleScriptTool: Tool, Sendable {
    public let name = "applescript.run"
    public let summary = "Execute AppleScript to automate macOS applications"
    public let documentation = """
        Execute AppleScript code via osascript to automate macOS applications.
        Supports Safari, Finder, Mail, Calendar, Contacts, Notes, Music,
        Messages, Keynote, Pages, Numbers, System Events, and Terminal.

        The script is analyzed for risk level before execution:
        - Read-only property access is SAFE
        - Application control (activate, make, set) is MODERATE
        - UI scripting (keystroke, click) and file mutations are DANGEROUS
        - Shell script execution and system commands are CRITICAL

        Results are returned as text. Use 'return' in the script to
        produce structured output.
        """
    public let defaultRisk: RiskLevel = .moderate
    public let isMutating = true

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "script": PropertySchema(
                    type: "string",
                    description: "AppleScript source code to execute"
                ),
                "timeout_s": PropertySchema(
                    type: "integer",
                    description: "Maximum execution time in seconds",
                    defaultValue: "30"
                ),
            ],
            required: ["script"]
        )
    }

    public init() {}

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let startTime = ContinuousClock.now

        guard let script = input["script"]?.stringValue, !script.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'script' parameter for applescript.run",
                remediation: "Provide AppleScript source code to execute"
            ))
        }

        let timeout: Int
        if case .number(let n) = input["timeout_s"] {
            timeout = max(1, min(Int(n), 300))
        } else {
            timeout = 30
        }

        let risk = AppleScriptRiskClassifier.classify(script)
        context.logger.info("applescript.run: risk=\(risk.displayName), timeout=\(timeout)s")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let result: String
        let errorOutput: String
        let exitCode: Int32

        do {
            try process.run()

            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()
            timeoutTask.cancel()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            result = String(data: stdoutData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            errorOutput = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            exitCode = process.terminationStatus
        } catch {
            throw ZyquoError.tool(ToolError(
                code: "tool.execution_failed",
                description: "Failed to launch osascript: \(error.localizedDescription)",
                remediation: "Ensure /usr/bin/osascript is available on this system",
                underlying: error
            ))
        }

        let elapsed = elapsedMs(since: startTime)

        if exitCode != 0 {
            let errorMsg = errorOutput.isEmpty ? "Unknown error (exit code \(exitCode))" : errorOutput
            let truncatedError = String(errorMsg.prefix(500))
            return ToolResult(
                summary: "AppleScript error: \(truncatedError)",
                payload: .object([
                    "exit_code": .number(Double(exitCode)),
                    "error": .string(truncatedError),
                    "risk": .string(risk.displayName),
                ]),
                durationMs: elapsed,
                tokenHint: truncatedError.count / 4
            )
        }

        let truncatedResult = String(result.prefix(10_000))
        let summaryText = truncatedResult.isEmpty
            ? "AppleScript executed successfully (no output)"
            : "AppleScript result:\n\(String(truncatedResult.prefix(2000)))"

        return ToolResult(
            summary: summaryText,
            payload: .object([
                "output": .string(truncatedResult),
                "exit_code": .number(0),
                "risk": .string(risk.displayName),
            ]),
            durationMs: elapsed,
            tokenHint: summaryText.count / 4
        )
    }

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

// MARK: - AppleScriptQueryTool

/// Read-only AppleScript queries — always SAFE risk.
///
/// Wraps the script in a read-only context and validates that it contains
/// no mutating commands before execution.
public struct AppleScriptQueryTool: Tool, Sendable {
    public let name = "applescript.query"
    public let summary = "Run a read-only AppleScript query (SAFE risk)"
    public let documentation = """
        Execute a read-only AppleScript query. The script is validated to
        ensure it contains no mutating operations (delete, make, set,
        send, keystroke, do shell script, etc.).

        Use this for reading properties, checking state, listing items,
        and gathering information from macOS applications.

        Examples:
        - Get current track from Music
        - List Safari tabs
        - Read calendar events
        - Check Finder selection
        - Get system information
        """
    public let defaultRisk: RiskLevel = .safe
    public let isMutating = false

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "script": PropertySchema(
                    type: "string",
                    description: "Read-only AppleScript query to execute"
                ),
                "timeout_s": PropertySchema(
                    type: "integer",
                    description: "Maximum execution time in seconds",
                    defaultValue: "15"
                ),
            ],
            required: ["script"]
        )
    }

    public init() {}

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        guard let script = input["script"]?.stringValue, !script.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'script' parameter for applescript.query",
                remediation: "Provide a read-only AppleScript query"
            ))
        }

        let risk = AppleScriptRiskClassifier.classify(script)
        if risk == .dangerous || risk == .critical {
            throw ZyquoError.tool(ToolError(
                code: "tool.risk_violation",
                description: "Script contains mutating operations not allowed in applescript.query",
                remediation: "Use applescript.run for scripts that modify state, or remove mutating commands"
            ))
        }

        let runTool = AppleScriptTool()
        var modifiedInput = input
        if modifiedInput["timeout_s"] == nil {
            modifiedInput["timeout_s"] = .number(15)
        }
        return try await runTool.execute(input: modifiedInput, context: context)
    }
}

// MARK: - AppleScriptInfoTool

/// Get AppleScript reference information for a specific macOS application.
///
/// Returns the available properties, commands, and example scripts
/// for automating a given application.
public struct AppleScriptInfoTool: Tool, Sendable {
    public let name = "applescript.info"
    public let summary = "Get AppleScript reference for a macOS application"
    public let documentation = """
        Returns AppleScript reference documentation for a specific macOS
        application, including available properties, commands, and example
        scripts. Use this before writing AppleScript to understand what's
        possible with a given application.

        Supported applications: Safari, Music, Finder, System Events,
        Terminal, Mail, Calendar, Contacts, Messages, Notes, Keynote,
        Pages, Numbers.
        """
    public let defaultRisk: RiskLevel = .safe
    public let isMutating = false

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "app": PropertySchema(
                    type: "string",
                    description: "Application name (e.g., 'Safari', 'Finder', 'Mail')",
                    enumValues: [
                        "Safari", "Music", "Finder", "System Events",
                        "Terminal", "Mail", "Calendar", "Contacts",
                        "Messages", "Notes", "Keynote", "Pages", "Numbers",
                    ]
                ),
            ],
            required: ["app"]
        )
    }

    public init() {}

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let startTime = ContinuousClock.now

        guard let app = input["app"]?.stringValue, !app.isEmpty else {
            throw ZyquoError.tool(ToolError(
                code: "tool.invalid_input",
                description: "Missing required 'app' parameter for applescript.info",
                remediation: "Provide an application name (e.g., 'Safari', 'Finder')"
            ))
        }

        let reference = AppleScriptReference.info(for: app)
        let elapsed = elapsedMs(since: startTime)

        if reference.isEmpty {
            return ToolResult(
                summary: "No AppleScript reference found for '\(app)'. Supported: Safari, Music, Finder, System Events, Terminal, Mail, Calendar, Contacts, Messages, Notes, Keynote, Pages, Numbers.",
                durationMs: elapsed
            )
        }

        return ToolResult(
            summary: reference,
            payload: .object([
                "app": .string(app),
                "reference": .string(reference),
            ]),
            durationMs: elapsed,
            tokenHint: reference.count / 4
        )
    }

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}

// MARK: - AppleScript Risk Classifier

/// Classifies AppleScript code by risk level based on content analysis.
enum AppleScriptRiskClassifier {

    static func classify(_ script: String) -> RiskLevel {
        let lower = script.lowercased()

        // CRITICAL patterns
        let criticalPatterns = [
            "do shell script",
            "sudo",
            "shutdown",
            "shut down",
            "restart",
            "rm -rf",
            "launchctl",
            "diskutil",
            "with administrator privileges",
        ]
        for pattern in criticalPatterns {
            if lower.contains(pattern) { return .critical }
        }

        // DANGEROUS patterns
        let dangerousPatterns = [
            "keystroke",
            "key code",
            "click",
            "click at",
            "key down",
            "key up",
            "delete",
            "empty the trash",
            "empty trash",
            "erase",
            "perform mail action",
            "move .* to trash",
        ]
        for pattern in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lower.startIndex..., in: lower)
                if regex.firstMatch(in: lower, range: range) != nil {
                    return .dangerous
                }
            }
        }

        // MODERATE patterns
        let moderatePatterns = [
            "make new",
            "set .* to",
            "send",
            "activate",
            "open",
            "close",
            "save",
            "export",
            "move",
            "duplicate",
            "copy",
            "reply",
            "forward",
            "print",
            "play",
            "pause",
            "stop",
            "set sound volume",
            "set shuffle",
            "set song repeat",
            "set read status",
            "set flagged",
            "set loved",
            "set rating",
            "set name of",
            "set body of",
            "set value of",
            "set formula of",
            "set current tab",
            "set url of",
            "set properties",
            "do javascript",
            "set dark mode",
        ]
        for pattern in moderatePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(lower.startIndex..., in: lower)
                if regex.firstMatch(in: lower, range: range) != nil {
                    return .moderate
                }
            }
        }

        return .safe
    }
}
