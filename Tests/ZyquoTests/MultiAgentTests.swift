import XCTest
@testable import Zyquo

final class MultiAgentTests: XCTestCase {

    // MARK: - SubAgentType: Tool Whitelists

    func testArchitectAgentToolWhitelist() {
        let agent = ArchitectAgent()
        XCTAssertEqual(agent.id, "architect")
        XCTAssertEqual(agent.riskCeiling, .safe)
        XCTAssertEqual(agent.maxSteps, 20)

        // Allowed tools
        XCTAssertTrue(agent.isToolAllowed("file.read"))
        XCTAssertTrue(agent.isToolAllowed("file.search"))
        XCTAssertTrue(agent.isToolAllowed("file.list"))
        XCTAssertTrue(agent.isToolAllowed("task.plan"))

        // Wildcard: memory.* allows memory.read, memory.write, etc.
        XCTAssertTrue(agent.isToolAllowed("memory.read"))
        XCTAssertTrue(agent.isToolAllowed("memory.write"))
        XCTAssertTrue(agent.isToolAllowed("memory.search"))

        // Wildcard: workspace.* allows workspace.index, etc.
        XCTAssertTrue(agent.isToolAllowed("workspace.index"))
        XCTAssertTrue(agent.isToolAllowed("workspace.detect"))

        // Disallowed tools
        XCTAssertFalse(agent.isToolAllowed("shell.run"))
        XCTAssertFalse(agent.isToolAllowed("file.write"))
        XCTAssertFalse(agent.isToolAllowed("file.patch"))
        XCTAssertFalse(agent.isToolAllowed("git.commit"))
        XCTAssertFalse(agent.isToolAllowed("git.push"))
    }

    func testCoderAgentToolWhitelist() {
        let agent = CoderAgent()
        XCTAssertEqual(agent.id, "coder")
        XCTAssertEqual(agent.riskCeiling, .moderate)
        XCTAssertEqual(agent.maxSteps, 30)

        // Coder has access to all V1 tools
        XCTAssertTrue(agent.isToolAllowed("shell.run"))
        XCTAssertTrue(agent.isToolAllowed("file.read"))
        XCTAssertTrue(agent.isToolAllowed("file.write"))
        XCTAssertTrue(agent.isToolAllowed("file.patch"))
        XCTAssertTrue(agent.isToolAllowed("file.list"))
        XCTAssertTrue(agent.isToolAllowed("file.search"))
        XCTAssertTrue(agent.isToolAllowed("file.delete"))
        XCTAssertTrue(agent.isToolAllowed("git.commit"))
        XCTAssertTrue(agent.isToolAllowed("git.status"))
        XCTAssertTrue(agent.isToolAllowed("git.diff"))
        XCTAssertTrue(agent.isToolAllowed("git.push"))
        XCTAssertTrue(agent.isToolAllowed("memory.read"))
        XCTAssertTrue(agent.isToolAllowed("workspace.index"))
        XCTAssertTrue(agent.isToolAllowed("task.plan"))
        XCTAssertTrue(agent.isToolAllowed("task.verify"))
        XCTAssertTrue(agent.isToolAllowed("build.run"))
        XCTAssertTrue(agent.isToolAllowed("test.run"))
    }

    func testShellAgentToolWhitelist() {
        let agent = ShellAgent()
        XCTAssertEqual(agent.id, "shell")
        XCTAssertEqual(agent.riskCeiling, .moderate)
        XCTAssertEqual(agent.maxSteps, 25)

        // Allowed
        XCTAssertTrue(agent.isToolAllowed("shell.run"))
        XCTAssertTrue(agent.isToolAllowed("shell.cancel"))
        XCTAssertTrue(agent.isToolAllowed("shell.history"))
        XCTAssertTrue(agent.isToolAllowed("shell.which"))
        XCTAssertTrue(agent.isToolAllowed("file.read"))
        XCTAssertTrue(agent.isToolAllowed("git.status"))
        XCTAssertTrue(agent.isToolAllowed("git.diff"))
        XCTAssertTrue(agent.isToolAllowed("git.commit"))
        XCTAssertTrue(agent.isToolAllowed("git.push"))

        // Disallowed
        XCTAssertFalse(agent.isToolAllowed("file.write"))
        XCTAssertFalse(agent.isToolAllowed("file.patch"))
        XCTAssertFalse(agent.isToolAllowed("file.delete"))
        XCTAssertFalse(agent.isToolAllowed("memory.read"))
        XCTAssertFalse(agent.isToolAllowed("workspace.index"))
    }

