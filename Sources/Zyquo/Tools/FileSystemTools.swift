import Foundation
import Logging

// MARK: - FileWriteTool

/// Write (create or overwrite) a UTF-8 text file inside the workspace.
///
/// All writes are boundary-checked: the resolved path MUST be inside the
/// workspace root. Intermediate directories are created as needed. The write
/// is atomic (temp + rename).
///
/// Reference: CLAUDE.md §17.1 (file.write), Appendix A.2
public struct FileWriteTool: Tool, Sendable {
    public let name = "file.write"
    public let summary = "Write or overwrite a text file inside the workspace"
    public let documentation = """
        Creates or overwrites a UTF-8 text file. The path must be inside the
        workspace. Intermediate directories are created automatically. Writes
        are atomic. Use file.patch for surgical edits to existing files.
        """
    public let defaultRisk: RiskLevel = .moderate
    public let isMutating = true

    public init() {}

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "path": PropertySchema(
                    type: "string",
                    description: "File path, relative to the workspace root or absolute inside it"
                ),
                "content": PropertySchema(
                    type: "string",
                    description: "Full UTF-8 text content to write"
                ),
            ],
            required: ["path", "content"]
        )
    }

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let start = Date()
        guard let pathStr = input["path"]?.stringValue else {
            return ToolResult(summary: "Error: missing required 'path'", durationMs: ms(since: start))
        }
        guard let content = input["content"]?.stringValue else {
            return ToolResult(summary: "Error: missing required 'content'", durationMs: ms(since: start))
        }

        let url = ToolPathResolver.resolve(pathStr, workspaceRoot: context.workspaceRoot)
        let guard_ = BoundaryGuard(workspaceRoot: context.workspaceRoot)
        guard guard_.isInside(url) else {
            return ToolResult(
                summary: "Error: path '\(pathStr)' is outside the workspace boundary",
                durationMs: ms(since: start)
            )
        }

        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let existed = FileManager.default.fileExists(atPath: url.path)
            try content.write(to: url, atomically: true, encoding: .utf8)
            let verb = existed ? "Overwrote" : "Created"
            return ToolResult(
                summary: "\(verb) \(url.path) (\(content.utf8.count) bytes)",
                payload: .object([
                    "path": .string(url.path),
                    "bytes": .number(Double(content.utf8.count)),
                    "created": .bool(!existed),
                ]),
                artifacts: [ToolArtifact(name: url.lastPathComponent, path: url.path, mediaType: "text/plain", size: content.utf8.count)],
                durationMs: ms(since: start)
            )
        } catch {
            return ToolResult(summary: "Error writing \(pathStr): \(error.localizedDescription)", durationMs: ms(since: start))
        }
    }

    private func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
}

// MARK: - FilePatchTool

/// Apply a unified diff to a file inside the workspace.
///
/// The diff is parsed with `HunkParser` and applied with `PatchEngine`,
/// optionally verifying the pre-image SHA. Boundary-checked.
///
/// Reference: CLAUDE.md §20 (file.patch), Appendix A.2
public struct FilePatchTool: Tool, Sendable {
    public let name = "file.patch"
    public let summary = "Apply a unified diff to a file inside the workspace"
    public let documentation = """
        Applies a unified diff (the standard `@@ -a,b +c,d @@` format) to an
        existing file. Prefer this over file.write for targeted edits. The path
        must be inside the workspace.
        """
    public let defaultRisk: RiskLevel = .moderate
    public let isMutating = true

    public init() {}

    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "path": PropertySchema(
                    type: "string",
                    description: "File to patch, relative to the workspace root or absolute inside it"
                ),
                "diff": PropertySchema(
                    type: "string",
                    description: "Unified diff text with @@ hunk headers"
                ),
                "expect_sha": PropertySchema(
                    type: "string",
                    description: "Optional SHA-256 of the current file content for a safety check"
                ),
            ],
            required: ["path", "diff"]
        )
    }

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let start = Date()
        guard let pathStr = input["path"]?.stringValue else {
            return ToolResult(summary: "Error: missing required 'path'", durationMs: ms(since: start))
        }
        guard let diffText = input["diff"]?.stringValue else {
            return ToolResult(summary: "Error: missing required 'diff'", durationMs: ms(since: start))
        }

        let url = ToolPathResolver.resolve(pathStr, workspaceRoot: context.workspaceRoot)
        let boundary = BoundaryGuard(workspaceRoot: context.workspaceRoot)
        guard boundary.isInside(url) else {
            return ToolResult(summary: "Error: path '\(pathStr)' is outside the workspace boundary", durationMs: ms(since: start))
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ToolResult(summary: "Error: file '\(pathStr)' does not exist (use file.write to create it)", durationMs: ms(since: start))
        }
        guard let diff = HunkParser().parseSingle(diffText) else {
            return ToolResult(summary: "Error: could not parse unified diff", durationMs: ms(since: start))
        }

        do {
            let expectSHA = input["expect_sha"]?.stringValue
            try PatchEngine().applyToFile(diff: diff, path: url, expectSHA: expectSHA)
            return ToolResult(
                summary: "Patched \(url.path) (\(diff.hunks.count) hunk(s))",
                payload: .object([
                    "path": .string(url.path),
                    "hunks": .number(Double(diff.hunks.count)),
                ]),
                artifacts: [ToolArtifact(name: url.lastPathComponent, path: url.path, mediaType: "text/plain")],
                durationMs: ms(since: start)
            )
        } catch {
            return ToolResult(summary: "Error applying patch to \(pathStr): \(error)", durationMs: ms(since: start))
        }
    }

    private func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }
}

// MARK: - ToolPathResolver

/// Resolves a tool-provided path (relative or absolute) against the workspace.
enum ToolPathResolver {
    static func resolve(_ path: String, workspaceRoot: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return workspaceRoot.appendingPathComponent(path).standardizedFileURL
    }
}
