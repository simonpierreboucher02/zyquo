import Foundation
import Logging

public struct ZTPWorkflowStep: Sendable {
    public let toolName: String
    public let command: String
    public let input: [String: JSONValue]
    public let outputKey: String?

    public init(
        toolName: String,
        command: String,
        input: [String: JSONValue] = [:],
        outputKey: String? = nil
    ) {
        self.toolName = toolName
        self.command = command
        self.input = input
        self.outputKey = outputKey
    }
}

public struct ZTPWorkflowResult: Sendable {
    public let ok: Bool
    public let steps: [StepResult]
    public let artifacts: [ToolArtifact]
    public let totalDurationMs: Int

    public struct StepResult: Sendable {
        public let toolName: String
        public let command: String
        public let ok: Bool
        public let summary: String
        public let durationMs: Int
        public let outputPath: String?
    }
}

public actor ZTPWorkflowEngine {
    private let discovery: ZTPDiscovery
    private let ztpBinary: String
    private let logger: Logging.Logger

    public init(
        discovery: ZTPDiscovery,
        ztpBinary: String = "/opt/homebrew/bin/ztp",
        logger: Logging.Logger = ZyquoLogger.shared
    ) {
        self.discovery = discovery
        self.ztpBinary = ztpBinary
        self.logger = logger
    }

    public func execute(
        steps: [ZTPWorkflowStep],
        workspaceRoot: URL
    ) async -> ZTPWorkflowResult {
        let startTime = Date()
        var stepResults: [ZTPWorkflowResult.StepResult] = []
        var allArtifacts: [ToolArtifact] = []
        var previousOutputs: [String: String] = [:]
        var allOk = true

        let context = ToolContext(
            workspaceRoot: workspaceRoot,
            sessionId: "workflow-\(UUID().uuidString.prefix(8))",
            logger: logger
        )

        for step in steps {
            let manifest = await discovery.manifest(for: step.toolName)
            guard let manifest else {
                stepResults.append(.init(
                    toolName: step.toolName, command: step.command,
                    ok: false, summary: "Tool \(step.toolName) not found",
                    durationMs: 0, outputPath: nil
                ))
                allOk = false
                break
            }

            let bridge = ZTPToolBridge(manifest: manifest, ztpBinary: ztpBinary)

            var resolvedInput = step.input
            resolvedInput["command"] = .string(step.command)

            for (key, value) in resolvedInput {
                if case .string(let s) = value, s.hasPrefix("{{") && s.hasSuffix("}}") {
                    let ref = String(s.dropFirst(2).dropLast(2))
                    if let resolved = previousOutputs[ref] {
                        resolvedInput[key] = .string(resolved)
                    }
                }
            }

            do {
                let result = try await bridge.execute(input: resolvedInput, context: context)

                let outputPath = result.artifacts.first?.path

                if let key = step.outputKey, let path = outputPath {
                    previousOutputs[key] = path
                }

                let isOk = !result.summary.contains("FAILED")
                if !isOk { allOk = false }

                stepResults.append(.init(
                    toolName: step.toolName, command: step.command,
                    ok: isOk, summary: result.summary,
                    durationMs: result.durationMs, outputPath: outputPath
                ))
                allArtifacts.append(contentsOf: result.artifacts)

                if !isOk { break }
            } catch {
                stepResults.append(.init(
                    toolName: step.toolName, command: step.command,
                    ok: false, summary: "Error: \(error.localizedDescription)",
                    durationMs: 0, outputPath: nil
                ))
                allOk = false
                break
            }
        }

        let totalMs = Int(Date().timeIntervalSince(startTime) * 1000)
        return ZTPWorkflowResult(
            ok: allOk, steps: stepResults,
            artifacts: allArtifacts, totalDurationMs: totalMs
        )
    }
}
