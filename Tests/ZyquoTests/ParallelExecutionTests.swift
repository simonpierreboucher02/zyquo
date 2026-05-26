import XCTest
@testable import Zyquo

// MARK: - Test Node

/// Simple identifiable node for testing DependencyGraph generics.
private struct TestNode: Sendable, Identifiable {
    let id: String
    let label: String

    init(id: String, label: String = "") {
        self.id = id
        self.label = label
    }
}

// MARK: - DependencyGraph Tests

final class DependencyGraphTests: XCTestCase {

    // 1. Add nodes and edges
    func testAddNodesAndEdges() {
        var graph = DependencyGraph<TestNode>()
        let a = TestNode(id: "A")
        let b = TestNode(id: "B")
        let c = TestNode(id: "C")

        graph.addNode(a)
        graph.addNode(b)
        graph.addNode(c)
        graph.addEdge(from: "A", to: "B") // A depends on B
        graph.addEdge(from: "A", to: "C") // A depends on C

        XCTAssertEqual(graph.nodeCount, 3)
        XCTAssertEqual(graph.edgeCount, 2)
        XCTAssertNotNil(graph.node(for: "A"))
        XCTAssertNotNil(graph.node(for: "B"))
        XCTAssertNotNil(graph.node(for: "C"))
    }

