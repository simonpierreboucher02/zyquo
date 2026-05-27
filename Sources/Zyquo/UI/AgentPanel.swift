import Foundation

/// Renders agent execution progress to stdout using CommandOutput.
///
/// This is a sequential renderer -- it prints events as they arrive,
/// not a full-screen TUI. Each AgentEvent is rendered as a distinct
/// block of output (status badge, plan panel, step header, etc.).
///
/// Reference: CLAUDE.md §7, §9, §12
public struct AgentPanel: Sendable {
    let output: CommandOutput
    let noColor: Bool

    public init(noColor: Bool = false) {
        self.noColor = noColor
        self.output = CommandOutput(noColor: noColor)
    }

    // MARK: - Event Dispatch

    /// Render a single agent event to stdout.
    public func renderEvent(_ event: AgentEvent) {
        switch event {
        case .statusChanged(let status):
            renderStatus(status)
        case .planProduced(let plan):
            renderPlan(plan)
        case .stepStarted(let step):
            renderStepStarted(step)
        case .toolProposed(let toolCall, let riskLevel):
            renderToolProposed(toolCall, risk: riskLevel)
        case .approvalRequired(let toolCall, let assessment):
            renderApprovalRequired(toolCall, assessment: assessment)
        case .toolExecuted(let toolCall, let observation):
            renderToolExecuted(toolCall, observation: observation)
        case .verificationCompleted(let stepId, let verdict):
            renderVerification(stepId, verdict: verdict)
        case .contextCompacted(let before, let after):
            renderContextCompacted(before: before, after: after)
        case .finished(let summary):
            renderFinished(summary)
        case .error(let error):
            renderError(error)
        }
    }

    // MARK: - Status

    private func renderStatus(_ status: AgentStatus) {
        let (label, color) = statusDisplay(status)
        let icon = noColor ? ">" : "\u{25CF}" // filled circle
        let iconColor = output.fg(color)
        let boldCode = output.ansi("1")
        let rst = output.reset()

        print("\(iconColor)\(icon)\(rst) \(boldCode)\(iconColor)\(label)\(rst)")
    }

    private func statusDisplay(_ status: AgentStatus) -> (String, ANSIColor) {
        let theme = output.theme
        switch status {
        case .planning:   return ("PLANNING",   .cyan)
        case .executing:  return ("EXECUTING",  theme.colors.warn)
        case .verifying:  return ("VERIFYING",  .blue)
        case .blocked:    return ("BLOCKED",    theme.colors.risk)
        case .done:       return ("DONE",       theme.colors.ok)
        case .cancelled:  return ("CANCELLED",  theme.colors.fgMuted)
        case .failed:     return ("FAILED",     theme.colors.risk)
        }
    }

    // MARK: - Plan

    private func renderPlan(_ plan: Plan) {
        output.blank()
        output.header(title: "Plan", badge: "\(plan.steps.count) steps")

        let borderColor = output.fg(output.theme.colors.border)
        let fgColor = output.fg(output.theme.colors.fg)
        let mutedColor = output.fg(output.theme.colors.fgMuted)
        let accentColor = output.fg(output.theme.colors.accent)
        let rst = output.reset()
        let vt = noColor ? "|" : "\u{2502}"

        let innerWidth = output.width - 2

        for (i, step) in plan.steps.enumerated() {
            let number = "\(i + 1)."
            let statusTag = noColor ? "[ pending ]" : "[ pending ]"
            let goalText = step.goal
            let numberAndGoal = "\(number) \(goalText)"

            // Calculate available space
            let fixedLen = statusTag.count + 3 // spaces around statusTag
            let availableForGoal = max(10, innerWidth - fixedLen - 2)
            let truncatedGoal = String(numberAndGoal.prefix(availableForGoal))
            let pad = max(0, innerWidth - truncatedGoal.count - statusTag.count - 2)

            let line = borderColor + vt + rst
                + " " + accentColor + truncatedGoal + rst
                + String(repeating: " ", count: pad)
                + mutedColor + statusTag + rst + " "
                + borderColor + vt + rst
            print(line)
        }

        // Bottom border
        let bl = noColor ? "+" : "\u{2570}"
        let br = noColor ? "+" : "\u{256F}"
        let hz = noColor ? "-" : "\u{2500}"
        let bottom = borderColor + bl + String(repeating: hz, count: innerWidth) + br + rst
        print(bottom)
        output.blank()
    }

    // MARK: - Step Started

