import Foundation

// MARK: - DependencyGraph

/// A generic directed acyclic graph (DAG) for modeling task dependencies.
///
/// Nodes are values conforming to `Sendable & Identifiable`. Edges represent
/// "depends-on" relationships: `addEdge(from: A, to: B)` means A depends on B,
/// so B must complete before A can run.
///
/// Used by `TaskScheduler` to determine topological execution order and to
/// identify which tasks are ready to run given a set of completed tasks.
///
/// Reference: CLAUDE.md §30 Phase 7
public struct DependencyGraph<T: Sendable & Identifiable>: Sendable where T.ID: Hashable & Sendable {

    /// Storage for nodes keyed by their identifier.
    private var nodes: [T.ID: T] = [:]

    /// Forward edges: from -> [to]. "from depends on to".
    private var edges: [T.ID: Set<T.ID>] = [:]

    /// Reverse edges: to -> [from]. "to is depended on by from".
    private var reverseEdges: [T.ID: Set<T.ID>] = [:]

    /// Insertion order for deterministic iteration.
    private var insertionOrder: [T.ID] = []

    public init() {}

    // MARK: - Mutation

    /// Add a node to the graph.
    ///
    /// If a node with the same ID already exists, it is replaced.
    ///
    /// - Parameter value: The node value to add.
    public mutating func addNode(_ value: T) {
        let id = value.id
        if nodes[id] == nil {
            insertionOrder.append(id)
        }
        nodes[id] = value
        if edges[id] == nil {
            edges[id] = []
        }
        if reverseEdges[id] == nil {
            reverseEdges[id] = []
        }
    }

    /// Add a dependency edge.
    ///
    /// `from` depends on `to`, meaning `to` must complete before `from`
    /// can begin execution.
    ///
    /// - Parameters:
    ///   - from: The dependent node ID.
    ///   - to: The dependency node ID (must complete first).
    public mutating func addEdge(from: T.ID, to: T.ID) {
        edges[from, default: []].insert(to)
        reverseEdges[to, default: []].insert(from)
    }

    // MARK: - Queries

    /// The dependencies of a given node (nodes that must complete before it).
    ///
    /// - Parameter id: The node to query.
    /// - Returns: The IDs of nodes that `id` depends on.
    public func dependencies(of id: T.ID) -> [T.ID] {
        Array(edges[id] ?? [])
    }

    /// The dependents of a given node (nodes that depend on it).
    ///
    /// - Parameter id: The node to query.
    /// - Returns: The IDs of nodes that depend on `id`.
    public func dependents(of id: T.ID) -> [T.ID] {
        Array(reverseEdges[id] ?? [])
    }

    /// Compute a topological ordering of all node IDs.
    ///
    /// Returns `nil` if the graph contains a cycle. The ordering guarantees
    /// that for every edge (from, to), `to` appears before `from` in the
    /// result (since `to` must complete first).
    ///
    /// Uses Kahn's algorithm (BFS-based) for cycle detection.
    ///
    /// - Returns: A topologically sorted array of node IDs, or nil if cyclic.
    public func topologicalSort() -> [T.ID]? {
        // Compute in-degree for each node (number of dependencies)
        var inDegree: [T.ID: Int] = [:]
        for id in insertionOrder {
            inDegree[id] = (edges[id] ?? []).count
        }

        // Start with nodes that have no dependencies (in-degree 0)
        var queue: [T.ID] = []
        for id in insertionOrder {
            if inDegree[id] == 0 {
                queue.append(id)
            }
        }

        var result: [T.ID] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            result.append(current)

            // For each node that depends on `current`, decrement its in-degree
            for dependent in (reverseEdges[current] ?? []).sorted(by: { "\($0)" < "\($1)" }) {
                inDegree[dependent]! -= 1
                if inDegree[dependent] == 0 {
                    queue.append(dependent)
                }
            }
        }

        // If we visited all nodes, there is no cycle
        if result.count == nodes.count {
            return result
        } else {
            return nil // Cycle detected
        }
    }

    /// Determine which nodes are ready to execute given a set of completed nodes.
    ///
    /// A node is "ready" if all of its dependencies are in the `completed` set
    /// and the node itself is not yet completed.
    ///
    /// - Parameter completed: The set of already-completed node IDs.
    /// - Returns: IDs of nodes whose dependencies are fully satisfied.
    public func readyNodes(completed: Set<T.ID>) -> [T.ID] {
        var ready: [T.ID] = []
        for id in insertionOrder {
            guard !completed.contains(id) else { continue }
            let deps = edges[id] ?? []
            if deps.isSubset(of: completed) {
                ready.append(id)
            }
        }
        return ready
    }

    /// All nodes in the graph, in insertion order.
    public var allNodes: [T] {
        insertionOrder.compactMap { nodes[$0] }
    }

    /// The number of nodes in the graph.
    public var nodeCount: Int {
        nodes.count
    }

    /// The total number of edges in the graph.
    public var edgeCount: Int {
        edges.values.reduce(0) { $0 + $1.count }
    }

    /// Whether the graph contains a cycle.
    ///
    /// A graph has a cycle if topological sort fails.
    public func hasCycle() -> Bool {
        topologicalSort() == nil
    }

    /// Look up a node by its identifier.
    ///
    /// - Parameter id: The node identifier.
    /// - Returns: The node value, or nil if not found.
    public func node(for id: T.ID) -> T? {
        nodes[id]
    }

    /// All transitive dependents of a node (nodes that directly or indirectly
    /// depend on the given node). Used for cancellation propagation.
    ///
    /// - Parameter id: The root node whose dependents to collect.
    /// - Returns: All transitive dependent IDs (excluding the node itself).
    public func transitiveDependents(of id: T.ID) -> Set<T.ID> {
        var visited: Set<T.ID> = []
        var queue = Array(reverseEdges[id] ?? [])

        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard !visited.contains(current) else { continue }
            visited.insert(current)
            queue.append(contentsOf: reverseEdges[current] ?? [])
        }

        return visited
    }
}
