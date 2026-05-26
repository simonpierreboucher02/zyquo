import XCTest
@testable import Zyquo

// MARK: - NodeInfo Tests

final class NodeInfoTests: XCTestCase {

    // 1. NodeInfo creation and encoding/decoding round-trip
    func testNodeInfoCodableRoundTrip() throws {
        let node = NodeInfo(
            id: "M3U96a",
            hostname: "M3U96a",
            fqdn: "M3U96a.maclustr.io",
            cores: 32,
            memoryGB: 96,
            model: "Mac Studio",
            status: .online,
            capabilities: NodeCapabilities(
                hasGPU: true,
                swiftVersion: "5.10",
                availableDiskGB: 500,
                architecture: "arm64"
            )
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(node)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NodeInfo.self, from: data)

        XCTAssertEqual(decoded.id, "M3U96a")
        XCTAssertEqual(decoded.hostname, "M3U96a")
        XCTAssertEqual(decoded.fqdn, "M3U96a.maclustr.io")
        XCTAssertEqual(decoded.cores, 32)
        XCTAssertEqual(decoded.memoryGB, 96)
        XCTAssertEqual(decoded.model, "Mac Studio")
        XCTAssertEqual(decoded.status, .online)
        XCTAssertEqual(decoded.capabilities.hasGPU, true)
        XCTAssertEqual(decoded.capabilities.swiftVersion, "5.10")
        XCTAssertEqual(decoded.capabilities.availableDiskGB, 500)
        XCTAssertEqual(decoded.capabilities.architecture, "arm64")
    }

    // 2. NodeStatus transitions (all cases)
    func testNodeStatusAllCases() {
        let allCases: [NodeStatus] = [.online, .offline, .busy, .draining, .unknown]
        XCTAssertEqual(NodeStatus.allCases.count, 5)
        for status in allCases {
            XCTAssertTrue(NodeStatus.allCases.contains(status))
        }
    }

    // 3. NodeCapabilities default values and properties
    func testNodeCapabilitiesDefaults() {
        let caps = NodeCapabilities()
        XCTAssertTrue(caps.hasGPU)
        XCTAssertNil(caps.swiftVersion)
        XCTAssertEqual(caps.availableDiskGB, 0)
        XCTAssertEqual(caps.architecture, "arm64")
    }

    // 4. NodeInfo equality check
    func testNodeInfoEquality() {
        let date = Date()
        let caps = NodeCapabilities(hasGPU: true, swiftVersion: "5.10", availableDiskGB: 200, architecture: "arm64")
        let node1 = NodeInfo(id: "A", hostname: "A", cores: 8, memoryGB: 16, model: "Mac mini",
                             status: .online, lastSeen: date, capabilities: caps)
        let node2 = NodeInfo(id: "A", hostname: "A", cores: 8, memoryGB: 16, model: "Mac mini",
                             status: .online, lastSeen: date, capabilities: caps)

        XCTAssertEqual(node1, node2)
    }

    // 5. NodeInfo isAvailable property
    func testNodeInfoIsAvailable() {
        var node = NodeInfo(id: "X", hostname: "X", cores: 4, memoryGB: 8, model: "Test")
        node.status = .online
        XCTAssertTrue(node.isAvailable)

        node.status = .busy
        XCTAssertFalse(node.isAvailable)

        node.status = .offline
        XCTAssertFalse(node.isAvailable)

        node.status = .draining
        XCTAssertFalse(node.isAvailable)

        node.status = .unknown
        XCTAssertFalse(node.isAvailable)
    }

    // 6. NodeInfo summaryLine format
    func testNodeInfoSummaryLine() {
        let node = NodeInfo(id: "M3U96a", hostname: "M3U96a", cores: 32, memoryGB: 96,
                            model: "Mac Studio", status: .online)
        let line = node.summaryLine
        XCTAssertTrue(line.contains("M3U96a"))
        XCTAssertTrue(line.contains("32"))
        XCTAssertTrue(line.contains("96 GB"))
        XCTAssertTrue(line.contains("Mac Studio"))
    }
}

// MARK: - ClusterState Tests

final class ClusterStateTests: XCTestCase {

    private func makeNode(id: String, cores: Int = 8, memoryGB: Int = 16, status: NodeStatus = .online) -> NodeInfo {
        NodeInfo(id: id, hostname: id, cores: cores, memoryGB: memoryGB,
                 model: "Test", status: status)
    }

