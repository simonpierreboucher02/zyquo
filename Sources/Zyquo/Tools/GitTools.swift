import Foundation
import Logging

// MARK: - Git process helper

/// Runs `git` inside the workspace and captures output. Shared by the git tools.
enum GitRunner {
    struct Output: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { exitCode == 0 }
    }

    static func run(_ args: [String], cwd: URL) -> Output {
        let process = Process()
        let out = Pipe()
        let err = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = cwd
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return Output(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Output(exitCode: process.terminationStatus, stdout: o, stderr: e)
    }

    static func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

    static func result(_ o: Output, label: String, durationMs: Int) -> ToolResult {
        if o.ok {
            let body = o.stdout.isEmpty ? "(no output)" : String(o.stdout.prefix(4000))
            return ToolResult(
                summary: "\(label): OK\n\(body)",
                payload: .string(String(o.stdout.prefix(8000))),
                durationMs: durationMs,
                tokenHint: o.stdout.count / 4
            )
        } else {
            return ToolResult(
                summary: "\(label): FAILED (exit \(o.exitCode))\n\(o.stderr.prefix(800))",
                durationMs: durationMs
            )
        }
    }
}

// MARK: - git.status

public struct GitStatusTool: Tool, Sendable {
    public let name = "git.status"
    public let summary = "Show git working-tree status (branch + changes)"
    public let documentation = "Runs `git status --short --branch` in the workspace."
    public let defaultRisk: RiskLevel = .safe
    public let isMutating = false
    public init() {}
    public var inputSchema: ToolInputSchema { .empty }

    public func execute(input: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        let start = Date()
        let o = GitRunner.run(["status", "--short", "--branch"], cwd: context.workspaceRoot)
        return GitRunner.result(o, label: "git status", durationMs: GitRunner.ms(since: start))
    }
}

// MARK: - git.diff

public struct GitDiffTool: Tool, Sendable {
    public let name = "git.diff"
    public let summary = "Show a git diff (optionally staged or for a range/paths)"
    public let documentation = "Runs `git diff`. Pass `staged: true` for the index, `range` for a commit range, and `paths` to scope."
    public let defaultRisk: RiskLevel = .safe
    public let isMutating = false
    public init() {}
    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "staged": PropertySchema(type: "boolean", description: "Diff the staged index instead of the working tree", defaultValue: "false"),
                "range": PropertySchema(type: "string", description: "Commit range, e.g. HEAD~1..HEAD"),
                "paths": PropertySchema(type: "array", description: "Restrict the diff to these paths"),
            ],
            required: []
        )
    }

    public func execute(input: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        let start = Date()
        var args = ["diff"]
        if input["staged"]?.asBool == true { args.append("--staged") }
        if let range = input["range"]?.stringValue, !range.isEmpty { args.append(range) }
        if case .array(let arr) = input["paths"] {
            let paths = arr.compactMap { $0.stringValue }
            if !paths.isEmpty { args.append("--"); args.append(contentsOf: paths) }
        }
        let o = GitRunner.run(args, cwd: context.workspaceRoot)
        return GitRunner.result(o, label: "git diff", durationMs: GitRunner.ms(since: start))
    }
}

// MARK: - git.log

public struct GitLogTool: Tool, Sendable {
    public let name = "git.log"
    public let summary = "Show recent commit history (oneline)"
    public let documentation = "Runs `git log --oneline -n <limit>` (default 20)."
    public let defaultRisk: RiskLevel = .safe
    public let isMutating = false
    public init() {}
    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "limit": PropertySchema(type: "integer", description: "Number of commits to show", defaultValue: "20"),
            ],
            required: []
        )
    }

    public func execute(input: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        let start = Date()
        var limit = 20
        if case .number(let n) = input["limit"] { limit = max(1, min(200, Int(n))) }
        let o = GitRunner.run(["log", "--oneline", "-n", "\(limit)"], cwd: context.workspaceRoot)
        return GitRunner.result(o, label: "git log", durationMs: GitRunner.ms(since: start))
    }
}

// MARK: - git.commit

public struct GitCommitTool: Tool, Sendable {
    public let name = "git.commit"
    public let summary = "Stage listed paths and create a commit (never pushes)"
    public let documentation = """
        Stages the given `paths` (if any) and commits with `message`. Never
        stages everything implicitly and never pushes. Omit `paths` to commit
        what is already staged.
        """
    public let defaultRisk: RiskLevel = .moderate
    public let isMutating = true
    public init() {}
    public var inputSchema: ToolInputSchema {
        ToolInputSchema(
            properties: [
                "message": PropertySchema(type: "string", description: "Commit message"),
                "paths": PropertySchema(type: "array", description: "Paths to stage before committing (explicit; never all)"),
            ],
            required: ["message"]
        )
    }

    public func execute(input: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        let start = Date()
        guard let message = input["message"]?.stringValue, !message.isEmpty else {
            return ToolResult(summary: "Error: missing required 'message'", durationMs: GitRunner.ms(since: start))
        }
        if case .array(let arr) = input["paths"] {
            let paths = arr.compactMap { $0.stringValue }
            if !paths.isEmpty {
                let add = GitRunner.run(["add"] + paths, cwd: context.workspaceRoot)
                if !add.ok {
                    return ToolResult(summary: "git add: FAILED\n\(add.stderr.prefix(800))", durationMs: GitRunner.ms(since: start))
                }
            }
        }
        let o = GitRunner.run(["commit", "-m", message], cwd: context.workspaceRoot)
        return GitRunner.result(o, label: "git commit", durationMs: GitRunner.ms(since: start))
    }
}