    // 2. Topological sort returns correct order
    func testTopologicalSortCorrectOrder() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "A"))
        graph.addNode(TestNode(id: "B"))
        graph.addNode(TestNode(id: "C"))
        graph.addNode(TestNode(id: "D"))

        // D -> C -> B -> A (A depends on B, B depends on C, C depends on D)
        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "B", to: "C")
        graph.addEdge(from: "C", to: "D")

        let sorted = graph.topologicalSort()
        XCTAssertNotNil(sorted)

        guard let order = sorted else { return }
        XCTAssertEqual(order.count, 4)

        // D must come before C, C before B, B before A
        let indexD = order.firstIndex(of: "D")!
        let indexC = order.firstIndex(of: "C")!
        let indexB = order.firstIndex(of: "B")!
        let indexA = order.firstIndex(of: "A")!

        XCTAssertLessThan(indexD, indexC)
        XCTAssertLessThan(indexC, indexB)
        XCTAssertLessThan(indexB, indexA)
    }

    // 3. Cycle detection
    func testCycleDetection() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "A"))
        graph.addNode(TestNode(id: "B"))
        graph.addNode(TestNode(id: "C"))

        // A -> B -> C -> A (cycle)
        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "B", to: "C")
        graph.addEdge(from: "C", to: "A")

        XCTAssertNil(graph.topologicalSort())
        XCTAssertTrue(graph.hasCycle())
    }

    // 4. Ready nodes with no deps completed = root nodes only
    func testReadyNodesRootsOnly() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "A"))
        graph.addNode(TestNode(id: "B"))
        graph.addNode(TestNode(id: "C"))

        // A depends on B, A depends on C. B and C are roots.
        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "A", to: "C")

        let ready = graph.readyNodes(completed: [])
        // B and C have no dependencies, so they are ready. A is not.
        XCTAssertTrue(ready.contains("B"))
        XCTAssertTrue(ready.contains("C"))
        XCTAssertFalse(ready.contains("A"))
    }

    // 5. Ready nodes updates as deps complete
    func testReadyNodesUpdatesWithCompletion() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "A"))
        graph.addNode(TestNode(id: "B"))
        graph.addNode(TestNode(id: "C"))

        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "A", to: "C")

        // Initially: B and C are ready
        let ready1 = graph.readyNodes(completed: [])
        XCTAssertFalse(ready1.contains("A"))

        // After B completes: still not ready (C not done)
        let ready2 = graph.readyNodes(completed: ["B"])
        XCTAssertFalse(ready2.contains("A"))
        // C is still ready (not completed yet)
        XCTAssertTrue(ready2.contains("C"))

        // After B and C complete: A is now ready
        let ready3 = graph.readyNodes(completed: ["B", "C"])
        XCTAssertTrue(ready3.contains("A"))
    }

    // 6. Empty graph
    func testEmptyGraph() {
        let graph = DependencyGraph<TestNode>()
        XCTAssertEqual(graph.nodeCount, 0)
        XCTAssertEqual(graph.edgeCount, 0)
        XCTAssertTrue(graph.allNodes.isEmpty)
        XCTAssertFalse(graph.hasCycle())

        let sorted = graph.topologicalSort()
        XCTAssertNotNil(sorted)
        XCTAssertEqual(sorted?.count, 0)

        let ready = graph.readyNodes(completed: [])
        XCTAssertTrue(ready.isEmpty)
    }

    // 7. Single node
    func testSingleNode() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "solo"))

        XCTAssertEqual(graph.nodeCount, 1)
        XCTAssertEqual(graph.edgeCount, 0)
        XCTAssertFalse(graph.hasCycle())

        let sorted = graph.topologicalSort()
        XCTAssertEqual(sorted, ["solo"])

        let ready = graph.readyNodes(completed: [])
        XCTAssertEqual(ready, ["solo"])

        let readyAfter = graph.readyNodes(completed: ["solo"])
        XCTAssertTrue(readyAfter.isEmpty)
    }

    // 8. Diamond dependency
    func testDiamondDependency() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "A")) // top
        graph.addNode(TestNode(id: "B")) // left
        graph.addNode(TestNode(id: "C")) // right
        graph.addNode(TestNode(id: "D")) // bottom

        // A depends on B and C; B and C both depend on D
        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "A", to: "C")
        graph.addEdge(from: "B", to: "D")
        graph.addEdge(from: "C", to: "D")

        XCTAssertFalse(graph.hasCycle())
        XCTAssertEqual(graph.edgeCount, 4)

        let sorted = graph.topologicalSort()
        XCTAssertNotNil(sorted)
        guard let order = sorted else { return }

        // D must come first, A must come last
        let indexD = order.firstIndex(of: "D")!
        let indexB = order.firstIndex(of: "B")!
        let indexC = order.firstIndex(of: "C")!
        let indexA = order.firstIndex(of: "A")!

        XCTAssertLessThan(indexD, indexB)
        XCTAssertLessThan(indexD, indexC)
        XCTAssertLessThan(indexB, indexA)
        XCTAssertLessThan(indexC, indexA)

        // Initially only D is ready
        let ready0 = graph.readyNodes(completed: [])
        XCTAssertEqual(ready0, ["D"])

        // After D: B and C are ready
        let ready1 = graph.readyNodes(completed: ["D"])
        XCTAssertTrue(ready1.contains("B"))
        XCTAssertTrue(ready1.contains("C"))
        XCTAssertFalse(ready1.contains("A"))

        // After D, B, C: A is ready
        let ready2 = graph.readyNodes(completed: ["D", "B", "C"])
        XCTAssertEqual(ready2, ["A"])
    }

    // 9. Dependencies and dependents lookup
    func testDependenciesAndDependentsLookup() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "A"))
        graph.addNode(TestNode(id: "B"))
        graph.addNode(TestNode(id: "C"))

        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "A", to: "C")

        let deps = graph.dependencies(of: "A")
        XCTAssertEqual(Set(deps), Set(["B", "C"]))

        let deptsOfB = graph.dependents(of: "B")
        XCTAssertEqual(deptsOfB, ["A"])

        let deptsOfC = graph.dependents(of: "C")
        XCTAssertEqual(deptsOfC, ["A"])

        // A has no dependents
        XCTAssertTrue(graph.dependents(of: "A").isEmpty)

        // B and C have no dependencies
        XCTAssertTrue(graph.dependencies(of: "B").isEmpty)
        XCTAssertTrue(graph.dependencies(of: "C").isEmpty)
    }

    // 10. Node count and edge count
    func testNodeCountAndEdgeCount() {
        var graph = DependencyGraph<TestNode>()
        XCTAssertEqual(graph.nodeCount, 0)
        XCTAssertEqual(graph.edgeCount, 0)

        graph.addNode(TestNode(id: "X"))
        XCTAssertEqual(graph.nodeCount, 1)
        XCTAssertEqual(graph.edgeCount, 0)

        graph.addNode(TestNode(id: "Y"))
        graph.addNode(TestNode(id: "Z"))
        graph.addEdge(from: "X", to: "Y")
        graph.addEdge(from: "X", to: "Z")
        graph.addEdge(from: "Y", to: "Z")

        XCTAssertEqual(graph.nodeCount, 3)
        XCTAssertEqual(graph.edgeCount, 3)
    }

    // 11. Transitive dependents
    func testTransitiveDependents() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "A"))
        graph.addNode(TestNode(id: "B"))
        graph.addNode(TestNode(id: "C"))
        graph.addNode(TestNode(id: "D"))

        // Chain: D <- C <- B <- A
        graph.addEdge(from: "A", to: "B")
        graph.addEdge(from: "B", to: "C")
        graph.addEdge(from: "C", to: "D")

        let transitive = graph.transitiveDependents(of: "D")
        XCTAssertEqual(transitive, Set(["C", "B", "A"]))

        let transitiveC = graph.transitiveDependents(of: "C")
        XCTAssertEqual(transitiveC, Set(["B", "A"]))

        let transitiveA = graph.transitiveDependents(of: "A")
        XCTAssertTrue(transitiveA.isEmpty)
    }

    // 12. Node lookup returns nil for missing ID
    func testNodeLookupMissing() {
        let graph = DependencyGraph<TestNode>()
        XCTAssertNil(graph.node(for: "nonexistent"))
    }

    // 13. Adding duplicate node replaces value
    func testDuplicateNodeReplacesValue() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "A", label: "first"))
        graph.addNode(TestNode(id: "A", label: "second"))

        XCTAssertEqual(graph.nodeCount, 1) // still one node
        XCTAssertEqual(graph.node(for: "A")?.label, "second")
    }

    // 14. No cycle in acyclic graph
    func testNoCycleInAcyclicGraph() {
        var graph = DependencyGraph<TestNode>()
        graph.addNode(TestNode(id: "1"))
        graph.addNode(TestNode(id: "2"))
        graph.addNode(TestNode(id: "3"))
        graph.addNode(TestNode(id: "4"))

        graph.addEdge(from: "1", to: "2")
        graph.addEdge(from: "1", to: "3")
        graph.addEdge(from: "2", to: "4")
        graph.addEdge(from: "3", to: "4")

        XCTAssertFalse(graph.hasCycle())
    }
}

