import XCTest
import Yams
@testable import Zyquo

final class SkillTests: XCTestCase {

    // MARK: - SkillManifest Parsing

    func testSkillManifestParsingFromYAML() throws {
        let yaml = """
        id: fix_swift_build
        version: 0.1.0
        title: Fix a failing Swift build
        description: Diagnose and fix Swift build failures
        authors:
          - zyquo
          - contributor
        inputs:
          - { name: package_path, type: path, required: true, description: "Path to package" }
          - { name: test_filter, type: string, required: false }
        tools_allowed:
          - shell.run
          - file.read
          - file.patch
          - git.status
        prompt: ./prompt.md
        verify:
          command: "swift test"
          expect_exit_code: 0
        budget:
          max_steps: 25
          max_cost_usd: 1.50
        risk_ceiling: MODERATE
        """

        let decoder = YAMLDecoder()
        let manifest = try decoder.decode(SkillManifest.self, from: yaml)

        XCTAssertEqual(manifest.id, "fix_swift_build")
        XCTAssertEqual(manifest.version, "0.1.0")
        XCTAssertEqual(manifest.title, "Fix a failing Swift build")
        XCTAssertEqual(manifest.description, "Diagnose and fix Swift build failures")
        XCTAssertEqual(manifest.authors, ["zyquo", "contributor"])
        XCTAssertEqual(manifest.inputs.count, 2)
        XCTAssertEqual(manifest.toolsAllowed, ["shell.run", "file.read", "file.patch", "git.status"])
        XCTAssertEqual(manifest.promptFile, "./prompt.md")
        XCTAssertNotNil(manifest.verify)
        XCTAssertEqual(manifest.verify?.command, "swift test")
        XCTAssertEqual(manifest.verify?.expectExitCode, 0)
        XCTAssertEqual(manifest.budget.maxSteps, 25)
        XCTAssertEqual(manifest.budget.maxCostUSD, 1.50)
        XCTAssertEqual(manifest.riskCeiling, "MODERATE")
    }

