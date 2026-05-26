import Foundation

// MARK: - TaskPriority

/// Priority level for scheduled tasks.
///
/// Higher-priority tasks are scheduled first among equally-ready tasks.
public enum TaskPriority: Int, Sendable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - ScheduledTaskStatus

/// Lifecycle status of a task within the scheduler.
public enum ScheduledTaskStatus: String, Sendable {
    /// Waiting for dependencies to complete.
    case waiting
    /// All dependencies satisfied; ready to execute.
    case ready
    /// Currently executing.
    case running
    /// Execution completed successfully.
    case completed
    /// Execution failed.
    case failed
    /// Cancelled before or during execution.
    case cancelled
}

// MARK: - ScheduledTask

/// A task wrapped with scheduling metadata for the DAG scheduler.
public struct ScheduledTask: Sendable, Identifiable {
    /// Unique identifier (matches the subtask id).
    public let id: String
    /// The underlying subtask.
    public let subtask: SubTask
    /// Execution priority among equally-ready tasks.
    public let priority: TaskPriority
    /// Current scheduling status.
    public var status: ScheduledTaskStatus

    public init(
        id: String,
        subtask: SubTask,
        priority: TaskPriority = .normal,
        status: ScheduledTaskStatus = .waiting
    ) {
        self.id = id
        self.subtask = subtask
        self.priority = priority
        self.status = status
    }
}

// MARK: - SchedulerEvent

/// Events emitted by the TaskScheduler as tasks progress through the DAG.
public enum SchedulerEvent: Sendable {
    /// A task's dependencies are satisfied and it is ready to execute.
    case taskReady(ScheduledTask)
    /// A task has started execution.
    case taskStarted(ScheduledTask)
    /// A task completed successfully.
    case taskCompleted(ScheduledTask)
    /// A task failed with an error description.
    case taskFailed(ScheduledTask, String)
    /// A task was cancelled.
    case taskCancelled(ScheduledTask)
    /// All tasks in the graph have completed (or been cancelled/failed).
    case allCompleted
    /// The entire schedule was cancelled.
    case cancelled
}

// MARK: - TaskScheduler

