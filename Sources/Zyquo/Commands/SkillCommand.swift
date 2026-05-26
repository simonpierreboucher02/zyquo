import ArgumentParser
import Foundation

// MARK: - SkillCommand

/// List, inspect, and run Zyquo skills.
///
/// Skills are versioned, prompted workflows with constrained tool access
/// and budget enforcement. They live in `.zyquo/skills/` (project) or
/// `~/.zyquo/skills/` (global), each in a directory with `skill.yaml`
/// and `prompt.md`.
///
/// Reference: CLAUDE.md §30 Phase 6
struct SkillCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "List, inspect, and run skills",
        subcommands: [
            ListSkills.self,
            ShowSkill.self,
            RunSkill.self,
        ],
        defaultSubcommand: ListSkills.self
    )

    // MARK: - List Subcommand

    struct ListSkills: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all discovered skills"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let container = AppContainer(flags: globals.flags)
            let noColor = container.config.ui.noColor

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let loader = SkillLoader()
            let searchPaths = SkillLoader.defaultSearchPaths(workspaceRoot: workspaceRoot)
            let skills = loader.discoverSkills(searchPaths: searchPaths)

            if skills.isEmpty {
                print("No skills found.")
                print("")
                print("Skills are loaded from:")
                for path in searchPaths {
                    print("  \(path.path)")
                }
                print("")
                print("Each skill directory must contain skill.yaml + prompt.md")
                return
            }

            // Header
            if noColor {
                print("Available Skills (\(skills.count)):")
                print(String(repeating: "-", count: 70))
            } else {
                print("\u{1B}[1mAvailable Skills (\(skills.count)):\u{1B}[0m")
                print("\u{1B}[2m\(String(repeating: "-", count: 70))\u{1B}[0m")
            }

            let maxIdLen = skills.map(\.manifest.id.count).max() ?? 12

            for skill in skills {
                let id = skill.manifest.id.padding(toLength: maxIdLen + 2, withPad: " ", startingAt: 0)
                let version = "v\(skill.manifest.version)"
                let ceiling = skill.manifest.riskCeiling

                if noColor {
                    print("  \(id) \(version.padding(toLength: 8, withPad: " ", startingAt: 0)) [\(ceiling)] \(skill.manifest.title)")
                } else {
                    let ceilingColor = colorForCeiling(skill.manifest.resolvedRiskCeiling)
                    print("  \u{1B}[1m\(id)\u{1B}[0m \u{1B}[2m\(version.padding(toLength: 8, withPad: " ", startingAt: 0))\u{1B}[0m \(ceilingColor)[\(ceiling)]\u{1B}[0m \(skill.manifest.title)")
                }
            }
        }

        private func colorForCeiling(_ risk: RiskLevel) -> String {
            switch risk {
            case .safe: return "\u{1B}[32m"
            case .moderate: return "\u{1B}[33m"
            case .dangerous: return "\u{1B}[31m"
            case .critical: return "\u{1B}[1;31m"
            }
        }
    }

    // MARK: - Show Subcommand

    struct ShowSkill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show skill details"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "The skill ID to show")
        var id: String

        func run() async throws {
            Bootstrap.setupSignalHandlers()

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let loader = SkillLoader()
            let searchPaths = SkillLoader.defaultSearchPaths(workspaceRoot: workspaceRoot)
            let skills = loader.discoverSkills(searchPaths: searchPaths)

            guard let skill = skills.first(where: { $0.manifest.id == id }) else {
                print("Skill '\(id)' not found.")
                print("")
                print("Available skills:")
                for s in skills {
                    print("  \(s.manifest.id)")
                }
                return
            }

            let m = skill.manifest
            print("Skill: \(m.id)")
            print("Title: \(m.title)")
            print("Version: \(m.version)")
            if let desc = m.description {
                print("Description: \(desc)")
            }
            if !m.authors.isEmpty {
                print("Authors: \(m.authors.joined(separator: ", "))")
            }
            print("Risk Ceiling: \(m.riskCeiling)")
            print("Budget: \(m.budget.maxSteps) steps, $\(String(format: "%.2f", m.budget.maxCostUSD)) max")
            print("")

            if !m.inputs.isEmpty {
                print("Inputs:")
                for input in m.inputs {
                    let req = input.required ? " (required)" : ""
                    let def = input.defaultValue.map { " [default: \($0)]" } ?? ""
                    let desc = input.description.map { " - \($0)" } ?? ""
                    print("  \(input.name): \(input.type)\(req)\(def)\(desc)")
                }
                print("")
            }

            if !m.toolsAllowed.isEmpty {
                print("Allowed Tools:")
                for tool in m.toolsAllowed {
                    print("  \(tool)")
                }
                print("")
            }

            if let verify = m.verify {
                print("Verification: \(verify.command) (expect exit code \(verify.expectExitCode))")
                print("")
            }

            // Prompt preview (first 10 lines)
            let promptLines = skill.prompt.split(separator: "\n", omittingEmptySubsequences: false)
            let previewCount = min(promptLines.count, 10)
            if previewCount > 0 {
                print("Prompt (first \(previewCount) lines):")
                for line in promptLines.prefix(previewCount) {
                    print("  \(line)")
                }
                if promptLines.count > previewCount {
                    print("  ... (\(promptLines.count - previewCount) more lines)")
                }
            }

            print("")
            print("Source: \(skill.sourcePath.path)")
        }
    }

    // MARK: - Run Subcommand

    struct RunSkill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Run a skill (placeholder)"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "The skill ID to run")
        var id: String

        @Option(name: .long, parsing: .singleValue, help: "Skill input as key=value")
        var input: [String] = []

        func run() async throws {
            Bootstrap.setupSignalHandlers()

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

            let loader = SkillLoader()
            let searchPaths = SkillLoader.defaultSearchPaths(workspaceRoot: workspaceRoot)
            let skills = loader.discoverSkills(searchPaths: searchPaths)

            guard let skill = skills.first(where: { $0.manifest.id == id }) else {
                print("Skill '\(id)' not found.")
                return
            }

            // Parse inputs
            var parsedInputs: [String: String] = [:]
            for entry in input {
                let parts = entry.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    parsedInputs[String(parts[0])] = String(parts[1])
                } else {
                    print("Invalid input format '\(entry)'. Use key=value.")
                    return
                }
            }

            let m = skill.manifest
            print("Would run skill '\(m.id)' v\(m.version)")
            print("  Title: \(m.title)")
            print("  Risk ceiling: \(m.riskCeiling)")
            print("  Budget: \(m.budget.maxSteps) steps, $\(String(format: "%.2f", m.budget.maxCostUSD)) max")
            print("  Tools: \(m.toolsAllowed.joined(separator: ", "))")
            if !parsedInputs.isEmpty {
                print("  Inputs: \(parsedInputs)")
            }
            if let verify = m.verify {
                print("  Verification: \(verify.command)")
            }
        }
    }
}