    // 1. Add and list nodes
    func testAddAndListNodes() async {
        let state = ClusterState()
        await state.addNode(makeNode(id: "A"))
        await state.addNode(makeNode(id: "B"))
        await state.addNode(makeNode(id: "C"))

        let all = await state.allNodes()
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.map(\.id), ["A", "B", "C"])
    }

    // 2. Remove node
    func testRemoveNode() async {
        let state = ClusterState()
        await state.addNode(makeNode(id: "A"))
        await state.addNode(makeNode(id: "B"))
        await state.addNode(makeNode(id: "C"))

        await state.removeNode(id: "B")

        let all = await state.allNodes()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.map(\.id), ["A", "C"])
        let removed = await state.node(id: "B")
        XCTAssertNil(removed)
    }

    // 3. Update node status
    func testUpdateNodeStatus() async {
        let state = ClusterState()
        await state.addNode(makeNode(id: "A", status: .unknown))

        await state.updateNode(id: "A", status: .online)
        let node = await state.node(id: "A")
        XCTAssertEqual(node?.status, .online)

        await state.updateNode(id: "A", status: .offline)
        let updated = await state.node(id: "A")
        XCTAssertEqual(updated?.status, .offline)
    }

    // 4. Online nodes filter
    func testOnlineNodesFilter() async {
        let state = ClusterState()
        await state.addNode(makeNode(id: "A", status: .online))
        await state.addNode(makeNode(id: "B", status: .offline))
        await state.addNode(makeNode(id: "C", status: .online))
        await state.addNode(makeNode(id: "D", status: .busy))

        let online = await state.onlineNodes()
        XCTAssertEqual(online.count, 2)
        XCTAssertEqual(Set(online.map(\.id)), Set(["A", "C"]))
    }

    // 5. Total cores and memory calculation
    func testTotalCoresAndMemory() async {
        let state = ClusterState()
        await state.addNode(makeNode(id: "A", cores: 32, memoryGB: 96))
        await state.addNode(makeNode(id: "B", cores: 16, memoryGB: 64))
        await state.addNode(makeNode(id: "C", cores: 8, memoryGB: 24))

        let totalCores = await state.totalCores()
        XCTAssertEqual(totalCores, 56)

        let totalMemory = await state.totalMemoryGB()
        XCTAssertEqual(totalMemory, 184)
    }

    // 6. Node count and online count
    func testNodeCountAndOnlineCount() async {
        let state = ClusterState()
        await state.addNode(makeNode(id: "A", status: .online))
        await state.addNode(makeNode(id: "B", status: .offline))
        await state.addNode(makeNode(id: "C", status: .online))

        let count = await state.nodeCount
        XCTAssertEqual(count, 3)

        let onlineCount = await state.onlineCount
        XCTAssertEqual(onlineCount, 2)
    }

    // 7. Initialize with pre-populated nodes
    func testInitWithNodes() async {
        let nodes = [
            makeNode(id: "X", cores: 10),
            makeNode(id: "Y", cores: 20),
        ]
        let state = ClusterState(nodes: nodes)

        let all = await state.allNodes()
        XCTAssertEqual(all.count, 2)
        let total = await state.totalCores()
        XCTAssertEqual(total, 30)
    }

    // 8. Replace existing node
    func testReplaceExistingNode() async {
        let state = ClusterState()
        await state.addNode(makeNode(id: "A", cores: 8))
        await state.addNode(makeNode(id: "A", cores: 16))

        let all = await state.allNodes()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.cores, 16)
    }

    // 9. Online cores and memory
    func testOnlineCoresAndMemory() async {
        let state = ClusterState()
        await state.addNode(makeNode(id: "A", cores: 32, memoryGB: 96, status: .online))
        await state.addNode(makeNode(id: "B", cores: 16, memoryGB: 64, status: .offline))
        await state.addNode(makeNode(id: "C", cores: 8, memoryGB: 24, status: .online))

        let onlineCores = await state.onlineCores()
        XCTAssertEqual(onlineCores, 40)

        let onlineMemory = await state.onlineMemoryGB()
        XCTAssertEqual(onlineMemory, 120)
    }
}

// MARK: - ClusterScheduler Tests

final class ClusterSchedulerTests: XCTestCase {

