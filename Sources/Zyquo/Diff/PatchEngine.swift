import Foundation

// MARK: - PatchError

/// Errors that can occur during patch application.
public enum PatchError: Error, Sendable, CustomStringConvertible {
    /// The pre-image SHA-256 does not match the expected value.
    case stalePreImage(expected: String, actual: String)
    /// A hunk could not be applied because the context does not match.
    case hunkMismatch(hunkIndex: Int, reason: String)
    /// The file to be patched does not exist.
    case fileNotFound(path: String)
    /// An I/O error occurred during file operations.
    case ioError(String)

    public var description: String {
        switch self {
        case .stalePreImage(let expected, let actual):
            return "Stale pre-image: expected SHA-256 \(expected.prefix(12))..., got \(actual.prefix(12))..."
        case .hunkMismatch(let idx, let reason):
            return "Hunk \(idx) failed to apply: \(reason)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .ioError(let msg):
            return "I/O error: \(msg)"
        }
    }
}

// MARK: - PatchEngine

/// Applies and reverses unified diffs, with atomic file write support.
///
/// All file writes use temp-file + POSIX rename for atomicity.
/// Reference: CLAUDE.md §20, §29 Phase 7
public struct PatchEngine: Sendable {

    public init() {}

    // MARK: - Apply to String

    /// Apply a unified diff to string content.
    ///
    /// - Parameters:
    ///   - diff: The unified diff to apply.
    ///   - content: The original string content.
    ///   - expectSHA: Optional expected SHA-256 of the original content. If provided
    ///     and it does not match, a `PatchError.stalePreImage` is thrown.
    /// - Returns: The patched content string.
    public func apply(_ diff: UnifiedDiff, to content: String, expectSHA: String? = nil) throws -> String {
        // Verify pre-image hash if provided
        if let expected = expectSHA {
            let actual = DiffEngine.sha256(of: content)
            guard actual == expected else {
                throw PatchError.stalePreImage(expected: expected, actual: actual)
            }
        }

        if diff.isEmpty {
            return content
        }

        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // If content ends with newline, remove trailing empty element
        let hadTrailingNewline = content.hasSuffix("\n")
        if hadTrailingNewline && lines.last == "" {
            lines.removeLast()
        }

        // Apply hunks in reverse order to preserve line numbers
        let sortedHunks = diff.hunks.sorted { $0.oldStart > $1.oldStart }

        for (hunkIdx, hunk) in sortedHunks.enumerated() {
            let startIdx = hunk.oldStart - 1 // convert 1-based to 0-based

            // Verify context lines match (best-effort)
            var readIdx = startIdx
            for line in hunk.lines {
                switch line.kind {
                case .context:
                    if readIdx < lines.count {
                        if lines[readIdx] != line.content {
                            throw PatchError.hunkMismatch(
                                hunkIndex: diff.hunks.count - 1 - hunkIdx,
                                reason: "Context mismatch at line \(readIdx + 1): expected '\(line.content)', found '\(lines[readIdx])'"
                            )
                        }
                    }
                    readIdx += 1
                case .removed:
                    if readIdx < lines.count {
                        if lines[readIdx] != line.content {
                            throw PatchError.hunkMismatch(
                                hunkIndex: diff.hunks.count - 1 - hunkIdx,
                                reason: "Remove mismatch at line \(readIdx + 1): expected '\(line.content)', found '\(lines[readIdx])'"
                            )
                        }
                    }
                    readIdx += 1
                case .added:
                    break // added lines don't consume old lines
                }
            }

            // Apply the hunk
            var newLines: [String] = []
            var oldLineIdx = startIdx

            for line in hunk.lines {
                switch line.kind {
                case .context:
                    if oldLineIdx < lines.count {
                        newLines.append(lines[oldLineIdx])
                    }
                    oldLineIdx += 1
                case .removed:
                    oldLineIdx += 1 // skip the removed line
                case .added:
                    newLines.append(line.content)
                }
            }

            // Replace the range in lines
            let endIdx = startIdx + hunk.oldCount
            let safeEnd = min(endIdx, lines.count)
            let safeStart = min(startIdx, lines.count)

            if safeStart <= safeEnd {
                lines.replaceSubrange(safeStart..<safeEnd, with: newLines)
            }
        }

        // Reconstruct the string
        if lines.isEmpty {
            return hadTrailingNewline ? "" : ""
        }
        var result = lines.joined(separator: "\n")
        if hadTrailingNewline {
            result.append("\n")
        }
        return result
    }