    private func renderStepStarted(_ step: AgentStep) {
        let accentColor = output.fg(output.theme.colors.accent)
        let boldCode = output.ansi("1")
        let mutedColor = output.fg(output.theme.colors.fgMuted)
        let rst = output.reset()

        let stepIcon = noColor ? "-->" : "\u{25B8}" // right-pointing triangle
        let stepNumber = step.index + 1
        print("\(accentColor)\(stepIcon)\(rst) \(boldCode)Step \(stepNumber)\(rst) \(mutedColor)\(step.goal)\(rst)")
    }

    // MARK: - Tool Proposed

    private func renderToolProposed(_ toolCall: ToolCall, risk: RiskLevel) {
        let mutedColor = output.fg(output.theme.colors.fgMuted)
        let fgColor = output.fg(output.theme.colors.fg)
        let boldCode = output.ansi("1")
        let rst = output.reset()

        let riskBadge = formatRiskBadge(risk)
        let toolIcon = noColor ? "$" : "\u{2192}" // right arrow

        var line = "  \(mutedColor)\(toolIcon)\(rst) \(boldCode)\(fgColor)\(toolCall.toolName)\(rst) \(riskBadge)"

        // Show command for shell.run
        if toolCall.toolName == "shell.run", let cmd = toolCall.input["command"]?.stringValue {
            let truncatedCmd = String(cmd.prefix(max(20, output.width - 40)))
            line += " \(mutedColor)\(truncatedCmd)\(rst)"
        }

        print(line)
    }

    private func formatRiskBadge(_ risk: RiskLevel) -> String {
        let color = riskColor(risk)
        let colorCode = output.fg(color)
        let boldCode = output.ansi("1")
        let rst = output.reset()
        let label = risk.displayName
        if noColor {
            return "[\(label)]"
        }
        return "\(boldCode)\(colorCode)[\(label)]\(rst)"
    }

    private func riskColor(_ risk: RiskLevel) -> ANSIColor {
        let theme = output.theme
        switch risk {
        case .safe:      return theme.colors.ok
        case .moderate:  return theme.colors.warn
        case .dangerous: return theme.colors.risk
        case .critical:  return .brightRed
        }
    }

    // MARK: - Approval Required

    private func renderApprovalRequired(_ toolCall: ToolCall, assessment: RiskAssessment) {
        let command: String
        if toolCall.toolName == "shell.run", let cmd = toolCall.input["command"]?.stringValue {
            command = cmd
        } else {
            command = "\(toolCall.toolName)(\(toolCall.input.keys.sorted().joined(separator: ", ")))"
        }

        let panel = ApprovalPanel(noColor: noColor)
        panel.render(
            command: command,
            risk: assessment.tier.displayName,
            reasons: assessment.escalationReasons.isEmpty
                ? [assessment.rationale]
                : assessment.escalationReasons
        )
    }

    // MARK: - Tool Executed

    private func renderToolExecuted(_ toolCall: ToolCall, observation: Observation) {
        let rst = output.reset()

        if observation.isError {
            let icon = noColor ? "[FAIL]" : "\u{2717}"
            let errorColor = output.fg(output.theme.colors.risk)
            let mutedColor = output.fg(output.theme.colors.fgMuted)
            let summaryLine = String(observation.summary.prefix(output.width - 20))
            print("  \(errorColor)\(icon)\(rst) \(mutedColor)\(toolCall.toolName)\(rst) \(errorColor)\(summaryLine)\(rst)")
        } else {
            let icon = noColor ? "[OK]" : "\u{2713}"
            let okColor = output.fg(output.theme.colors.ok)
            let mutedColor = output.fg(output.theme.colors.fgMuted)
            let summaryLine = String(observation.summary.prefix(output.width - 20))
            print("  \(okColor)\(icon)\(rst) \(mutedColor)\(toolCall.toolName)\(rst) \(summaryLine)")
        }

        // Show duration if meaningful
        if observation.durationMs > 0 {
            let dimCode = output.ansi("2")
            let mutedColor = output.fg(output.theme.colors.fgMuted)
            let durationStr = observation.durationMs >= 1000
                ? String(format: "%.1fs", Double(observation.durationMs) / 1000.0)
                : "\(observation.durationMs)ms"
            print("    \(dimCode)\(mutedColor)\(durationStr)\(rst)")
        }
    }

    // MARK: - Verification