    private func makeNode(id: String, cores: Int) -> NodeInfo {
        NodeInfo(id: id, hostname: id, cores: cores, memoryGB: cores * 3,
                 model: "Test", status: .online)
    }

    private func makeTask(id: String = UUID().uuidString) -> SubTask {
        SubTask(
            id: id,
            agentType: "coder",
            goal: "Task \(id)",
            successCriteria: "Done"
        )
    }

    // 1. Proportional distribution assigns more tasks to nodes with more cores
    func testProportionalDistribution() {
        let scheduler = ClusterScheduler()
        let nodes = [
            makeNode(id: "big", cores: 32),
            makeNode(id: "small", cores: 8),
        ]
        // 10 tasks: big should get ~8, small should get ~2
        let tasks = (0..<10).map { makeTask(id: "t\($0)") }

        let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: .proportional)

        XCTAssertEqual(assignments.count, 10)

        let bigCount = assignments.filter { $0.nodeId == "big" }.count
        let smallCount = assignments.filter { $0.nodeId == "small" }.count

        // Big node has 32/(32+8) = 80% of cores, should get more tasks
        XCTAssertGreaterThan(bigCount, smallCount)
        XCTAssertEqual(bigCount + smallCount, 10)
    }

    // 2. Round robin distribution splits equally
    func testRoundRobinDistribution() {
        let scheduler = ClusterScheduler()
        let nodes = [
            makeNode(id: "A", cores: 32),
            makeNode(id: "B", cores: 8),
        ]
        let tasks = (0..<6).map { makeTask(id: "t\($0)") }

        let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: .roundRobin)

        XCTAssertEqual(assignments.count, 6)

        let aCount = assignments.filter { $0.nodeId == "A" }.count
        let bCount = assignments.filter { $0.nodeId == "B" }.count

        // Round robin: 3 each regardless of cores
        XCTAssertEqual(aCount, 3)
        XCTAssertEqual(bCount, 3)
    }

    // 3. Least loaded distribution
    func testLeastLoadedDistribution() {
        let scheduler = ClusterScheduler()
        let nodes = [
            makeNode(id: "A", cores: 32),
            makeNode(id: "B", cores: 16),
            makeNode(id: "C", cores: 8),
        ]
        let tasks = (0..<3).map { makeTask(id: "t\($0)") }

        let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: .leastLoaded)

        XCTAssertEqual(assignments.count, 3)

        // Each node should get exactly 1 task (since all start at 0 load)
        let nodeIds = Set(assignments.map(\.nodeId))
        XCTAssertEqual(nodeIds.count, 3)
    }

    // 4. Single node gets all tasks
    func testSingleNodeGetsAllTasks() {
        let scheduler = ClusterScheduler()
        let nodes = [makeNode(id: "solo", cores: 16)]
        let tasks = (0..<5).map { makeTask(id: "t\($0)") }

        let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: .proportional)

        XCTAssertEqual(assignments.count, 5)
        XCTAssertTrue(assignments.allSatisfy { $0.nodeId == "solo" })
    }

    // 5. Empty tasks returns empty assignments
    func testEmptyTasksReturnsEmpty() {
        let scheduler = ClusterScheduler()
        let nodes = [makeNode(id: "A", cores: 16)]
        let tasks: [SubTask] = []

        let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: .proportional)

        XCTAssertTrue(assignments.isEmpty)
    }

    // 6. Assignment reasons are populated
    func testAssignmentReasonsPopulated() {
        let scheduler = ClusterScheduler()
        let nodes = [makeNode(id: "A", cores: 16), makeNode(id: "B", cores: 8)]
        let tasks = [makeTask(id: "t1")]

        for strategy in DistributionStrategy.allCases {
            let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: strategy)
            for assignment in assignments {
                XCTAssertFalse(assignment.reason.isEmpty,
                               "Reason should not be empty for strategy: \(strategy.rawValue)")
            }
        }
    }

    // 7. Empty nodes returns empty assignments
    func testEmptyNodesReturnsEmpty() {
        let scheduler = ClusterScheduler()
        let nodes: [NodeInfo] = []
        let tasks = [makeTask(id: "t1")]

        let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: .proportional)

        XCTAssertTrue(assignments.isEmpty)
    }

    // 8. Proportional with equal nodes distributes evenly
    func testProportionalEqualNodes() {
        let scheduler = ClusterScheduler()
        let nodes = [
            makeNode(id: "A", cores: 16),
            makeNode(id: "B", cores: 16),
        ]
        let tasks = (0..<10).map { makeTask(id: "t\($0)") }

        let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: .proportional)

        let aCount = assignments.filter { $0.nodeId == "A" }.count
        let bCount = assignments.filter { $0.nodeId == "B" }.count

        XCTAssertEqual(aCount, 5)
        XCTAssertEqual(bCount, 5)
    }

    // 9. Least loaded with many tasks spreads evenly
    func testLeastLoadedManyTasks() {
        let scheduler = ClusterScheduler()
        let nodes = [
            makeNode(id: "A", cores: 32),
            makeNode(id: "B", cores: 32),
        ]
        let tasks = (0..<8).map { makeTask(id: "t\($0)") }

        let assignments = scheduler.distribute(tasks: tasks, nodes: nodes, strategy: .leastLoaded)

        let aCount = assignments.filter { $0.nodeId == "A" }.count
        let bCount = assignments.filter { $0.nodeId == "B" }.count

        // Should be evenly split
        XCTAssertEqual(aCount, 4)
        XCTAssertEqual(bCount, 4)
    }
}

