import ArgumentParser
import Foundation
import Yams

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
            CandidatesSkill.self,
            AcceptSkill.self,
            RejectSkill.self,
            RefineSkill_.self,
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

    // MARK: - Candidates Subcommand

    struct CandidatesSkill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "candidates",
            abstract: "List auto-extracted skill candidates awaiting review"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let candidates = await SkillCandidateStore().list()

            guard !candidates.isEmpty else {
                print("No skill candidates yet.")
                print("")
                print("Candidates are extracted automatically from successful agentic")
                print("runs (`zyquo run ...`). Review them here, then:")
                print("  zyquo skills accept <id>   # promote to a runnable skill")
                print("  zyquo skills reject <id>   # discard")
                return
            }

            print("\u{1B}[1mSkill Candidates (\(candidates.count)):\u{1B}[0m")
            print("\u{1B}[2m\(String(repeating: "-", count: 70))\u{1B}[0m")
            for c in candidates {
                let conf = Int((c.confidence * 100).rounded())
                print("  \u{1B}[1m\(c.suggestedId)\u{1B}[0m  \u{1B}[2m(conf \(conf)%, \(c.stepsCount) steps)\u{1B}[0m")
                print("    \(c.suggestedTitle)")
                print("    \u{1B}[2mtools: \(c.toolsUsed.joined(separator: ", "))\u{1B}[0m")
            }
            print("")
            print("Accept with: zyquo skills accept <id>")
        }
    }

    // MARK: - Accept Subcommand

    struct AcceptSkill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "accept",
            abstract: "Promote a candidate into a runnable skill"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "The candidate ID to accept")
        var id: String

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let store = SkillCandidateStore()
            guard let candidate = await store.load(id: id) else {
                print("No candidate '\(id)'. Run `zyquo skills candidates` to list them.")
                throw ExitCode.failure
            }

            let skillsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".zyquo")
                .appendingPathComponent("skills")
                .appendingPathComponent(candidate.suggestedId)
            try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)

            // Write skill.yaml + prompt.md
            let manifest = candidate.toManifest()
            let yaml = try YAMLEncoder().encode(manifest)
            try yaml.write(
                to: skillsDir.appendingPathComponent("skill.yaml"),
                atomically: true, encoding: .utf8
            )
            try candidate.suggestedPrompt.write(
                to: skillsDir.appendingPathComponent("prompt.md"),
                atomically: true, encoding: .utf8
            )

            try? await store.delete(id: id)
            // Resolve the matching nudge if present.
            try? await NudgeStore().markActed(
                id: LearningNudge.makeId(kind: .saveSkill, subject: candidate.suggestedId)
            )

            print("\u{1B}[32m\u{2713}\u{1B}[0m Promoted candidate '\(candidate.suggestedId)' to a skill.")
            print("  \(skillsDir.path)")
            print("  Run it with: zyquo skills run \(candidate.suggestedId)")
        }
    }

    // MARK: - Reject Subcommand

    struct RejectSkill: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reject",
            abstract: "Discard a skill candidate"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "The candidate ID to reject")
        var id: String

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let store = SkillCandidateStore()
            guard await store.load(id: id) != nil else {
                print("No candidate '\(id)'.")
                throw ExitCode.failure
            }
            try await store.delete(id: id)
            try? await NudgeStore().markDismissed(
                id: LearningNudge.makeId(kind: .saveSkill, subject: id)
            )
            print("Discarded candidate '\(id)'.")
        }
    }

    // MARK: - Refine Subcommand

    struct RefineSkill_: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "refine",
            abstract: "Review or apply a proposed skill refinement"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        @Argument(help: "The skill ID to refine")
        var id: String

        @Flag(name: .long, help: "Apply the proposed refinement")
        var apply = false

        func run() async throws {
            Bootstrap.setupSignalHandlers()

            let workspaceRoot = globals.workspace.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let loader = SkillLoader()
            let skills = loader.discoverSkills(
                searchPaths: SkillLoader.defaultSearchPaths(workspaceRoot: workspaceRoot)
            )
            guard let skill = skills.first(where: { $0.manifest.id == id }) else {
                print("Skill '\(id)' not found.")
                throw ExitCode.failure
            }
            guard let proposal = SkillRefiner.load(skillDirectory: skill.sourcePath) else {
                print("No pending refinement for '\(id)'.")
                return
            }

            print("\u{1B}[1mProposed refinement for '\(id)':\u{1B}[0m")
            print("  Rationale: \(proposal.rationale)")
            if proposal.suggestedMaxSteps > 0 {
                print("  Budget: \(skill.manifest.budget.maxSteps) -> \(proposal.suggestedMaxSteps) steps")
            }
            if !proposal.addTools.isEmpty {
                print("  Add tools: \(proposal.addTools.joined(separator: ", "))")
            }
            if !proposal.removeTools.isEmpty {
                print("  Remove tools: \(proposal.removeTools.joined(separator: ", "))")
            }
            if !proposal.newPrompt.isEmpty {
                print("  Prompt: revised (\(proposal.newPrompt.count) chars)")
            }

            guard apply else {
                print("")
                print("Apply with: zyquo skills refine \(id) --apply")
                return
            }

            // Apply: rewrite prompt.md and skill.yaml in the skill directory.
            if !proposal.newPrompt.isEmpty {
                let promptPath = skill.sourcePath.appendingPathComponent("prompt.md")
                try proposal.newPrompt.write(to: promptPath, atomically: true, encoding: .utf8)
            }

            let m = skill.manifest
            let newBudget = proposal.suggestedMaxSteps > 0
                ? SkillBudget(maxSteps: proposal.suggestedMaxSteps, maxCostUSD: m.budget.maxCostUSD)
                : m.budget
            var tools = m.toolsAllowed
            for t in proposal.addTools where !tools.contains(t) { tools.append(t) }
            tools.removeAll { proposal.removeTools.contains($0) }

            let updated = SkillManifest(
                id: m.id,
                version: bumpPatch(m.version),
                title: m.title,
                description: m.description,
                authors: m.authors,
                inputs: m.inputs,
                toolsAllowed: tools,
                promptFile: m.promptFile,
                verify: m.verify,
                budget: newBudget,
                riskCeiling: m.riskCeiling   // never raised
            )
            let yaml = try YAMLEncoder().encode(updated)
            try yaml.write(
                to: skill.sourcePath.appendingPathComponent("skill.yaml"),
                atomically: true, encoding: .utf8
            )

            SkillRefiner.clear(skillDirectory: skill.sourcePath)
            try? await NudgeStore().markActed(
                id: LearningNudge.makeId(kind: .refineSkill, subject: id)
            )
            print("\u{1B}[32m\u{2713}\u{1B}[0m Applied refinement to '\(id)' (now v\(updated.version)).")
        }

        private func bumpPatch(_ version: String) -> String {
            let parts = version.split(separator: ".").map(String.init)
            guard parts.count == 3, let patch = Int(parts[2]) else { return version }
            return "\(parts[0]).\(parts[1]).\(patch + 1)"
        }
    }
}
