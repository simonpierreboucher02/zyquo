import ArgumentParser
import Foundation

// MARK: - ClusterCommand

/// Manage and inspect the distributed compute cluster.
///
/// Provides subcommands for checking node status, listing nodes,
/// health-checking individual nodes, and testing cluster connectivity.
///
/// Reference: CLAUDE.md §30 Phase 9
struct ClusterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cluster",
        abstract: "Manage the distributed compute cluster",
        subcommands: [
            ClusterStatusCommand.self,
            ClusterNodesCommand.self,
            ClusterCheckCommand.self,
            ClusterTestCommand.self,
        ],
        defaultSubcommand: ClusterStatusCommand.self
    )

    // MARK: - Status Subcommand

    struct ClusterStatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Show cluster status with all nodes"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let noColor = globals.flags.noColor

            let nodes = ClusterInventory.allNodes
            let totalCores = nodes.reduce(0) { $0 + $1.cores }
            let totalMemory = nodes.reduce(0) { $0 + $1.memoryGB }

            print()
            if noColor {
                print("  Zyquo Cluster Status")
                print("  " + String(repeating: "-", count: 68))
            } else {
                print("  \u{1B}[1mZyquo Cluster Status\u{1B}[0m")
                print("  \u{1B}[2m" + String(repeating: "-", count: 68) + "\u{1B}[0m")
            }

            // Summary
            print()
            if noColor {
                print("  Nodes: \(nodes.count)  |  Cores: \(totalCores)  |  Memory: \(totalMemory) GB")
            } else {
                print("  \u{1B}[1mNodes:\u{1B}[0m \(nodes.count)  |  \u{1B}[1mCores:\u{1B}[0m \(totalCores)  |  \u{1B}[1mMemory:\u{1B}[0m \(totalMemory) GB")
            }
            print()

            // Node table header
            let header = "  "
                + "Node".padding(toLength: 12, withPad: " ", startingAt: 0)
                + "Cores".padding(toLength: 8, withPad: " ", startingAt: 0)
                + "RAM".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "Model"

            if noColor {
                print(header)
                print("  " + String(repeating: "-", count: 68))
            } else {
                print("\u{1B}[1m\(header)\u{1B}[0m")
                print("  \u{1B}[2m" + String(repeating: "-", count: 68) + "\u{1B}[0m")
            }

            for node in nodes {
                let line = "  "
                    + node.hostname.padding(toLength: 12, withPad: " ", startingAt: 0)
                    + "\(node.cores)".padding(toLength: 8, withPad: " ", startingAt: 0)
                    + "\(node.memoryGB) GB".padding(toLength: 10, withPad: " ", startingAt: 0)
                    + node.model

                if noColor {
                    print(line)
                } else {
                    print(line)
                }
            }

            print()
        }
    }

    // MARK: - Nodes Subcommand

    struct ClusterNodesCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "nodes",
            abstract: "List all cluster nodes in table format"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let noColor = globals.flags.noColor
            let nodes = ClusterInventory.allNodes

            if globals.flags.json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(nodes)
                if let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
                return
            }

            let header = "  "
                + "Alias".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "FQDN".padding(toLength: 26, withPad: " ", startingAt: 0)
                + "Cores".padding(toLength: 8, withPad: " ", startingAt: 0)
                + "RAM".padding(toLength: 10, withPad: " ", startingAt: 0)
                + "Model"

            print()
            if noColor {
                print(header)
                print("  " + String(repeating: "-", count: 72))
            } else {
                print("\u{1B}[1m\(header)\u{1B}[0m")
                print("  \u{1B}[2m" + String(repeating: "-", count: 72) + "\u{1B}[0m")
            }

            for node in nodes {
                let line = "  "
                    + node.hostname.padding(toLength: 10, withPad: " ", startingAt: 0)
                    + (node.fqdn ?? "-").padding(toLength: 26, withPad: " ", startingAt: 0)
                    + "\(node.cores)".padding(toLength: 8, withPad: " ", startingAt: 0)
                    + "\(node.memoryGB) GB".padding(toLength: 10, withPad: " ", startingAt: 0)
                    + node.model
                print(line)
            }
            print()
        }
    }

    // MARK: - Check Subcommand

    struct ClusterCheckCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "check",
            abstract: "Health check a specific node"
        )

        @Argument(help: "Node alias or hostname to check")
        var node: String

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let noColor = globals.flags.noColor

            guard let nodeInfo = ClusterInventory.find(alias: node) else {
                let known = ClusterInventory.allNodes.map(\.hostname).joined(separator: ", ")
                print("Unknown node: '\(node)'. Known nodes: \(known)")
                throw ExitCode(rawValue: 2)
            }

            if noColor {
                print("Checking node: \(nodeInfo.hostname) (\(nodeInfo.model), \(nodeInfo.cores) cores)...")
            } else {
                print("\u{1B}[1mChecking node:\u{1B}[0m \(nodeInfo.hostname) (\(nodeInfo.model), \(nodeInfo.cores) cores)...")
            }

            let executor = SSHRemoteExecutor(connectTimeoutSeconds: 10)
            let clusterState = ClusterState()
            let monitor = NodeMonitor(executor: executor, clusterState: clusterState)

            let result = await monitor.healthCheck(node: nodeInfo)

            let check = noColor ? "[OK]" : "\u{1B}[32m\u{2713}\u{1B}[0m"
            let fail = noColor ? "[FAIL]" : "\u{1B}[31m\u{2717}\u{1B}[0m"

            if result.reachable {
                print("  \(check) Reachable")
                if let ms = result.responseTimeMs {
                    print("  \(check) Response time: \(ms) ms")
                }
                if let load = result.loadAverage {
                    print("  \(check) Load average: \(String(format: "%.2f", load))")
                }
                if let mem = result.availableMemoryGB {
                    print("  \(check) Memory: \(mem) GB")
                }
            } else {
                print("  \(fail) Node unreachable")
            }
        }
    }

    // MARK: - Test Subcommand

    struct ClusterTestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Run a connectivity test on all nodes"
        )

        @OptionGroup var globals: ZyquoCLI.GlobalOptions

        func run() async throws {
            Bootstrap.setupSignalHandlers()
            let noColor = globals.flags.noColor

            let nodes = ClusterInventory.allNodes
            let executor = SSHRemoteExecutor(connectTimeoutSeconds: 10)

            if noColor {
                print("Testing connectivity to \(nodes.count) nodes...")
            } else {
                print("\u{1B}[1mTesting connectivity to \(nodes.count) nodes...\u{1B}[0m")
            }
            print()

            let check = noColor ? "[OK]" : "\u{1B}[32m\u{2713}\u{1B}[0m"
            let fail = noColor ? "[FAIL]" : "\u{1B}[31m\u{2717}\u{1B}[0m"

            var passed = 0
            var failed = 0

            // Run connectivity tests in parallel
            await withTaskGroup(of: (NodeInfo, Bool).self) { group in
                for node in nodes {
                    group.addTask {
                        let reachable = await executor.isReachable(node: node)
                        return (node, reachable)
                    }
                }

                // Collect results (order may vary)
                var results: [(NodeInfo, Bool)] = []
                for await result in group {
                    results.append(result)
                }

                // Sort by the original node order for deterministic output
                let nodeOrder = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
                results.sort { (nodeOrder[$0.0.id] ?? 0) < (nodeOrder[$1.0.id] ?? 0) }

                for (node, reachable) in results {
                    let hostname = node.hostname.padding(toLength: 10, withPad: " ", startingAt: 0)
                    if reachable {
                        print("  \(check) \(hostname) reachable")
                        passed += 1
                    } else {
                        print("  \(fail) \(hostname) unreachable")
                        failed += 1
                    }
                }
            }

            print()
            if noColor {
                print("Results: \(passed) passed, \(failed) failed, \(nodes.count) total")
            } else {
                let passColor = passed > 0 ? "\u{1B}[32m" : ""
                let failColor = failed > 0 ? "\u{1B}[31m" : ""
                print("Results: \(passColor)\(passed) passed\u{1B}[0m, \(failColor)\(failed) failed\u{1B}[0m, \(nodes.count) total")
            }
        }
    }
}