// MARK: - RemoteShell Tests

final class RemoteShellTests: XCTestCase {

    private func makeNode(id: String) -> NodeInfo {
        NodeInfo(id: id, hostname: id, cores: 8, memoryGB: 16, model: "Test", status: .online)
    }

    // 1. MockRemoteExecutor returns configured results
    func testMockExecutorReturnsConfiguredResults() async throws {
        let mock = MockRemoteExecutor()
        let customResult = RemoteResult(
            nodeId: "A",
            exitCode: 0,
            stdout: "hello from A\n",
            stderr: "",
            durationMs: 42
        )
        mock.addResponse(for: "A", result: customResult)

        let result = try await mock.execute(command: "echo hello", on: makeNode(id: "A"), cwd: nil)

        XCTAssertEqual(result.nodeId, "A")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello from A\n")
        XCTAssertEqual(result.durationMs, 42)
        XCTAssertTrue(result.succeeded)
    }

    // 2. MockRemoteExecutor reachability check
    func testMockExecutorReachability() async {
        let mock = MockRemoteExecutor()
        mock.setReachable("A", reachable: true)
        mock.setReachable("B", reachable: false)

        let reachA = await mock.isReachable(node: makeNode(id: "A"))
        XCTAssertTrue(reachA)

        let reachB = await mock.isReachable(node: makeNode(id: "B"))
        XCTAssertFalse(reachB)

        // Default is reachable
        let reachC = await mock.isReachable(node: makeNode(id: "C"))
        XCTAssertTrue(reachC)
    }

    // 3. RemoteResult properties
    func testRemoteResultProperties() {
        let success = RemoteResult(nodeId: "X", exitCode: 0, stdout: "ok", stderr: "", durationMs: 10)
        XCTAssertTrue(success.succeeded)
        XCTAssertEqual(success.nodeId, "X")
        XCTAssertEqual(success.durationMs, 10)

        let failure = RemoteResult(nodeId: "Y", exitCode: 1, stdout: "", stderr: "error", durationMs: 20)
        XCTAssertFalse(failure.succeeded)
        XCTAssertEqual(failure.stderr, "error")
    }

    // 4. MockRemoteExecutor tracks execution log
    func testMockExecutorExecutionLog() async throws {
        let mock = MockRemoteExecutor()

        _ = try await mock.execute(command: "echo 1", on: makeNode(id: "A"), cwd: nil)
        _ = try await mock.execute(command: "echo 2", on: makeNode(id: "B"), cwd: nil)
        _ = try await mock.execute(command: "echo 3", on: makeNode(id: "A"), cwd: nil)

        let log = mock.executionLog
        XCTAssertEqual(log.count, 3)
        XCTAssertEqual(log[0].command, "echo 1")
        XCTAssertEqual(log[0].nodeId, "A")
        XCTAssertEqual(log[1].command, "echo 2")
        XCTAssertEqual(log[1].nodeId, "B")
        XCTAssertEqual(log[2].command, "echo 3")
        XCTAssertEqual(log[2].nodeId, "A")
    }