    // MARK: - Apply to File

    /// Apply a unified diff to a file on disk, atomically.
    ///
    /// Reads the file, applies the diff, writes to a temporary file, then renames.
    /// POSIX `rename()` is atomic on the same filesystem.
    ///
    /// - Parameters:
    ///   - diff: The diff to apply.
    ///   - path: The file URL to patch.
    ///   - expectSHA: Optional pre-image SHA for staleness check.
    public func applyToFile(diff: UnifiedDiff, path: URL, expectSHA: String? = nil) throws {
        let fm = FileManager.default

        // For new files (old path is /dev/null), create the file
        if diff.oldPath == "/dev/null" || !fm.fileExists(atPath: path.path) {
            let content = reconstructFromAdds(diff)
            try atomicWrite(content: content, to: path)
            return
        }

        guard let data = fm.contents(atPath: path.path),
              let content = String(data: data, encoding: .utf8) else {
            throw PatchError.fileNotFound(path: path.path)
        }

        let patched = try apply(diff, to: content, expectSHA: expectSHA)
        try atomicWrite(content: patched, to: path)
    }

    // MARK: - Reverse

    /// Compute the inverse of a unified diff.
    ///
    /// The reverse diff, when applied to the patched content, restores the original.
    public func reverse(_ diff: UnifiedDiff) -> UnifiedDiff {
        let reversedHunks = diff.hunks.map { hunk -> UnifiedHunk in
            let reversedLines = hunk.lines.map { line -> UnifiedLine in
                switch line.kind {
                case .context:
                    return line
                case .added:
                    return UnifiedLine(kind: .removed, content: line.content)
                case .removed:
                    return UnifiedLine(kind: .added, content: line.content)
                }
            }

            return UnifiedHunk(
                oldStart: hunk.newStart,
                oldCount: hunk.newCount,
                newStart: hunk.oldStart,
                newCount: hunk.oldCount,
                lines: reversedLines
            )
        }

        return UnifiedDiff(
            oldPath: diff.newPath,
            newPath: diff.oldPath,
            hunks: reversedHunks,
            linesAdded: diff.linesRemoved,
            linesRemoved: diff.linesAdded
        )
    }

    // MARK: - Helpers

    /// Reconstruct content from a diff that is purely additions (new file).
    private func reconstructFromAdds(_ diff: UnifiedDiff) -> String {
        var lines: [String] = []
        for hunk in diff.hunks {
            for line in hunk.lines {
                if line.kind == .added || line.kind == .context {
                    lines.append(line.content)
                }
            }
        }
        if lines.isEmpty { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write content to a file atomically using temp + rename.
    private func atomicWrite(content: String, to path: URL) throws {
        let fm = FileManager.default
        let dir = path.deletingLastPathComponent()

        // Ensure directory exists
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Write to temporary file in same directory (same filesystem for atomic rename)
        let tempName = ".\(path.lastPathComponent).zyquo-tmp-\(UUID().uuidString)"
        let tempURL = dir.appendingPathComponent(tempName)

        guard let data = content.data(using: .utf8) else {
            throw PatchError.ioError("Failed to encode content as UTF-8")
        }

        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            throw PatchError.ioError("Failed to write temp file: \(error.localizedDescription)")
        }

        // Atomic rename
        do {
            // Remove existing file first if it exists (rename requires this on some systems)
            if fm.fileExists(atPath: path.path) {
                try fm.removeItem(at: path)
            }
            try fm.moveItem(at: tempURL, to: path)
        } catch {
            // Clean up temp file on failure
            try? fm.removeItem(at: tempURL)
            throw PatchError.ioError("Failed to rename temp file: \(error.localizedDescription)")
        }
    }
}
