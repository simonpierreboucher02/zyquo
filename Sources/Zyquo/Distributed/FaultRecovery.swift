import Foundation

// MARK: - FaultRecoveryPlan

/// A plan for recovering from a node failure.
///
/// Contains reassignments for tasks that were on the failed node and
/// a list of tasks that could not be reassigned.
public struct FaultRecoveryPlan: Sendable {
    /// Tasks reassigned to other available nodes.
    public let reassignments: [TaskAssignment]
    /// Task IDs that were cancelled because no node was available.
    public let cancelledTasks: [String]
    /// Human-readable description of the recovery actions taken.
    public let description: String

    public init(
        reassignments: [TaskAssignment],
        cancelledTasks: [String],
        description: String
    ) {
        self.reassignments = reassignments
        self.cancelledTasks = cancelledTasks
        self.description = description
    }

    /// Whether the recovery plan has any cancelled tasks.
    public var hasCancellations: Bool {
        !cancelledTasks.isEmpty
    }

    /// Whether the recovery was fully successful (all tasks reassigned).
    public var isFullRecovery: Bool {
        cancelledTasks.isEmpty
    }
}

// MARK: - FaultRecovery

/// Handles graceful degradation when cluster nodes fail.
///
/// When a node goes offline, the fault recovery system reassigns its
/// incomplete tasks to remaining available nodes. If no nodes are
/// available, tasks are cancelled with appropriate logging.
///
/// Reference: CLAUDE.md §30 Phase 9
public struct FaultRecovery: Sendable {

    private let scheduler: ClusterScheduler

    public init(scheduler: ClusterScheduler = ClusterScheduler()) {
        self.scheduler = scheduler
    }

    /// Handle the failure of one or more nodes.
    ///
    /// Reassigns tasks that were assigned to the failed node(s) to
    /// the remaining available nodes using proportional distribution.
    ///
    /// - Parameters:
    ///   - failedNodeId: The identifier of the failed node.
    ///   - assignments: The current list of all task assignments.
    ///   - availableNodes: Nodes that are still online and can accept work.
    /// - Returns: A recovery plan with reassignments and/or cancellations.
    public func handleNodeFailure(
        failedNodeId: String,
        assignments: [TaskAssignment],
        availableNodes: [NodeInfo]
    ) -> FaultRecoveryPlan {
        // Find tasks assigned to the failed node
        let affectedAssignments = assignments.filter { $0.nodeId == failedNodeId }
        let affectedTasks = affectedAssignments.map(\.task)

        guard !affectedTasks.isEmpty else {
            return FaultRecoveryPlan(
                reassignments: [],
                cancelledTasks: [],
                description: "Node '\(failedNodeId)' failed but had no assigned tasks."
            )
        }

        // If no nodes are available, cancel all affected tasks
        guard !availableNodes.isEmpty else {
            return FaultRecoveryPlan(
                reassignments: [],
                cancelledTasks: affectedTasks.map(\.id),
                description: "Node '\(failedNodeId)' failed with \(affectedTasks.count) tasks. "
                    + "No available nodes for reassignment; all tasks cancelled."
            )
        }

        // Redistribute affected tasks to available nodes
        let newAssignments = scheduler.distribute(
            tasks: affectedTasks,
            nodes: availableNodes,
            strategy: .proportional
        )

        let reassignedIds = Set(newAssignments.map(\.task.id))
        let cancelledIds = affectedTasks
            .map(\.id)
            .filter { !reassignedIds.contains($0) }

        // Build description
        var description = "Node '\(failedNodeId)' failed with \(affectedTasks.count) task(s). "
        if !newAssignments.isEmpty {
            let nodeIds = Array(Set(newAssignments.map(\.nodeId))).sorted()
            description += "Reassigned \(newAssignments.count) task(s) to \(nodeIds.joined(separator: ", ")). "
        }
        if !cancelledIds.isEmpty {
            description += "Cancelled \(cancelledIds.count) task(s) that could not be reassigned."
        }

        return FaultRecoveryPlan(
            reassignments: newAssignments,
            cancelledTasks: cancelledIds,
            description: description
        )
    }

    /// Handle the failure of multiple nodes simultaneously.
    ///
    /// Collects all affected tasks from all failed nodes and redistributes
    /// them to the remaining available nodes.
    ///
    /// - Parameters:
    ///   - failedNodeIds: The identifiers of the failed nodes.
    ///   - assignments: The current list of all task assignments.
    ///   - availableNodes: Nodes that are still online and can accept work.
    /// - Returns: A recovery plan with reassignments and/or cancellations.
    public func handleMultipleNodeFailures(
        failedNodeIds: [String],
        assignments: [TaskAssignment],
        availableNodes: [NodeInfo]
    ) -> FaultRecoveryPlan {
        let failedSet = Set(failedNodeIds)

        // Find all tasks assigned to any failed node
        let affectedAssignments = assignments.filter { failedSet.contains($0.nodeId) }
        let affectedTasks = affectedAssignments.map(\.task)

        guard !affectedTasks.isEmpty else {
            return FaultRecoveryPlan(
                reassignments: [],
                cancelledTasks: [],
                description: "\(failedNodeIds.count) node(s) failed but had no assigned tasks."
            )
        }

        // Filter out failed nodes from available nodes
        let safeNodes = availableNodes.filter { !failedSet.contains($0.id) }

        guard !safeNodes.isEmpty else {
            return FaultRecoveryPlan(
                reassignments: [],
                cancelledTasks: affectedTasks.map(\.id),
                description: "\(failedNodeIds.count) node(s) failed with \(affectedTasks.count) tasks. "
                    + "No available nodes remaining; all tasks cancelled."
            )
        }

        // Redistribute all affected tasks
        let newAssignments = scheduler.distribute(
            tasks: affectedTasks,
            nodes: safeNodes,
            strategy: .proportional
        )

        let reassignedIds = Set(newAssignments.map(\.task.id))
        let cancelledIds = affectedTasks
            .map(\.id)
            .filter { !reassignedIds.contains($0) }

        var description = "\(failedNodeIds.count) node(s) [\(failedNodeIds.joined(separator: ", "))] failed "
        description += "with \(affectedTasks.count) task(s). "
        if !newAssignments.isEmpty {
            description += "Reassigned \(newAssignments.count) to remaining nodes. "
        }
        if !cancelledIds.isEmpty {
            description += "Cancelled \(cancelledIds.count) task(s)."
        }

        return FaultRecoveryPlan(
            reassignments: newAssignments,
            cancelledTasks: cancelledIds,
            description: description
        )
    }
}