    // 5. MockRemoteExecutor uses default result for unconfigured nodes
    func testMockExecutorDefaultResult() async throws {
        let defaultResult = RemoteResult(
            nodeId: "default",
            exitCode: 42,
            stdout: "default output",
            stderr: "default error",
            durationMs: 99
        )
        let mock = MockRemoteExecutor(defaultResult: defaultResult)

        let result = try await mock.execute(command: "anything", on: makeNode(id: "Z"), cwd: nil)

        XCTAssertEqual(result.nodeId, "Z")
        XCTAssertEqual(result.exitCode, 42)
        XCTAssertEqual(result.stdout, "default output")
        XCTAssertEqual(result.stderr, "default error")
        XCTAssertEqual(result.durationMs, 99)
    }

    // 6. RemoteExecutorError descriptions
    func testRemoteExecutorErrorDescriptions() {
        let err1 = RemoteExecutorError.unreachable(nodeId: "X", reason: "timeout")
        XCTAssertTrue(err1.description.contains("X"))
        XCTAssertTrue(err1.description.contains("timeout"))

        let err2 = RemoteExecutorError.sshNotFound
        XCTAssertTrue(err2.description.contains("SSH"))

        let err3 = RemoteExecutorError.timeout(nodeId: "Y", seconds: 120)
        XCTAssertTrue(err3.description.contains("Y"))
        XCTAssertTrue(err3.description.contains("120"))

        let err4 = RemoteExecutorError.executionFailed(nodeId: "Z", reason: "bad command")
        XCTAssertTrue(err4.description.contains("Z"))
        XCTAssertTrue(err4.description.contains("bad command"))
    }
}

// MARK: - NodeMonitor Tests

final class NodeMonitorTests: XCTestCase {

    private func makeNode(id: String, status: NodeStatus = .online) -> NodeInfo {
        NodeInfo(id: id, hostname: id, cores: 8, memoryGB: 16, model: "Test", status: status)
    }

    // 1. Health check result creation and properties
    func testHealthCheckResultProperties() {
        let result = NodeHealthResult(
            nodeId: "A",
            reachable: true,
            responseTimeMs: 15,
            loadAverage: 1.5,
            availableMemoryGB: 12
        )

        XCTAssertEqual(result.nodeId, "A")
        XCTAssertTrue(result.reachable)
        XCTAssertEqual(result.responseTimeMs, 15)
        XCTAssertEqual(result.loadAverage, 1.5)
        XCTAssertEqual(result.availableMemoryGB, 12)
    }

    // 2. Health check result summary
    func testHealthCheckResultSummary() {
        let reachable = NodeHealthResult(
            nodeId: "A",
            reachable: true,
            responseTimeMs: 10,
            loadAverage: 0.5,
            availableMemoryGB: 8
        )
        let summary = reachable.summary
        XCTAssertTrue(summary.contains("reachable"))
        XCTAssertTrue(summary.contains("10 ms"))

        let unreachable = NodeHealthResult(nodeId: "B", reachable: false)
        XCTAssertEqual(unreachable.summary, "unreachable")
    }

    // 3. NodeEvent types are constructable
    func testNodeEventTypes() {
        let node = makeNode(id: "A")

        let onlineEvent = NodeEvent.nodeOnline(node)
        let offlineEvent = NodeEvent.nodeOffline("A")
        let recoveredEvent = NodeEvent.nodeRecovered(node)
        let failedEvent = NodeEvent.healthCheckFailed("A", "timeout")

        // Verify event pattern matching works
        if case .nodeOnline(let n) = onlineEvent {
            XCTAssertEqual(n.id, "A")
        } else { XCTFail("Expected nodeOnline") }

        if case .nodeOffline(let id) = offlineEvent {
            XCTAssertEqual(id, "A")
        } else { XCTFail("Expected nodeOffline") }

        if case .nodeRecovered(let n) = recoveredEvent {
            XCTAssertEqual(n.id, "A")
        } else { XCTFail("Expected nodeRecovered") }

        if case .healthCheckFailed(let id, let reason) = failedEvent {
            XCTAssertEqual(id, "A")
            XCTAssertEqual(reason, "timeout")
        } else { XCTFail("Expected healthCheckFailed") }
    }