// MARK: - TaskScheduler Tests

final class TaskSchedulerTests: XCTestCase {

    private func makeScheduledTask(id: String, priority: TaskPriority = .normal) -> ScheduledTask {
        let subtask = SubTask(
            id: id,
            agentType: "coder",
            goal: "Task \(id)",
            successCriteria: "completes"
        )
        return ScheduledTask(id: id, subtask: subtask, priority: priority)
    }

    // 1. Schedule independent tasks (all become ready)
    func testScheduleIndependentTasks() async {
        let scheduler = TaskScheduler()

        var graph = DependencyGraph<ScheduledTask>()
        graph.addNode(makeScheduledTask(id: "t1"))
        graph.addNode(makeScheduledTask(id: "t2"))
        graph.addNode(makeScheduledTask(id: "t3"))

        let stream = await scheduler.schedule(graph: graph)

        var readyIds: [String] = []
        for await event in stream {
            switch event {
            case .taskReady(let task):
                readyIds.append(task.id)
                // Report each as completed immediately
                await scheduler.reportStarted(id: task.id)
                await scheduler.reportCompleted(id: task.id)
            case .allCompleted:
                break
            default:
                break
            }
        }

        XCTAssertEqual(Set(readyIds), Set(["t1", "t2", "t3"]))
    }

