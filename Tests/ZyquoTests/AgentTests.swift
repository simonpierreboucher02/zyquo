import XCTest
@testable import Zyquo

final class AgentTests: XCTestCase {

    // MARK: - SessionID Tests

    func testSessionIDFormat() {
        let id = SessionID()
        // Format: "zq_<yyyymmdd>_<hex>"
        XCTAssertTrue(id.value.hasPrefix("zq_"), "SessionID should start with 'zq_'")
        let parts = id.value.split(separator: "_")
        XCTAssertEqual(parts.count, 3, "SessionID should have 3 parts separated by underscores")
        // Second part should be 8-digit date
        XCTAssertEqual(parts[1].count, 8, "Date part should be 8 digits")
        XCTAssertTrue(parts[1].allSatisfy(\.isNumber), "Date part should be all digits")
    }

    func testSessionIDCustomValue() {
        let id = SessionID(value: "zq_20260526_abc1")
        XCTAssertEqual(id.value, "zq_20260526_abc1")
        XCTAssertEqual(id.description, "zq_20260526_abc1")
    }

    func testSessionIDHashable() {
        let id1 = SessionID(value: "zq_20260526_abc1")
        let id2 = SessionID(value: "zq_20260526_abc1")
        let id3 = SessionID(value: "zq_20260526_def2")
        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)

        var set = Set<SessionID>()
        set.insert(id1)
        set.insert(id2)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - StepID Tests

    func testStepIDFormat() {
        let id = StepID()
        XCTAssertTrue(id.value.hasPrefix("zs_"), "StepID should start with 'zs_'")
    }

    func testStepIDHashable() {
        let id1 = StepID(value: "zs_abc")
        let id2 = StepID(value: "zs_abc")
        XCTAssertEqual(id1, id2)
    }

    // MARK: - AgentState Tests

    func testAgentStateInitialStatus() {
        let state = AgentState(intent: "fix tests")
        XCTAssertEqual(state.status, .planning)
        XCTAssertEqual(state.intent, "fix tests")
        XCTAssertTrue(state.steps.isEmpty)
        XCTAssertTrue(state.plan.steps.isEmpty)
        XCTAssertFalse(state.plan.isComplete)
    }

    func testAgentStateConsecutiveFailures() {
        var state = AgentState(intent: "test")

        // No steps -> 0 failures
        XCTAssertEqual(state.consecutiveFailures, 0)

        // Add a successful step
        var step1 = AgentStep(index: 0, goal: "g1", successCriteria: "c1")
        step1.observation = Observation(summary: "ok", isError: false)
        state.steps.append(step1)
        XCTAssertEqual(state.consecutiveFailures, 0)

        // Add two failed steps
        var step2 = AgentStep(index: 1, goal: "g2", successCriteria: "c2")
        step2.observation = Observation(summary: "err", isError: true)
        state.steps.append(step2)
        XCTAssertEqual(state.consecutiveFailures, 1)

        var step3 = AgentStep(index: 2, goal: "g3", successCriteria: "c3")
        step3.observation = Observation(summary: "err", isError: true)
        state.steps.append(step3)
        XCTAssertEqual(state.consecutiveFailures, 2)

        // Add a success -> resets
        var step4 = AgentStep(index: 3, goal: "g4", successCriteria: "c4")
        step4.observation = Observation(summary: "ok", isError: false)
        state.steps.append(step4)
        XCTAssertEqual(state.consecutiveFailures, 0)
    }

    func testAgentStateConsecutiveUnclear() {
        var state = AgentState(intent: "test")

        var step1 = AgentStep(index: 0, goal: "g1", successCriteria: "c1")
        step1.verdict = .unclear
        state.steps.append(step1)
        XCTAssertEqual(state.consecutiveUnclearVerdicts, 1)

        var step2 = AgentStep(index: 1, goal: "g2", successCriteria: "c2")
        step2.verdict = .unclear
        state.steps.append(step2)
        XCTAssertEqual(state.consecutiveUnclearVerdicts, 2)

        var step3 = AgentStep(index: 2, goal: "g3", successCriteria: "c3")
        step3.verdict = .pass
        state.steps.append(step3)
        XCTAssertEqual(state.consecutiveUnclearVerdicts, 0)
    }

