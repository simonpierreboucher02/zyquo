import Foundation
import Logging

public struct ZTPToolBridge: Tool, Sendable {
    public let name: String
    public let summary: String
    public let documentation: String
    public let inputSchema: ToolInputSchema
    public let defaultRisk: RiskLevel
    public let isMutating: Bool

    private let ztpBinary: String
    private let ztpToolName: String
    private let manifest: ZTPToolManifest

    public init(manifest: ZTPToolManifest, ztpBinary: String = "ztp") {
        self.manifest = manifest
        self.ztpBinary = ztpBinary
        self.ztpToolName = manifest.name.hasPrefix("ztp-")
            ? String(manifest.name.dropFirst(4))
            : manifest.name

        self.name = "ztp.\(ztpToolName)"
        self.summary = "ZTP \(ztpToolName) — \(manifest.capabilities.prefix(3).joined(separator: ", "))"
        self.documentation = Self.buildDocumentation(manifest: manifest)
        self.inputSchema = Self.buildSchema(manifest: manifest, toolName: ztpToolName)

        let hasNetwork = manifest.permissions["network"] == true
        let hasAppleScript = manifest.permissions["applescript"] == true
        self.defaultRisk = (hasNetwork || hasAppleScript) ? .moderate : .safe
        self.isMutating = manifest.commands.contains { $0.name == "build" || $0.name == "send" }
    }

    public func execute(
        input: [String: JSONValue],
        context: ToolContext
    ) async throws -> ToolResult {
        let command = input["command"]?.stringValue ?? "build"
        let specJSON = input["spec"]?.stringValue
        let specFile = input["spec_file"]?.stringValue
        let outputPath = input["output"]?.stringValue
        let confirmed = input["confirmed"]?.asBool ?? false

        let start = Date()

        let result: ZTPExecutionResult
        if let spec = specJSON {
            result = try await executeWithInlineSpec(
                command: command, spec: spec, output: outputPath,
                confirmed: confirmed, cwd: context.workspaceRoot
            )
        } else if let file = specFile {
            result = try await executeWithSpecFile(
                command: command, specFile: file, output: outputPath,
                confirmed: confirmed, cwd: context.workspaceRoot
            )
        } else {
            result = try await executeRawCommand(
                command: command, input: input, output: outputPath,
                confirmed: confirmed, cwd: context.workspaceRoot
            )
        }

        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return buildToolResult(from: result, durationMs: durationMs)
    }

    // MARK: - Execution Modes

    private func executeWithInlineSpec(
        command: String, spec: String, output: String?,
        confirmed: Bool, cwd: URL
    ) async throws -> ZTPExecutionResult {
        let tempDir = FileManager.default.temporaryDirectory
        let specPath = tempDir.appendingPathComponent("zyquo-ztp-\(UUID().uuidString).json")
        try spec.write(to: specPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: specPath) }

        var args = [command, specPath.path]
        if let out = output { args += ["--output", out] }
        if confirmed { args.append("--confirmed") }
        args.append("--json")