    // 2. Schedule with dependencies (respects order)
    func testScheduleWithDependencies() async {
        let scheduler = TaskScheduler()

        var graph = DependencyGraph<ScheduledTask>()
        graph.addNode(makeScheduledTask(id: "base"))
        graph.addNode(makeScheduledTask(id: "dependent"))
        graph.addEdge(from: "dependent", to: "base")

        let stream = await scheduler.schedule(graph: graph)

        var readyOrder: [String] = []
        for await event in stream {
            switch event {
            case .taskReady(let task):
                readyOrder.append(task.id)
                await scheduler.reportStarted(id: task.id)
                await scheduler.reportCompleted(id: task.id)
            case .allCompleted:
                break
            default:
                break
            }
        }

        // "base" must become ready before "dependent"
        XCTAssertEqual(readyOrder.count, 2)
        XCTAssertEqual(readyOrder[0], "base")
        XCTAssertEqual(readyOrder[1], "dependent")
    }

    // 3. Cancel propagates to pending tasks
    func testCancelPropagates() async {
        let scheduler = TaskScheduler()

        var graph = DependencyGraph<ScheduledTask>()
        graph.addNode(makeScheduledTask(id: "root"))
        graph.addNode(makeScheduledTask(id: "child"))
        graph.addEdge(from: "child", to: "root")

        let stream = await scheduler.schedule(graph: graph)

        var sawCancelled = false
        var sawCancelledEvent = false

        for await event in stream {
            switch event {
            case .taskReady(let task):
                if task.id == "root" {
                    // Cancel the whole schedule instead of completing root
                    await scheduler.cancel()
                }
            case .taskCancelled(let task):
                if task.id == "child" {
                    sawCancelled = true
                }
            case .cancelled:
                sawCancelledEvent = true
            default:
                break
            }
        }

        XCTAssertTrue(sawCancelled, "Child task should have been cancelled")
        XCTAssertTrue(sawCancelledEvent, "Should have received cancelled event")
    }

    // 4. Priority ordering (higher priority first among ready)
    func testPriorityOrdering() async {
        let scheduler = TaskScheduler()

        var graph = DependencyGraph<ScheduledTask>()
        graph.addNode(makeScheduledTask(id: "low", priority: .low))
        graph.addNode(makeScheduledTask(id: "high", priority: .high))
        graph.addNode(makeScheduledTask(id: "critical", priority: .critical))
        graph.addNode(makeScheduledTask(id: "normal", priority: .normal))

        let stream = await scheduler.schedule(graph: graph)

        var readyOrder: [String] = []
        for await event in stream {
            switch event {
            case .taskReady(let task):
                readyOrder.append(task.id)
                await scheduler.reportStarted(id: task.id)
                await scheduler.reportCompleted(id: task.id)
            case .allCompleted:
                break
            default:
                break
            }
        }

        // Since all are independent, they should all become ready at once,
        // ordered by priority: critical, high, normal, low
        XCTAssertEqual(readyOrder.count, 4)
        XCTAssertEqual(readyOrder[0], "critical")
        XCTAssertEqual(readyOrder[1], "high")
        XCTAssertEqual(readyOrder[2], "normal")
        XCTAssertEqual(readyOrder[3], "low")
    }

    // 5. Empty graph produces allCompleted immediately
    func testEmptyGraphCompletesImmediately() async {
        let scheduler = TaskScheduler()
        let graph = DependencyGraph<ScheduledTask>()
        let stream = await scheduler.schedule(graph: graph)

        var events: [String] = []
        for await event in stream {
            switch event {
            case .allCompleted:
                events.append("allCompleted")
            default:
                events.append("other")
            }
        }

        XCTAssertEqual(events, ["allCompleted"])
    }

    // 6. Failed task cancels dependents
    func testFailedTaskCancelsDependents() async {
        let scheduler = TaskScheduler()

        var graph = DependencyGraph<ScheduledTask>()
        graph.addNode(makeScheduledTask(id: "root"))
        graph.addNode(makeScheduledTask(id: "child1"))
        graph.addNode(makeScheduledTask(id: "grandchild"))
        graph.addEdge(from: "child1", to: "root")
        graph.addEdge(from: "grandchild", to: "child1")

        let stream = await scheduler.schedule(graph: graph)

        var cancelledIds: Set<String> = []
        for await event in stream {
            switch event {
            case .taskReady(let task):
                if task.id == "root" {
                    await scheduler.reportStarted(id: task.id)
                    await scheduler.reportFailed(id: task.id, error: "test error")
                }
            case .taskCancelled(let task):
                cancelledIds.insert(task.id)
            default:
                break
            }
        }

        XCTAssertTrue(cancelledIds.contains("child1"), "child1 should be cancelled")
        XCTAssertTrue(cancelledIds.contains("grandchild"), "grandchild should be cancelled")
    }

