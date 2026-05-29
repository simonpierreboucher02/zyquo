import Foundation
import Logging

public struct ZTPToolManifest: Sendable, Codable {
    public let name: String
    public let version: String
    public let protocolVersion: String
    public let capabilities: [String]
    public let permissions: [String: Bool]
    public let commands: [ZTPCommandInfo]

    public init(
        name: String,
        version: String,
        protocolVersion: String = "ztp/1",
        capabilities: [String] = [],
        permissions: [String: Bool] = [:],
        commands: [ZTPCommandInfo] = []
    ) {
        self.name = name
        self.version = version
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.permissions = permissions
        self.commands = commands
    }
}

public struct ZTPCommandInfo: Sendable, Codable {
    public let name: String
    public let summary: String
    public let requiresInput: Bool
    public let requiresOutput: Bool
    public let requiresConfirmation: Bool

    public init(
        name: String,
        summary: String = "",
        requiresInput: Bool = false,
        requiresOutput: Bool = false,
        requiresConfirmation: Bool = false
    ) {
        self.name = name
        self.summary = summary
        self.requiresInput = requiresInput
        self.requiresOutput = requiresOutput
        self.requiresConfirmation = requiresConfirmation
    }
}

public actor ZTPDiscovery {
    private let ztpBinary: String
    private var cachedManifests: [String: ZTPToolManifest] = [:]
    private var lastScanTime: Date?
    private let cacheTTL: TimeInterval = 300

    public init(ztpBinary: String = "ztp") {
        self.ztpBinary = ztpBinary
    }

    public func discoverTools() async -> [ZTPToolManifest] {
        if let lastScan = lastScanTime,
           Date().timeIntervalSince(lastScan) < cacheTTL,
           !cachedManifests.isEmpty {
            return Array(cachedManifests.values)
        }

        guard let ztpPath = resolveZTPPath() else { return [] }

        var manifests: [ZTPToolManifest] = []
        let toolNames = ["excel", "docx", "slides", "chart", "mail", "message", "browser", "macos", "ocr", "notes", "files", "finder"]

        for toolName in toolNames {
            if let manifest = await probeToolManifest(ztpPath: ztpPath, toolName: toolName) {
                manifests.append(manifest)
                cachedManifests[manifest.name] = manifest
            }
        }

        lastScanTime = Date()
        return manifests
    }

    public func manifest(for toolName: String) async -> ZTPToolManifest? {
        let normalized = toolName.hasPrefix("ztp-") ? toolName : "ztp-\(toolName)"
        if let cached = cachedManifests[normalized] { return cached }
        _ = await discoverTools()
        return cachedManifests[normalized]
    }

    public nonisolated func isAvailable() -> Bool {
        Self.resolveBinaryPath() != nil
    }

    /// Resolve the `ztp` binary path robustly across install layouts
    /// (Homebrew arm64/x86_64, ~/.local/bin, then `which ztp`). Returns nil if
    /// not installed. Shared by the integration so the path is never hardcoded.
    public nonisolated static func resolveBinaryPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ztp",
            "/usr/local/bin/ztp",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/ztp",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "which ztp"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed)) ? trimmed : nil
    }

    private func resolveZTPPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ztp",
            "/usr/local/bin/ztp",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/ztp",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        let result = shell("which ztp 2>/dev/null")
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && FileManager.default.isExecutableFile(atPath: trimmed) {
            return trimmed
        }
        return nil
    }

    private func probeToolManifest(ztpPath: String, toolName: String) async -> ZTPToolManifest? {
        let helpOutput = shell("\(ztpPath) \(toolName) --help 2>/dev/null")
        guard !helpOutput.isEmpty else { return nil }

        let commands = parseSubcommands(from: helpOutput)
        let capabilities = deriveCapabilities(toolName: toolName, commands: commands)
        let permissions = derivePermissions(toolName: toolName)

        return ZTPToolManifest(
            name: "ztp-\(toolName)",
            version: "0.1.0",
            protocolVersion: "ztp/1",
            capabilities: capabilities,
            permissions: permissions,
            commands: commands
        )
    }

    private func parseSubcommands(from helpText: String) -> [ZTPCommandInfo] {
        var commands: [ZTPCommandInfo] = []
        let lines = helpText.components(separatedBy: "\n")
        var inSubcommands = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SUBCOMMANDS:") {
                inSubcommands = true
                continue
            }
            if inSubcommands {
                if trimmed.isEmpty || trimmed.hasPrefix("See ") { break }
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                guard let cmdName = parts.first else { continue }
                let name = String(cmdName)
                let summary = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                let requiresInput = name == "build" || name == "validate-spec" || name == "send" || name == "run"
                let requiresOutput = name == "build" || name == "screenshot" || name == "pdf"
                let requiresConfirmation = name == "send"
                commands.append(ZTPCommandInfo(
                    name: name,
                    summary: summary,
                    requiresInput: requiresInput,
                    requiresOutput: requiresOutput,
                    requiresConfirmation: requiresConfirmation
                ))
            }
        }
        return commands
    }

    private func deriveCapabilities(toolName: String, commands: [ZTPCommandInfo]) -> [String] {
        commands.map { "\(toolName).\($0.name.replacingOccurrences(of: "-", with: "_"))" }
    }

    private func derivePermissions(toolName: String) -> [String: Bool] {
        var perms: [String: Bool] = ["filesystem": true]
        switch toolName {
        case "browser", "mail":
            perms["network"] = true
        case "macos":
            perms["process"] = true
            perms["applescript"] = true
            perms["notifications"] = true
            perms["screenshots"] = true
        case "message", "notes", "finder":
            perms["applescript"] = true
        case "ocr":
            perms["screenshots"] = true
        default:
            break
        }
        return perms
    }

    private func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
