import Foundation
import CryptoKit

// MARK: - Core Diff Types

/// A unified diff between two versions of content.
public struct UnifiedDiff: Sendable, Equatable {
    /// Original file path (nil for new files).
    public let oldPath: String?
    /// New file path (nil for deleted files).
    public let newPath: String?
    /// The hunks comprising this diff.
    public let hunks: [UnifiedHunk]
    /// Total lines added across all hunks.
    public let linesAdded: Int
    /// Total lines removed across all hunks.
    public let linesRemoved: Int

    public init(
        oldPath: String? = nil,
        newPath: String? = nil,
        hunks: [UnifiedHunk],
        linesAdded: Int,
        linesRemoved: Int
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.hunks = hunks
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }

    /// Whether this diff represents no changes.
    public var isEmpty: Bool {
        hunks.isEmpty
    }

    /// Render this diff to standard unified diff text format.
    public func render() -> String {
        var lines: [String] = []

        let oldName = oldPath ?? "/dev/null"
        let newName = newPath ?? "/dev/null"
        lines.append("--- a/\(oldName)")
        lines.append("+++ b/\(newName)")

        for hunk in hunks {
            lines.append("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
            for line in hunk.lines {
                switch line.kind {
                case .context:
                    lines.append(" \(line.content)")
                case .added:
                    lines.append("+\(line.content)")
                case .removed:
                    lines.append("-\(line.content)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}

/// A single hunk in a unified diff.
public struct UnifiedHunk: Sendable, Equatable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [UnifiedLine]

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, lines: [UnifiedLine]) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

/// A single line within a unified diff hunk.
public struct UnifiedLine: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case context
        case added
        case removed
    }

    public let kind: Kind
    public let content: String

    public init(kind: Kind, content: String) {
        self.kind = kind
        self.content = content
    }
}

// MARK: - DiffEngine

/// Computes unified diffs between strings using an LCS-based diff algorithm.
///
/// This is a pure-Swift implementation with no external dependencies.
/// Reference: CLAUDE.md §20, §29 Phase 7
public struct DiffEngine: Sendable {

    /// Number of context lines to include around each change.
    public let contextLines: Int

    public init(contextLines: Int = 3) {
        self.contextLines = contextLines
    }

    /// Compute a unified diff between two strings.
    ///
    /// - Parameters:
    ///   - old: The original content.
    ///   - new: The modified content.
    ///   - oldPath: Optional path for the original file.
    ///   - newPath: Optional path for the new file.
    /// - Returns: A `UnifiedDiff` representing the changes.
    public func diff(
        old: String,
        new: String,
        oldPath: String? = nil,
        newPath: String? = nil
    ) -> UnifiedDiff {
        let oldLines = splitLines(old)
        let newLines = splitLines(new)

        // Compute the edit operations using LCS
        let ops = computeEditOps(old: oldLines, new: newLines)

        // Check if there are any actual changes
        let hasChanges = ops.contains { $0.kind != .equal }
        if !hasChanges {
            return UnifiedDiff(oldPath: oldPath, newPath: newPath, hunks: [], linesAdded: 0, linesRemoved: 0)
        }

        // Build hunks from edit operations
        let hunks = buildHunks(ops: ops, oldLines: oldLines, newLines: newLines)

        var totalAdded = 0
        var totalRemoved = 0
        for hunk in hunks {
            for line in hunk.lines {
                switch line.kind {
                case .added: totalAdded += 1
                case .removed: totalRemoved += 1
                case .context: break
                }
            }
        }

        return UnifiedDiff(
            oldPath: oldPath,
            newPath: newPath,
            hunks: hunks,
            linesAdded: totalAdded,
            linesRemoved: totalRemoved
        )
    }

    /// Compute intra-line diff for highlighting changed portions within a line.
    ///
    /// Returns ranges within the old and new lines that differ.
    public func intraLineDiff(
        oldLine: String,
        newLine: String
    ) -> (oldRanges: [Range<String.Index>], newRanges: [Range<String.Index>]) {
        let oldWords = tokenizeForIntraLine(oldLine)
        let newWords = tokenizeForIntraLine(newLine)

        let ops = computeEditOps(old: oldWords, new: newWords)

        var oldRanges: [Range<String.Index>] = []
        var newRanges: [Range<String.Index>] = []

        // Reconstruct positions using word offsets
        var oldOffset = oldLine.startIndex
        var newOffset = newLine.startIndex

        for op in ops {
            switch op.kind {
            case .equal:
                let oldWord = oldWords[op.oldIndex!]
                let newWord = newWords[op.newIndex!]
                oldOffset = oldLine.index(oldOffset, offsetBy: oldWord.count, limitedBy: oldLine.endIndex) ?? oldLine.endIndex
                newOffset = newLine.index(newOffset, offsetBy: newWord.count, limitedBy: newLine.endIndex) ?? newLine.endIndex
            case .delete:
                let word = oldWords[op.oldIndex!]
                let end = oldLine.index(oldOffset, offsetBy: word.count, limitedBy: oldLine.endIndex) ?? oldLine.endIndex
                oldRanges.append(oldOffset..<end)
                oldOffset = end
            case .insert:
                let word = newWords[op.newIndex!]
                let end = newLine.index(newOffset, offsetBy: word.count, limitedBy: newLine.endIndex) ?? newLine.endIndex
                newRanges.append(newOffset..<end)
                newOffset = end
            }
        }

        return (oldRanges, newRanges)
    }

    /// Compute the SHA-256 hash of a string's content.
    public static func sha256(of content: String) -> String {
        let data = Data(content.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Compute the SHA-256 hash of data.
    public static func sha256(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Edit Operations via LCS

    /// An edit operation produced by comparing two sequences.
    private struct EditOp {
        enum Kind { case equal, delete, insert }
        let kind: Kind
        let oldIndex: Int? // index into old array
        let newIndex: Int? // index into new array
    }

    /// Compute edit operations using LCS (Longest Common Subsequence).
    ///
    /// Returns a sequence of equal/delete/insert operations that transforms `old` into `new`.
    private func computeEditOps(old: [String], new: [String]) -> [EditOp] {
        let n = old.count
        let m = new.count

        if n == 0 && m == 0 { return [] }
        if n == 0 {
            return (0..<m).map { EditOp(kind: .insert, oldIndex: nil, newIndex: $0) }
        }
        if m == 0 {
            return (0..<n).map { EditOp(kind: .delete, oldIndex: $0, newIndex: nil) }
        }

        // Build LCS DP table
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = Swift.max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to produce edit operations
        var ops: [EditOp] = []
        var i = n
        var j = m

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && old[i - 1] == new[j - 1] {
                ops.append(EditOp(kind: .equal, oldIndex: i - 1, newIndex: j - 1))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                ops.append(EditOp(kind: .insert, oldIndex: nil, newIndex: j - 1))
                j -= 1
            } else {
                ops.append(EditOp(kind: .delete, oldIndex: i - 1, newIndex: nil))
                i -= 1
            }
        }

        ops.reverse()
        return ops
    }

    // MARK: - Hunk Construction

    /// Build unified diff hunks from edit operations.
    private func buildHunks(ops: [EditOp], oldLines: [String], newLines: [String]) -> [UnifiedHunk] {
        // Convert edit ops to a flat list with line content
        struct DiffLine {
            let kind: UnifiedLine.Kind
            let content: String
            let oldIdx: Int? // 0-based index in old
            let newIdx: Int? // 0-based index in new
        }

        var diffLines: [DiffLine] = []
        for op in ops {
            switch op.kind {
            case .equal:
                diffLines.append(DiffLine(
                    kind: .context,
                    content: oldLines[op.oldIndex!],
                    oldIdx: op.oldIndex,
                    newIdx: op.newIndex
                ))
            case .delete:
                diffLines.append(DiffLine(
                    kind: .removed,
                    content: oldLines[op.oldIndex!],
                    oldIdx: op.oldIndex,
                    newIdx: nil
                ))
            case .insert:
                diffLines.append(DiffLine(
                    kind: .added,
                    content: newLines[op.newIndex!],
                    oldIdx: nil,
                    newIdx: op.newIndex
                ))
            }
        }

        // Find indices of changed lines
        var changeIndices: [Int] = []
        for (i, line) in diffLines.enumerated() {
            if line.kind != .context {
                changeIndices.append(i)
            }
        }

        if changeIndices.isEmpty { return [] }

        // Group changes into hunk regions (merge changes within 2*contextLines+1 of each other)
        var groups: [Range<Int>] = []
        var groupStart = changeIndices[0]
        var groupEnd = changeIndices[0]

        for i in 1..<changeIndices.count {
            if changeIndices[i] - groupEnd <= contextLines * 2 + 1 {
                groupEnd = changeIndices[i]
            } else {
                groups.append(groupStart..<groupEnd + 1)
                groupStart = changeIndices[i]
                groupEnd = changeIndices[i]
            }
        }
        groups.append(groupStart..<groupEnd + 1)

        // Build each hunk
        var hunks: [UnifiedHunk] = []

        for group in groups {
            let hunkStart = Swift.max(0, group.lowerBound - contextLines)
            let hunkEnd = Swift.min(diffLines.count, group.upperBound + contextLines)

            var hunkLines: [UnifiedLine] = []
            var oldCount = 0
            var newCount = 0

            // Determine oldStart and newStart from the first line in the hunk
            var oldStart = 1 // default for empty old
            var newStart = 1 // default for empty new

            // Walk through to find the starting old/new line numbers
            for i in hunkStart..<hunkEnd {
                let dl = diffLines[i]
                if i == hunkStart {
                    if let oi = dl.oldIdx {
                        oldStart = oi + 1 // 1-based
                    } else {
                        // First line is an insert; find the old position from context
                        // Look backward for a context/delete line
                        var found = false
                        for j in stride(from: i - 1, through: 0, by: -1) {
                            if let oi = diffLines[j].oldIdx {
                                oldStart = oi + 2 // 1-based, next line
                                found = true
                                break
                            }
                        }
                        if !found {
                            oldStart = 1
                        }
                    }
                    if let ni = dl.newIdx {
                        newStart = ni + 1
                    } else {
                        var found = false
                        for j in stride(from: i - 1, through: 0, by: -1) {
                            if let ni = diffLines[j].newIdx {
                                newStart = ni + 2
                                found = true
                                break
                            }
                        }
                        if !found {
                            newStart = 1
                        }
                    }
                }

                switch dl.kind {
                case .context:
                    hunkLines.append(UnifiedLine(kind: .context, content: dl.content))
                    oldCount += 1
                    newCount += 1
                case .removed:
                    hunkLines.append(UnifiedLine(kind: .removed, content: dl.content))
                    oldCount += 1
                case .added:
                    hunkLines.append(UnifiedLine(kind: .added, content: dl.content))
                    newCount += 1
                }
            }

            hunks.append(UnifiedHunk(
                oldStart: oldStart,
                oldCount: oldCount,
                newStart: newStart,
                newCount: newCount,
                lines: hunkLines
            ))
        }

        return hunks
    }

    // MARK: - Helpers

    /// Split content into lines, preserving empty trailing lines only if content ends with newline.
    private func splitLines(_ content: String) -> [String] {
        if content.isEmpty { return [] }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // If the content ends with a newline, the split produces a trailing empty string.
        // Remove it since it's not a real line.
        if content.hasSuffix("\n") && lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    /// Tokenize a line into words for intra-line diffing.
    private func tokenizeForIntraLine(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for char in line {
            if char.isWhitespace || char.isPunctuation || char == "(" || char == ")" || char == "{" || char == "}" || char == "[" || char == "]" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
