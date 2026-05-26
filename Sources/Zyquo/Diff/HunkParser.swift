import Foundation

// MARK: - HunkParser

/// Parses standard unified diff text format into structured `UnifiedDiff` values.
///
/// Handles multi-file diffs, standard `@@ -start,count +start,count @@` headers,
/// and `--- a/` / `+++ b/` file markers.
///
/// Reference: CLAUDE.md §29 Phase 7
public struct HunkParser: Sendable {

    public init() {}

    /// Parse a unified diff string into an array of `UnifiedDiff` values (one per file).
    public func parse(_ text: String) -> [UnifiedDiff] {
        let rawLines = text.components(separatedBy: "\n")
        var diffs: [UnifiedDiff] = []

        var currentOldPath: String?
        var currentNewPath: String?
        var currentHunks: [UnifiedHunk] = []
        var currentHunkLines: [UnifiedLine] = []
        var currentOldStart = 0
        var currentOldCount = 0
        var currentNewStart = 0
        var currentNewCount = 0
        var inHunk = false
        var totalAdded = 0
        var totalRemoved = 0

        func flushHunk() {
            if inHunk {
                currentHunks.append(UnifiedHunk(
                    oldStart: currentOldStart,
                    oldCount: currentOldCount,
                    newStart: currentNewStart,
                    newCount: currentNewCount,
                    lines: currentHunkLines
                ))
                currentHunkLines = []
                inHunk = false
            }
        }

        func flushFile() {
            flushHunk()
            if currentOldPath != nil || currentNewPath != nil {
                diffs.append(UnifiedDiff(
                    oldPath: currentOldPath,
                    newPath: currentNewPath,
                    hunks: currentHunks,
                    linesAdded: totalAdded,
                    linesRemoved: totalRemoved
                ))
                currentHunks = []
                currentOldPath = nil
                currentNewPath = nil
                totalAdded = 0
                totalRemoved = 0
            }
        }

        for line in rawLines {
            if line.hasPrefix("--- ") {
                // Start of a new file pair — the old path
                let path = extractPath(from: line, prefix: "--- ")
                // If we already have a file in progress, flush it
                if currentNewPath != nil {
                    flushFile()
                }
                currentOldPath = path
                continue
            }

            if line.hasPrefix("+++ ") {
                let path = extractPath(from: line, prefix: "+++ ")
                currentNewPath = path
                continue
            }

            if line.hasPrefix("@@") {
                flushHunk()
                let (oldStart, oldCount, newStart, newCount) = parseHunkHeader(line)
                currentOldStart = oldStart
                currentOldCount = oldCount
                currentNewStart = newStart
                currentNewCount = newCount
                inHunk = true
                continue
            }

            if line.hasPrefix("diff ") {
                // `diff --git` header — flush any previous file
                if currentNewPath != nil {
                    flushFile()
                }
                continue
            }

            if line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted file") ||
               line.hasPrefix("old mode") || line.hasPrefix("new mode") || line.hasPrefix("similarity") ||
               line.hasPrefix("rename ") || line.hasPrefix("copy ") || line.hasPrefix("Binary files") {
                // Git extended diff headers — skip
                continue
            }

            guard inHunk else { continue }

            if line.hasPrefix("+") {
                currentHunkLines.append(UnifiedLine(kind: .added, content: String(line.dropFirst())))
                totalAdded += 1
            } else if line.hasPrefix("-") {
                currentHunkLines.append(UnifiedLine(kind: .removed, content: String(line.dropFirst())))
                totalRemoved += 1
            } else if line.hasPrefix(" ") {
                currentHunkLines.append(UnifiedLine(kind: .context, content: String(line.dropFirst())))
            } else if line == "\\ No newline at end of file" {
                // Skip this marker
                continue
            } else if line.isEmpty {
                // Empty context line (no leading space — happens at end of hunks)
                currentHunkLines.append(UnifiedLine(kind: .context, content: ""))
            }
        }

        flushFile()
        return diffs
    }

    /// Parse a single unified diff string into one `UnifiedDiff`.
    /// If the text contains multiple files, only the first is returned.
    public func parseSingle(_ text: String) -> UnifiedDiff? {
        let diffs = parse(text)
        return diffs.first
    }

    // MARK: - Helpers

    /// Extract a file path from a diff header line.
    private func extractPath(from line: String, prefix: String) -> String {
        var path = String(line.dropFirst(prefix.count))
        // Remove `a/` or `b/` prefix used by git
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path = String(path.dropFirst(2))
        }
        // Handle /dev/null
        if path == "/dev/null" {
            return path
        }
        return path
    }

    /// Parse a hunk header line like `@@ -1,3 +1,4 @@` or `@@ -1 +1,2 @@`.
    private func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        // Pattern: @@ -oldStart[,oldCount] +newStart[,newCount] @@
        var oldStart = 1
        var oldCount = 1
        var newStart = 1
        var newCount = 1

        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard stripped.hasPrefix("@@") else {
            return (oldStart, oldCount, newStart, newCount)
        }

        // Find content between @@ markers
        let parts = stripped.components(separatedBy: "@@")
        guard parts.count >= 3 else {
            return (oldStart, oldCount, newStart, newCount)
        }

        let rangePart = parts[1].trimmingCharacters(in: .whitespaces)
        let tokens = rangePart.components(separatedBy: " ")

        for token in tokens {
            if token.hasPrefix("-") {
                let nums = String(token.dropFirst()).components(separatedBy: ",")
                if let s = Int(nums[0]) { oldStart = s }
                if nums.count > 1, let c = Int(nums[1]) { oldCount = c }
            } else if token.hasPrefix("+") {
                let nums = String(token.dropFirst()).components(separatedBy: ",")
                if let s = Int(nums[0]) { newStart = s }
                if nums.count > 1, let c = Int(nums[1]) { newCount = c }
            }
        }

        return (oldStart, oldCount, newStart, newCount)
    }
}
