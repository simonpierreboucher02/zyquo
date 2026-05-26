import Foundation

// MARK: - ClusterState

/// Actor managing the topology and state of all nodes in the cluster.
///
/// Provides thread-safe access to node metadata, status transitions,
/// and aggregate statistics. The `NodeMonitor` updates node status via
/// this actor; the `ClusterScheduler` reads it for placement decisions.
///
/// Reference: CLAUDE.md §30 Phase 9
public actor ClusterState {

    /// All known nodes keyed by their identifier.
    private var nodes: [String: NodeInfo] = [:]

    /// Insertion order for deterministic iteration.
    private var nodeOrder: [String] = []

    public init() {}

    /// Initialize with a pre-populated set of nodes.
    public init(nodes: [NodeInfo]) {
        for node in nodes {
            self.nodes[node.id] = node
            self.nodeOrder.append(node.id)
        }
    }

    // MARK: - Mutation

    /// Add a node to the cluster. If a node with the same id exists, it is replaced.
    ///
    /// - Parameter node: The node to add.
    public func addNode(_ node: NodeInfo) {
        if nodes[node.id] == nil {
            nodeOrder.append(node.id)
        }
        nodes[node.id] = node
    }

    /// Remove a node from the cluster by its identifier.
    ///
    /// - Parameter id: The node identifier to remove.
    public func removeNode(id: String) {
        nodes.removeValue(forKey: id)
        nodeOrder.removeAll { $0 == id }
    }

    /// Update the status of a specific node.
    ///
    /// - Parameters:
    ///   - id: The node identifier.
    ///   - status: The new status.
    public func updateNode(id: String, status: NodeStatus) {
        nodes[id]?.status = status
        if status == .online {
            nodes[id]?.lastSeen = Date()
        }
    }

    /// Update a node's last-seen timestamp.
    ///
    /// - Parameter id: The node identifier.
    public func touchNode(id: String) {
        nodes[id]?.lastSeen = Date()
    }

    // MARK: - Queries

    /// All known nodes in insertion order.
    public func allNodes() -> [NodeInfo] {
        nodeOrder.compactMap { nodes[$0] }
    }

    /// Nodes that are currently online and accepting work.
    public func onlineNodes() -> [NodeInfo] {
        nodeOrder.compactMap { nodes[$0] }.filter { $0.status == .online }
    }

    /// Nodes that are available for scheduling (online, not draining).
    public func availableNodes() -> [NodeInfo] {
        nodeOrder.compactMap { nodes[$0] }.filter { $0.isAvailable }
    }

    /// Total CPU cores across all known nodes.
    public func totalCores() -> Int {
        nodes.values.reduce(0) { $0 + $1.cores }
    }

    /// Total memory (GB) across all known nodes.
    public func totalMemoryGB() -> Int {
        nodes.values.reduce(0) { $0 + $1.memoryGB }
    }

    /// Total CPU cores across online nodes only.
    public func onlineCores() -> Int {
        nodes.values.filter { $0.status == .online }.reduce(0) { $0 + $1.cores }
    }

    /// Total memory (GB) across online nodes only.
    public func onlineMemoryGB() -> Int {
        nodes.values.filter { $0.status == .online }.reduce(0) { $0 + $1.memoryGB }
    }

    /// Look up a specific node by identifier.
    ///
    /// - Parameter id: The node identifier.
    /// - Returns: The node info, or nil if not found.
    public func node(id: String) -> NodeInfo? {
        nodes[id]
    }

    /// Number of known nodes.
    public var nodeCount: Int {
        nodes.count
    }

    /// Number of online nodes.
    public var onlineCount: Int {
        nodes.values.filter { $0.status == .online }.count
    }
}
