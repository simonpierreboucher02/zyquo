import Foundation

public struct BoundaryGuard: Sendable {
    public let workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot.standardizedFileURL
    }

    public func validate(_ path: URL) -> BoundaryResult {
        let resolved = resolveSymlinks(path).standardizedFileURL
        let rootPath = workspaceRoot.path
        let targetPath = resolved.path

        guard targetPath.hasPrefix(rootPath) else {
            return .violation(path: targetPath, reason: "Path is outside workspace root")
        }

        if isSensitivePath(targetPath) {
            return .sensitive(path: targetPath, reason: "Path touches sensitive system location")
        }

        return .allowed
    }

    public func validate(_ path: String) -> BoundaryResult {
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = workspaceRoot.appendingPathComponent(path)
        }
        return validate(url)
    }

    public func isInside(_ path: URL) -> Bool {
        if case .allowed = validate(path) { return true }
        return false
    }

    public func isInside(_ path: String) -> Bool {
        if case .allowed = validate(path) { return true }
        return false
    }

    private func resolveSymlinks(_ url: URL) -> URL {
        let path = url.path
        guard let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return url.resolvingSymlinksInPath()
        }
        if resolved.hasPrefix("/") {
            return URL(fileURLWithPath: resolved)
        }
        return url.deletingLastPathComponent().appendingPathComponent(resolved).resolvingSymlinksInPath()
    }

    private func isSensitivePath(_ path: String) -> Bool {
        let sensitive = [
            "/.ssh", "/.aws", "/.gnupg", "/.config/gcloud",
            "/Library/", "/System/", "/private/",
            "/usr/bin", "/usr/sbin", "/usr/lib",
        ]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for s in sensitive {
            if s.hasPrefix("/") && !s.hasPrefix("/.") {
                if path.hasPrefix(s) { return true }
            } else {
                if path.hasPrefix(home + s) { return true }
            }
        }
        return false
    }
}

public enum BoundaryResult: Sendable, Equatable {
    case allowed
    case violation(path: String, reason: String)
    case sensitive(path: String, reason: String)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}