    func testReviewerAgentToolWhitelist() {
        let agent = ReviewerAgent()
        XCTAssertEqual(agent.id, "reviewer")
        XCTAssertEqual(agent.riskCeiling, .safe)
        XCTAssertEqual(agent.maxSteps, 15)

        // Allowed
        XCTAssertTrue(agent.isToolAllowed("file.read"))
        XCTAssertTrue(agent.isToolAllowed("file.search"))
        XCTAssertTrue(agent.isToolAllowed("file.list"))
        XCTAssertTrue(agent.isToolAllowed("git.diff"))

        // Disallowed
        XCTAssertFalse(agent.isToolAllowed("shell.run"))
        XCTAssertFalse(agent.isToolAllowed("file.write"))
        XCTAssertFalse(agent.isToolAllowed("file.patch"))
        XCTAssertFalse(agent.isToolAllowed("git.commit"))
        XCTAssertFalse(agent.isToolAllowed("git.push"))
        XCTAssertFalse(agent.isToolAllowed("git.status"))
        XCTAssertFalse(agent.isToolAllowed("memory.read"))
    }

    func testResearchAgentToolWhitelist() {
        let agent = ResearchAgent()
        XCTAssertEqual(agent.id, "research")
        XCTAssertEqual(agent.riskCeiling, .safe)
        XCTAssertEqual(agent.maxSteps, 20)

        // Allowed
        XCTAssertTrue(agent.isToolAllowed("file.read"))
        XCTAssertTrue(agent.isToolAllowed("file.search"))
        XCTAssertTrue(agent.isToolAllowed("file.list"))
        XCTAssertTrue(agent.isToolAllowed("memory.read"))
        XCTAssertTrue(agent.isToolAllowed("memory.write"))
        XCTAssertTrue(agent.isToolAllowed("memory.search"))

        // Disallowed
        XCTAssertFalse(agent.isToolAllowed("shell.run"))
        XCTAssertFalse(agent.isToolAllowed("file.write"))
        XCTAssertFalse(agent.isToolAllowed("file.patch"))
        XCTAssertFalse(agent.isToolAllowed("git.commit"))
    }

    func testVerifierAgentToolWhitelist() {
        let agent = VerifierAgent()
        XCTAssertEqual(agent.id, "verifier")
        XCTAssertEqual(agent.riskCeiling, .moderate)
        XCTAssertEqual(agent.maxSteps, 15)

        // Allowed
        XCTAssertTrue(agent.isToolAllowed("shell.run"))
        XCTAssertTrue(agent.isToolAllowed("file.read"))
        XCTAssertTrue(agent.isToolAllowed("file.list"))

        // Disallowed
        XCTAssertFalse(agent.isToolAllowed("file.write"))
        XCTAssertFalse(agent.isToolAllowed("file.patch"))
        XCTAssertFalse(agent.isToolAllowed("git.commit"))
        XCTAssertFalse(agent.isToolAllowed("memory.read"))
        XCTAssertFalse(agent.isToolAllowed("shell.cancel"))
    }

    // MARK: - Tool Whitelist Enforcement

    func testToolWhitelistEnforcement() {
        // Agent can only use tools in its whitelist
        let reviewer = ReviewerAgent()

        // file.read is in the whitelist
        XCTAssertTrue(reviewer.isToolAllowed("file.read"))

        // shell.run is NOT in the whitelist
        XCTAssertFalse(reviewer.isToolAllowed("shell.run"))

        // file.write is NOT in the whitelist
        XCTAssertFalse(reviewer.isToolAllowed("file.write"))

        // Exact match required for non-wildcard tools
        XCTAssertFalse(reviewer.isToolAllowed("file.reader"))
    }

