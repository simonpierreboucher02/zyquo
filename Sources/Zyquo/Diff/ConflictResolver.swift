import Foundation

// MARK: - MergeResult

/// The result of a three-way merge operation.
public enum MergeResult: Sendable, Equatable {
    /// All changes merged cleanly without conflicts.
    case clean(merged: String)
    /// Conflicts were detected. The content includes conflict markers.
    case conflicted(content: String, conflicts: [ConflictRegion])
}

// MARK: - ConflictRegion

/// A region within the merged output where conflicts exist.
public struct ConflictRegion: Sendable, Equatable {
    /// 1-based line range in the merged output where the conflict starts (at the <<<<<<< marker).
    public let startLine: Int
    /// 1-based line range in the merged output where the conflict ends (at the >>>>>>> marker).
    public let endLine: Int
    /// The "ours" side content.
    public let ours: String
    /// The "theirs" side content.
    public let theirs: String

    public init(startLine: Int, endLine: Int, ours: String, theirs: String) {
        self.startLine = startLine
        self.endLine = endLine
        self.ours = ours
        self.theirs = theirs
    }
}

// MARK: - ConflictResolver

/// Performs three-way merge between a base version, "ours" version, and "theirs" version.
///
/// Uses a line-based diff-merge strategy:
/// 1. Compute diff(base, ours) and diff(base, theirs)
/// 2. Walk through base lines, applying non-overlapping changes from both sides
/// 3. When both sides modify the same region, emit conflict markers
///
/// Reference: CLAUDE.md §20.4, §29 Phase 7
public struct ConflictResolver: Sendable {

    public init() {}

    /// Perform a three-way merge.
    ///
    /// - Parameters:
    ///   - base: The common ancestor content.
    ///   - ours: Our version of the content.
    ///   - theirs: Their version of the content.
    /// - Returns: A `MergeResult` that is either clean or contains conflicts.
    public func threeWayMerge(base: String, ours: String, theirs: String) -> MergeResult {
        let baseLines = splitLines(base)
        let ourLines = splitLines(ours)
        let theirLines = splitLines(theirs)

        // If ours == theirs, trivially clean
        if ours == theirs {
            return .clean(merged: ours)
        }

        // If ours == base, take theirs
        if ours == base {
            return .clean(merged: theirs)
        }

        // If theirs == base, take ours
        if theirs == base {
            return .clean(merged: ours)
        }

        // Compute change regions for each side relative to base
        let ourChanges = computeChangeRegions(base: baseLines, modified: ourLines)
        let theirChanges = computeChangeRegions(base: baseLines, modified: theirLines)

        // Merge the changes
        return mergeChanges(
            baseLines: baseLines,
            ourLines: ourLines,
            theirLines: theirLines,
            ourChanges: ourChanges,
            theirChanges: theirChanges,
            hadTrailingNewline: base.hasSuffix("\n")
        )
    }

    // MARK: - Change Regions

    /// A region of change in the modified text relative to base.
    private struct ChangeRegion {
        /// Start index in base (inclusive).
        let baseStart: Int
        /// End index in base (exclusive).
        let baseEnd: Int
        /// The replacement lines from the modified version.
        let newLines: [String]
    }

    /// Compute contiguous regions of change between base and modified.
    private func computeChangeRegions(base: [String], modified: [String]) -> [ChangeRegion] {
        // Use LCS-based approach to find matching lines
        let lcs = longestCommonSubsequence(base, modified)

        var regions: [ChangeRegion] = []
        var baseIdx = 0
        var modIdx = 0
        var lcsIdx = 0

        while baseIdx < base.count || modIdx < modified.count {
            if lcsIdx < lcs.count {
                let (lcsBaseIdx, lcsModIdx) = lcs[lcsIdx]

                // Everything before the next LCS match is a change
                if baseIdx < lcsBaseIdx || modIdx < lcsModIdx {
                    let baseStart = baseIdx
                    let baseEnd = lcsBaseIdx
                    var newLines: [String] = []
                    while modIdx < lcsModIdx {
                        newLines.append(modified[modIdx])
                        modIdx += 1
                    }
                    if baseStart < baseEnd || !newLines.isEmpty {
                        regions.append(ChangeRegion(baseStart: baseStart, baseEnd: baseEnd, newLines: newLines))
                    }
                }

                // Skip the matching line
                baseIdx = lcsBaseIdx + 1
                modIdx = lcsModIdx + 1
                lcsIdx += 1
            } else {
                // Remainder after LCS is exhausted
                let baseStart = baseIdx
                var newLines: [String] = []
                while modIdx < modified.count {
                    newLines.append(modified[modIdx])
                    modIdx += 1
                }
                if baseStart < base.count || !newLines.isEmpty {
                    regions.append(ChangeRegion(baseStart: baseStart, baseEnd: base.count, newLines: newLines))
                }
                baseIdx = base.count
            }
        }

        return regions
    }