    func testSkillManifestWithOptionalFields() throws {
        let yaml = """
        id: simple_skill
        version: 1.0.0
        title: Simple skill
        tools_allowed:
          - file.read
        prompt: ./prompt.md
        budget:
          max_steps: 10
          max_cost_usd: 0.50
        risk_ceiling: SAFE
        """

        let decoder = YAMLDecoder()
        let manifest = try decoder.decode(SkillManifest.self, from: yaml)

        XCTAssertEqual(manifest.id, "simple_skill")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.title, "Simple skill")
        XCTAssertNil(manifest.description)
        XCTAssertTrue(manifest.authors.isEmpty)
        XCTAssertTrue(manifest.inputs.isEmpty)
        XCTAssertNil(manifest.verify)
        XCTAssertEqual(manifest.budget.maxSteps, 10)
        XCTAssertEqual(manifest.budget.maxCostUSD, 0.50)
        XCTAssertEqual(manifest.riskCeiling, "SAFE")
    }

    // MARK: - SkillInput Types and Defaults

    func testSkillInputTypes() throws {
        let yaml = """
        id: typed_inputs
        version: 0.1.0
        title: Typed inputs test
        inputs:
          - { name: path_arg, type: path, required: true, description: "A path" }
          - { name: str_arg, type: string, required: false, default: "hello" }
          - { name: bool_arg, type: bool, required: false, default: "true" }
          - { name: int_arg, type: int, required: false, default: "42" }
        tools_allowed:
          - file.read
        prompt: ./prompt.md
        budget:
          max_steps: 5
          max_cost_usd: 0.10
        risk_ceiling: SAFE
        """

        let decoder = YAMLDecoder()
        let manifest = try decoder.decode(SkillManifest.self, from: yaml)

        XCTAssertEqual(manifest.inputs.count, 4)

        let pathInput = manifest.inputs[0]
        XCTAssertEqual(pathInput.name, "path_arg")
        XCTAssertEqual(pathInput.type, "path")
        XCTAssertTrue(pathInput.required)
        XCTAssertEqual(pathInput.description, "A path")
        XCTAssertNil(pathInput.defaultValue)

        let strInput = manifest.inputs[1]
        XCTAssertEqual(strInput.name, "str_arg")
        XCTAssertEqual(strInput.type, "string")
        XCTAssertFalse(strInput.required)
        XCTAssertEqual(strInput.defaultValue, "hello")

        let boolInput = manifest.inputs[2]
        XCTAssertEqual(boolInput.name, "bool_arg")
        XCTAssertEqual(boolInput.type, "bool")
        XCTAssertEqual(boolInput.defaultValue, "true")

        let intInput = manifest.inputs[3]
        XCTAssertEqual(intInput.name, "int_arg")
        XCTAssertEqual(intInput.type, "int")
        XCTAssertEqual(intInput.defaultValue, "42")
    }

    // MARK: - SkillBudget Defaults

    func testSkillBudgetDefaults() {
        let budget = SkillBudget()
        XCTAssertEqual(budget.maxSteps, 25)
        XCTAssertEqual(budget.maxCostUSD, 2.0)
    }

    func testSkillBudgetCustom() {
        let budget = SkillBudget(maxSteps: 10, maxCostUSD: 0.50)
        XCTAssertEqual(budget.maxSteps, 10)
        XCTAssertEqual(budget.maxCostUSD, 0.50)
    }

    // MARK: - SkillVerification Encoding/Decoding

    func testSkillVerificationCodable() throws {
        let verify = SkillVerification(command: "swift test", expectExitCode: 0)

        let encoder = JSONEncoder()
        let data = try encoder.encode(verify)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SkillVerification.self, from: data)

        XCTAssertEqual(decoded.command, "swift test")
        XCTAssertEqual(decoded.expectExitCode, 0)
    }

    func testSkillVerificationFromYAML() throws {
        let yaml = """
        command: "npm test"
        expect_exit_code: 0
        """

        let decoder = YAMLDecoder()
        let verify = try decoder.decode(SkillVerification.self, from: yaml)
        XCTAssertEqual(verify.command, "npm test")
        XCTAssertEqual(verify.expectExitCode, 0)
    }

    // MARK: - Risk Ceiling Mapping

    func testRiskCeilingMapping() {
        let cases: [(String, RiskLevel)] = [
            ("SAFE", .safe),
            ("safe", .safe),
            ("MODERATE", .moderate),
            ("moderate", .moderate),
            ("DANGEROUS", .dangerous),
            ("dangerous", .dangerous),
            ("CRITICAL", .critical),
            ("critical", .critical),
            ("unknown", .moderate),   // fallback
            ("", .moderate),          // fallback
        ]

        for (input, expected) in cases {
            let manifest = SkillManifest(
                id: "test",
                version: "0.1.0",
                title: "test",
                riskCeiling: input
            )
            XCTAssertEqual(manifest.resolvedRiskCeiling, expected, "Expected \(input) -> \(expected)")
        }
    }

    // MARK: - SkillLoader: Discover Skills from Directory

    func testSkillLoaderDiscoversSkills() throws {
        // Create a temporary directory with a skill
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_skills_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a skill directory
        let skillDir = tempDir.appendingPathComponent("test_skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let skillYaml = """
        id: test_skill
        version: 0.1.0
        title: Test Skill
        tools_allowed:
          - file.read
        prompt: ./prompt.md
        budget:
          max_steps: 5
          max_cost_usd: 0.10
        risk_ceiling: SAFE
        """
        try skillYaml.write(to: skillDir.appendingPathComponent("skill.yaml"), atomically: true, encoding: .utf8)
        try "Test prompt content".write(to: skillDir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)

        let loader = SkillLoader()
        let skills = loader.discoverSkills(searchPaths: [tempDir])

        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0].manifest.id, "test_skill")
        XCTAssertEqual(skills[0].manifest.title, "Test Skill")
        XCTAssertEqual(skills[0].prompt, "Test prompt content")
    }

    func testSkillLoaderFailsOnMissingSkillYaml() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_no_yaml_\(UUID().uuidString)")

        let loader = SkillLoader()

        XCTAssertThrowsError(try loader.loadSkill(at: tempDir)) { error in
            XCTAssertTrue(error is SkillLoadError)
            let loadError = error as! SkillLoadError
            if case .manifestNotFound = loadError {
                // expected
            } else {
                XCTFail("Expected manifestNotFound, got \(loadError)")
            }
        }
    }

    func testSkillLoaderFailsOnMissingPromptMd() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_no_prompt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillYaml = """
        id: no_prompt
        version: 0.1.0
        title: No Prompt
        tools_allowed: []
        prompt: ./prompt.md
        budget:
          max_steps: 5
          max_cost_usd: 0.10
        risk_ceiling: SAFE
        """
        try skillYaml.write(to: tempDir.appendingPathComponent("skill.yaml"), atomically: true, encoding: .utf8)
        // Deliberately NOT creating prompt.md

        let loader = SkillLoader()

        XCTAssertThrowsError(try loader.loadSkill(at: tempDir)) { error in
            XCTAssertTrue(error is SkillLoadError)
            let loadError = error as! SkillLoadError
            if case .promptNotFound = loadError {
                // expected
            } else {
                XCTFail("Expected promptNotFound, got \(loadError)")
            }
        }
    }

    func testSkillLoaderLoadsPromptContent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_prompt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillYaml = """
        id: prompt_test
        version: 0.1.0
        title: Prompt Test
        tools_allowed:
          - file.read
        prompt: ./prompt.md
        budget:
          max_steps: 5
          max_cost_usd: 0.10
        risk_ceiling: SAFE
        """
        let promptContent = "You are a helpful assistant.\n\nDo good work."
        try skillYaml.write(to: tempDir.appendingPathComponent("skill.yaml"), atomically: true, encoding: .utf8)
        try promptContent.write(to: tempDir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)

        let loader = SkillLoader()
        let skill = try loader.loadSkill(at: tempDir)

        XCTAssertEqual(skill.prompt, promptContent)
        XCTAssertEqual(skill.manifest.id, "prompt_test")
        XCTAssertEqual(skill.sourcePath, tempDir)
    }

    // MARK: - SkillRegistry Register and Lookup

    func testSkillRegistryRegisterAndLookup() throws {
        let registry = SkillRegistry()

        let skill = makeTestSkill(id: "test_skill", title: "Test Skill")
        registry.register(skill)

        XCTAssertEqual(registry.count, 1)

        let found = registry.skill(id: "test_skill")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.manifest.id, "test_skill")
        XCTAssertEqual(found?.manifest.title, "Test Skill")

        // Not found
        XCTAssertNil(registry.skill(id: "nonexistent"))
    }

    func testSkillRegistryAllSkills() {
        let registry = SkillRegistry()

        registry.register(makeTestSkill(id: "beta_skill", title: "Beta"))
        registry.register(makeTestSkill(id: "alpha_skill", title: "Alpha"))
        registry.register(makeTestSkill(id: "gamma_skill", title: "Gamma"))

        let all = registry.allSkills()
        XCTAssertEqual(all.count, 3)
        // Sorted by ID
        XCTAssertEqual(all[0].manifest.id, "alpha_skill")
        XCTAssertEqual(all[1].manifest.id, "beta_skill")
        XCTAssertEqual(all[2].manifest.id, "gamma_skill")
    }

    func testSkillRegistryReplaceExisting() {
        let registry = SkillRegistry()

        registry.register(makeTestSkill(id: "skill_a", title: "Version 1"))
        registry.register(makeTestSkill(id: "skill_a", title: "Version 2"))

        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.skill(id: "skill_a")?.manifest.title, "Version 2")
    }

    // MARK: - SkillRegistry Search

    func testSkillRegistrySearchByID() {
        let registry = SkillRegistry()
        registry.register(makeTestSkill(id: "fix_swift_build", title: "Fix Swift Build"))
        registry.register(makeTestSkill(id: "code_review", title: "Code Review"))
        registry.register(makeTestSkill(id: "onboard_repo", title: "Onboard Repo"))

        let results = registry.search(query: "fix_swift")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].manifest.id, "fix_swift_build")
    }

    func testSkillRegistrySearchByTitle() {
        let registry = SkillRegistry()
        registry.register(makeTestSkill(id: "fix_swift_build", title: "Fix Swift Build"))
        registry.register(makeTestSkill(id: "code_review", title: "Code Review"))
        registry.register(makeTestSkill(id: "onboard_repo", title: "Onboard Repo"))

        let results = registry.search(query: "review")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].manifest.id, "code_review")
    }

    func testSkillRegistrySearchByDescription() {
        let registry = SkillRegistry()
        registry.register(makeTestSkill(id: "skill_a", title: "Alpha", description: "Diagnose build failures"))
        registry.register(makeTestSkill(id: "skill_b", title: "Beta", description: "Generate documentation"))

        let results = registry.search(query: "diagnose")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].manifest.id, "skill_a")
    }

    func testSkillRegistrySearchEmptyQuery() {
        let registry = SkillRegistry()
        registry.register(makeTestSkill(id: "alpha", title: "Alpha"))
        registry.register(makeTestSkill(id: "beta", title: "Beta"))

        let results = registry.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSkillRegistrySearchNoMatch() {
        let registry = SkillRegistry()
        registry.register(makeTestSkill(id: "fix_swift_build", title: "Fix Swift Build"))

        let results = registry.search(query: "kubernetes")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Tool Whitelist Enforcement

    func testToolWhitelistEnforcement() async {
        let runner = SkillRunner()
        let allowed: Set<String> = ["file.read", "file.search", "git.status"]

        // Allowed
        let readAllowed = await runner.isToolAllowed("file.read", allowedTools: allowed)
        XCTAssertTrue(readAllowed)
        let searchAllowed = await runner.isToolAllowed("file.search", allowedTools: allowed)
        XCTAssertTrue(searchAllowed)
        let statusAllowed = await runner.isToolAllowed("git.status", allowedTools: allowed)
        XCTAssertTrue(statusAllowed)

        // Not allowed
        let writeAllowed = await runner.isToolAllowed("file.write", allowedTools: allowed)
        XCTAssertFalse(writeAllowed)
        let shellAllowed = await runner.isToolAllowed("shell.run", allowedTools: allowed)
        XCTAssertFalse(shellAllowed)
        let pushAllowed = await runner.isToolAllowed("git.push", allowedTools: allowed)
        XCTAssertFalse(pushAllowed)
    }

    func testToolWhitelistWildcard() async {
        let runner = SkillRunner()
        let allowed: Set<String> = ["git.*", "file.read"]

        let statusAllowed = await runner.isToolAllowed("git.status", allowedTools: allowed)
        XCTAssertTrue(statusAllowed)
        let diffAllowed = await runner.isToolAllowed("git.diff", allowedTools: allowed)
        XCTAssertTrue(diffAllowed)
        let commitAllowed = await runner.isToolAllowed("git.commit", allowedTools: allowed)
        XCTAssertTrue(commitAllowed)
        let readAllowed = await runner.isToolAllowed("file.read", allowedTools: allowed)
        XCTAssertTrue(readAllowed)

        // Not covered by wildcard
        let shellAllowed = await runner.isToolAllowed("shell.run", allowedTools: allowed)
        XCTAssertFalse(shellAllowed)
        let writeAllowed = await runner.isToolAllowed("file.write", allowedTools: allowed)
        XCTAssertFalse(writeAllowed)
    }

    func testScopedRegistryCreation() async {
        let runner = SkillRunner()

        // Create a full registry with multiple tools
        let fullRegistry = ToolRegistry()
        fullRegistry.registerAll([
            StubTool(name: "shell.run"),
            StubTool(name: "file.read"),
            StubTool(name: "file.write"),
            StubTool(name: "file.search"),
            StubTool(name: "git.status"),
            StubTool(name: "git.push"),
        ])

        let skill = makeTestSkill(
            id: "scoped_test",
            title: "Scoped",
            toolsAllowed: ["file.read", "file.search", "git.status"]
        )

        let scoped = await runner.createScopedRegistry(skill: skill, fullRegistry: fullRegistry)

        // Only allowed tools should be in scoped registry
        XCTAssertEqual(scoped.count, 3)
        XCTAssertNotNil(scoped.tool(named: "file.read"))
        XCTAssertNotNil(scoped.tool(named: "file.search"))
        XCTAssertNotNil(scoped.tool(named: "git.status"))
        XCTAssertNil(scoped.tool(named: "shell.run"))
        XCTAssertNil(scoped.tool(named: "file.write"))
        XCTAssertNil(scoped.tool(named: "git.push"))
    }

    // MARK: - Risk Ceiling Enforcement

    func testRiskCeilingEnforcement() async {
        let runner = SkillRunner()

        let moderateSkill = makeTestSkill(id: "mod", title: "Moderate", riskCeiling: "MODERATE")
        let safeSkill = makeTestSkill(id: "safe", title: "Safe", riskCeiling: "SAFE")

        // Moderate ceiling
        let safeMod = await runner.isRiskAllowed(.safe, skill: moderateSkill)
        XCTAssertTrue(safeMod)
        let modMod = await runner.isRiskAllowed(.moderate, skill: moderateSkill)
        XCTAssertTrue(modMod)
        let dangMod = await runner.isRiskAllowed(.dangerous, skill: moderateSkill)
        XCTAssertFalse(dangMod)
        let critMod = await runner.isRiskAllowed(.critical, skill: moderateSkill)
        XCTAssertFalse(critMod)

        // Safe ceiling
        let safeSafe = await runner.isRiskAllowed(.safe, skill: safeSkill)
        XCTAssertTrue(safeSafe)
        let modSafe = await runner.isRiskAllowed(.moderate, skill: safeSkill)
        XCTAssertFalse(modSafe)
    }

    // MARK: - Budget Enforcement

    func testStepBudgetEnforcement() async {
        let runner = SkillRunner()
        let skill = makeTestSkill(id: "budget", title: "Budget", maxSteps: 5)

        let avail0 = await runner.isStepBudgetAvailable(stepsUsed: 0, skill: skill)
        XCTAssertTrue(avail0)
        let avail4 = await runner.isStepBudgetAvailable(stepsUsed: 4, skill: skill)
        XCTAssertTrue(avail4)
        let avail5 = await runner.isStepBudgetAvailable(stepsUsed: 5, skill: skill)
        XCTAssertFalse(avail5)
        let avail6 = await runner.isStepBudgetAvailable(stepsUsed: 6, skill: skill)
        XCTAssertFalse(avail6)
    }

    func testCostBudgetEnforcement() async {
        let runner = SkillRunner()
        let skill = makeTestSkill(id: "cost", title: "Cost", maxCostUSD: 1.50)

        let avail0 = await runner.isCostBudgetAvailable(costUsed: 0.0, skill: skill)
        XCTAssertTrue(avail0)
        let avail1 = await runner.isCostBudgetAvailable(costUsed: 1.49, skill: skill)
        XCTAssertTrue(avail1)
        let avail2 = await runner.isCostBudgetAvailable(costUsed: 1.50, skill: skill)
        XCTAssertFalse(avail2)
        let avail3 = await runner.isCostBudgetAvailable(costUsed: 2.00, skill: skill)
        XCTAssertFalse(avail3)
    }

    // MARK: - LoadedSkill Properties

    func testLoadedSkillProperties() {
        let manifest = SkillManifest(
            id: "loaded_test",
            version: "1.2.3",
            title: "Loaded Test",
            description: "A test skill",
            authors: ["author1"],
            toolsAllowed: ["file.read"],
            riskCeiling: "DANGEROUS"
        )
        let skill = LoadedSkill(
            manifest: manifest,
            prompt: "You are a test agent.",
            sourcePath: URL(fileURLWithPath: "/tmp/skills/loaded_test")
        )

        XCTAssertEqual(skill.manifest.id, "loaded_test")
        XCTAssertEqual(skill.manifest.version, "1.2.3")
        XCTAssertEqual(skill.prompt, "You are a test agent.")
        XCTAssertEqual(skill.sourcePath.path, "/tmp/skills/loaded_test")
        XCTAssertEqual(skill.manifest.resolvedRiskCeiling, .dangerous)
    }

    // MARK: - Input Validation

    func testInputValidationMissingRequired() async {
        let runner = SkillRunner()
        let skill = makeTestSkill(
            id: "validate",
            title: "Validate",
            inputs: [
                SkillInput(name: "required_path", type: "path", required: true),
                SkillInput(name: "optional_str", type: "string", required: false),
            ]
        )

        do {
            try await runner.validateInputs(skill: skill, inputs: [:])
            XCTFail("Expected error for missing required input")
        } catch {
            XCTAssertTrue(error is SkillRunError)
            if let runError = error as? SkillRunError,
               case .missingRequiredInput(let name, _) = runError {
                XCTAssertEqual(name, "required_path")
            }
        }
    }

    func testInputValidationInvalidType() async {
        let runner = SkillRunner()
        let skill = makeTestSkill(
            id: "validate",
            title: "Validate",
            inputs: [
                SkillInput(name: "count", type: "int", required: true),
            ]
        )

        do {
            try await runner.validateInputs(skill: skill, inputs: ["count": "not_a_number"])
            XCTFail("Expected error for invalid type")
        } catch {
            XCTAssertTrue(error is SkillRunError)
            if let runError = error as? SkillRunError,
               case .inputTypeInvalid(let name, let expectedType, _) = runError {
                XCTAssertEqual(name, "count")
                XCTAssertEqual(expectedType, "int")
            }
        }
    }

    func testInputValidationValidInputs() async {
        let runner = SkillRunner()
        let skill = makeTestSkill(
            id: "validate",
            title: "Validate",
            inputs: [
                SkillInput(name: "path", type: "path", required: true),
                SkillInput(name: "count", type: "int", required: false),
                SkillInput(name: "flag", type: "bool", required: false),
            ]
        )

        do {
            try await runner.validateInputs(skill: skill, inputs: [
                "path": "/some/path",
                "count": "42",
                "flag": "true",
            ])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Skill Loader Discovers Multiple Skills

    func testSkillLoaderDiscoversMultipleSkills() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_multi_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for name in ["alpha", "beta", "gamma"] {
            let dir = tempDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let yaml = """
            id: \(name)
            version: 0.1.0
            title: \(name.capitalized)
            tools_allowed: []
            prompt: ./prompt.md
            budget:
              max_steps: 5
              max_cost_usd: 0.10
            risk_ceiling: SAFE
            """
            try yaml.write(to: dir.appendingPathComponent("skill.yaml"), atomically: true, encoding: .utf8)
            try "Prompt for \(name)".write(to: dir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)
        }

        let loader = SkillLoader()
        let skills = loader.discoverSkills(searchPaths: [tempDir])

        XCTAssertEqual(skills.count, 3)
        let ids = skills.map(\.manifest.id)
        XCTAssertTrue(ids.contains("alpha"))
        XCTAssertTrue(ids.contains("beta"))
        XCTAssertTrue(ids.contains("gamma"))
    }

    // MARK: - Skill Loader Deduplicates by ID

    func testSkillLoaderDeduplicatesByID() throws {
        let dir1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_dedup1_\(UUID().uuidString)")
        let dir2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo_test_dedup2_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }

        // Same skill ID in both directories
        for dir in [dir1, dir2] {
            let skillDir = dir.appendingPathComponent("my_skill")
            try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
            let title = dir == dir1 ? "Project Version" : "Global Version"
            let yaml = """
            id: my_skill
            version: 0.1.0
            title: \(title)
            tools_allowed: []
            prompt: ./prompt.md
            budget:
              max_steps: 5
              max_cost_usd: 0.10
            risk_ceiling: SAFE
            """
            try yaml.write(to: skillDir.appendingPathComponent("skill.yaml"), atomically: true, encoding: .utf8)
            try "Prompt".write(to: skillDir.appendingPathComponent("prompt.md"), atomically: true, encoding: .utf8)
        }

        let loader = SkillLoader()
        // dir1 (project) comes first, so it wins
        let skills = loader.discoverSkills(searchPaths: [dir1, dir2])

        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0].manifest.title, "Project Version")
    }

    // MARK: - SkillRegistry Unregister

    func testSkillRegistryUnregister() {
        let registry = SkillRegistry()
        registry.register(makeTestSkill(id: "removable", title: "Removable"))

        XCTAssertEqual(registry.count, 1)
        XCTAssertNotNil(registry.skill(id: "removable"))

        registry.unregister("removable")
        XCTAssertEqual(registry.count, 0)
        XCTAssertNil(registry.skill(id: "removable"))
    }

    // MARK: - Helpers

    private func makeTestSkill(
        id: String,
        title: String,
        description: String? = nil,
        toolsAllowed: [String] = ["file.read"],
        riskCeiling: String = "MODERATE",
        maxSteps: Int = 25,
        maxCostUSD: Double = 2.0,
        inputs: [SkillInput] = []
    ) -> LoadedSkill {
        let manifest = SkillManifest(
            id: id,
            version: "0.1.0",
            title: title,
            description: description,
            inputs: inputs,
            toolsAllowed: toolsAllowed,
            budget: SkillBudget(maxSteps: maxSteps, maxCostUSD: maxCostUSD),
            riskCeiling: riskCeiling
        )
        return LoadedSkill(
            manifest: manifest,
            prompt: "Test prompt for \(id)",
            sourcePath: URL(fileURLWithPath: "/tmp/skills/\(id)")
        )
    }
}

// MARK: - StubTool for Scoped Registry Tests

private struct StubTool: Tool {
    let name: String
    var summary: String { "Stub tool" }
    var documentation: String { "" }
    var inputSchema: ToolInputSchema { .empty }
    var defaultRisk: RiskLevel { .safe }
    var isMutating: Bool { false }

    func execute(input: [String: JSONValue], context: ToolContext) async throws -> ToolResult {
        ToolResult(summary: "stub")
    }
}
