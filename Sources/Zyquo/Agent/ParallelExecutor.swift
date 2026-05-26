import Foundation

// MARK: - ParallelEvent

/// Events emitted by the ParallelExecutor during concurrent task execution.
public enum ParallelEvent: Sendable {
    /// A task started execution.
    case started(taskId: String)
    /// A task completed with a result.
    case completed(taskId: String, result: SubTaskResult)
    /// A task failed with an error description.
    case failed(taskId: String, error: String)
    /// Progress update: how many completed, total count, and currently running.
    case progress(completed: Int, total: Int, running: Int)
}

// MARK: - ParallelExecutor

/// Executes tasks concurrently using Swift TaskGroup, respecting a
/// configurable concurrency limit.
///
/// The executor runs independent tasks in parallel. Cancellation of one
/// task does NOT cancel siblings -- only the `TaskScheduler` cancels
/// transitive dependents. Each task runs in its own child Task for
/// isolation.
///
/// Reference: CLAUDE.md §30 Phase 7
public actor ParallelExecutor {

    /// Maximum number of tasks to run concurrently.
    public let maxConcurrent: Int

    /// Whether the executor has been cancelled.
    private var isCancelled = false

    /// Creates a new parallel executor.
    ///
    /// - Parameter maxConcurrent: Maximum concurrent tasks. Defaults to
    ///   half the active processor count, minimum 2.
    public init(maxConcurrent: Int? = nil) {
        let cpuDefault = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        self.maxConcurrent = maxConcurrent ?? cpuDefault
    }

    // MARK: - Execution

    /// Execute a batch of tasks concurrently.
    ///
    /// Tasks are dispatched up to `maxConcurrent` at a time. Each task
    /// is executed by calling the provided `executor` closure.
    ///
    /// - Parameters:
    ///   - tasks: The tasks to execute.
    ///   - executor: A closure that executes a single task and returns its result.
    /// - Returns: An async stream of parallel execution events.
    public func execute(
        tasks: [ScheduledTask],
        executor: @Sendable @escaping (ScheduledTask) async throws -> SubTaskResult
    ) -> AsyncStream<ParallelEvent> {
        isCancelled = false

        return AsyncStream { [maxConcurrent] continuation in
            let taskList = tasks
            let concurrencyLimit = maxConcurrent

            Task {
                // Handle empty task list
                guard !taskList.isEmpty else {
                    continuation.yield(.progress(completed: 0, total: 0, running: 0))
                    continuation.finish()
                    return
                }

                // Use a resource limiter to cap concurrency
                let limiter = ResourceLimiter(maxConcurrentTasks: concurrencyLimit)

                let completedCount = CompletionCounter()
                let total = taskList.count

                await withTaskGroup(of: Void.self) { group in
                    for task in taskList {
                        group.addTask {
                            // Acquire a slot (blocks if at limit)
                            await limiter.acquire()

                            let running = await limiter.active
                            continuation.yield(.started(taskId: task.id))

                            let count = await completedCount.value
                            continuation.yield(.progress(
                                completed: count,
                                total: total,
                                running: running
                            ))

                            do {
                                let result = try await executor(task)
                                await completedCount.increment()
                                let newCount = await completedCount.value
                                continuation.yield(.completed(taskId: task.id, result: result))
                                await limiter.release()

                                let nowRunning = await limiter.active
                                continuation.yield(.progress(
                                    completed: newCount,
                                    total: total,
                                    running: nowRunning
                                ))
                            } catch {
                                await completedCount.increment()
                                let newCount = await completedCount.value
                                continuation.yield(.failed(taskId: task.id, error: error.localizedDescription))
                                await limiter.release()

                                let nowRunning = await limiter.active
                                continuation.yield(.progress(
                                    completed: newCount,
                                    total: total,
                                    running: nowRunning
                                ))
                            }
                        }
                    }

                    // Wait for all tasks to finish
                    await group.waitForAll()
                }

                continuation.finish()
            }
        }
    }

    /// Cancel all running tasks.
    public func cancel() {
        isCancelled = true
    }
}

// MARK: - CompletionCounter

/// Actor-isolated counter for tracking completed tasks.
private actor CompletionCounter {
    var value: Int = 0

    func increment() {
        value += 1
    }
}
