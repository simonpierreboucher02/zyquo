import ArgumentParser
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Agentic run (tools enabled)"
    )

    @OptionGroup var globals: ZyquoCLI.GlobalOptions

    @Argument(help: "Intent to execute")
    var intent: String

    func run() async throws {
        Bootstrap.setupSignalHandlers()
        Bootstrap.ensureDirectories()

        let container = AppContainer(flags: globals.flags)
        container.logger.info("Run mode", metadata: ["intent": "\(intent)"])

        let noColor = container.config.ui.noColor
        let termWidth = Terminal.size.width
        let theme = ThemeEngine().load(named: container.config.ui.theme)

        // Print header
        printHeader(intent: intent, config: container.config, noColor: noColor, width: termWidth)

        // Set up workspace
        let root = Bootstrap.detectWorkspaceRoot(override: globals.workspace)
        let workspace = Workspace(root: root)

        // Print workspace summary
        let wsIndex = await workspace.scan()
        if !container.config.ui.noColor {
            print("  \u{1B}[2m\(wsIndex.summaryCard.replacingOccurrences(of: "\n", with: "\n  "))\u{1B}[0m")
        } else {
            print("  \(wsIndex.summaryCard.replacingOccurrences(of: "\n", with: "\n  "))")
        }
        print()

        // Set up model router and providers
        let router = ModelRouter(config: container.config.providers)
        await router.register(AnthropicProvider())
        await router.register(OpenRouterProvider())

        // Verify we have a working provider
        let providerId = container.config.providers.resolvedProvider
        guard await router.resolve(for: .planning) != nil else {
            printError(
                "No provider configured for '\(providerId)'",
                remediation: "Run `zyquo provider login \(providerId)`",
                noColor: noColor
            )
            throw ExitCode.failure
        }

        // Set up execution context
        let shellExecutor = ShellExecutor(config: container.config.shell, logger: container.logger)
        let riskClassifier = RiskClassifier(workspaceRoot: root)
        let approvalGate = ApprovalGate(autoApproveSafe: container.config.agent.autoApproveSafe)
        let trustStore = TrustStore(workspaceRoot: root)

        let agentConfig = container.config.agent

        // Build the agent tool registry: built-ins (web/db/applescript) +
        // filesystem/git tools + ZTP bridges (discovered from the ztp binary).
        let toolRegistry = ToolRegistry()
        registerBuiltinTools(in: toolRegistry)
        toolRegistry.registerAll([
            FileWriteTool(), FilePatchTool(),
            GitStatusTool(), GitDiffTool(), GitLogTool(), GitCommitTool(),
        ])
        await ZTPIntegration.shared.bootstrap(registry: toolRegistry, logger: container.logger)
        let toolGuidance = await ZTPIntegration.shared.systemPromptFragment()

        let executionContext = ExecutionContext(
            workspace: workspace,
            shellExecutor: shellExecutor,
            riskClassifier: riskClassifier,
            approvalGate: approvalGate,
            trustStore: trustStore,
            config: agentConfig,
            logger: container.logger,
            toolRegistry: toolRegistry
        )

        // Create agent runtime
        let runtime = AgentRuntime(
            executionContext: executionContext,
            logger: container.logger
        )

        // Run the agent loop
        let events = await runtime.run(
            intent: intent,
            workspace: workspace,
            config: agentConfig,
            router: router,
            toolGuidance: toolGuidance
        )

        // Consume and render events
        let startTime = Date()
        var stepCount = 0
        var totalSteps = 0
        var sessionCost = SessionCost()

        for await event in events {
            renderEvent(
                event,
                noColor: noColor,
                width: termWidth,
                theme: theme,
                stepCount: &stepCount,
                totalSteps: &totalSteps,
                sessionCost: &sessionCost,
                startTime: startTime
            )
        }

        // Persist the session and run the closed learning loop (best-effort).
        if let finalState = await runtime.currentState() {
            let learning = await SessionFinalizer.finalize(
                state: finalState,
                workspaceRoot: root,
                router: router,
                config: container.config
            )
            SessionFinalizer.renderNudges(learning, noColor: noColor)
        }

        // Final separator
        print()
    }

    // MARK: - Header

    private func printHeader(intent: String, config: Config, noColor: Bool, width: Int) {
        let border = noColor ? "-" : "\u{2500}"
        let tl = noColor ? "+" : "\u{256D}"
        let tr = noColor ? "+" : "\u{256E}"
        let bl = noColor ? "+" : "\u{2570}"
        let br = noColor ? "+" : "\u{256F}"
        let v = noColor ? "|" : "\u{2502}"

        let innerWidth = min(width - 2, 62)
        let title = " Zyquo Agent "
        let titlePad = innerWidth - title.count
        let leftPad = titlePad / 2
        let rightPad = titlePad - leftPad

        let topLine = tl + String(repeating: border, count: leftPad) + title + String(repeating: border, count: rightPad) + tr

        func padLine(_ left: String, _ right: String) -> String {
            let content = " \(left)"
            let rightPart = "\(right) "
            let space = max(1, innerWidth - content.count - rightPart.count)
            return v + content + String(repeating: " ", count: space) + rightPart + v
        }

        let ws = "Workspace: \(FileManager.default.currentDirectoryPath)"
        let model = "Model: \(config.providers.resolvedModel)"
        let mode = "Mode: Agentic Run"
        let status = "Status: Starting"
        let bottomLine = bl + String(repeating: border, count: innerWidth) + br

        if noColor {
            print(topLine)
            print(padLine(ws, model))
            print(padLine(mode, status))
            print(bottomLine)
        } else {
            print("\u{1B}[36m\(topLine)\u{1B}[0m")
            print("\u{1B}[36m\(padLine(ws, model))\u{1B}[0m")
            print("\u{1B}[36m\(padLine(mode, status))\u{1B}[0m")
            print("\u{1B}[36m\(bottomLine)\u{1B}[0m")
        }
        print()

        // Print intent
        let intentLine = "Intent: \(intent)"
        if noColor {
            print("  \(intentLine)")
        } else {
            print("  \u{1B}[1m\(intentLine)\u{1B}[0m")
        }
        print()
    }

    // MARK: - Event Rendering

    private func renderEvent(
        _ event: AgentEvent,
        noColor: Bool,
        width: Int,
        theme: Theme,
        stepCount: inout Int,
        totalSteps: inout Int,
        sessionCost: inout SessionCost,
        startTime: Date
    ) {
        switch event {
        case .statusChanged(let status):
            renderStatus(status, noColor: noColor)

        case .planProduced(let plan):
            totalSteps = plan.steps.count
            renderPlan(plan, noColor: noColor, width: width)

        case .stepStarted(let step):
            stepCount += 1
            renderStepStart(step, stepCount: stepCount, totalSteps: totalSteps, noColor: noColor)

        case .toolProposed(let toolCall, let risk):
            renderToolProposed(toolCall, risk: risk, noColor: noColor)

        case .approvalRequired(let toolCall, let assessment):
            renderApprovalRequired(toolCall, assessment: assessment, noColor: noColor)

        case .toolExecuted(let toolCall, let observation):
            renderToolExecuted(toolCall, observation: observation, noColor: noColor)

        case .verificationCompleted(let stepId, let verdict):
            renderVerdict(stepId: stepId, verdict: verdict, noColor: noColor)

        case .contextCompacted(let before, let after):
            if !noColor {
                print("  \u{1B}[2mContext compacted: \(before) -> \(after) tokens\u{1B}[0m")
            } else {
                print("  Context compacted: \(before) -> \(after) tokens")
            }

        case .finished(let summary):
            renderSummary(summary, noColor: noColor, width: width)

        case .error(let error):
            renderError(error, noColor: noColor)
        }
    }

    private func renderStatus(_ status: AgentStatus, noColor: Bool) {
        let label = status.rawValue.uppercased()
        if noColor {
            print("  [\(label)]")
        } else {
            let color: String
            switch status {
            case .planning: color = "\u{1B}[36m"       // cyan
            case .executing: color = "\u{1B}[34m"      // blue
            case .verifying: color = "\u{1B}[35m"      // magenta
            case .blocked: color = "\u{1B}[33m"        // yellow
            case .done: color = "\u{1B}[32m"           // green
            case .cancelled: color = "\u{1B}[33m"      // yellow
            case .failed: color = "\u{1B}[31m"         // red
            }
            print("  \(color)\u{25B8} \(label)\u{1B}[0m")
        }
    }

    private func renderPlan(_ plan: Plan, noColor: Bool, width: Int) {
        print()
        if noColor {
            print("  Plan (\(plan.steps.count) steps):")
            for (i, step) in plan.steps.enumerated() {
                print("    \(i + 1). \(step.goal)")
            }
        } else {
            print("  \u{1B}[1mPlan\u{1B}[0m \u{1B}[2m(\(plan.steps.count) steps)\u{1B}[0m")
            for (i, step) in plan.steps.enumerated() {
                print("  \u{1B}[36m\(i + 1).\u{1B}[0m \(step.goal)")
            }
        }
        print()
    }

    private func renderStepStart(_ step: AgentStep, stepCount: Int, totalSteps: Int, noColor: Bool) {
        if noColor {
            print("  Step \(stepCount)/\(totalSteps): \(step.goal)")
        } else {
            print("  \u{1B}[1m\u{25B8} Step \(stepCount)/\(totalSteps)\u{1B}[0m \(step.goal)")
        }
    }

    private func renderToolProposed(_ toolCall: ToolCall, risk: RiskLevel, noColor: Bool) {
        let riskLabel = risk.displayName
        let toolName = toolCall.toolName

        if noColor {
            if toolName == "shell.run", let cmd = toolCall.input["command"]?.stringValue {
                print("    Tool: \(toolName) [\(riskLabel)]")
                print("    $ \(cmd)")
            } else if let path = toolCall.input["path"]?.stringValue {
                print("    Tool: \(toolName) [\(riskLabel)] path=\(path)")
            } else {
                print("    Tool: \(toolName) [\(riskLabel)]")
            }
        } else {
            let riskColor: String
            switch risk {
            case .safe: riskColor = "\u{1B}[32m"
            case .moderate: riskColor = "\u{1B}[33m"
            case .dangerous: riskColor = "\u{1B}[31m"
            case .critical: riskColor = "\u{1B}[91m"
            }

            if toolName == "shell.run", let cmd = toolCall.input["command"]?.stringValue {
                print("    \u{1B}[2mTool:\u{1B}[0m \(toolName) \(riskColor)[\(riskLabel)]\u{1B}[0m")
                print("    \u{1B}[1m$ \(cmd)\u{1B}[0m")
            } else if let path = toolCall.input["path"]?.stringValue {
                print("    \u{1B}[2mTool:\u{1B}[0m \(toolName) \(riskColor)[\(riskLabel)]\u{1B}[0m path=\(path)")
            } else {
                print("    \u{1B}[2mTool:\u{1B}[0m \(toolName) \(riskColor)[\(riskLabel)]\u{1B}[0m")
            }
        }
    }

    private func renderApprovalRequired(_ toolCall: ToolCall, assessment: RiskAssessment, noColor: Bool) {
        if noColor {
            print("    [APPROVAL REQUIRED] \(assessment.tier.displayName): \(assessment.rationale)")
            // In V1, auto-approve SAFE; skip MODERATE+ unless --yes
            print("    Auto-approving for V1 demo (use --yes for SAFE auto-approve)")
        } else {
            print("    \u{1B}[33m\u{26A0} Approval required:\u{1B}[0m \(assessment.rationale)")
        }
    }

    private func renderToolExecuted(_ toolCall: ToolCall, observation: Observation, noColor: Bool) {
        let duration = observation.durationMs
        let summaryLines = observation.summary.components(separatedBy: "\n")
        let firstLine = String(summaryLines.first?.prefix(120) ?? "")

        if noColor {
            if observation.isError {
                print("    [ERROR] \(firstLine) (\(duration)ms)")
            } else {
                print("    [OK] \(firstLine) (\(duration)ms)")
            }
        } else {
            if observation.isError {
                print("    \u{1B}[31m\u{2717}\u{1B}[0m \(firstLine) \u{1B}[2m(\(duration)ms)\u{1B}[0m")
            } else {
                print("    \u{1B}[32m\u{2713}\u{1B}[0m \(firstLine) \u{1B}[2m(\(duration)ms)\u{1B}[0m")
            }
        }

        // Print additional output lines (truncated)
        if summaryLines.count > 1 {
            let extraLines = summaryLines.dropFirst().prefix(5)
            for line in extraLines {
                let truncated = String(line.prefix(100))
                if noColor {
                    print("      \(truncated)")
                } else {
                    print("      \u{1B}[2m\(truncated)\u{1B}[0m")
                }
            }
            if summaryLines.count > 6 {
                let remaining = summaryLines.count - 6
                if noColor {
                    print("      ... (\(remaining) more lines)")
                } else {
                    print("      \u{1B}[2m... (\(remaining) more lines)\u{1B}[0m")
                }
            }
        }
    }

    private func renderVerdict(stepId: StepID, verdict: Verdict, noColor: Bool) {
        if noColor {
            print("    Verdict: \(verdict.rawValue.uppercased())")
        } else {
            let color: String
            switch verdict {
            case .pass: color = "\u{1B}[32m"
            case .fail: color = "\u{1B}[31m"
            case .unclear: color = "\u{1B}[33m"
            }
            print("    \(color)Verdict: \(verdict.rawValue.uppercased())\u{1B}[0m")
        }
        print()
    }

    private func renderSummary(_ summary: SessionSummary, noColor: Bool, width: Int) {
        print()
        let border = noColor ? "-" : "\u{2500}"
        let tl = noColor ? "+" : "\u{256D}"
        let tr = noColor ? "+" : "\u{256E}"
        let bl = noColor ? "+" : "\u{2570}"
        let br = noColor ? "+" : "\u{256F}"
        let v = noColor ? "|" : "\u{2502}"
        let innerWidth = min(width - 2, 62)

        let title = " Session Summary "
        let titlePad = innerWidth - title.count
        let lp = titlePad / 2
        let rp = titlePad - lp

        let topLine = tl + String(repeating: border, count: lp) + title + String(repeating: border, count: rp) + tr
        let bottomLine = bl + String(repeating: border, count: innerWidth) + br

        func padContent(_ text: String) -> String {
            let content = " \(text)"
            let pad = max(0, innerWidth - content.count)
            return v + content + String(repeating: " ", count: pad) + v
        }

        let lines = [
            topLine,
            padContent("Outcome: \(summary.outcome)"),
            padContent("Steps: \(summary.stepsCompleted)/\(summary.stepsTotal)"),
            padContent("Duration: \(summary.formattedDuration)"),
            padContent("Cost: \(summary.cost.formattedCost)"),
            padContent("Tokens: \(summary.tokensUsed.inputTokens) in / \(summary.tokensUsed.outputTokens) out"),
        ]

        var allLines = lines

        if !summary.commandsRun.isEmpty {
            allLines.append(padContent("Commands: \(summary.commandsRun.count) executed"))
        }

        if !summary.filesModified.isEmpty {
            allLines.append(padContent("Files modified: \(summary.filesModified.count)"))
        }

        allLines.append(bottomLine)

        for line in allLines {
            if noColor {
                print(line)
            } else {
                if line == topLine || line == bottomLine {
                    print("\u{1B}[36m\(line)\u{1B}[0m")
                } else {
                    print("\u{1B}[36m\(v)\u{1B}[0m\(String(line.dropFirst().dropLast()))\u{1B}[36m\(v)\u{1B}[0m")
                }
            }
        }
    }

    private func renderError(_ error: ZyquoError, noColor: Bool) {
        if noColor {
            print("  [ERROR] \(error.description)")
        } else {
            print("  \u{1B}[31mError: \(error.description)\u{1B}[0m")
        }
    }

    private func printError(_ message: String, remediation: String, noColor: Bool) {
        if noColor {
            print("[ERROR] \(message)")
            print("  Fix: \(remediation)")
        } else {
            print("\u{1B}[31mError:\u{1B}[0m \(message)")
            print("\u{1B}[2m  Fix: \(remediation)\u{1B}[0m")
        }
    }
}