    // MARK: - Plan Tests

    func testPlanCreation() {
        let steps = [
            PlanStep(goal: "Read file", successCriteria: "File contents retrieved"),
            PlanStep(goal: "Fix bug", successCriteria: "Code compiles"),
        ]
        let plan = Plan(steps: steps, isComplete: false)
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertFalse(plan.isComplete)
    }

    func testPlanEmpty() {
        let plan = Plan.empty
        XCTAssertTrue(plan.steps.isEmpty)
        XCTAssertTrue(plan.isComplete)
    }

    func testPlanStepIteration() {
        let plan = Plan(steps: [
            PlanStep(goal: "A", successCriteria: "a"),
            PlanStep(goal: "B", successCriteria: "b"),
            PlanStep(goal: "C", successCriteria: "c"),
        ])
        var goals: [String] = []
        for step in plan.steps {
            goals.append(step.goal)
        }
        XCTAssertEqual(goals, ["A", "B", "C"])
    }

    // MARK: - StopConditions Tests

    func testStopConditionsMaxSteps() {
        var state = AgentState(intent: "test")
        let config = AgentConfig(
            flags: CommandFlags(maxSteps: 3),
            env: [:],
            workspace: [:],
            user: [:]
        )

        // Under limit
        state.steps = [
            AgentStep(index: 0, goal: "g1", successCriteria: "c1"),
            AgentStep(index: 1, goal: "g2", successCriteria: "c2"),
        ]
        XCTAssertNil(StopConditions.evaluate(state: state, config: config))

        // At limit
        state.steps.append(AgentStep(index: 2, goal: "g3", successCriteria: "c3"))
        let reason = StopConditions.evaluate(state: state, config: config)
        XCTAssertNotNil(reason)
        if case .maxStepsReached(let limit) = reason {
            XCTAssertEqual(limit, 3)
        } else {
            XCTFail("Expected maxStepsReached, got \(String(describing: reason))")
        }
    }

    func testStopConditionsMaxCost() {
        var state = AgentState(intent: "test")
        state.cost = SessionCost()
        // Simulate recording cost
        let model = ModelCatalog.claudeSonnet4_6
        let usage = TokenUsage(inputTokens: 100_000, outputTokens: 50_000)
        state.cost.record(usage: usage, model: model)

        let config = AgentConfig(
            flags: CommandFlags(maxCost: 0.01),
            env: [:],
            workspace: [:],
            user: [:]
        )

        let reason = StopConditions.evaluate(state: state, config: config)
        XCTAssertNotNil(reason)
        if case .maxCostReached = reason {
            // expected
        } else {
            XCTFail("Expected maxCostReached, got \(String(describing: reason))")
        }
    }

    func testStopConditionsConsecutiveFailures() {
        var state = AgentState(intent: "test")
        let config = AgentConfig(
            flags: CommandFlags(),
            env: [:],
            workspace: [:],
            user: [:]
        )

        for i in 0..<3 {
            var step = AgentStep(index: i, goal: "g\(i)", successCriteria: "c\(i)")
            step.observation = Observation(summary: "err", isError: true)
            state.steps.append(step)
        }

        let reason = StopConditions.evaluate(state: state, config: config)
        XCTAssertNotNil(reason)
        if case .consecutiveFailures(let count) = reason {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected consecutiveFailures, got \(String(describing: reason))")
        }
    }

    func testStopConditionsLoopDetection() {
        var state = AgentState(intent: "test")
        let config = AgentConfig(
            flags: CommandFlags(),
            env: [:],
            workspace: [:],
            user: [:]
        )

        // Create 3 steps with the exact same tool call
        let tc = ToolCall(toolName: "shell.run", input: ["command": .string("echo hello")], id: "t1")
        for i in 0..<3 {
            var step = AgentStep(index: i, goal: "g\(i)", successCriteria: "c\(i)")
            step.toolCall = tc
            step.observation = Observation(summary: "ok", isError: false)
            state.steps.append(step)
        }

        let reason = StopConditions.evaluate(state: state, config: config)
        XCTAssertNotNil(reason)
        if case .loopDetected(_, let count) = reason {
            XCTAssertGreaterThanOrEqual(count, 3)
        } else {
            XCTFail("Expected loopDetected, got \(String(describing: reason))")
        }
    }

