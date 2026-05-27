import ArgumentParser
import Foundation
import ZyquoCore

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnostics: keys, permissions, providers, tools"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    func run() async throws {
        Bootstrap.ensureDirectories()
        let container = AppContainer(flags: globals.flags)
        let noColor = container.config.ui.noColor

        let co = CommandOutput(noColor: noColor)

        co.blank()
        co.header(title: "Zyquo Doctor", subtitle: "v\(ZyquoInfo.versionString)")
        co.blank()

        // --- System ---
        co.section(title: "System")

        // Swift version
        co.checkItem("Swift runtime available")

        // macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        if osVersion.majorVersion >= 14 {
            co.checkItem("macOS \(osString)", detail: "requires 14+")
        } else {
            co.failItem("macOS \(osString)", detail: "requires 14+")
        }

        // Architecture
        #if arch(arm64)
        co.checkItem("Architecture: arm64 (Apple Silicon)")
        #elseif arch(x86_64)
        co.checkItem("Architecture: x86_64 (Intel)")
        #else
        co.warnItem("Architecture: unknown")
        #endif

        // Available disk space
        let cwd = FileManager.default.currentDirectoryPath
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: cwd),
           let freeSpace = attrs[.systemFreeSize] as? UInt64 {
            let freeGB = Double(freeSpace) / 1_073_741_824.0
            if freeGB > 1.0 {
                co.checkItem("Disk space: \(String(format: "%.1f", freeGB)) GB free")
            } else {
                co.warnItem("Disk space: \(String(format: "%.1f", freeGB)) GB free", detail: "low")
            }
        }

        co.blank()

        // --- Workspace ---
        co.section(title: "Workspace")

        let zyquoDir = URL(fileURLWithPath: cwd).appendingPathComponent(".zyquo")
        if FileManager.default.fileExists(atPath: zyquoDir.path) {
            co.checkItem("Workspace initialized (.zyquo/ found)")
        } else {
            co.warnItem("Workspace not initialized", detail: "run `zyquo init`")
        }

        // Workspace scan
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let workspace = Workspace(root: root)
        let wsIndex = await workspace.scan()

        if let lang = wsIndex.primaryLanguage {
            co.checkItem("Primary language: \(lang.displayName)")
        } else {
            co.infoItem("No primary language detected")
        }

        if !wsIndex.frameworks.isEmpty {
            co.checkItem("Frameworks: \(wsIndex.frameworks.map(\.displayName).joined(separator: ", "))")
        }

        if let testCmd = wsIndex.testCommand {
            co.checkItem("Test command: \(testCmd)")
        } else {
            co.infoItem("No test command detected")
        }

        if let buildCmd = wsIndex.buildCommand {
            co.checkItem("Build command: \(buildCmd)")
        } else {
            co.infoItem("No build command detected")
        }

        co.infoItem("Files indexed: \(wsIndex.fileCount)")

        if let git = wsIndex.gitStatus {
            var gitInfo = "Git: "
            if let branch = git.branch { gitInfo += branch }
            if git.isClean { gitInfo += " (clean)" }
            else { gitInfo += " (modified)" }
            co.checkItem(gitInfo)
        } else {
            co.infoItem("Not a git repository")
        }

        co.blank()

        // --- Required Binaries ---
        co.section(title: "Required Binaries")

        // Git
        let gitPath = findBinary("git")
        if let path = gitPath {
            let version = getBinaryVersion("git", args: ["--version"])
            co.checkItem("git\(version.map { " (\($0))" } ?? "")", detail: path)
        } else {
            co.failItem("git not found", detail: "install Xcode CLT")
        }

        // Ripgrep
        let rgPath = findBinary("rg")
        if let path = rgPath {
            let version = getBinaryVersion("rg", path: path, args: ["--version"])
            let versionStr = version.map { " (\($0.components(separatedBy: "\n").first ?? $0))" } ?? ""
            co.checkItem("rg (ripgrep)\(versionStr)", detail: path)
        } else {
            co.failItem("rg (ripgrep) not found", detail: "brew install ripgrep")
        }

        co.blank()

        // --- Optional Binaries ---
        co.section(title: "Optional Binaries")

        let optionalBinaries: [(String, String, String)] = [
            ("swift-format", "Swift formatter", "brew install swift-format"),
            ("swiftlint", "Swift linter", "brew install swiftlint"),
            ("prettier", "JS/TS/MD formatter", "npm install -g prettier"),
            ("fd", "Fast file finder", "brew install fd"),
            ("bat", "Syntax-highlighted cat", "brew install bat"),
            ("delta", "Fancy diff pager", "brew install git-delta"),
            ("jq", "JSON processor", "brew install jq"),
            ("shellcheck", "Shell script linter", "brew install shellcheck"),
        ]

        for (binary, desc, installHint) in optionalBinaries {
            if let path = findBinary(binary) {
                co.checkItem("\(binary) (\(desc))", detail: path)
            } else {
                co.infoItem("\(binary) (\(desc)) not found", detail: installHint)
            }
        }

        co.blank()

        // --- Providers ---
        co.section(title: "Providers")

        let anthropicKey = KeychainHelper.read(service: "dev.zyquo.cli", account: "anthropic")
        if anthropicKey != nil {
            co.checkItem("Anthropic API key in Keychain")
        } else {
            co.warnItem("Anthropic API key not found", detail: "run `zyquo provider login anthropic`")
        }

        let openrouterKey = KeychainHelper.read(service: "dev.zyquo.cli", account: "openrouter")
        if openrouterKey != nil {
            co.checkItem("OpenRouter API key in Keychain")
        } else {
            co.infoItem("OpenRouter API key not found", detail: "optional, run `zyquo provider login openrouter`")
        }

        co.blank()

        // --- Configuration ---
        co.section(title: "Configuration")
        co.keyValue("Provider", container.config.providers.resolvedProvider)
        co.keyValue("Model", container.config.providers.resolvedModel)
        co.keyValue("Max steps", "\(container.config.agent.maxSteps)")
        co.keyValue("Max cost", "$\(String(format: "%.2f", container.config.agent.maxCostUSD))")
        co.keyValue("Auto-approve SAFE", "\(container.config.agent.autoApproveSafe)")
        co.keyValue("Theme", container.config.ui.theme)
        co.keyValue("Shell", container.config.shell.defaultShell)
        co.keyValue("Shell timeout", "\(container.config.shell.timeoutSeconds)s")

        co.blank()

        // --- Paths ---
        co.section(title: "Paths")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let globalConfig = home.appendingPathComponent(".zyquo/config.toml")
        let globalThemes = home.appendingPathComponent(".zyquo/themes")
        let logsDir = home.appendingPathComponent("Library/Logs/Zyquo")

        co.keyValue("Global config", "\(globalConfig.path) \(FileManager.default.fileExists(atPath: globalConfig.path) ? "(exists)" : "(not found)")")
        co.keyValue("Themes dir", globalThemes.path)
        co.keyValue("Logs dir", logsDir.path)
        co.keyValue("Workspace", cwd)

        // --- Summary footer ---
        var passCount = 0
        var warnCount = 0
        // Count results: system checks + binaries + providers
        if osVersion.majorVersion >= 14 { passCount += 1 } else { warnCount += 1 }
        passCount += 1 // Swift runtime
        passCount += 1 // Architecture
        if gitPath != nil { passCount += 1 } else { warnCount += 1 }
        if rgPath != nil { passCount += 1 } else { warnCount += 1 }
        if anthropicKey != nil { passCount += 1 } else { warnCount += 1 }

        co.blank()
        co.footer(items: [
            ("Result", "\(passCount) passed \u{00B7} \(warnCount) warnings"),
        ])
    }

    private func findBinary(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func getBinaryVersion(_ name: String, path: String? = nil, args: [String] = ["--version"]) -> String? {
        let binPath = path ?? findBinary(name)
        guard let binPath else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binPath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