    /// Compute LCS as pairs of (baseIndex, modifiedIndex).
    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count
        let m = b.count

        if n == 0 || m == 0 { return [] }

        // DP table
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)

        for i in 1...n {
            for j in 1...m {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find the actual subsequence
        var result: [(Int, Int)] = []
        var i = n
        var j = m
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        result.reverse()
        return result
    }

    // MARK: - Merge Logic

    /// Check if two change regions overlap (touch the same base lines).
    private func regionsOverlap(_ a: ChangeRegion, _ b: ChangeRegion) -> Bool {
        return a.baseStart < b.baseEnd && b.baseStart < a.baseEnd
    }

    /// Merge changes from both sides, detecting conflicts.
    private func mergeChanges(
        baseLines: [String],
        ourLines: [String],
        theirLines: [String],
        ourChanges: [ChangeRegion],
        theirChanges: [ChangeRegion],
        hadTrailingNewline: Bool
    ) -> MergeResult {
        var result: [String] = []
        var conflicts: [ConflictRegion] = []
        var baseIdx = 0
        var ourIdx = 0
        var theirIdx = 0

        while ourIdx < ourChanges.count || theirIdx < theirChanges.count {
            let ourChange = ourIdx < ourChanges.count ? ourChanges[ourIdx] : nil
            let theirChange = theirIdx < theirChanges.count ? theirChanges[theirIdx] : nil

            if let oc = ourChange, let tc = theirChange {
                if regionsOverlap(oc, tc) {
                    // Emit base lines up to the start of the overlap
                    let overlapStart = min(oc.baseStart, tc.baseStart)
                    while baseIdx < overlapStart {
                        result.append(baseLines[baseIdx])
                        baseIdx += 1
                    }

                    // Check if both sides made the same change
                    if oc.newLines == tc.newLines && oc.baseStart == tc.baseStart && oc.baseEnd == tc.baseEnd {
                        // Identical change — no conflict
                        result.append(contentsOf: oc.newLines)
                    } else {
                        // Conflict
                        let conflictStart = result.count + 1 // 1-based

                        let oursContent = oc.newLines.joined(separator: "\n")
                        let theirsContent = tc.newLines.joined(separator: "\n")

                        result.append("<<<<<<< ours")
                        result.append(contentsOf: oc.newLines)
                        result.append("=======")
                        result.append(contentsOf: tc.newLines)
                        result.append(">>>>>>> theirs")

                        let conflictEnd = result.count // 1-based (already points to last line)

                        conflicts.append(ConflictRegion(
                            startLine: conflictStart,
                            endLine: conflictEnd,
                            ours: oursContent,
                            theirs: theirsContent
                        ))
                    }

                    baseIdx = max(oc.baseEnd, tc.baseEnd)
                    ourIdx += 1
                    theirIdx += 1
                } else if oc.baseStart <= tc.baseStart {
                    // Our change comes first — apply it
                    while baseIdx < oc.baseStart {
                        result.append(baseLines[baseIdx])
                        baseIdx += 1
                    }
                    result.append(contentsOf: oc.newLines)
                    baseIdx = oc.baseEnd
                    ourIdx += 1
                } else {
                    // Their change comes first — apply it
                    while baseIdx < tc.baseStart {
                        result.append(baseLines[baseIdx])
                        baseIdx += 1
                    }
                    result.append(contentsOf: tc.newLines)
                    baseIdx = tc.baseEnd
                    theirIdx += 1
                }
            } else if let oc = ourChange {
                while baseIdx < oc.baseStart {
                    result.append(baseLines[baseIdx])
                    baseIdx += 1
                }
                result.append(contentsOf: oc.newLines)
                baseIdx = oc.baseEnd
                ourIdx += 1
            } else if let tc = theirChange {
                while baseIdx < tc.baseStart {
                    result.append(baseLines[baseIdx])
                    baseIdx += 1
                }
                result.append(contentsOf: tc.newLines)
                baseIdx = tc.baseEnd
                theirIdx += 1
            }
        }

        // Append remaining base lines
        while baseIdx < baseLines.count {
            result.append(baseLines[baseIdx])
            baseIdx += 1
        }

        var merged = result.joined(separator: "\n")
        if hadTrailingNewline && !merged.isEmpty {
            merged.append("\n")
        }

        if conflicts.isEmpty {
            return .clean(merged: merged)
        } else {
            return .conflicted(content: merged, conflicts: conflicts)
        }
    }

    // MARK: - Helpers

    private func splitLines(_ content: String) -> [String] {
        if content.isEmpty { return [] }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if content.hasSuffix("\n") && lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