    func testStopConditionsPlanCompleted() {
        var state = AgentState(intent: "test")
        state.plan = Plan(steps: [
            PlanStep(goal: "g1", successCriteria: "c1"),
        ], isComplete: true)

        var step = AgentStep(index: 0, goal: "g1", successCriteria: "c1")
        step.finishedAt = Date()
        state.steps.append(step)

        let config = AgentConfig(
            flags: CommandFlags(),
            env: [:],
            workspace: [:],
            user: [:]
        )

        let reason = StopConditions.evaluate(state: state, config: config)
        XCTAssertNotNil(reason)
        if case .planCompleted = reason {
            // expected
        } else {
            XCTFail("Expected planCompleted, got \(String(describing: reason))")
        }
    }

    func testStopConditionsNoStop() {
        let state = AgentState(intent: "test")
        let config = AgentConfig(
            flags: CommandFlags(),
            env: [:],
            workspace: [:],
            user: [:]
        )

        let reason = StopConditions.evaluate(state: state, config: config)
        XCTAssertNil(reason, "Should not stop with no steps and default config")
    }

    func testStopReasonIsHard() {
        XCTAssertTrue(AgentStopReason.maxStepsReached(limit: 40).isHard)
        XCTAssertTrue(AgentStopReason.maxCostReached(cost: 5.0, limit: 5.0).isHard)
        XCTAssertTrue(AgentStopReason.userCancellation.isHard)
        XCTAssertTrue(AgentStopReason.consecutiveFailures(count: 3).isHard)
        XCTAssertFalse(AgentStopReason.planCompleted.isHard)
        XCTAssertFalse(AgentStopReason.loopDetected(toolCallHash: "abc", count: 3).isHard)
        XCTAssertFalse(AgentStopReason.consecutiveUnclearVerdicts(count: 5).isHard)
    }

    // MARK: - TokenBudget Tests

    func testTokenBudgetCalculations() {
        let budget = TokenBudget(
            modelContextWindow: 200_000,
            tokensUsed: 0,
            reserveForOutput: 8_192
        )
        XCTAssertEqual(budget.remaining, 200_000 - 8_192)
        XCTAssertEqual(budget.utilizationPercent, 0.0, accuracy: 0.001)
        XCTAssertFalse(budget.needsCompaction)
    }

    func testTokenBudgetUsage() {
        var budget = TokenBudget(
            modelContextWindow: 200_000,
            tokensUsed: 0,
            reserveForOutput: 8_192
        )
        budget.record(tokens: 50_000)
        XCTAssertEqual(budget.tokensUsed, 50_000)
        XCTAssertEqual(budget.remaining, 200_000 - 50_000 - 8_192)
    }

    func testTokenBudgetCompactionTrigger() {
        // 70% of (200_000 - 8_192) = ~134_265
        var budget = TokenBudget(
            modelContextWindow: 200_000,
            tokensUsed: 0,
            reserveForOutput: 8_192
        )

        budget.record(tokens: 134_000)
        XCTAssertFalse(budget.needsCompaction, "Just under 70% should not trigger compaction")

        budget.record(tokens: 2000)
        XCTAssertTrue(budget.needsCompaction, "Over 70% should trigger compaction")
    }

    func testTokenBudgetReset() {
        var budget = TokenBudget(
            modelContextWindow: 200_000,
            tokensUsed: 100_000,
            reserveForOutput: 8_192
        )
        budget.reset(to: 5000)
        XCTAssertEqual(budget.tokensUsed, 5000)
    }

    func testTokenBudgetZeroWindow() {
        let budget = TokenBudget(modelContextWindow: 0, tokensUsed: 0, reserveForOutput: 0)
        XCTAssertEqual(budget.remaining, 0)
        XCTAssertEqual(budget.utilizationPercent, 0)
    }

    // MARK: - Summarizer Tests