/// DAG-based task scheduler that respects dependency ordering and priorities.
///
/// The scheduler walks a `DependencyGraph<ScheduledTask>`, emitting
/// `SchedulerEvent`s as tasks become ready. It delegates actual execution
/// to the caller; it only manages ordering, readiness, and cancellation.
///
/// Reference: CLAUDE.md §30 Phase 7
public actor TaskScheduler {

    /// Internal status tracking for each task.
    private var taskStatuses: [String: ScheduledTaskStatus] = [:]

    /// The dependency graph being scheduled.
    private var graph: DependencyGraph<ScheduledTask>?

    /// Whether the scheduler has been cancelled.
    private var isCancelled = false

    /// Continuation for emitting events.
    private var continuation: AsyncStream<SchedulerEvent>.Continuation?

    /// Set of completed task IDs (for readyNodes computation).
    private var completedIds: Set<String> = []

    /// Set of failed/cancelled task IDs.
    private var terminatedIds: Set<String> = []

    public init() {}

    // MARK: - Schedule

    /// Schedule tasks from a dependency graph.
    ///
    /// Returns a stream of `SchedulerEvent`s. The caller is responsible for
    /// executing tasks when `taskReady` events are received and reporting
    /// completion via `reportCompleted` / `reportFailed`.
    ///
    /// - Parameter graph: The dependency graph to schedule.
    /// - Returns: An async stream of scheduler events.
    public func schedule(graph: DependencyGraph<ScheduledTask>) -> AsyncStream<SchedulerEvent> {
        self.graph = graph
        self.isCancelled = false
        self.completedIds = []
        self.terminatedIds = []

        // Initialize statuses
        for node in graph.allNodes {
            taskStatuses[node.id] = .waiting
        }

        return AsyncStream { continuation in
            self.continuation = continuation

            // Handle empty graph
            if graph.nodeCount == 0 {
                continuation.yield(.allCompleted)
                continuation.finish()
                return
            }

            // Emit initial ready tasks
            Task { [weak self] in
                await self?.emitReadyTasks()
            }
        }
    }

    // MARK: - Status Reporting

    /// Report that a task has started execution.
    ///
    /// - Parameter id: The task identifier.
    public func reportStarted(id: String) {
        taskStatuses[id] = .running
        if var task = graph?.node(for: id) {
            task.status = .running
            continuation?.yield(.taskStarted(task))
        }
    }

    /// Report that a task completed successfully.
    ///
    /// This may cause dependent tasks to become ready.
    ///
    /// - Parameter id: The task identifier.
    public func reportCompleted(id: String) {
        taskStatuses[id] = .completed
        completedIds.insert(id)

        if var task = graph?.node(for: id) {
            task.status = .completed
            continuation?.yield(.taskCompleted(task))
        }

        // Check if all tasks are done
        if isAllDone() {
            continuation?.yield(.allCompleted)
            continuation?.finish()
            return
        }

        // Emit newly ready tasks
        emitReadyTasks()
    }

    /// Report that a task failed.
    ///
    /// Transitive dependents of the failed task are automatically cancelled.
    ///
    /// - Parameters:
    ///   - id: The task identifier.
    ///   - error: A description of the failure.
    public func reportFailed(id: String, error: String) {
        taskStatuses[id] = .failed
        terminatedIds.insert(id)

        if var task = graph?.node(for: id) {
            task.status = .failed
            continuation?.yield(.taskFailed(task, error))
        }

        // Cancel transitive dependents
        if let graph {
            let dependents = graph.transitiveDependents(of: id)
            for depId in dependents {
                guard taskStatuses[depId] == .waiting || taskStatuses[depId] == .ready else { continue }
                taskStatuses[depId] = .cancelled
                terminatedIds.insert(depId)
                if var depTask = graph.node(for: depId) {
                    depTask.status = .cancelled
                    continuation?.yield(.taskCancelled(depTask))
                }
            }
        }

        if isAllDone() {
            continuation?.yield(.allCompleted)
            continuation?.finish()
        }
    }

    // MARK: - Cancellation

    /// Cancel the entire schedule.
    ///
    /// All non-terminal tasks are moved to cancelled state.
    public func cancel() {
        isCancelled = true

        for (id, status) in taskStatuses {
            if status == .waiting || status == .ready {
                taskStatuses[id] = .cancelled
                terminatedIds.insert(id)
                if var task = graph?.node(for: id) {
                    task.status = .cancelled
                    continuation?.yield(.taskCancelled(task))
                }
            }
        }

        continuation?.yield(.cancelled)
        continuation?.finish()
    }

    /// Cancel a single task and its transitive dependents.
    ///
    /// - Parameter id: The task identifier to cancel.
    public func cancelTask(id: String) {
        guard let status = taskStatuses[id],
              status == .waiting || status == .ready else { return }

        taskStatuses[id] = .cancelled
        terminatedIds.insert(id)
        if var task = graph?.node(for: id) {
            task.status = .cancelled
            continuation?.yield(.taskCancelled(task))
        }

        // Cancel transitive dependents
        if let graph {
            let dependents = graph.transitiveDependents(of: id)
            for depId in dependents {
                guard taskStatuses[depId] == .waiting || taskStatuses[depId] == .ready else { continue }
                taskStatuses[depId] = .cancelled
                terminatedIds.insert(depId)
                if var depTask = graph.node(for: depId) {
                    depTask.status = .cancelled
                    continuation?.yield(.taskCancelled(depTask))
                }
            }
        }

        if isAllDone() {
            continuation?.yield(.allCompleted)
            continuation?.finish()
        }
    }

    // MARK: - Internal

    /// Emit taskReady events for all tasks whose dependencies are satisfied.
    private func emitReadyTasks() {
        guard let graph, !isCancelled else { return }

        let allTerminated = completedIds.union(terminatedIds)
        let readyIds = graph.readyNodes(completed: completedIds)

        // Filter to only tasks that are still waiting (not already ready/running/done)
        var readyTasks: [ScheduledTask] = []
        for id in readyIds {
            guard !allTerminated.contains(id) else { continue }
            if taskStatuses[id] == .waiting {
                taskStatuses[id] = .ready
                if var task = graph.node(for: id) {
                    task.status = .ready
                    readyTasks.append(task)
                }
            }
        }

        // Sort by priority (highest first) for deterministic ordering
        readyTasks.sort { $0.priority > $1.priority }

        for task in readyTasks {
            continuation?.yield(.taskReady(task))
        }
    }

    /// Check if all tasks have reached a terminal state.
    private func isAllDone() -> Bool {
        guard let graph else { return true }
        let terminalCount = completedIds.count + terminatedIds.count
        return terminalCount >= graph.nodeCount
    }
}
