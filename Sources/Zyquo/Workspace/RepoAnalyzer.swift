import Foundation

public struct GitStatus: Sendable {
    public let branch: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let isClean: Bool
    public let stagedCount: Int
    public let unstagedCount: Int
    public let untrackedCount: Int
    public let hasMergeInProgress: Bool
    public let hasRebaseInProgress: Bool
}

public struct RepoAnalyzer: Sendable {
    public init() {}

    public func analyzeGit(at root: URL) -> GitStatus? {
        let fm = FileManager.default
        let gitDir = root.appendingPathComponent(".git")
        guard fm.fileExists(atPath: gitDir.path) else { return nil }

        let branch = readBranch(gitDir: gitDir)
        let (ahead, behind, upstream) = readUpstream(at: root, branch: branch)
        let (staged, unstaged, untracked) = readStatus(at: root)
        let merging = fm.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path)
        let rebasing = fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-merge").path) ||
                       fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-apply").path)

        return GitStatus(
            branch: branch,
            upstream: upstream,
            ahead: ahead,
            behind: behind,
            isClean: staged == 0 && unstaged == 0 && untracked == 0,
            stagedCount: staged,
            unstagedCount: unstaged,
            untrackedCount: untracked,
            hasMergeInProgress: merging,
            hasRebaseInProgress: rebasing
        )
    }

    public func readREADME(at root: URL, maxBytes: Int = 8192) -> String? {
        let candidates = ["README.md", "README.txt", "README", "readme.md", "Readme.md"]
        for name in candidates {
            let url = root.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = String(data: data.prefix(maxBytes), encoding: .utf8)
            return text
        }
        return nil
    }

    public func findDocumentation(at root: URL) -> [String] {
        let fm = FileManager.default
        let candidates = [
            "README.md", "ARCHITECTURE.md", "CONTRIBUTING.md",
            "CHANGELOG.md", "CLAUDE.md", "docs/",
        ]
        var found: [String] = []
        for name in candidates {
            let url = root.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { found.append(name) }
        }
        return found
    }

    private func readBranch(gitDir: URL) -> String? {
        let headFile = gitDir.appendingPathComponent("HEAD")
        guard let content = try? String(contentsOf: headFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        if content.hasPrefix("ref: refs/heads/") {
            return String(content.dropFirst("ref: refs/heads/".count))
        }
        return String(content.prefix(8))
    }

    private func readUpstream(at root: URL, branch: String?) -> (ahead: Int, behind: Int, upstream: String?) {
        guard let branch else { return (0, 0, nil) }
        let result = runGit(at: root, args: ["rev-list", "--left-right", "--count", "\(branch)...@{upstream}"])
        guard let output = result else { return (0, 0, nil) }
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
        guard parts.count == 2 else { return (0, 0, nil) }
        let ahead = Int(parts[0]) ?? 0
        let behind = Int(parts[1]) ?? 0

        let upstreamResult = runGit(at: root, args: ["config", "--get", "branch.\(branch).remote"])
        let remote = upstreamResult?.trimmingCharacters(in: .whitespacesAndNewlines)

        return (ahead, behind, remote)
    }

    private func readStatus(at root: URL) -> (staged: Int, unstaged: Int, untracked: Int) {
        guard let output = runGit(at: root, args: ["status", "--porcelain", "-z"]) else {
            return (0, 0, 0)
        }
        var staged = 0, unstaged = 0, untracked = 0
        let entries = output.split(separator: "\0", omittingEmptySubsequences: false)
        for entry in entries {
            guard entry.count >= 2 else { continue }
            let idx = entry.index(entry.startIndex, offsetBy: 0)
            let wt = entry.index(entry.startIndex, offsetBy: 1)
            let x = entry[idx]
            let y = entry[wt]
            if x == "?" { untracked += 1 }
            else {
                if x != " " && x != "?" { staged += 1 }
                if y != " " && y != "?" { unstaged += 1 }
            }
        }
        return (staged, unstaged, untracked)
    }

    private func runGit(at root: URL, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        process.environment = ["GIT_TERMINAL_PROMPT": "0"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