    func testSummarizerProducesCorrectSummary() {
        var state = AgentState(
            sessionId: SessionID(value: "zq_20260526_test"),
            intent: "fix the tests",
            status: .done,
            startedAt: Date().addingTimeInterval(-60) // 1 minute ago
        )
        state.plan = Plan(steps: [
            PlanStep(goal: "Read test file", successCriteria: "Contents retrieved"),
            PlanStep(goal: "Fix bug", successCriteria: "Code compiles"),
            PlanStep(goal: "Run tests", successCriteria: "Tests pass"),
        ])

        // Step 1: file.read
        var step1 = AgentStep(index: 0, goal: "Read test file", successCriteria: "Contents retrieved")
        step1.toolCall = ToolCall(toolName: "file.read", input: ["path": .string("test.swift")], id: "t1")
        step1.observation = Observation(summary: "ok", isError: false)
        step1.verdict = .pass
        step1.finishedAt = Date()
        state.steps.append(step1)

        // Step 2: shell.run
        var step2 = AgentStep(index: 1, goal: "Fix bug", successCriteria: "Code compiles")
        step2.toolCall = ToolCall(toolName: "shell.run", input: ["command": .string("swift build")], id: "t2")
        step2.observation = Observation(summary: "ok", isError: false)
        step2.verdict = .pass
        step2.finishedAt = Date()
        state.steps.append(step2)

        // Step 3: shell.run
        var step3 = AgentStep(index: 2, goal: "Run tests", successCriteria: "Tests pass")
        step3.toolCall = ToolCall(toolName: "shell.run", input: ["command": .string("swift test")], id: "t3")
        step3.observation = Observation(summary: "ok", isError: false)
        step3.verdict = .pass
        step3.finishedAt = Date()
        state.steps.append(step3)

        let summarizer = Summarizer()
        let summary = summarizer.summarize(state: state)

        XCTAssertEqual(summary.intent, "fix the tests")
        XCTAssertEqual(summary.stepsCompleted, 3)
        XCTAssertEqual(summary.stepsTotal, 3)
        XCTAssertEqual(summary.commandsRun.count, 2)
        XCTAssertTrue(summary.commandsRun.contains("swift build"))
        XCTAssertTrue(summary.commandsRun.contains("swift test"))
        XCTAssertEqual(summary.outcome, "Completed successfully")
        XCTAssertGreaterThan(summary.duration, 0)
    }

    func testSummarizerWithFailedSteps() {
        var state = AgentState(
            intent: "deploy",
            status: .done
        )
        state.plan = Plan(steps: [
            PlanStep(goal: "Deploy", successCriteria: "Success"),
        ])

        var step1 = AgentStep(index: 0, goal: "Deploy", successCriteria: "Success")
        step1.toolCall = ToolCall(toolName: "shell.run", input: ["command": .string("deploy")], id: "t1")
        step1.observation = Observation(summary: "failed", isError: true)
        step1.verdict = .fail
        step1.finishedAt = Date()
        state.steps.append(step1)

        let summarizer = Summarizer()
        let summary = summarizer.summarize(state: state)
        XCTAssertTrue(summary.outcome.contains("failed"))
    }

    func testSummarizerCancelledSession() {
        var state = AgentState(intent: "test", status: .cancelled)
        state.plan = Plan(steps: [PlanStep(goal: "g", successCriteria: "c")])

        let summarizer = Summarizer()
        let summary = summarizer.summarize(state: state)
        XCTAssertEqual(summary.outcome, "Cancelled by user")
    }

    // MARK: - ToolCall Tests

    func testToolCallCreation() {
        let tc = ToolCall(
            toolName: "shell.run",
            input: ["command": .string("ls -la")],
            id: "tool_123"
        )
        XCTAssertEqual(tc.toolName, "shell.run")
        XCTAssertEqual(tc.id, "tool_123")
        XCTAssertEqual(tc.input["command"]?.stringValue, "ls -la")
    }

    func testToolCallContentHash() {
        let tc1 = ToolCall(toolName: "shell.run", input: ["command": .string("ls")], id: "a")
        let tc2 = ToolCall(toolName: "shell.run", input: ["command": .string("ls")], id: "b")
        let tc3 = ToolCall(toolName: "shell.run", input: ["command": .string("pwd")], id: "c")

        // Same tool + same input = same hash (regardless of id)
        XCTAssertEqual(tc1.contentHash, tc2.contentHash)
        // Different input = different hash
        XCTAssertNotEqual(tc1.contentHash, tc3.contentHash)
    }