        return runZTP(args: args, cwd: cwd)
    }

    private func executeWithSpecFile(
        command: String, specFile: String, output: String?,
        confirmed: Bool, cwd: URL
    ) async throws -> ZTPExecutionResult {
        var args = [command, specFile]
        if let out = output { args += ["--output", out] }
        if confirmed { args.append("--confirmed") }
        args.append("--json")

        return runZTP(args: args, cwd: cwd)
    }

    private func executeRawCommand(
        command: String, input: [String: JSONValue], output: String?,
        confirmed: Bool, cwd: URL
    ) async throws -> ZTPExecutionResult {
        let consumed: Set<String> = ["command", "spec", "spec_file", "output", "confirmed"]

        var positionals: [String] = []
        var flags: [String] = []

        // Browser subcommands take the URL as a positional argument
        // (e.g. `ztp browser text <url>`), not as `--url`.
        if ztpToolName == "browser", let url = input["url"]?.stringValue {
            positionals.append(url)
        }

        for (key, value) in input where !consumed.contains(key) {
            if ztpToolName == "browser", key == "url" { continue } // already positional
            let flag = Self.flagName(for: key, tool: ztpToolName)
            switch value {
            case .string(let s): flags += [flag, s]
            case .number(let n): flags += [flag, n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : "\(n)"]
            case .bool(let b): if b { flags.append(flag) }
            default: break
            }
        }

        var fullArgs = [command] + positionals + flags
        if let out = output { fullArgs += ["--output", out] }
        if confirmed { fullArgs.append("--confirmed") }
        fullArgs.append("--json")

        return runZTP(args: fullArgs, cwd: cwd)
    }

    /// Maps a schema input key to the matching ztp CLI flag, accounting for
    /// per-tool option naming (e.g. browser viewport uses `--width`/`--height`).
    private static func flagName(for key: String, tool: String) -> String {
        if tool == "browser" {
            switch key {
            case "viewport_width": return "--width"
            case "viewport_height": return "--height"
            default: break
            }
        }
        return "--\(key.replacingOccurrences(of: "_", with: "-"))"
    }

    // MARK: - Shell Execution

    private func runZTP(args: [String], cwd: URL) -> ZTPExecutionResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: ztpBinary)
        process.arguments = [ztpToolName] + args
        process.currentDirectoryURL = cwd
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ZTPExecutionResult(
                ok: false, exitCode: -1,
                stdout: "", stderr: error.localizedDescription,
                json: nil
            )
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""

        let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any]

        return ZTPExecutionResult(
            ok: json?["ok"] as? Bool ?? (process.terminationStatus == 0),
            exitCode: Int(process.terminationStatus),
            stdout: outStr,
            stderr: errStr,
            json: json
        )
    }

    // MARK: - Result Building

    private func buildToolResult(from result: ZTPExecutionResult, durationMs: Int) -> ToolResult {
        var artifacts: [ToolArtifact] = []

        if let json = result.json {
            if let path = json["output_path"] as? String ?? json["file"] as? String {
                let size = json["file_size_bytes"] as? Int ?? json["size_bytes"] as? Int ?? 0
                let ext = (path as NSString).pathExtension
                let mediaType = mimeType(for: ext)
                artifacts.append(ToolArtifact(name: (path as NSString).lastPathComponent, path: path, mediaType: mediaType, size: size))
            }
        }

        let summaryStr: String
        if result.ok {
            if let json = result.json {
                let cmd = json["command"] as? String ?? ztpToolName
                let dur = json["duration_ms"] as? Int ?? durationMs
                var parts = ["ztp-\(ztpToolName) \(cmd): OK (\(dur)ms)"]
                if let fileSize = json["file_size_bytes"] as? Int {
                    parts.append("\(fileSize) bytes")
                }
                if let path = json["output_path"] as? String {
                    parts.append("→ \(path)")
                }
                summaryStr = parts.joined(separator: " | ")
            } else {
                summaryStr = "ztp-\(ztpToolName): OK"
            }
        } else {
            let errMsg = result.json?["error"] as? String
                ?? (result.json?["error"] as? [String: Any])?["message"] as? String
                ?? result.stderr.prefix(200).description
            summaryStr = "ztp-\(ztpToolName): FAILED — \(errMsg)"
        }

        let payload: JSONValue?
        if let json = result.json {
            payload = jsonToJSONValue(json)
        } else {
            payload = .string(result.stdout)
        }

        return ToolResult(
            summary: summaryStr,
            payload: payload,
            artifacts: artifacts,
            durationMs: durationMs,
            tokenHint: min(result.stdout.count / 4, 2000)
        )
    }

    // MARK: - Helpers

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "svg": return "image/svg+xml"
        case "html": return "text/html"
        case "json": return "application/json"
        case "eml": return "message/rfc822"
        default: return "application/octet-stream"
        }
    }

    private func jsonToJSONValue(_ obj: Any) -> JSONValue {
        switch obj {
        case let s as String: return .string(s)
        case let n as Int: return .number(Double(n))
        case let d as Double: return .number(d)
        case let b as Bool: return .bool(b)
        case let arr as [Any]: return .array(arr.map { jsonToJSONValue($0) })
        case let dict as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (k, v) in dict { result[k] = jsonToJSONValue(v) }
            return .object(result)
        default: return .null
        }
    }

    // MARK: - Schema Generation

    static func buildDocumentation(manifest: ZTPToolManifest) -> String {
        var doc = "ZTP tool: \(manifest.name) v\(manifest.version)\n"
        doc += "Capabilities: \(manifest.capabilities.joined(separator: ", "))\n"
        doc += "Commands:\n"
        for cmd in manifest.commands {
            doc += "  - \(cmd.name): \(cmd.summary)\n"
        }
        return doc
    }

    static func buildSchema(manifest: ZTPToolManifest, toolName: String) -> ToolInputSchema {
        var properties: [String: PropertySchema] = [:]
        var required: [String] = ["command"]

        let commandNames = manifest.commands.map(\.name)
        properties["command"] = PropertySchema(
            type: "string",
            description: "ZTP subcommand to execute: \(commandNames.joined(separator: ", "))",
            enumValues: commandNames
        )

        properties["spec"] = PropertySchema(
            type: "string",
            description: "Inline JSON spec content for document generation (build/validate-spec commands)"
        )

        properties["spec_file"] = PropertySchema(
            type: "string",
            description: "Path to JSON spec file (alternative to inline spec)"
        )

        properties["output"] = PropertySchema(
            type: "string",
            description: "Output file path for generated artifacts"
        )

        properties["confirmed"] = PropertySchema(
            type: "boolean",
            description: "Set to true for destructive operations (send, delete)",
            defaultValue: "false"
        )

        switch toolName {
        case "browser":
            properties["url"] = PropertySchema(type: "string", description: "URL to navigate to")
            properties["viewport_width"] = PropertySchema(type: "integer", description: "Viewport width in pixels", defaultValue: "1280")
            properties["viewport_height"] = PropertySchema(type: "integer", description: "Viewport height in pixels", defaultValue: "720")
        case "macos":
            properties["path"] = PropertySchema(type: "string", description: "File/directory path for file operations")
            properties["content"] = PropertySchema(type: "string", description: "Content for write operations or script text")
            properties["app"] = PropertySchema(type: "string", description: "Application name for app operations")
        case "chart":
            properties["format"] = PropertySchema(
                type: "string",
                description: "Output format for charts",
                enumValues: ["png", "svg", "pdf"],
                defaultValue: "png"
            )
        default:
            break
        }

        return ToolInputSchema(properties: properties, required: required)
    }
}

// MARK: - ZTPExecutionResult

struct ZTPExecutionResult: Sendable {
    let ok: Bool
    let exitCode: Int
    let stdout: String
    let stderr: String
    let json: [String: Any]?

    init(ok: Bool, exitCode: Int, stdout: String, stderr: String, json: [String: Any]?) {
        self.ok = ok
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.json = json
    }
}

extension ZTPExecutionResult: @unchecked Sendable {}