// MARK: - Cluster Inventory

/// Static inventory of known MacLustr cluster nodes.
///
/// This matches the cluster inventory from the global CLAUDE.md.
enum ClusterInventory {

    /// All known cluster nodes.
    static let allNodes: [NodeInfo] = [
        NodeInfo(id: "M3U96a", hostname: "M3U96a", fqdn: "M3U96a.maclustr.io",
                 cores: 32, memoryGB: 96, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "M3U96b", hostname: "M3U96b", fqdn: "M3U96b.maclustr.io",
                 cores: 32, memoryGB: 96, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "M2U64", hostname: "M2U64", fqdn: "M2U64.maclustr.io",
                 cores: 24, memoryGB: 64, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "M4M64a", hostname: "M4M64a", fqdn: "M4M64a.maclustr.io",
                 cores: 16, memoryGB: 64, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "M4M64b", hostname: "M4M64b", fqdn: "M4M64b.maclustr.io",
                 cores: 16, memoryGB: 64, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "M4BP48", hostname: "M4BP48", fqdn: "M4BP48.maclustr.io",
                 cores: 16, memoryGB: 48, model: "MacBook Pro", status: .unknown),
        NodeInfo(id: "M4BP36", hostname: "M4BP36", fqdn: "M4BP36.maclustr.io",
                 cores: 14, memoryGB: 36, model: "MacBook Pro", status: .unknown),
        NodeInfo(id: "M4M36", hostname: "M4M36", fqdn: "M4M36.maclustr.io",
                 cores: 14, memoryGB: 36, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "M2M32", hostname: "M2M32", fqdn: "M2M32.maclustr.io",
                 cores: 12, memoryGB: 32, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "M2M32b", hostname: "M2M32b", fqdn: "M2M32b.maclustr.io",
                 cores: 12, memoryGB: 32, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "M2M32c", hostname: "M2M32c", fqdn: "M2M32c.maclustr.io",
                 cores: 12, memoryGB: 32, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "m4mc", hostname: "m4mc", fqdn: "m4mc.maclustr.io",
                 cores: 12, memoryGB: 24, model: "Mac mini", status: .unknown),
        NodeInfo(id: "M1M32", hostname: "M1M32", fqdn: "M1M32.maclustr.io",
                 cores: 10, memoryGB: 32, model: "Mac Studio", status: .unknown),
        NodeInfo(id: "m4ma", hostname: "m4ma", fqdn: "m4ma.maclustr.io",
                 cores: 10, memoryGB: 24, model: "Mac mini", status: .unknown),
        NodeInfo(id: "m4mb", hostname: "m4mb", fqdn: "m4mb.maclustr.io",
                 cores: 10, memoryGB: 16, model: "Mac mini", status: .unknown),
        NodeInfo(id: "M3BA24", hostname: "M3BA24", fqdn: "M3BA24.maclustr.io",
                 cores: 8, memoryGB: 24, model: "MacBook Air", status: .unknown),
    ]

    /// Find a node by its alias (case-insensitive).
    static func find(alias: String) -> NodeInfo? {
        allNodes.first { $0.id.lowercased() == alias.lowercased() }
    }

    /// Total cores across all nodes.
    static var totalCores: Int {
        allNodes.reduce(0) { $0 + $1.cores }
    }

    /// Total memory across all nodes.
    static var totalMemoryGB: Int {
        allNodes.reduce(0) { $0 + $1.memoryGB }
    }
}