    // MARK: - Observation Tests

    func testObservationCreation() {
        let obs = Observation(
            summary: "Command succeeded",
            payload: .object(["exit_code": .number(0)]),
            durationMs: 150,
            tokenHint: 42,
            isError: false
        )
        XCTAssertEqual(obs.summary, "Command succeeded")
        XCTAssertEqual(obs.durationMs, 150)
        XCTAssertEqual(obs.tokenHint, 42)
        XCTAssertFalse(obs.isError)
    }

    func testObservationDefaults() {
        let obs = Observation(summary: "done")
        XCTAssertNil(obs.payload)
        XCTAssertEqual(obs.durationMs, 0)
        XCTAssertEqual(obs.tokenHint, 0)
        XCTAssertFalse(obs.isError)
    }

    // MARK: - AgentStep Tests

    func testAgentStepDuration() {
        var step = AgentStep(index: 0, goal: "test", successCriteria: "ok")
        XCTAssertNil(step.durationMs)

        let start = Date()
        step.startedAt = start
        XCTAssertNil(step.durationMs, "Should be nil without finishedAt")

        step.finishedAt = start.addingTimeInterval(1.5) // 1500ms
        XCTAssertEqual(step.durationMs, 1500)
    }

    func testAgentStepIsComplete() {
        var step = AgentStep(index: 0, goal: "test", successCriteria: "ok")
        XCTAssertFalse(step.isComplete)

        step.finishedAt = Date()
        XCTAssertTrue(step.isComplete)
    }

    // MARK: - AgentStatus Tests

    func testAgentStatusValues() {
        let all: [AgentStatus] = [.planning, .executing, .verifying, .blocked, .done, .cancelled, .failed]
        XCTAssertEqual(all.count, 7)
        XCTAssertEqual(AgentStatus.planning.rawValue, "planning")
        XCTAssertEqual(AgentStatus.executing.rawValue, "executing")
        XCTAssertEqual(AgentStatus.done.rawValue, "done")
    }

    // MARK: - Verdict Tests

    func testVerdictValues() {
        XCTAssertEqual(Verdict.pass.rawValue, "pass")
        XCTAssertEqual(Verdict.fail.rawValue, "fail")
        XCTAssertEqual(Verdict.unclear.rawValue, "unclear")
    }

    // MARK: - Planner Parsing Tests

    func testPlannerParsePlan() {
        let planner = Planner()
        let text = """
        1. Read the test file to understand the failure | File contents are retrieved
        2. Identify the root cause of the test failure | Root cause documented
        3. Patch the source code | Code compiles without errors
        4. Run the tests | All tests pass with exit code 0
        """

        let plan = planner.parsePlan(from: text)
        XCTAssertEqual(plan.steps.count, 4)
        XCTAssertEqual(plan.steps[0].goal, "Read the test file to understand the failure")
        XCTAssertEqual(plan.steps[0].successCriteria, "File contents are retrieved")
        XCTAssertEqual(plan.steps[3].goal, "Run the tests")
        XCTAssertFalse(plan.isComplete)
    }

