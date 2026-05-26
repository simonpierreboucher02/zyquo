import Foundation

// MARK: - NodeHealthResult

/// The result of a health check on a single node.
public struct NodeHealthResult: Sendable {
    /// The node identifier.
    public let nodeId: String
    /// Whether the node responded to the health check.
    public let reachable: Bool
    /// Round-trip response time in milliseconds, if reachable.
    public let responseTimeMs: Int?
    /// System load average (1 minute), if retrievable.
    public let loadAverage: Double?
    /// Available memory in gigabytes, if retrievable.
    public let availableMemoryGB: Int?

    public init(
        nodeId: String,
        reachable: Bool,
        responseTimeMs: Int? = nil,
        loadAverage: Double? = nil,
        availableMemoryGB: Int? = nil
    ) {
        self.nodeId = nodeId
        self.reachable = reachable
        self.responseTimeMs = responseTimeMs
        self.loadAverage = loadAverage
        self.availableMemoryGB = availableMemoryGB
    }

    /// A human-readable summary of the health check.
    public var summary: String {
        if reachable {
            var parts = ["reachable"]
            if let ms = responseTimeMs {
                parts.append("\(ms) ms")
            }
            if let load = loadAverage {
                parts.append("load: \(String(format: "%.2f", load))")
            }
            if let mem = availableMemoryGB {
                parts.append("\(mem) GB free")
            }
            return parts.joined(separator: ", ")
        } else {
            return "unreachable"
        }
    }
}

// MARK: - NodeEvent

/// Events emitted by the NodeMonitor during health tracking.
public enum NodeEvent: Sendable {
    /// A node that was offline is now online.
    case nodeOnline(NodeInfo)
    /// A node that was online is now offline.
    case nodeOffline(String)
    /// A node that was offline has recovered to online.
    case nodeRecovered(NodeInfo)
    /// A health check failed for a node.
    case healthCheckFailed(String, String)  // nodeId, reason
}

// MARK: - NodeMonitor

/// Monitors the health of cluster nodes via periodic checks.
///
/// The monitor runs health checks on a configurable interval, updating
/// `ClusterState` and emitting `NodeEvent`s via an async stream. It
/// detects node failures, recoveries, and degraded performance.
///
/// Reference: CLAUDE.md §30 Phase 9
public actor NodeMonitor {

    private let executor: any RemoteExecutor
    private let clusterState: ClusterState
    private var monitorTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<NodeEvent>.Continuation?
    private var _events: AsyncStream<NodeEvent>?

    /// Previous known status per node, for detecting transitions.
    private var previousStatus: [String: NodeStatus] = [:]

    public init(executor: any RemoteExecutor, clusterState: ClusterState) {
        self.executor = executor
        self.clusterState = clusterState
    }

    /// An async stream of node lifecycle events.
    ///
    /// The stream is lazily created on first access and shared.
    public var events: AsyncStream<NodeEvent> {
        if let existing = _events {
            return existing
        }
        let stream = AsyncStream<NodeEvent> { continuation in
            self.eventContinuation = continuation
        }
        _events = stream
        return stream
    }

    // MARK: - Monitoring Control

    /// Start periodic health monitoring.
    ///
    /// - Parameters:
    ///   - nodes: The nodes to monitor.
    ///   - interval: Seconds between health check rounds.
    public func startMonitoring(nodes: [NodeInfo], interval: TimeInterval = 30) {
        stopMonitoring()

        // Initialize previous status
        for node in nodes {
            previousStatus[node.id] = node.status
        }

        // Ensure the event stream is initialized
        let _ = events

        monitorTask = Task { [weak self] in
            guard let self else { return }

            // Register all nodes in cluster state
            for node in nodes {
                await self.clusterState.addNode(node)
            }

            while !Task.isCancelled {
                // Run health checks in parallel
                await self.runHealthCheckRound(nodes: nodes)

                // Wait for the next interval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Stop the periodic monitoring loop.
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Individual Health Check

    /// Perform a health check on a single node.
    ///
    /// Executes a lightweight command (`uptime`) via the remote executor
    /// and parses the response for load average and response time.
    ///
    /// - Parameter node: The node to check.
    /// - Returns: The health check result.
    public func healthCheck(node: NodeInfo) async -> NodeHealthResult {
        let startTime = ContinuousClock.now

        let reachable = await executor.isReachable(node: node)

        let elapsed = ContinuousClock.now - startTime
        let responseTimeMs = Int(elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        guard reachable else {
            return NodeHealthResult(
                nodeId: node.id,
                reachable: false
            )
        }

        // Try to get load average via a simple command
        var loadAverage: Double?
        var availableMemoryGB: Int?

        do {
            let result = try await executor.execute(
                command: "sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}'",
                on: node,
                cwd: nil
            )
            if result.succeeded {
                loadAverage = Double(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {
            // Load average is best-effort
        }

        do {
            let result = try await executor.execute(
                command: "sysctl -n hw.memsize 2>/dev/null",
                on: node,
                cwd: nil
            )
            if result.succeeded,
               let bytes = UInt64(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
                availableMemoryGB = Int(bytes / 1_073_741_824)
            }
        } catch {
            // Memory info is best-effort
        }

        return NodeHealthResult(
            nodeId: node.id,
            reachable: true,
            responseTimeMs: responseTimeMs,
            loadAverage: loadAverage,
            availableMemoryGB: availableMemoryGB
        )
    }

    // MARK: - Internal

    /// Run a full round of health checks across all monitored nodes.
    private func runHealthCheckRound(nodes: [NodeInfo]) async {
        await withTaskGroup(of: (NodeInfo, NodeHealthResult).self) { group in
            for node in nodes {
                group.addTask { [self] in
                    let result = await self.healthCheck(node: node)
                    return (node, result)
                }
            }

            for await (node, result) in group {
                let previousState = previousStatus[node.id] ?? .unknown

                if result.reachable {
                    await clusterState.updateNode(id: node.id, status: .online)

                    if previousState == .offline || previousState == .unknown {
                        var updatedNode = node
                        updatedNode.status = .online
                        updatedNode.lastSeen = Date()
                        eventContinuation?.yield(.nodeRecovered(updatedNode))
                    }

                    previousStatus[node.id] = .online
                } else {
                    await clusterState.updateNode(id: node.id, status: .offline)

                    if previousState == .online {
                        eventContinuation?.yield(.nodeOffline(node.id))
                    }
                    eventContinuation?.yield(.healthCheckFailed(
                        node.id,
                        "Node did not respond to health check"
                    ))

                    previousStatus[node.id] = .offline
                }
            }
        }
    }
}