    // 7. CancelTask cancels a single task and dependents
    func testCancelSingleTask() async {
        let scheduler = TaskScheduler()

        var graph = DependencyGraph<ScheduledTask>()
        graph.addNode(makeScheduledTask(id: "a"))
        graph.addNode(makeScheduledTask(id: "b"))
        graph.addNode(makeScheduledTask(id: "c"))
        graph.addEdge(from: "c", to: "b")

        let stream = await scheduler.schedule(graph: graph)

        var cancelledIds: Set<String> = []
        var completedIds: Set<String> = []

        for await event in stream {
            switch event {
            case .taskReady(let task):
                if task.id == "a" {
                    await scheduler.reportStarted(id: task.id)
                    await scheduler.reportCompleted(id: task.id)
                } else if task.id == "b" {
                    // Cancel b instead of running it
                    await scheduler.cancelTask(id: task.id)
                }
            case .taskCompleted(let task):
                completedIds.insert(task.id)
            case .taskCancelled(let task):
                cancelledIds.insert(task.id)
            default:
                break
            }
        }

        XCTAssertTrue(completedIds.contains("a"))
        XCTAssertTrue(cancelledIds.contains("b"))
        XCTAssertTrue(cancelledIds.contains("c"), "c depends on b, should also be cancelled")
    }
}

// MARK: - ParallelExecutor Tests

final class ParallelExecutorTests: XCTestCase {

    private func makeScheduledTask(id: String) -> ScheduledTask {
        let subtask = SubTask(
            id: id,
            agentType: "coder",
            goal: "Task \(id)",
            successCriteria: "completes"
        )
        return ScheduledTask(id: id, subtask: subtask)
    }

    // 1. Execute independent tasks concurrently (wall time < sequential)
    func testConcurrentExecutionFasterThanSequential() async {
        let executor = ParallelExecutor(maxConcurrent: 4)

        let tasks = (1...4).map { makeScheduledTask(id: "t\($0)") }

        let start = Date()
        let stream = await executor.execute(tasks: tasks) { _ in
            // Each task takes ~100ms
            try await Task.sleep(nanoseconds: 100_000_000)
            return SubTaskResult(summary: "done")
        }

        var completedCount = 0
        for await event in stream {
            if case .completed = event {
                completedCount += 1
            }
        }

        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(completedCount, 4)
        // If running sequentially, 4 * 100ms = 400ms minimum.
        // With concurrency, should complete in ~100-200ms.
        XCTAssertLessThan(elapsed, 0.35, "Concurrent execution should be faster than sequential")
    }

    // 2. Max concurrent limit enforced
    func testMaxConcurrentLimitEnforced() async {
        let executor = ParallelExecutor(maxConcurrent: 2)
        let peakTracker = PeakConcurrencyTracker()

        let tasks = (1...6).map { makeScheduledTask(id: "t\($0)") }

        let stream = await executor.execute(tasks: tasks) { [peakTracker] _ in
            await peakTracker.enter()
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await peakTracker.exit()
            return SubTaskResult(summary: "done")
        }

        for await _ in stream {}

        let peak = await peakTracker.peak
        XCTAssertLessThanOrEqual(peak, 2, "Should never exceed maxConcurrent=2")
    }

    // 3. Failed task doesn't cancel siblings
    func testFailedTaskDoesNotCancelSiblings() async {
        let executor = ParallelExecutor(maxConcurrent: 4)

        let tasks = (1...3).map { makeScheduledTask(id: "t\($0)") }

        var completedIds: Set<String> = []
        var failedIds: Set<String> = []

        let stream = await executor.execute(tasks: tasks) { task in
            if task.id == "t2" {
                throw TestError.intentional
            }
            return SubTaskResult(summary: "done")
        }

        for await event in stream {
            switch event {
            case .completed(let taskId, _):
                completedIds.insert(taskId)
            case .failed(let taskId, _):
                failedIds.insert(taskId)
            default:
                break
            }
        }

        XCTAssertTrue(failedIds.contains("t2"))
        XCTAssertTrue(completedIds.contains("t1"))
        XCTAssertTrue(completedIds.contains("t3"))
    }

