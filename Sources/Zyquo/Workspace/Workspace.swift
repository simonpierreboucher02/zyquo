import Foundation

public actor Workspace {
    public let root: URL
    private let boundaryGuard: BoundaryGuard
    private let ignoreRules: IgnoreRules
    private let detector: ProjectDetector
    private let analyzer: RepoAnalyzer
    private var cachedIndex: WorkspaceIndex?

    public init(root: URL) {
        self.root = root.standardizedFileURL
        self.boundaryGuard = BoundaryGuard(workspaceRoot: root)
        self.detector = ProjectDetector()
        self.analyzer = RepoAnalyzer()

        var ignoreURLs: [URL] = []
        let gitignore = root.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: gitignore.path) {
            ignoreURLs.append(gitignore)
        }
        let zyquoignore = root.appendingPathComponent(".zyquoignore")
        if FileManager.default.fileExists(atPath: zyquoignore.path) {
            ignoreURLs.append(zyquoignore)
        }
        self.ignoreRules = IgnoreRules.load(from: ignoreURLs)
    }

    public func scan() async -> WorkspaceIndex {
        if let cached = cachedIndex { return cached }
        let index = await performScan()
        cachedIndex = index
        return index
    }

    public func rescan() async -> WorkspaceIndex {
        cachedIndex = nil
        return await scan()
    }

    public func isInsideBoundary(_ path: URL) -> Bool {
        boundaryGuard.isInside(path)
    }

    public func isInsideBoundary(_ path: String) -> Bool {
        boundaryGuard.isInside(path)
    }

    public func validateBoundary(_ path: String) throws {
        let result = boundaryGuard.validate(path)
        switch result {
        case .allowed:
            break
        case .violation(let p, _):
            throw ZyquoError.workspace(.boundaryViolation(path: p))
        case .sensitive(let p, let reason):
            throw ZyquoError.workspace(WorkspaceError(
                code: "workspace.sensitive",
                description: "Sensitive path: \(p)",
                remediation: reason
            ))
        }
    }

    public func isIgnored(_ relativePath: String) -> Bool {
        ignoreRules.isIgnored(relativePath)
    }

    public func detect() -> ProjectDescriptor {
        let files = collectFiles()
        return detector.detect(at: root, files: files)
    }

    public func gitStatus() -> GitStatus? {
        analyzer.analyzeGit(at: root)
    }

    private func performScan() async -> WorkspaceIndex {
        let files = collectFiles()
        let descriptor = detector.detect(at: root, files: files)
        let gitStatus = analyzer.analyzeGit(at: root)
        let docs = analyzer.findDocumentation(at: root)
        let totalSize = files.reduce(UInt64(0)) { $0 + $1.size }

        return WorkspaceIndex(
            root: root,
            languages: descriptor.languages,
            frameworks: descriptor.frameworks,
            packageManager: descriptor.packageManager,
            testCommand: descriptor.testCommand,
            buildCommand: descriptor.buildCommand,
            gitStatus: gitStatus,
            fileCount: files.count,
            totalSize: totalSize,
            lastFullScan: Date(),
            documentation: docs
        )
    }

    private func collectFiles() -> [FileSnapshot] {
        let fm = FileManager.default
        var snapshots: [FileSnapshot] = []

        let skipDirs: Set<String> = [
            ".git", ".hg", ".svn", "node_modules", ".build", "build",
            "DerivedData", "Pods", ".venv", "venv", "__pycache__",
            "target", "dist", ".next", ".nuxt", ".output",
        ]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent

            if skipDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            guard let snapshot = FileSnapshot.from(url: url, relativeTo: root) else { continue }

            if snapshot.isDirectory {
                if ignoreRules.isIgnored(snapshot.relativePath + "/") {
                    enumerator.skipDescendants()
                }
                continue
            }

            if ignoreRules.isIgnored(snapshot.relativePath) { continue }

            snapshots.append(snapshot)
        }

        return snapshots
    }
}
