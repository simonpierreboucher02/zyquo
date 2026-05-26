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

        let check = noColor ? "[OK]" : "\u{1B}[32m\u{2713}\u{1B}[0m"
        let fail = noColor ? "[FAIL]" : "\u{1B}[31m\u{2717}\u{1B}[0m"
        let warn = noColor ? "[WARN]" : "\u{1B}[33m!\u{1B}[0m"
        let info = noColor ? "[INFO]" : "\u{1B}[34m\u{2139}\u{1B}[0m"

        print()
        print(noColor ? "  Zyquo Doctor" : "  \u{1B}[1mZyquo Doctor\u{1B}[0m")
        print(noColor ? "  Version: \(ZyquoInfo.versionString)" : "  \u{1B}[2mVersion: \(ZyquoInfo.versionString)\u{1B}[0m")
        print()

        // --- System ---
        print(noColor ? "  System:" : "  \u{1B}[1mSystem:\u{1B}[0m")

        // Swift version
        print("  \(check) Swift runtime available")

        // macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        if osVersion.majorVersion >= 14 {
            print("  \(check) macOS \(osString) (requires 14+)")
        } else {
            print("  \(fail) macOS \(osString) (requires 14+)")
        }

        // Architecture
        #if arch(arm64)
        print("  \(check) Architecture: arm64 (Apple Silicon)")
        #elseif arch(x86_64)
        print("  \(check) Architecture: x86_64 (Intel)")
        #else
        print("  \(warn) Architecture: unknown")
        #endif

        // Available disk space
        let cwd = FileManager.default.currentDirectoryPath
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: cwd),
           let freeSpace = attrs[.systemFreeSize] as? UInt64 {
            let freeGB = Double(freeSpace) / 1_073_741_824.0
            if freeGB > 1.0 {
                print("  \(check) Disk space: \(String(format: "%.1f", freeGB)) GB free")
            } else {
                print("  \(warn) Disk space: \(String(format: "%.1f", freeGB)) GB free (low)")
            }
        }

        print()

        // --- Workspace ---
        print(noColor ? "  Workspace:" : "  \u{1B}[1mWorkspace:\u{1B}[0m")

        let zyquoDir = URL(fileURLWithPath: cwd).appendingPathComponent(".zyquo")
        if FileManager.default.fileExists(atPath: zyquoDir.path) {
            print("  \(check) Workspace initialized (.zyquo/ found)")
        } else {
            print("  \(warn) Workspace not initialized (run `zyquo init`)")
        }

        // Workspace scan
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let workspace = Workspace(root: root)
        let wsIndex = await workspace.scan()

        if let lang = wsIndex.primaryLanguage {
            print("  \(check) Primary language: \(lang.displayName)")
        } else {
            print("  \(info) No primary language detected")
        }

        if !wsIndex.frameworks.isEmpty {
            print("  \(check) Frameworks: \(wsIndex.frameworks.map(\.displayName).joined(separator: ", "))")
        }

        if let testCmd = wsIndex.testCommand {
            print("  \(check) Test command: \(testCmd)")
        } else {
            print("  \(info) No test command detected")
        }

        if let buildCmd = wsIndex.buildCommand {
            print("  \(check) Build command: \(buildCmd)")
        } else {
            print("  \(info) No build command detected")
        }

        print("  \(info) Files indexed: \(wsIndex.fileCount)")

        if let git = wsIndex.gitStatus {
            var gitInfo = "Git: "
            if let branch = git.branch { gitInfo += branch }
            if git.isClean { gitInfo += " (clean)" }
            else { gitInfo += " (modified)" }
            print("  \(check) \(gitInfo)")
        } else {
            print("  \(info) Not a git repository")
        }

        print()

        // --- Required Binaries ---
        print(noColor ? "  Required Binaries:" : "  \u{1B}[1mRequired Binaries:\u{1B}[0m")

        // Git
        let gitPath = findBinary("git")
        if let path = gitPath {
            let version = getBinaryVersion("git", args: ["--version"])
            print("  \(check) git found at \(path)\(version.map { " (\($0))" } ?? "")")
        } else {
            print("  \(fail) git not found")
        }

        // Ripgrep
        let rgPath = findBinary("rg")
        if let path = rgPath {
            let version = getBinaryVersion("rg", path: path, args: ["--version"])
            let versionStr = version.map { " (\($0.components(separatedBy: "\n").first ?? $0))" } ?? ""
            print("  \(check) rg (ripgrep) found at \(path)\(versionStr)")
        } else {
            print("  \(fail) rg (ripgrep) not found -- install with `brew install ripgrep`")
        }

        print()

        // --- Optional Binaries ---
        print(noColor ? "  Optional Binaries:" : "  \u{1B}[1mOptional Binaries:\u{1B}[0m")

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
                print("  \(check) \(binary) (\(desc)) at \(path)")
            } else {
                print("  \(info) \(binary) (\(desc)) not found -- \(installHint)")
            }
        }

        print()

        // --- Providers ---
        print(noColor ? "  Providers:" : "  \u{1B}[1mProviders:\u{1B}[0m")

        let anthropicKey = KeychainHelper.read(service: "dev.zyquo.cli", account: "anthropic")
        if anthropicKey != nil {
            print("  \(check) Anthropic API key in Keychain")
        } else {
            print("  \(warn) Anthropic API key not found (run `zyquo provider login anthropic`)")
        }

        let openrouterKey = KeychainHelper.read(service: "dev.zyquo.cli", account: "openrouter")
        if openrouterKey != nil {
            print("  \(check) OpenRouter API key in Keychain")
        } else {
            print("  \(info) OpenRouter API key not found (optional, run `zyquo provider login openrouter`)")
        }

        print()

        // --- Configuration ---
        print(noColor ? "  Configuration:" : "  \u{1B}[1mConfiguration:\u{1B}[0m")
        print("  Provider: \(container.config.providers.resolvedProvider)")
        print("  Model: \(container.config.providers.resolvedModel)")
        print("  Max steps: \(container.config.agent.maxSteps)")
        print("  Max cost: $\(String(format: "%.2f", container.config.agent.maxCostUSD))")
        print("  Auto-approve SAFE: \(container.config.agent.autoApproveSafe)")
        print("  Theme: \(container.config.ui.theme)")
        print("  Shell: \(container.config.shell.defaultShell)")
        print("  Shell timeout: \(container.config.shell.timeoutSeconds)s")
        print()

        // --- Paths ---
        print(noColor ? "  Paths:" : "  \u{1B}[1mPaths:\u{1B}[0m")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let globalConfig = home.appendingPathComponent(".zyquo/config.toml")
        let globalThemes = home.appendingPathComponent(".zyquo/themes")
        let logsDir = home.appendingPathComponent("Library/Logs/Zyquo")

        print("  Global config: \(globalConfig.path) \(FileManager.default.fileExists(atPath: globalConfig.path) ? "(exists)" : "(not found)")")
        print("  Themes dir: \(globalThemes.path)")
        print("  Logs dir: \(logsDir.path)")
        print("  Workspace: \(cwd)")
        print()
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