    func testWildcardToolMatching() {
        let architect = ArchitectAgent()

        // memory.* should match any memory.X tool
        XCTAssertTrue(architect.isToolAllowed("memory.read"))
        XCTAssertTrue(architect.isToolAllowed("memory.write"))
        XCTAssertTrue(architect.isToolAllowed("memory.search"))
        XCTAssertTrue(architect.isToolAllowed("memory.compact"))

        // workspace.* should match any workspace.X tool
        XCTAssertTrue(architect.isToolAllowed("workspace.index"))
        XCTAssertTrue(architect.isToolAllowed("workspace.detect"))
        XCTAssertTrue(architect.isToolAllowed("workspace.summary"))

        // But not "memoryX" (missing dot after prefix)
        XCTAssertFalse(architect.isToolAllowed("memoryread"))

        // And not tools in different namespaces
        XCTAssertFalse(architect.isToolAllowed("shell.run"))
    }

    // MARK: - Risk Ceiling Enforcement

    func testRiskCeilingEnforcement() {
        let architect = ArchitectAgent()
        XCTAssertTrue(architect.isRiskAllowed(.safe))
        XCTAssertFalse(architect.isRiskAllowed(.moderate))
        XCTAssertFalse(architect.isRiskAllowed(.dangerous))
        XCTAssertFalse(architect.isRiskAllowed(.critical))

        let coder = CoderAgent()
        XCTAssertTrue(coder.isRiskAllowed(.safe))
        XCTAssertTrue(coder.isRiskAllowed(.moderate))
        XCTAssertFalse(coder.isRiskAllowed(.dangerous))
        XCTAssertFalse(coder.isRiskAllowed(.critical))

        let reviewer = ReviewerAgent()
        XCTAssertTrue(reviewer.isRiskAllowed(.safe))
        XCTAssertFalse(reviewer.isRiskAllowed(.moderate))

        let verifier = VerifierAgent()
        XCTAssertTrue(verifier.isRiskAllowed(.safe))
        XCTAssertTrue(verifier.isRiskAllowed(.moderate))
        XCTAssertFalse(verifier.isRiskAllowed(.dangerous))
    }

    // MARK: - Agent Selection Logic

    func testAgentSelectionExplicitType() {
        let orchestrator = Orchestrator()

        // Explicit agent type match
        let coderTask = SubTask(agentType: "coder", goal: "anything", successCriteria: "ok")
        let selected = orchestrator.selectAgent(for: coderTask)
        XCTAssertEqual(selected.id, "coder")

        let architectTask = SubTask(agentType: "architect", goal: "anything", successCriteria: "ok")
        let archSelected = orchestrator.selectAgent(for: architectTask)
        XCTAssertEqual(archSelected.id, "architect")

        let verifierTask = SubTask(agentType: "verifier", goal: "anything", successCriteria: "ok")
        let verSelected = orchestrator.selectAgent(for: verifierTask)
        XCTAssertEqual(verSelected.id, "verifier")
    }

    func testAgentSelectionByKeyword() {
        let orchestrator = Orchestrator()

        // Code-related task defaults to coder
        let codeTask = SubTask(agentType: "unknown_agent", goal: "implement feature X", successCriteria: "ok")
        let codeAgent = orchestrator.selectAgent(for: codeTask)
        XCTAssertEqual(codeAgent.id, "coder")

        // Test-related task selects verifier
        let testTask = SubTask(agentType: "unknown", goal: "run tests to verify the fix", successCriteria: "ok")
        let testAgent = orchestrator.selectAgent(for: testTask)
        XCTAssertEqual(testAgent.id, "verifier")

        // Review task selects reviewer
        let reviewTask = SubTask(agentType: "unknown", goal: "review the changes for correctness", successCriteria: "ok")
        let reviewAgent = orchestrator.selectAgent(for: reviewTask)
        XCTAssertEqual(reviewAgent.id, "reviewer")

        // Build task selects shell
        let buildTask = SubTask(agentType: "unknown", goal: "build the project", successCriteria: "ok")
        let buildAgent = orchestrator.selectAgent(for: buildTask)
        XCTAssertEqual(buildAgent.id, "shell")

        // Research task selects research
        let researchTask = SubTask(agentType: "unknown", goal: "research the authentication patterns", successCriteria: "ok")
        let researchAgent = orchestrator.selectAgent(for: researchTask)
        XCTAssertEqual(researchAgent.id, "research")

        // Architecture task selects architect
        let archTask = SubTask(agentType: "unknown", goal: "design the module architecture", successCriteria: "ok")
        let archAgent = orchestrator.selectAgent(for: archTask)
        XCTAssertEqual(archAgent.id, "architect")
    }