    func testPlannerParsePlanNoCriteria() {
        let planner = Planner()
        let text = """
        1. Read the test file
        2. Fix the bug
        """

        let plan = planner.parsePlan(from: text)
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps[0].successCriteria, "Step completes without errors")
    }

    func testPlannerParsePlanEmptyText() {
        let planner = Planner()
        let plan = planner.parsePlan(from: "")
        XCTAssertTrue(plan.steps.isEmpty)
    }

    func testPlannerParsePlanFreeformText() {
        let planner = Planner()
        let plan = planner.parsePlan(from: "I will fix the bug by editing the code")
        XCTAssertEqual(plan.steps.count, 1)
        XCTAssertTrue(plan.steps[0].goal.contains("fix"))
    }

    func testPlannerParseToolInput() {
        let planner = Planner()
        let input = planner.parseToolInput("{\"command\": \"ls -la\", \"cwd\": \"/tmp\"}")
        XCTAssertEqual(input["command"]?.stringValue, "ls -la")
        XCTAssertEqual(input["cwd"]?.stringValue, "/tmp")
    }

    func testPlannerParseToolInputInvalid() {
        let planner = Planner()
        let input = planner.parseToolInput("not json")
        XCTAssertEqual(input["raw_input"]?.stringValue, "not json")
    }

    func testPlannerParseToolInputEmpty() {
        let planner = Planner()
        let input = planner.parseToolInput("")
        XCTAssertTrue(input.isEmpty)
    }

    // MARK: - Verifier Parsing Tests

    func testVerifierParseVerdictPass() {
        let verifier = Verifier()
        XCTAssertEqual(verifier.parseVerdict(from: "verdict: pass\nThe step succeeded."), .pass)
        XCTAssertEqual(verifier.parseVerdict(from: "verdict:pass"), .pass)
    }

    func testVerifierParseVerdictFail() {
        let verifier = Verifier()
        XCTAssertEqual(verifier.parseVerdict(from: "verdict: fail\nThe command exited with error."), .fail)
    }

    func testVerifierParseVerdictUnclear() {
        let verifier = Verifier()
        XCTAssertEqual(verifier.parseVerdict(from: "verdict: unclear\nNot enough information."), .unclear)
    }

    func testVerifierParseVerdictFallback() {
        let verifier = Verifier()
        XCTAssertEqual(verifier.parseVerdict(from: "The tests passed successfully."), .pass)
        XCTAssertEqual(verifier.parseVerdict(from: "The build failed."), .fail)
        XCTAssertEqual(verifier.parseVerdict(from: "Something happened."), .unclear)
    }

    func testVerifierQuickVerify() {
        let verifier = Verifier()

        var step = AgentStep(index: 0, goal: "test", successCriteria: "ok")
        XCTAssertEqual(verifier.quickVerify(step: step), .unclear)

        step.observation = Observation(summary: "done", isError: false)
        XCTAssertEqual(verifier.quickVerify(step: step), .pass)

        step.observation = Observation(summary: "err", isError: true)
        XCTAssertEqual(verifier.quickVerify(step: step), .fail)
    }

    // MARK: - ContextAssembler Tests

    func testContextAssemblerTokenEstimation() {
        let tokens = ContextAssembler.estimateStringTokens("hello world")
        // "hello world" = 11 chars / 4 = 2 tokens (minimum 1)
        XCTAssertEqual(tokens, 2)
    }

    func testContextAssemblerEstimateEmpty() {
        let tokens = ContextAssembler.estimateStringTokens("")
        XCTAssertEqual(tokens, 1, "Empty string should estimate at least 1 token")
    }

    func testContextAssemblerAssembleForPlanning() {
        let assembler = ContextAssembler()
        let budget = TokenBudget(modelContextWindow: 200_000, tokensUsed: 0)

        let (context, updatedBudget) = assembler.assembleForPlanning(
            intent: "fix the tests",
            workspaceSummary: "Swift project with 100 files",
            projectMemory: "Uses XCTest for testing",
            tools: [],
            budget: budget
        )

        XCTAssertFalse(context.systemPrompt.isEmpty)
        XCTAssertFalse(context.messages.isEmpty)
        XCTAssertGreaterThan(context.totalTokenEstimate, 0)
        XCTAssertGreaterThan(updatedBudget.tokensUsed, 0)
    }

    func testContextAssemblerAssembleForExecution() {
        let assembler = ContextAssembler()
        let budget = TokenBudget(modelContextWindow: 200_000, tokensUsed: 0)

        let plan = Plan(steps: [
            PlanStep(goal: "Read file", successCriteria: "ok"),
            PlanStep(goal: "Fix bug", successCriteria: "ok"),
        ])

        let (context, _) = assembler.assembleForExecution(
            intent: "fix tests",
            plan: plan,
            steps: [],
            currentStepIndex: 0,
            workspaceSummary: "project",
            tools: [],
            budget: budget
        )

        XCTAssertFalse(context.systemPrompt.isEmpty)
        XCTAssertGreaterThan(context.messages.count, 0)
    }

    func testContextAssemblerAssembleForVerification() {
        let assembler = ContextAssembler()
        var step = AgentStep(index: 0, goal: "Run tests", successCriteria: "Exit code 0")
        step.observation = Observation(summary: "Tests passed, exit code 0")

        let context = assembler.assembleForVerification(step: step)
        XCTAssertFalse(context.systemPrompt.isEmpty)
        XCTAssertEqual(context.messages.count, 1)
        XCTAssertTrue(context.tools.isEmpty)
    }

    // MARK: - AssembledContext Tests

    func testAssembledContextEmpty() {
        let ctx = AssembledContext.empty
        XCTAssertTrue(ctx.systemPrompt.isEmpty)
        XCTAssertTrue(ctx.messages.isEmpty)
        XCTAssertTrue(ctx.tools.isEmpty)
        XCTAssertEqual(ctx.totalTokenEstimate, 0)
    }

    // MARK: - Loop Detection Tests

    func testLoopDetectionNoLoop() {
        var state = AgentState(intent: "test")

        for i in 0..<3 {
            var step = AgentStep(index: i, goal: "g\(i)", successCriteria: "c\(i)")
            step.toolCall = ToolCall(
                toolName: "shell.run",
                input: ["command": .string("cmd\(i)")],
                id: "t\(i)"
            )
            state.steps.append(step)
        }

        XCTAssertNil(state.detectLoop())
    }

    func testLoopDetectionWithLoop() {
        var state = AgentState(intent: "test")

        let repeatedTC = ToolCall(
            toolName: "shell.run",
            input: ["command": .string("same_command")],
            id: "any"
        )

        for i in 0..<4 {
            var step = AgentStep(index: i, goal: "g\(i)", successCriteria: "c\(i)")
            step.toolCall = repeatedTC
            state.steps.append(step)
        }

        let loop = state.detectLoop(threshold: 3, windowSize: 5)
        XCTAssertNotNil(loop)
        XCTAssertGreaterThanOrEqual(loop!.count, 3)
    }

    // MARK: - SessionSummary Tests

    func testSessionSummaryFormattedDuration() {
        let summary = SessionSummary(
            intent: "test",
            stepsCompleted: 1,
            stepsTotal: 1,
            filesModified: [],
            commandsRun: [],
            tokensUsed: TokenUsage(),
            cost: SessionCost(),
            duration: 83,
            outcome: "ok"
        )
        XCTAssertEqual(summary.formattedDuration, "1m 23s")
    }

    func testSessionSummaryFormattedDurationSeconds() {
        let summary = SessionSummary(
            intent: "test",
            stepsCompleted: 1,
            stepsTotal: 1,
            filesModified: [],
            commandsRun: [],
            tokensUsed: TokenUsage(),
            cost: SessionCost(),
            duration: 45,
            outcome: "ok"
        )
        XCTAssertEqual(summary.formattedDuration, "45s")
    }

    func testSessionSummaryOneLiner() {
        let summary = SessionSummary(
            intent: "test",
            stepsCompleted: 3,
            stepsTotal: 5,
            filesModified: [],
            commandsRun: [],
            tokensUsed: TokenUsage(),
            cost: SessionCost(),
            duration: 30,
            outcome: "Completed"
        )
        let oneLiner = summary.oneLiner
        XCTAssertTrue(oneLiner.contains("3/5"))
        XCTAssertTrue(oneLiner.contains("30s"))
        XCTAssertTrue(oneLiner.contains("Completed"))
    }

    // MARK: - AgentPrompts Tests

    func testAgentPromptsExist() {
        XCTAssertFalse(AgentPrompts.plannerSystem.isEmpty)
        XCTAssertFalse(AgentPrompts.executorSystem.isEmpty)
        XCTAssertFalse(AgentPrompts.verifierSystem.isEmpty)
        XCTAssertFalse(AgentPrompts.summarizerSystem.isEmpty)
    }

    func testPlannerPromptContainsKeyInstructions() {
        let prompt = AgentPrompts.plannerSystem
        XCTAssertTrue(prompt.contains("Planner"))
        XCTAssertTrue(prompt.contains("numbered"))
        XCTAssertTrue(prompt.contains("tool"))
    }

    func testVerifierPromptContainsVerdictInstructions() {
        let prompt = AgentPrompts.verifierSystem
        XCTAssertTrue(prompt.contains("verdict: pass"))
        XCTAssertTrue(prompt.contains("verdict: fail"))
        XCTAssertTrue(prompt.contains("verdict: unclear"))
    }
}