    // 4. Progress events emitted correctly
    func testProgressEventsEmitted() async {
        let executor = ParallelExecutor(maxConcurrent: 4)

        let tasks = (1...3).map { makeScheduledTask(id: "t\($0)") }

        var progressEvents: [(completed: Int, total: Int)] = []

        let stream = await executor.execute(tasks: tasks) { _ in
            return SubTaskResult(summary: "done")
        }

        for await event in stream {
            if case .progress(let completed, let total, _) = event {
                progressEvents.append((completed, total))
            }
        }

        // Should have received progress events
        XCTAssertGreaterThan(progressEvents.count, 0)

        // All totals should be 3
        for p in progressEvents {
            XCTAssertEqual(p.total, 3)
        }

        // The maximum completed count seen should be 3
        // (individual events may arrive out of order in concurrent execution)
        let maxCompleted = progressEvents.map(\.completed).max() ?? 0
        XCTAssertEqual(maxCompleted, 3)
    }

    // 5. Empty task list completes immediately
    func testEmptyTaskListCompletesImmediately() async {
        let executor = ParallelExecutor(maxConcurrent: 4)
        let tasks: [ScheduledTask] = []

        var events: [String] = []

        let stream = await executor.execute(tasks: tasks) { _ in
            return SubTaskResult(summary: "done")
        }

        for await event in stream {
            switch event {
            case .progress:
                events.append("progress")
            default:
                events.append("other")
            }
        }

        // Should get at least one progress event for the empty case
        XCTAssertTrue(events.contains("progress"))
    }

    // 6. Started events emitted for each task
    func testStartedEventsEmitted() async {
        let executor = ParallelExecutor(maxConcurrent: 4)
        let tasks = (1...3).map { makeScheduledTask(id: "t\($0)") }

        var startedIds: Set<String> = []

        let stream = await executor.execute(tasks: tasks) { _ in
            return SubTaskResult(summary: "done")
        }

        for await event in stream {
            if case .started(let taskId) = event {
                startedIds.insert(taskId)
            }
        }

        XCTAssertEqual(startedIds, Set(["t1", "t2", "t3"]))
    }
}

// MARK: - ConflictDetector Tests

final class ConflictDetectorTests: XCTestCase {

    // 1. No conflict when tasks touch different files
    func testNoConflictDifferentFiles() {
        let results: [(taskId: String, agentType: String, filesModified: [String])] = [
            (taskId: "t1", agentType: "coder", filesModified: ["Sources/A.swift"]),
            (taskId: "t2", agentType: "shell", filesModified: ["Sources/B.swift"]),
            (taskId: "t3", agentType: "verifier", filesModified: ["Tests/C.swift"]),
        ]

        let conflicts = ConflictDetector.detect(results: results)
        XCTAssertTrue(conflicts.isEmpty)
    }