    // MARK: - SubTask Status Transitions

    func testSubTaskStatusTransitions() {
        var task = SubTask(agentType: "coder", goal: "fix bug", successCriteria: "tests pass")

        // Initial state
        XCTAssertEqual(task.status, .pending)
        XCTAssertFalse(task.isTerminal)
        XCTAssertNil(task.startedAt)

        // Assign
        task.status = .assigned
        XCTAssertEqual(task.status, .assigned)
        XCTAssertFalse(task.isTerminal)

        // Start running
        task.status = .running
        task.startedAt = Date()
        XCTAssertEqual(task.status, .running)
        XCTAssertFalse(task.isTerminal)

        // Complete
        task.status = .completed
        task.finishedAt = Date()
        XCTAssertEqual(task.status, .completed)
        XCTAssertTrue(task.isTerminal)
    }

    func testSubTaskTerminalStates() {
        let completed = SubTask(agentType: "coder", goal: "g", successCriteria: "c", status: .completed)
        XCTAssertTrue(completed.isTerminal)

        let failed = SubTask(agentType: "coder", goal: "g", successCriteria: "c", status: .failed)
        XCTAssertTrue(failed.isTerminal)

        let cancelled = SubTask(agentType: "coder", goal: "g", successCriteria: "c", status: .cancelled)
        XCTAssertTrue(cancelled.isTerminal)

        let pending = SubTask(agentType: "coder", goal: "g", successCriteria: "c", status: .pending)
        XCTAssertFalse(pending.isTerminal)

        let assigned = SubTask(agentType: "coder", goal: "g", successCriteria: "c", status: .assigned)
        XCTAssertFalse(assigned.isTerminal)

        let running = SubTask(agentType: "coder", goal: "g", successCriteria: "c", status: .running)
        XCTAssertFalse(running.isTerminal)
    }

    func testSubTaskDuration() {
        let start = Date()
        let end = start.addingTimeInterval(5.5)
        let task = SubTask(
            agentType: "coder", goal: "g", successCriteria: "c",
            startedAt: start, finishedAt: end
        )
        XCTAssertEqual(task.durationSeconds!, 5.5, accuracy: 0.01)
    }

    func testSubTaskDurationNilWhenNotFinished() {
        let task = SubTask(agentType: "coder", goal: "g", successCriteria: "c", startedAt: Date())
        XCTAssertNil(task.durationSeconds)
    }

    // MARK: - Conflict Detection

    func testConflictDetectionTwoAgentsSameFile() {
        let merger = ChangeSetMerger()

        var task1 = SubTask(agentType: "coder", goal: "fix auth", successCriteria: "ok", status: .completed)
        task1.result = SubTaskResult(
            summary: "Fixed auth",
            filesModified: ["Sources/Auth.swift", "Sources/Login.swift"]
        )

        var task2 = SubTask(agentType: "shell", goal: "generate config", successCriteria: "ok", status: .completed)
        task2.result = SubTaskResult(
            summary: "Generated config",
            filesModified: ["Sources/Auth.swift", "Tests/AuthTests.swift"]
        )

        let merged = merger.merge(subtasks: [task1, task2])
        XCTAssertEqual(merged.conflicts.count, 1)
        XCTAssertEqual(merged.conflicts[0].path, "Sources/Auth.swift")
        XCTAssertEqual(merged.conflicts[0].agentA, "coder")
        XCTAssertEqual(merged.conflicts[0].agentB, "shell")
        XCTAssertFalse(merged.isClean)
    }

