import Foundation

// MARK: - TrustScope

/// The scope/lifetime of a trust grant.
///
/// Reference: CLAUDE.md §19.4
public enum TrustScope: String, Sendable, Codable, CaseIterable, Comparable {
    /// Applies to this single invocation only.
    case once
    /// Applies for the duration of the current session (in-memory only).
    case session
    /// Persisted in `.zyquo/trust.json` for this workspace.
    case workspace
    /// Persisted in `~/.zyquo/trust.json` for all workspaces.
    case global

    private var ordinal: Int {
        switch self {
        case .once: return 0
        case .session: return 1
        case .workspace: return 2
        case .global: return 3
        }
    }

    public static func < (lhs: TrustScope, rhs: TrustScope) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

// MARK: - TrustGrant

/// A recorded trust grant that auto-approves matching future commands.
public struct TrustGrant: Sendable, Codable, Equatable {
    /// The command pattern this grant applies to. Can be a literal command
    /// string or a prefix/glob.
    public let pattern: String
    /// The scope of this grant.
    public let scope: TrustScope
    /// When the grant was created.
    public let grantedAt: Date
    /// The risk tier that was approved.
    public let riskTier: RiskLevel

    public init(pattern: String, scope: TrustScope, grantedAt: Date = Date(), riskTier: RiskLevel) {
        self.pattern = pattern
        self.scope = scope
        self.grantedAt = grantedAt
        self.riskTier = riskTier
    }

    /// Check whether this grant matches a given command.
    public func matches(command: String) -> Bool {
        // Exact match
        if command == pattern { return true }
        // Prefix match (e.g. "git push" matches "git push origin main")
        if command.hasPrefix(pattern + " ") || command.hasPrefix(pattern + "\t") {
            return true
        }
        return false
    }
}

// MARK: - TrustStore

/// Manages trust grants across scopes (session, workspace, global).
///
/// - Session grants live in memory only.
/// - Workspace grants are persisted to `.zyquo/trust.json`.
/// - Global grants are persisted to `~/.zyquo/trust.json`.
/// - CRITICAL commands can NEVER receive workspace or global scope.
///
/// Reference: CLAUDE.md §19.4
public final class TrustStore: @unchecked Sendable {
    private var sessionGrants: [TrustGrant] = []
    private let workspaceTrustPath: URL
    private let globalTrustPath: URL
    private let lock = NSLock()

    public init(workspaceRoot: URL) {
        self.workspaceTrustPath = workspaceRoot
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("trust.json")
        self.globalTrustPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zyquo")
            .appendingPathComponent("trust.json")
    }

    /// Create a TrustStore for testing that does not touch the filesystem.
    internal init(workspaceTrustPath: URL, globalTrustPath: URL) {
        self.workspaceTrustPath = workspaceTrustPath
        self.globalTrustPath = globalTrustPath
    }

    // MARK: - Query

    /// Find a matching trust grant for a command at or below a given risk tier.
    public func findGrant(for command: String, riskTier: RiskLevel) -> TrustGrant? {
        lock.lock()
        defer { lock.unlock() }

        // Check session grants first (most specific)
        for grant in sessionGrants where grant.matches(command: command) && grant.riskTier >= riskTier {
            return grant
        }

        // Check workspace grants
        let workspaceGrants = loadGrants(from: workspaceTrustPath)
        for grant in workspaceGrants where grant.matches(command: command) && grant.riskTier >= riskTier {
            return grant
        }

        // Check global grants
        let globalGrants = loadGrants(from: globalTrustPath)
        for grant in globalGrants where grant.matches(command: command) && grant.riskTier >= riskTier {
            return grant
        }

        return nil
    }

    // MARK: - Grant

    /// Add a new trust grant. Returns false if the grant is invalid
    /// (e.g., CRITICAL with workspace/global scope).
    @discardableResult
    public func addGrant(_ grant: TrustGrant) -> Bool {
        // Enforce: CRITICAL commands never get workspace or global scope
        if grant.riskTier >= .critical && grant.scope >= .workspace {
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        switch grant.scope {
        case .once:
            // "once" grants are ephemeral — the caller handles them.
            // We still record them in session for audit purposes.
            sessionGrants.append(grant)
        case .session:
            sessionGrants.append(grant)
        case .workspace:
            var grants = loadGrants(from: workspaceTrustPath)
            grants.append(grant)
            saveGrants(grants, to: workspaceTrustPath)
        case .global:
            var grants = loadGrants(from: globalTrustPath)
            grants.append(grant)
            saveGrants(grants, to: globalTrustPath)
        }
        return true
    }

    // MARK: - Revoke

    /// Clear all session-level grants (the `/untrust` command).
    public func clearSessionGrants() {
        lock.lock()
        defer { lock.unlock() }
        sessionGrants.removeAll()
    }

    /// Remove a specific grant by pattern from a given scope.
    public func removeGrant(pattern: String, scope: TrustScope) {
        lock.lock()
        defer { lock.unlock() }

        switch scope {
        case .once, .session:
            sessionGrants.removeAll { $0.pattern == pattern }
        case .workspace:
            var grants = loadGrants(from: workspaceTrustPath)
            grants.removeAll { $0.pattern == pattern }
            saveGrants(grants, to: workspaceTrustPath)
        case .global:
            var grants = loadGrants(from: globalTrustPath)
            grants.removeAll { $0.pattern == pattern }
            saveGrants(grants, to: globalTrustPath)
        }
    }

    // MARK: - Listing

    /// All active session grants.
    public var activeSessionGrants: [TrustGrant] {
        lock.lock()
        defer { lock.unlock() }
        return sessionGrants
    }

    /// All workspace-persisted grants.
    public var workspaceGrants: [TrustGrant] {
        loadGrants(from: workspaceTrustPath)
    }

    /// All global grants.
    public var globalGrants: [TrustGrant] {
        loadGrants(from: globalTrustPath)
    }

    // MARK: - Persistence

    private func loadGrants(from path: URL) -> [TrustGrant] {
        guard let data = try? Data(contentsOf: path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([TrustGrant].self, from: data)) ?? []
    }

    private func saveGrants(_ grants: [TrustGrant], to path: URL) {
        let dir = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(grants) else { return }
        try? data.write(to: path, options: .atomic)
    }
}