    // 2. Conflict detected when two tasks modify same file
    func testConflictSameFile() {
        let results: [(taskId: String, agentType: String, filesModified: [String])] = [
            (taskId: "t1", agentType: "coder", filesModified: ["Sources/Config.swift"]),
            (taskId: "t2", agentType: "shell", filesModified: ["Sources/Config.swift"]),
        ]

        let conflicts = ConflictDetector.detect(results: results)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].filePath, "Sources/Config.swift")
        XCTAssertEqual(conflicts[0].taskIds, ["t1", "t2"])
        XCTAssertTrue(conflicts[0].agentTypes.contains("coder"))
        XCTAssertTrue(conflicts[0].agentTypes.contains("shell"))
    }

    // 3. Multiple conflicts reported
    func testMultipleConflicts() {
        let results: [(taskId: String, agentType: String, filesModified: [String])] = [
            (taskId: "t1", agentType: "coder", filesModified: ["Sources/A.swift", "Sources/B.swift"]),
            (taskId: "t2", agentType: "shell", filesModified: ["Sources/A.swift", "Sources/C.swift"]),
            (taskId: "t3", agentType: "verifier", filesModified: ["Sources/B.swift", "Sources/C.swift"]),
        ]

        let conflicts = ConflictDetector.detect(results: results)
        XCTAssertEqual(conflicts.count, 3)

        let conflictedFiles = Set(conflicts.map(\.filePath))
        XCTAssertTrue(conflictedFiles.contains("Sources/A.swift"))
        XCTAssertTrue(conflictedFiles.contains("Sources/B.swift"))
        XCTAssertTrue(conflictedFiles.contains("Sources/C.swift"))
    }

    // 4. Three tasks touching same file
    func testThreeTasksSameFile() {
        let results: [(taskId: String, agentType: String, filesModified: [String])] = [
            (taskId: "t1", agentType: "coder", filesModified: ["Sources/Main.swift"]),
            (taskId: "t2", agentType: "shell", filesModified: ["Sources/Main.swift"]),
            (taskId: "t3", agentType: "reviewer", filesModified: ["Sources/Main.swift"]),
        ]

        let conflicts = ConflictDetector.detect(results: results)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].taskIds.count, 3)
    }

    // 5. No files modified means no conflicts
    func testNoFilesNoConflicts() {
        let results: [(taskId: String, agentType: String, filesModified: [String])] = [
            (taskId: "t1", agentType: "coder", filesModified: []),
            (taskId: "t2", agentType: "shell", filesModified: []),
        ]

        let conflicts = ConflictDetector.detect(results: results)
        XCTAssertTrue(conflicts.isEmpty)
    }

    // 6. Conflict description mentions agent types
    func testConflictDescriptionContent() {
        let results: [(taskId: String, agentType: String, filesModified: [String])] = [
            (taskId: "t1", agentType: "coder", filesModified: ["file.txt"]),
            (taskId: "t2", agentType: "shell", filesModified: ["file.txt"]),
        ]

        let conflicts = ConflictDetector.detect(results: results)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertTrue(conflicts[0].description.contains("file.txt"))
    }
}

// MARK: - ResourceLimiter Tests

final class ResourceLimiterTests: XCTestCase {

    // 1. Acquire and release
    func testAcquireAndRelease() async {
        let limiter = ResourceLimiter(maxConcurrentTasks: 3)

        await limiter.acquire()
        var active = await limiter.active
        XCTAssertEqual(active, 1)

        await limiter.acquire()
        active = await limiter.active
        XCTAssertEqual(active, 2)

        await limiter.release()
        active = await limiter.active
        XCTAssertEqual(active, 1)

        await limiter.release()
        active = await limiter.active
        XCTAssertEqual(active, 0)
    }

    // 2. Available count tracks correctly
    func testAvailableCountTracksCorrectly() async {
        let limiter = ResourceLimiter(maxConcurrentTasks: 3)

        var available = await limiter.available
        XCTAssertEqual(available, 3)

        await limiter.acquire()
        available = await limiter.available
        XCTAssertEqual(available, 2)

        await limiter.acquire()
        available = await limiter.available
        XCTAssertEqual(available, 1)

        await limiter.acquire()
        available = await limiter.available
        XCTAssertEqual(available, 0)

        await limiter.release()
        available = await limiter.available
        XCTAssertEqual(available, 1)
    }

    // 3. Default max from processor count
    func testDefaultMaxFromProcessorCount() async {
        let limiter = ResourceLimiter()
        let expected = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        let maxTasks = await limiter.maxConcurrentTasks
        XCTAssertEqual(maxTasks, expected)
    }

    // 4. Release never goes below zero
    func testReleaseNeverBelowZero() async {
        let limiter = ResourceLimiter(maxConcurrentTasks: 2)

        // Release without acquire
        await limiter.release()
        let active = await limiter.active
        XCTAssertEqual(active, 0)
    }