    // 4. NodeMonitor performs health check via mock executor
    func testHealthCheckViaMock() async {
        let mock = MockRemoteExecutor()
        mock.setReachable("A", reachable: true)
        mock.addResponse(for: "A", result: RemoteResult(
            nodeId: "A", exitCode: 0, stdout: "1.23", stderr: "", durationMs: 5
        ))

        let state = ClusterState()
        let monitor = NodeMonitor(executor: mock, clusterState: state)
        let node = makeNode(id: "A")

        let result = await monitor.healthCheck(node: node)

        XCTAssertTrue(result.reachable)
        XCTAssertEqual(result.nodeId, "A")
        XCTAssertNotNil(result.responseTimeMs)
    }

    // 5. NodeMonitor health check for unreachable node
    func testHealthCheckUnreachable() async {
        let mock = MockRemoteExecutor()
        mock.setReachable("B", reachable: false)

        let state = ClusterState()
        let monitor = NodeMonitor(executor: mock, clusterState: state)
        let node = makeNode(id: "B")

        let result = await monitor.healthCheck(node: node)

        XCTAssertFalse(result.reachable)
        XCTAssertEqual(result.nodeId, "B")
        XCTAssertNil(result.responseTimeMs)
        XCTAssertNil(result.loadAverage)
        XCTAssertNil(result.availableMemoryGB)
    }
}

// MARK: - FaultRecovery Tests

final class FaultRecoveryTests: XCTestCase {

    private func makeNode(id: String, cores: Int = 8) -> NodeInfo {
        NodeInfo(id: id, hostname: id, cores: cores, memoryGB: cores * 2,
                 model: "Test", status: .online)
    }

    private func makeTask(id: String) -> SubTask {
        SubTask(id: id, agentType: "coder", goal: "Task \(id)", successCriteria: "Done")
    }

    private func makeAssignment(taskId: String, nodeId: String) -> TaskAssignment {
        TaskAssignment(
            task: makeTask(id: taskId),
            nodeId: nodeId,
            reason: "initial assignment"
        )
    }

    // 1. Reassign tasks from failed node
    func testReassignTasksFromFailedNode() {
        let recovery = FaultRecovery()

        let assignments = [
            makeAssignment(taskId: "t1", nodeId: "A"),
            makeAssignment(taskId: "t2", nodeId: "A"),
            makeAssignment(taskId: "t3", nodeId: "B"),
        ]

        let availableNodes = [makeNode(id: "B", cores: 16), makeNode(id: "C", cores: 8)]

        let plan = recovery.handleNodeFailure(
            failedNodeId: "A",
            assignments: assignments,
            availableNodes: availableNodes
        )

        // t1 and t2 should be reassigned to B or C
        XCTAssertEqual(plan.reassignments.count, 2)
        XCTAssertTrue(plan.cancelledTasks.isEmpty)
        XCTAssertTrue(plan.isFullRecovery)
        XCTAssertFalse(plan.hasCancellations)
        XCTAssertFalse(plan.description.isEmpty)

        // Verify reassigned tasks are the right ones
        let reassignedIds = Set(plan.reassignments.map(\.task.id))
        XCTAssertTrue(reassignedIds.contains("t1"))
        XCTAssertTrue(reassignedIds.contains("t2"))

        // Verify they are not assigned back to the failed node
        for assignment in plan.reassignments {
            XCTAssertNotEqual(assignment.nodeId, "A")
        }
    }

    // 2. Cancel tasks when no nodes available
    func testCancelTasksWhenNoNodesAvailable() {
        let recovery = FaultRecovery()

        let assignments = [
            makeAssignment(taskId: "t1", nodeId: "A"),
            makeAssignment(taskId: "t2", nodeId: "A"),
        ]

        let plan = recovery.handleNodeFailure(
            failedNodeId: "A",
            assignments: assignments,
            availableNodes: []
        )

        XCTAssertTrue(plan.reassignments.isEmpty)
        XCTAssertEqual(plan.cancelledTasks.count, 2)
        XCTAssertTrue(plan.cancelledTasks.contains("t1"))
        XCTAssertTrue(plan.cancelledTasks.contains("t2"))
        XCTAssertFalse(plan.isFullRecovery)
        XCTAssertTrue(plan.hasCancellations)
    }

    // 3. Recovery plan description is populated
    func testRecoveryPlanDescriptionPopulated() {
        let recovery = FaultRecovery()

        let assignments = [makeAssignment(taskId: "t1", nodeId: "FailedNode")]
        let plan = recovery.handleNodeFailure(
            failedNodeId: "FailedNode",
            assignments: assignments,
            availableNodes: [makeNode(id: "Survivor")]
        )

        XCTAssertFalse(plan.description.isEmpty)
        XCTAssertTrue(plan.description.contains("FailedNode"))
    }

