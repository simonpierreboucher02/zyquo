import Foundation

// MARK: - DistributionStrategy

/// Strategy for distributing tasks across cluster nodes.
///
/// The scheduler uses this to decide how to assign subtasks to nodes.
public enum DistributionStrategy: String, Sendable, CaseIterable {
    /// Distribute proportional to core count. Nodes with more cores
    /// receive more tasks.
    case proportional
    /// Equal distribution across all nodes (round-robin).
    case roundRobin
    /// Assign to the node with the fewest current assignments.
    case leastLoaded
    /// User-specified node assignment (requires task metadata).
    case manual
}

// MARK: - TaskAssignment

/// A mapping of a subtask to a specific cluster node.
///
/// Created by the scheduler and consumed by the distributed executor.
public struct TaskAssignment: Sendable {
    /// The subtask to execute.
    public let task: SubTask
    /// The identifier of the node assigned to run this task.
    public let nodeId: String
    /// Human-readable reason for the assignment decision.
    public let reason: String

    public init(task: SubTask, nodeId: String, reason: String) {
        self.task = task
        self.nodeId = nodeId
        self.reason = reason
    }
}

// MARK: - ClusterScheduler

/// Distributes tasks across cluster nodes according to a chosen strategy.
///
/// The scheduler is stateless; it takes a list of tasks and nodes,
/// and produces a list of assignments. Load tracking for the
/// `leastLoaded` strategy uses the current assignment count per node.
///
/// Reference: CLAUDE.md §30 Phase 9
public struct ClusterScheduler: Sendable {

    public init() {}

    /// Distribute tasks across available nodes.
    ///
    /// - Parameters:
    ///   - tasks: The subtasks to distribute.
    ///   - nodes: The available cluster nodes (should be online).
    ///   - strategy: The distribution strategy to apply.
    /// - Returns: An array of task assignments mapping each task to a node.
    public func distribute(
        tasks: [SubTask],
        nodes: [NodeInfo],
        strategy: DistributionStrategy
    ) -> [TaskAssignment] {
        guard !tasks.isEmpty else { return [] }
        guard !nodes.isEmpty else { return [] }

        switch strategy {
        case .proportional:
            return distributeProportional(tasks: tasks, nodes: nodes)
        case .roundRobin:
            return distributeRoundRobin(tasks: tasks, nodes: nodes)
        case .leastLoaded:
            return distributeLeastLoaded(tasks: tasks, nodes: nodes)
        case .manual:
            // Manual falls back to proportional since we have no
            // per-task node hints in SubTask at this layer.
            return distributeProportional(tasks: tasks, nodes: nodes)
        }
    }

    // MARK: - Proportional Distribution

    /// Assign tasks proportional to each node's core count.
    ///
    /// A node with 32 cores gets twice as many tasks as a node with 16 cores.
    /// Remaining tasks (from integer rounding) go to the highest-core nodes.
    private func distributeProportional(tasks: [SubTask], nodes: [NodeInfo]) -> [TaskAssignment] {
        let totalCores = nodes.reduce(0) { $0 + $1.cores }
        guard totalCores > 0 else {
            // Fallback: round-robin if all nodes report 0 cores
            return distributeRoundRobin(tasks: tasks, nodes: nodes)
        }

        // Sort nodes by core count descending for deterministic assignment
        let sortedNodes = nodes.sorted { $0.cores > $1.cores }
        let taskCount = tasks.count

        // Calculate proportional share per node
        var shares: [(node: NodeInfo, count: Int)] = []
        var assigned = 0
        for (index, node) in sortedNodes.enumerated() {
            let share: Int
            if index == sortedNodes.count - 1 {
                // Last node gets the remainder
                share = taskCount - assigned
            } else {
                share = (taskCount * node.cores) / totalCores
            }
            shares.append((node, max(0, share)))
            assigned += max(0, share)
        }

        // Build assignments
        var assignments: [TaskAssignment] = []
        var taskIndex = 0
        for (node, count) in shares {
            for _ in 0..<count {
                guard taskIndex < tasks.count else { break }
                assignments.append(TaskAssignment(
                    task: tasks[taskIndex],
                    nodeId: node.id,
                    reason: "Proportional: \(node.id) has \(node.cores) cores (\(node.cores * 100 / totalCores)% of cluster)"
                ))
                taskIndex += 1
            }
        }

        return assignments
    }

    // MARK: - Round Robin Distribution

    /// Assign tasks equally across nodes in round-robin order.
    private func distributeRoundRobin(tasks: [SubTask], nodes: [NodeInfo]) -> [TaskAssignment] {
        var assignments: [TaskAssignment] = []
        for (index, task) in tasks.enumerated() {
            let node = nodes[index % nodes.count]
            assignments.append(TaskAssignment(
                task: task,
                nodeId: node.id,
                reason: "Round-robin: slot \(index % nodes.count + 1) of \(nodes.count)"
            ))
        }
        return assignments
    }

    // MARK: - Least Loaded Distribution

    /// Assign each task to the node with the fewest current assignments.
    ///
    /// Ties are broken by core count (more cores preferred).
    private func distributeLeastLoaded(tasks: [SubTask], nodes: [NodeInfo]) -> [TaskAssignment] {
        var loadMap: [String: Int] = [:]
        for node in nodes {
            loadMap[node.id] = 0
        }

        var assignments: [TaskAssignment] = []
        for task in tasks {
            // Find the least loaded node, tie-break by cores descending
            let target = nodes.min { a, b in
                let loadA = loadMap[a.id, default: 0]
                let loadB = loadMap[b.id, default: 0]
                if loadA != loadB { return loadA < loadB }
                return a.cores > b.cores
            }!

            loadMap[target.id, default: 0] += 1

            assignments.append(TaskAssignment(
                task: task,
                nodeId: target.id,
                reason: "Least-loaded: \(target.id) had \(loadMap[target.id, default: 1] - 1) prior assignments"
            ))
        }
        return assignments
    }
}