    // 5. Acquire blocks when at limit
    func testAcquireBlocksWhenAtLimit() async {
        let limiter = ResourceLimiter(maxConcurrentTasks: 1)

        // Acquire the single slot
        await limiter.acquire()
        let active = await limiter.active
        XCTAssertEqual(active, 1)

        // Start a task that will try to acquire (should block)
        let acquired = WaitFlag()

        Task {
            await limiter.acquire()
            await acquired.set()
        }

        // Give the task a moment to start
        try? await Task.sleep(nanoseconds: 50_000_000)

        // It should NOT have acquired yet
        let didAcquire = await acquired.value
        XCTAssertFalse(didAcquire, "Should be blocked waiting for a slot")

        // Release the slot
        await limiter.release()

        // Give the blocked task time to proceed
        try? await Task.sleep(nanoseconds: 50_000_000)

        let didAcquireNow = await acquired.value
        XCTAssertTrue(didAcquireNow, "Should have acquired after release")
    }
}

// MARK: - TaskPriority Tests

final class TaskPriorityTests: XCTestCase {

    func testPriorityOrdering() {
        XCTAssertLessThan(TaskPriority.low, TaskPriority.normal)
        XCTAssertLessThan(TaskPriority.normal, TaskPriority.high)
        XCTAssertLessThan(TaskPriority.high, TaskPriority.critical)
    }

    func testPriorityRawValues() {
        XCTAssertEqual(TaskPriority.low.rawValue, 0)
        XCTAssertEqual(TaskPriority.normal.rawValue, 1)
        XCTAssertEqual(TaskPriority.high.rawValue, 2)
        XCTAssertEqual(TaskPriority.critical.rawValue, 3)
    }
}

// MARK: - ScheduledTask Tests

final class ScheduledTaskTests: XCTestCase {

    func testScheduledTaskCreation() {
        let subtask = SubTask(id: "st1", agentType: "coder", goal: "fix bug", successCriteria: "works")
        let scheduled = ScheduledTask(id: "st1", subtask: subtask, priority: .high)

        XCTAssertEqual(scheduled.id, "st1")
        XCTAssertEqual(scheduled.priority, .high)
        XCTAssertEqual(scheduled.status, .waiting)
        XCTAssertEqual(scheduled.subtask.agentType, "coder")
    }

    func testScheduledTaskDefaultPriority() {
        let subtask = SubTask(id: "st2", agentType: "shell", goal: "build", successCriteria: "ok")
        let scheduled = ScheduledTask(id: "st2", subtask: subtask)

        XCTAssertEqual(scheduled.priority, .normal)
        XCTAssertEqual(scheduled.status, .waiting)
    }

    func testScheduledTaskStatusValues() {
        XCTAssertEqual(ScheduledTaskStatus.waiting.rawValue, "waiting")
        XCTAssertEqual(ScheduledTaskStatus.ready.rawValue, "ready")
        XCTAssertEqual(ScheduledTaskStatus.running.rawValue, "running")
        XCTAssertEqual(ScheduledTaskStatus.completed.rawValue, "completed")
        XCTAssertEqual(ScheduledTaskStatus.failed.rawValue, "failed")
        XCTAssertEqual(ScheduledTaskStatus.cancelled.rawValue, "cancelled")
    }
}

// MARK: - ParallelConflict Tests

final class ParallelConflictTests: XCTestCase {

    func testParallelConflictCreation() {
        let conflict = ParallelConflict(
            filePath: "Sources/Auth.swift",
            taskIds: ["t1", "t2"],
            agentTypes: ["coder", "shell"],
            description: "Both modified Auth.swift"
        )

        XCTAssertEqual(conflict.filePath, "Sources/Auth.swift")
        XCTAssertEqual(conflict.taskIds.count, 2)
        XCTAssertEqual(conflict.agentTypes.count, 2)
        XCTAssertTrue(conflict.description.contains("Auth.swift"))
    }
}

// MARK: - Test Helpers

private enum TestError: Error {
    case intentional
}

/// Tracks peak concurrency for testing maxConcurrent enforcement.
private actor PeakConcurrencyTracker {
    var current: Int = 0
    var peak: Int = 0

    func enter() {
        current += 1
        if current > peak {
            peak = current
        }
    }

    func exit() {
        current -= 1
    }
}

/// Simple flag for async coordination in tests.
private actor WaitFlag {
    var value: Bool = false

    func set() {
        value = true
    }
}