    // 4. Multiple failed nodes handled
    func testMultipleFailedNodesHandled() {
        let recovery = FaultRecovery()

        let assignments = [
            makeAssignment(taskId: "t1", nodeId: "A"),
            makeAssignment(taskId: "t2", nodeId: "B"),
            makeAssignment(taskId: "t3", nodeId: "C"),
            makeAssignment(taskId: "t4", nodeId: "A"),
        ]

        let availableNodes = [makeNode(id: "C", cores: 16), makeNode(id: "D", cores: 8)]

        let plan = recovery.handleMultipleNodeFailures(
            failedNodeIds: ["A", "B"],
            assignments: assignments,
            availableNodes: availableNodes
        )

        // t1, t2, t4 were on A or B; t3 was on C (not failed)
        // So 3 tasks need reassignment
        XCTAssertEqual(plan.reassignments.count, 3)
        XCTAssertTrue(plan.cancelledTasks.isEmpty)
        XCTAssertTrue(plan.description.contains("A"))
        XCTAssertTrue(plan.description.contains("B"))
    }

    // 5. No tasks on failed node produces empty plan
    func testNoTasksOnFailedNode() {
        let recovery = FaultRecovery()

        let assignments = [
            makeAssignment(taskId: "t1", nodeId: "B"),
        ]

        let plan = recovery.handleNodeFailure(
            failedNodeId: "A",
            assignments: assignments,
            availableNodes: [makeNode(id: "B")]
        )

        XCTAssertTrue(plan.reassignments.isEmpty)
        XCTAssertTrue(plan.cancelledTasks.isEmpty)
        XCTAssertTrue(plan.description.contains("no assigned tasks"))
    }

    // 6. Multiple failures with no survivors cancels all
    func testMultipleFailuresNoSurvivors() {
        let recovery = FaultRecovery()

        let assignments = [
            makeAssignment(taskId: "t1", nodeId: "A"),
            makeAssignment(taskId: "t2", nodeId: "B"),
        ]

        let plan = recovery.handleMultipleNodeFailures(
            failedNodeIds: ["A", "B"],
            assignments: assignments,
            availableNodes: []
        )

        XCTAssertTrue(plan.reassignments.isEmpty)
        XCTAssertEqual(plan.cancelledTasks.count, 2)
        XCTAssertFalse(plan.isFullRecovery)
    }

    // 7. FaultRecoveryPlan isFullRecovery and hasCancellations
    func testFaultRecoveryPlanProperties() {
        let fullPlan = FaultRecoveryPlan(
            reassignments: [TaskAssignment(task: makeTask(id: "t"), nodeId: "X", reason: "test")],
            cancelledTasks: [],
            description: "full recovery"
        )
        XCTAssertTrue(fullPlan.isFullRecovery)
        XCTAssertFalse(fullPlan.hasCancellations)

        let partialPlan = FaultRecoveryPlan(
            reassignments: [],
            cancelledTasks: ["t1"],
            description: "partial"
        )
        XCTAssertFalse(partialPlan.isFullRecovery)
        XCTAssertTrue(partialPlan.hasCancellations)
    }
}

// MARK: - ClusterInventory Tests

final class ClusterInventoryTests: XCTestCase {

    func testAllNodesCount() {
        XCTAssertEqual(ClusterInventory.allNodes.count, 16)
    }

    func testTotalCores() {
        XCTAssertEqual(ClusterInventory.totalCores, 250)
    }

    func testTotalMemory() {
        XCTAssertEqual(ClusterInventory.totalMemoryGB, 720)
    }

    func testFindNodeByAlias() {
        let node = ClusterInventory.find(alias: "M3U96a")
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.cores, 32)
        XCTAssertEqual(node?.memoryGB, 96)
        XCTAssertEqual(node?.model, "Mac Studio")
    }

    func testFindNodeCaseInsensitive() {
        let node = ClusterInventory.find(alias: "m3u96a")
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.id, "M3U96a")
    }

    func testFindUnknownNodeReturnsNil() {
        let node = ClusterInventory.find(alias: "nonexistent")
        XCTAssertNil(node)
    }
}