    func testNoConflictWhenDifferentFiles() {
        let merger = ChangeSetMerger()

        var task1 = SubTask(agentType: "coder", goal: "fix auth", successCriteria: "ok", status: .completed)
        task1.result = SubTaskResult(
            summary: "Fixed auth",
            filesModified: ["Sources/Auth.swift"]
        )

        var task2 = SubTask(agentType: "shell", goal: "run tests", successCriteria: "ok", status: .completed)
        task2.result = SubTaskResult(
            summary: "Tests pass",
            filesModified: ["Tests/Output.log"]
        )

        let merged = merger.merge(subtasks: [task1, task2])
        XCTAssertTrue(merged.conflicts.isEmpty)
        XCTAssertTrue(merged.isClean)
        XCTAssertEqual(merged.filesModified.count, 2)
        XCTAssertTrue(merged.filesModified.contains("Sources/Auth.swift"))
        XCTAssertTrue(merged.filesModified.contains("Tests/Output.log"))
    }

    func testNoConflictSameAgentSameFile() {
        let merger = ChangeSetMerger()

        var task1 = SubTask(agentType: "coder", goal: "fix part 1", successCriteria: "ok", status: .completed)
        task1.result = SubTaskResult(
            summary: "Fixed part 1",
            filesModified: ["Sources/Main.swift"]
        )

        var task2 = SubTask(agentType: "coder", goal: "fix part 2", successCriteria: "ok", status: .completed)
        task2.result = SubTaskResult(
            summary: "Fixed part 2",
            filesModified: ["Sources/Main.swift"]
        )

        let merged = merger.merge(subtasks: [task1, task2])
        // Same agent type touching the same file is not a conflict
        XCTAssertTrue(merged.conflicts.isEmpty)
        XCTAssertTrue(merged.isClean)
    }

    func testConflictDifferentAgentTypes() {
        let merger = ChangeSetMerger()

        var task1 = SubTask(agentType: "coder", goal: "implement feature", successCriteria: "ok", status: .completed)
        task1.result = SubTaskResult(
            summary: "Done",
            filesModified: ["Sources/Config.swift"]
        )

        var task2 = SubTask(agentType: "shell", goal: "generate config", successCriteria: "ok", status: .completed)
        task2.result = SubTaskResult(
            summary: "Done",
            filesModified: ["Sources/Config.swift"]
        )

        let merged = merger.merge(subtasks: [task1, task2])
        XCTAssertEqual(merged.conflicts.count, 1)
        XCTAssertFalse(merged.isClean)
    }

    // MARK: - Message Creation and Routing

    func testMessageCreation() {
        let msg = AgentMessage(
            from: "orchestrator",
            to: "coder",
            kind: .taskDelegation,
            content: "Fix the auth bug"
        )
        XCTAssertEqual(msg.from, "orchestrator")
        XCTAssertEqual(msg.to, "coder")
        XCTAssertEqual(msg.kind, .taskDelegation)
        XCTAssertEqual(msg.content, "Fix the auth bug")
        XCTAssertFalse(msg.id.isEmpty)
        XCTAssertTrue(msg.metadata.isEmpty)
    }

    func testMessageWithMetadata() {
        let msg = AgentMessage(
            from: "coder",
            to: "orchestrator",
            kind: .taskResult,
            content: "Done",
            metadata: ["files_modified": "3", "status": "success"]
        )
        XCTAssertEqual(msg.metadata["files_modified"], "3")
        XCTAssertEqual(msg.metadata["status"], "success")
    }

    func testMessageKindValues() {
        let kinds: [MessageKind] = MessageKind.allCases
        XCTAssertEqual(kinds.count, 6)
        XCTAssertTrue(kinds.contains(.taskDelegation))
        XCTAssertTrue(kinds.contains(.taskResult))
        XCTAssertTrue(kinds.contains(.contextShare))
        XCTAssertTrue(kinds.contains(.progressUpdate))
        XCTAssertTrue(kinds.contains(.conflictReport))
        XCTAssertTrue(kinds.contains(.question))
    }