    private func renderVerification(_ stepId: StepID, verdict: Verdict) {
        let rst = output.reset()
        let (icon, color, label) = verdictDisplay(verdict)
        let colorCode = output.fg(color)
        print("  \(colorCode)\(icon)\(rst) Verification: \(colorCode)\(label)\(rst)")
    }

    private func verdictDisplay(_ verdict: Verdict) -> (String, ANSIColor, String) {
        let theme = output.theme
        switch verdict {
        case .pass:
            return (noColor ? "[PASS]" : "\u{2713}", theme.colors.ok, "PASS")
        case .fail:
            return (noColor ? "[FAIL]" : "\u{2717}", theme.colors.risk, "FAIL")
        case .unclear:
            return (noColor ? "[??]" : "?", theme.colors.warn, "UNCLEAR")
        }
    }

    // MARK: - Context Compacted

    private func renderContextCompacted(before: Int, after: Int) {
        let dimCode = output.ansi("2")
        let mutedColor = output.fg(output.theme.colors.fgMuted)
        let rst = output.reset()

        let saved = before - after
        let pct = before > 0 ? Int(Double(saved) / Double(before) * 100) : 0
        print("  \(dimCode)\(mutedColor)Context compacted: \(formatTokenCount(before)) -> \(formatTokenCount(after)) (-\(pct)%)\(rst)")
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    // MARK: - Finished

    private func renderFinished(_ summary: SessionSummary) {
        output.blank()

        let badgeColor: ANSIColor
        if summary.outcome.contains("successfully") {
            badgeColor = output.theme.colors.ok
        } else if summary.outcome.contains("Cancelled") {
            badgeColor = output.theme.colors.warn
        } else {
            badgeColor = output.theme.colors.risk
        }

        output.header(
            title: "Session Complete",
            badge: summary.outcome,
            badgeColor: badgeColor
        )

        output.footer(items: [
            ("Steps", "\(summary.stepsCompleted)/\(summary.stepsTotal)"),
            ("Duration", summary.formattedDuration),
            ("Cost", summary.cost.formattedCost),
            ("Tokens", "\(summary.tokensUsed.inputTokens) in / \(summary.tokensUsed.outputTokens) out"),
        ])

        // Show files modified if any
        if !summary.filesModified.isEmpty {
            output.blank()
            let mutedColor = output.fg(output.theme.colors.fgMuted)
            let rst = output.reset()
            print("  \(mutedColor)Files modified:\(rst)")
            for file in summary.filesModified.prefix(10) {
                output.infoItem(file)
            }
            if summary.filesModified.count > 10 {
                let remaining = summary.filesModified.count - 10
                output.pendingItem("... and \(remaining) more")
            }
        }

        // Show commands run if any
        if !summary.commandsRun.isEmpty {
            output.blank()
            let mutedColor = output.fg(output.theme.colors.fgMuted)
            let rst = output.reset()
            print("  \(mutedColor)Commands run:\(rst)")
            for cmd in summary.commandsRun.prefix(5) {
                let truncated = String(cmd.prefix(output.width - 10))
                output.infoItem(truncated)
            }
            if summary.commandsRun.count > 5 {
                let remaining = summary.commandsRun.count - 5
                output.pendingItem("... and \(remaining) more")
            }
        }

        output.blank()
    }

    // MARK: - Error

    private func renderError(_ error: ZyquoError) {
        let riskColor = output.fg(output.theme.colors.risk)
        let boldCode = output.ansi("1")
        let rst = output.reset()
        let icon = noColor ? "[ERROR]" : "\u{2717}"

        print("\(boldCode)\(riskColor)\(icon) Error:\(rst) \(riskColor)\(error.description)\(rst)")

        // Show remediation hint if available
        if let hint = extractRemediation(from: error) {
            let mutedColor = output.fg(output.theme.colors.fgMuted)
            let dimCode = output.ansi("2")
            print("  \(dimCode)\(mutedColor)Hint: \(hint)\(rst)")
        }
    }

    private func extractRemediation(from error: ZyquoError) -> String? {
        switch error {
        case .config(let e):      return e.remediation
        case .provider(let e):    return e.remediation
        case .tool(let e):        return e.remediation
        case .shell(let e):       return e.remediation
        case .workspace(let e):   return e.remediation
        case .persistence(let e): return e.remediation
        case .approval(let e):    return e.remediation
        case .risk(let e):        return e.remediation
        case .plugin(let e):      return e.remediation
        case .cancelled:          return nil
        case .userExit:           return nil
        }
    }
}
