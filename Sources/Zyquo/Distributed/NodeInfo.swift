import Foundation

// MARK: - NodeStatus

/// Health status of a cluster node.
///
/// Nodes transition between states based on health checks and workload.
/// The monitor updates status via `ClusterState.updateNode`.
public enum NodeStatus: String, Sendable, Codable, CaseIterable {
    /// Node is reachable and accepting work.
    case online
    /// Node is unreachable or not responding to health checks.
    case offline
    /// Node is reachable but currently at capacity.
    case busy
    /// Node is online but not accepting new work (graceful shutdown).
    case draining
    /// Node status has not been determined yet.
    case unknown
}

// MARK: - NodeCapabilities

/// Hardware and software capabilities of a cluster node.
///
/// Used by the scheduler to make placement decisions (e.g. prefer
/// nodes with GPU for Metal-accelerated local inference).
public struct NodeCapabilities: Sendable, Codable, Equatable {
    /// Whether the node has a discrete or integrated GPU suitable for Metal.
    public let hasGPU: Bool
    /// Swift toolchain version installed on the node, if detected.
    public let swiftVersion: String?
    /// Available disk space in gigabytes.
    public let availableDiskGB: Int
    /// CPU architecture identifier ("arm64" or "x86_64").
    public let architecture: String

    public init(
        hasGPU: Bool = true,
        swiftVersion: String? = nil,
        availableDiskGB: Int = 0,
        architecture: String = "arm64"
    ) {
        self.hasGPU = hasGPU
        self.swiftVersion = swiftVersion
        self.availableDiskGB = availableDiskGB
        self.architecture = architecture
    }
}

// MARK: - NodeInfo

/// Identity and metadata for a single node in the compute cluster.
///
/// Each node is identified by its hostname (alias). The scheduler uses
/// `cores` and `memoryGB` for proportional task distribution. The
/// monitor uses `lastSeen` and `status` for health tracking.
///
/// Reference: CLAUDE.md §30 Phase 9
public struct NodeInfo: Sendable, Codable, Identifiable, Equatable {
    /// Unique identifier, typically the hostname alias (e.g. "M3U96a").
    public let id: String
    /// Short hostname used for SSH connections.
    public let hostname: String
    /// Fully qualified domain name (e.g. "M3U96a.maclustr.io").
    public let fqdn: String?
    /// Number of CPU cores available on this node.
    public let cores: Int
    /// Total memory in gigabytes.
    public let memoryGB: Int
    /// Hardware model description (e.g. "Mac Studio", "MacBook Pro").
    public let model: String
    /// Current operational status.
    public var status: NodeStatus
    /// Timestamp of the last successful health check.
    public var lastSeen: Date
    /// Hardware and software capabilities.
    public var capabilities: NodeCapabilities

    public init(
        id: String,
        hostname: String,
        fqdn: String? = nil,
        cores: Int,
        memoryGB: Int,
        model: String,
        status: NodeStatus = .unknown,
        lastSeen: Date = Date(),
        capabilities: NodeCapabilities = NodeCapabilities()
    ) {
        self.id = id
        self.hostname = hostname
        self.fqdn = fqdn
        self.cores = cores
        self.memoryGB = memoryGB
        self.model = model
        self.status = status
        self.lastSeen = lastSeen
        self.capabilities = capabilities
    }

    /// Whether the node can accept new work.
    public var isAvailable: Bool {
        status == .online
    }

    /// A human-readable summary line for table display.
    public var summaryLine: String {
        let statusStr = status.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
        let coresStr = "\(cores)".padding(toLength: 4, withPad: " ", startingAt: 0)
        let memStr = "\(memoryGB) GB".padding(toLength: 7, withPad: " ", startingAt: 0)
        return "\(hostname.padding(toLength: 10, withPad: " ", startingAt: 0)) \(statusStr) \(coresStr) cores  \(memStr) RAM  \(model)"
    }
}