    func testMessageCodable() throws {
        let msg = AgentMessage(
            id: "msg_123",
            from: "orchestrator",
            to: "coder",
            kind: .taskDelegation,
            content: "Fix bug",
            timestamp: Date(timeIntervalSince1970: 1748275200),
            metadata: ["priority": "high"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(msg)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentMessage.self, from: data)

        XCTAssertEqual(decoded.id, "msg_123")
        XCTAssertEqual(decoded.from, "orchestrator")
        XCTAssertEqual(decoded.to, "coder")
        XCTAssertEqual(decoded.kind, .taskDelegation)
        XCTAssertEqual(decoded.content, "Fix bug")
        XCTAssertEqual(decoded.metadata["priority"], "high")
    }

    // MARK: - Orchestrator Decomposition Parsing

    func testOrchestratorParseSubTasks() {
        let orchestrator = Orchestrator()
        let text = """
        1. [architect] Analyze the codebase structure | Architecture summary produced
        2. [coder] Implement authentication module | Code compiles and tests pass
        3. [reviewer] Review changes for correctness | No critical issues found
        4. [verifier] Run the full test suite | All tests pass
        """

        let tasks = orchestrator.parseSubTasks(from: text)
        XCTAssertEqual(tasks.count, 4)

        XCTAssertEqual(tasks[0].agentType, "architect")
        XCTAssertEqual(tasks[0].goal, "Analyze the codebase structure")
        XCTAssertEqual(tasks[0].successCriteria, "Architecture summary produced")

        XCTAssertEqual(tasks[1].agentType, "coder")
        XCTAssertEqual(tasks[1].goal, "Implement authentication module")

        XCTAssertEqual(tasks[2].agentType, "reviewer")
        XCTAssertEqual(tasks[3].agentType, "verifier")
    }

    func testOrchestratorParseSubTasksNoAgentType() {
        let orchestrator = Orchestrator()
        let text = """
        1. Read the test file | File contents retrieved
        2. Fix the failing assertion | Test passes
        """

        let tasks = orchestrator.parseSubTasks(from: text)
        XCTAssertEqual(tasks.count, 2)
        // Default agent type should be "coder"
        XCTAssertEqual(tasks[0].agentType, "coder")
        XCTAssertEqual(tasks[1].agentType, "coder")
    }

    func testOrchestratorParseSubTasksEmpty() {
        let orchestrator = Orchestrator()
        let tasks = orchestrator.parseSubTasks(from: "")
        XCTAssertTrue(tasks.isEmpty)
    }

    func testOrchestratorParseSubTasksMixed() {
        let orchestrator = Orchestrator()
        let text = """
        Some preamble text.

        1. [research] Investigate the current auth patterns | Patterns documented
        2. Write the new auth handler | Code compiles
        3. [verifier] Run tests | All pass

        Some trailing text.
        """

        let tasks = orchestrator.parseSubTasks(from: text)
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].agentType, "research")
        XCTAssertEqual(tasks[1].agentType, "coder") // default
        XCTAssertEqual(tasks[2].agentType, "verifier")
    }

    // MARK: - Merge Results Aggregation

    func testMergeResultsAggregation() {
        let merger = ChangeSetMerger()

        var task1 = SubTask(agentType: "coder", goal: "fix auth", successCriteria: "ok", status: .completed)
        task1.result = SubTaskResult(
            summary: "Fixed auth",
            filesModified: ["Sources/Auth.swift", "Sources/Login.swift"],
            commandsRun: ["swift build"]
        )

        var task2 = SubTask(agentType: "verifier", goal: "verify", successCriteria: "ok", status: .completed)
        task2.result = SubTaskResult(
            summary: "Tests pass",
            filesModified: [],
            commandsRun: ["swift test"]
        )

        var task3 = SubTask(agentType: "reviewer", goal: "review", successCriteria: "ok", status: .failed)
        task3.result = SubTaskResult(summary: "Found issues")

        let merged = merger.merge(subtasks: [task1, task2, task3])

        XCTAssertEqual(merged.subtasks.count, 3)
        XCTAssertEqual(merged.completedCount, 2)
        XCTAssertEqual(merged.failedCount, 1)
        XCTAssertEqual(merged.filesModified.count, 2)
        XCTAssertTrue(merged.filesModified.contains("Sources/Auth.swift"))
        XCTAssertTrue(merged.filesModified.contains("Sources/Login.swift"))
        XCTAssertTrue(merged.isClean)
        XCTAssertTrue(merged.summary.contains("2/3"))
    }

    func testMergeResultsNoSubTasks() {
        let merger = ChangeSetMerger()
        let merged = merger.merge(subtasks: [])

        XCTAssertTrue(merged.subtasks.isEmpty)
        XCTAssertTrue(merged.filesModified.isEmpty)
        XCTAssertTrue(merged.conflicts.isEmpty)
        XCTAssertTrue(merged.isClean)
    }

    func testMergeResultsWithConflictsSummary() {
        let merger = ChangeSetMerger()

        var task1 = SubTask(agentType: "coder", goal: "fix", successCriteria: "ok", status: .completed)
        task1.result = SubTaskResult(
            summary: "Done",
            filesModified: ["Sources/Config.swift"]
        )

        var task2 = SubTask(agentType: "shell", goal: "gen", successCriteria: "ok", status: .completed)
        task2.result = SubTaskResult(
            summary: "Done",
            filesModified: ["Sources/Config.swift", "Sources/Extra.swift"]
        )

        let merged = merger.merge(subtasks: [task1, task2])
        XCTAssertFalse(merged.isClean)
        XCTAssertTrue(merged.summary.contains("conflict"))
    }

    // MARK: - SubTask Encoding/Decoding

    func testSubTaskStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in SubTaskStatus.allCases {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(SubTaskStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testSubTaskResultCreation() {
        let result = SubTaskResult(
            summary: "Fixed 3 bugs",
            filesModified: ["a.swift", "b.swift"],
            commandsRun: ["swift build", "swift test"],
            observations: [
                Observation(summary: "build ok"),
                Observation(summary: "tests pass"),
            ]
        )
        XCTAssertEqual(result.summary, "Fixed 3 bugs")
        XCTAssertEqual(result.filesModified.count, 2)
        XCTAssertEqual(result.commandsRun.count, 2)
        XCTAssertEqual(result.observations.count, 2)
    }

    func testSubTaskResultDefaults() {
        let result = SubTaskResult(summary: "done")
        XCTAssertTrue(result.filesModified.isEmpty)
        XCTAssertTrue(result.commandsRun.isEmpty)
        XCTAssertTrue(result.observations.isEmpty)
    }

    // MARK: - Agent Registry

    func testSubAgentRegistryContainsAllAgents() {
        let agents = SubAgentRegistry.allAgents
        XCTAssertEqual(agents.count, 6)

        let ids = Set(agents.map { $0.id })
        XCTAssertTrue(ids.contains("architect"))
        XCTAssertTrue(ids.contains("coder"))
        XCTAssertTrue(ids.contains("shell"))
        XCTAssertTrue(ids.contains("reviewer"))
        XCTAssertTrue(ids.contains("research"))
        XCTAssertTrue(ids.contains("verifier"))
    }

    func testSubAgentRegistryFind() {
        let coder = SubAgentRegistry.find(id: "coder")
        XCTAssertNotNil(coder)
        XCTAssertEqual(coder?.id, "coder")

        let unknown = SubAgentRegistry.find(id: "nonexistent")
        XCTAssertNil(unknown)
    }

    // MARK: - Agent Properties

    func testAllAgentsHaveDisplayNames() {
        for agent in SubAgentRegistry.allAgents {
            XCTAssertFalse(agent.displayName.isEmpty, "Agent '\(agent.id)' should have a display name")
        }
    }

    func testAllAgentsHaveDescriptions() {
        for agent in SubAgentRegistry.allAgents {
            XCTAssertFalse(agent.description.isEmpty, "Agent '\(agent.id)' should have a description")
        }
    }

    func testAllAgentsHaveSystemPrompts() {
        for agent in SubAgentRegistry.allAgents {
            XCTAssertFalse(agent.systemPrompt.isEmpty, "Agent '\(agent.id)' should have a system prompt")
        }
    }

    func testAllAgentsHavePositiveMaxSteps() {
        for agent in SubAgentRegistry.allAgents {
            XCTAssertGreaterThan(agent.maxSteps, 0, "Agent '\(agent.id)' should have positive max steps")
        }
    }

    func testAllAgentsHaveAllowedTools() {
        for agent in SubAgentRegistry.allAgents {
            XCTAssertFalse(agent.allowedTools.isEmpty, "Agent '\(agent.id)' should have at least one allowed tool")
        }
    }

    // MARK: - OrchestratorEvent

    func testOrchestratorEventDecomposed() {
        let tasks = [
            SubTask(agentType: "coder", goal: "fix", successCriteria: "ok"),
            SubTask(agentType: "verifier", goal: "test", successCriteria: "ok"),
        ]
        let event = OrchestratorEvent.decomposed(subtasks: tasks)
        if case .decomposed(let subtasks) = event {
            XCTAssertEqual(subtasks.count, 2)
        } else {
            XCTFail("Expected decomposed event")
        }
    }

    func testOrchestratorEventConflict() {
        let conflict = FileConflict(
            path: "Sources/Main.swift",
            agentA: "coder",
            agentB: "shell",
            description: "Both modified Main.swift"
        )
        let event = OrchestratorEvent.conflictDetected(conflict)
        if case .conflictDetected(let c) = event {
            XCTAssertEqual(c.path, "Sources/Main.swift")
            XCTAssertEqual(c.agentA, "coder")
            XCTAssertEqual(c.agentB, "shell")
        } else {
            XCTFail("Expected conflictDetected event")
        }
    }

    // MARK: - FileConflict

    func testFileConflictCreation() {
        let conflict = FileConflict(
            path: "Sources/Auth.swift",
            agentA: "coder",
            agentB: "shell",
            description: "Both agents modified the authentication module"
        )
        XCTAssertEqual(conflict.path, "Sources/Auth.swift")
        XCTAssertEqual(conflict.agentA, "coder")
        XCTAssertEqual(conflict.agentB, "shell")
        XCTAssertTrue(conflict.description.contains("authentication"))
    }

    // MARK: - MergedResult

    func testMergedResultIsClean() {
        let clean = MergedResult(subtasks: [], filesModified: [], conflicts: [], summary: "ok")
        XCTAssertTrue(clean.isClean)

        let dirty = MergedResult(
            subtasks: [],
            filesModified: [],
            conflicts: [FileConflict(path: "x", agentA: "a", agentB: "b", description: "conflict")],
            summary: "conflict"
        )
        XCTAssertFalse(dirty.isClean)
    }

    func testMergedResultCounts() {
        var t1 = SubTask(agentType: "coder", goal: "g1", successCriteria: "c1", status: .completed)
        t1.result = SubTaskResult(summary: "ok")
        var t2 = SubTask(agentType: "coder", goal: "g2", successCriteria: "c2", status: .failed)
        t2.result = SubTaskResult(summary: "err")
        var t3 = SubTask(agentType: "coder", goal: "g3", successCriteria: "c3", status: .completed)
        t3.result = SubTaskResult(summary: "ok")

        let merged = MergedResult(
            subtasks: [t1, t2, t3],
            filesModified: [],
            conflicts: [],
            summary: "mixed"
        )
        XCTAssertEqual(merged.completedCount, 2)
        XCTAssertEqual(merged.failedCount, 1)
    }

    // MARK: - Agent Prompts

    func testOrchestratorPromptExists() {
        XCTAssertFalse(AgentPrompts.orchestratorSystem.isEmpty)
        XCTAssertTrue(AgentPrompts.orchestratorSystem.contains("Orchestrator"))
    }

    func testArchitectPromptExists() {
        XCTAssertFalse(AgentPrompts.architectSystem.isEmpty)
        XCTAssertTrue(AgentPrompts.architectSystem.contains("Architect"))
    }

    func testCoderPromptExists() {
        XCTAssertFalse(AgentPrompts.coderSystem.isEmpty)
        XCTAssertTrue(AgentPrompts.coderSystem.contains("Coder"))
    }

    func testShellPromptExists() {
        XCTAssertFalse(AgentPrompts.shellSystem.isEmpty)
        XCTAssertTrue(AgentPrompts.shellSystem.contains("Shell"))
    }

    func testReviewerPromptExists() {
        XCTAssertFalse(AgentPrompts.reviewerSystem.isEmpty)
        XCTAssertTrue(AgentPrompts.reviewerSystem.contains("Reviewer"))
    }

    func testResearchPromptExists() {
        XCTAssertFalse(AgentPrompts.researchSystem.isEmpty)
        XCTAssertTrue(AgentPrompts.researchSystem.contains("Research"))
    }

    func testVerifierAgentPromptExists() {
        XCTAssertFalse(AgentPrompts.verifierAgentSystem.isEmpty)
        XCTAssertTrue(AgentPrompts.verifierAgentSystem.contains("Verifier"))
    }
}
