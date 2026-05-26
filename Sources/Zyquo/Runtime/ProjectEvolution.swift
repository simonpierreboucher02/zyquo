import Foundation

// MARK: - TrendDirection

/// The direction of a project's evolution over time.
public enum TrendDirection: String, Sendable, Codable {
    case growing
    case stable
    case shrinking
}

// MARK: - ProjectSnapshot

/// A point-in-time snapshot of a project's structural metrics.
///
/// Snapshots are taken periodically and compared to track how
/// a project evolves over time — file counts, line counts,
/// language distribution, and documentation coverage.
///
/// Reference: CLAUDE.md §30 Phase 10
public struct ProjectSnapshot: Sendable, Codable, Equatable {
    /// When this snapshot was taken.
    public let date: Date
    /// Total number of tracked files in the workspace.
    public let fileCount: Int
    /// Total lines of code across all files.
    public let totalLines: Int
    /// Number of files per language (language name -> file count).
    public let languageBreakdown: [String: Int]
    /// Number of files identified as test files.
    public let testFileCount: Int
    /// Number of files identified as documentation.
    public let docFileCount: Int
    /// Number of detected frameworks.
    public let frameworkCount: Int

    public init(
        date: Date = Date(),
        fileCount: Int,
        totalLines: Int,
        languageBreakdown: [String: Int] = [:],
        testFileCount: Int = 0,
        docFileCount: Int = 0,
        frameworkCount: Int = 0
    ) {
        self.date = date
        self.fileCount = fileCount
        self.totalLines = totalLines
        self.languageBreakdown = languageBreakdown
        self.testFileCount = testFileCount
        self.docFileCount = docFileCount
        self.frameworkCount = frameworkCount
    }

    /// The primary language by file count, or nil if no languages detected.
    public var primaryLanguage: String? {
        languageBreakdown.max(by: { $0.value < $1.value })?.key
    }

    /// Test-to-source ratio (0.0 if no non-test files).
    public var testRatio: Double {
        let sourceFiles = fileCount - testFileCount - docFileCount
        guard sourceFiles > 0 else { return 0.0 }
        return Double(testFileCount) / Double(sourceFiles)
    }
}

// MARK: - EvolutionDelta

/// The difference between two project snapshots, representing
/// how the project changed over a period.
public struct EvolutionDelta: Sendable {
    /// Human-readable period description (e.g. "7 days", "30 days").
    public let period: String
    /// Net files added.
    public let filesAdded: Int
    /// Net files removed.
    public let filesRemoved: Int
    /// Net lines added.
    public let linesAdded: Int
    /// Net lines removed.
    public let linesRemoved: Int
    /// Languages that appeared in the newer snapshot but not the older.
    public let newLanguages: [String]
    /// Human-readable summary of the evolution.
    public let summary: String

    public init(
        period: String,
        filesAdded: Int,
        filesRemoved: Int,
        linesAdded: Int,
        linesRemoved: Int,
        newLanguages: [String],
        summary: String
    ) {
        self.period = period
        self.filesAdded = filesAdded
        self.filesRemoved = filesRemoved
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.newLanguages = newLanguages
        self.summary = summary
    }

    /// Net file change (positive = growth, negative = shrinkage).
    public var netFiles: Int { filesAdded - filesRemoved }

    /// Net line change.
    public var netLines: Int { linesAdded - linesRemoved }
}

// MARK: - ProjectTrend

/// An aggregated trend computed from multiple snapshots over time.
public struct ProjectTrend: Sendable {
    /// Whether the project is growing, stable, or shrinking.
    public let direction: TrendDirection
    /// The rate of growth (positive) or shrinkage (negative) as a
    /// percentage per snapshot interval.
    public let growthRate: Double
    /// Human-readable description of the trend.
    public let description: String

    public init(direction: TrendDirection, growthRate: Double, description: String) {
        self.direction = direction
        self.growthRate = growthRate
        self.description = description
    }
}

// MARK: - ProjectEvolution

/// Tracks how a project evolves over time by comparing snapshots
/// and computing trends.
///
/// Used by the agent to understand whether a project is actively
/// growing, stabilizing, or being reduced. This context informs
/// planning strategies and helps the Architect agent make better
/// structural decisions.
///
/// Reference: CLAUDE.md §30 Phase 10
public struct ProjectEvolution: Sendable {

    public init() {}

    /// Take a snapshot of the current workspace state.
    ///
    /// - Parameter workspace: The workspace index to snapshot.
    /// - Returns: A ProjectSnapshot with current metrics.
    public func snapshot(workspace: WorkspaceIndex) -> ProjectSnapshot {
        // Build language breakdown from workspace languages
        var languageBreakdown: [String: Int] = [:]
        for (language, weight) in workspace.languages {
            // Estimate file count from weight percentage
            let estimatedFiles = Int(weight * Float(workspace.fileCount))
            if estimatedFiles > 0 {
                languageBreakdown[language.displayName] = estimatedFiles
            }
        }

        // Estimate test/doc file counts from workspace data
        let testFileCount = estimateTestFiles(workspace: workspace)
        let docFileCount = workspace.documentation.count

        return ProjectSnapshot(
            date: Date(),
            fileCount: workspace.fileCount,
            totalLines: estimateTotalLines(fileCount: workspace.fileCount),
            languageBreakdown: languageBreakdown,
            testFileCount: testFileCount,
            docFileCount: docFileCount,
            frameworkCount: workspace.frameworks.count
        )
    }

    /// Compare two snapshots to produce an evolution delta.
    ///
    /// - Parameters:
    ///   - old: The earlier snapshot.
    ///   - new: The later snapshot.
    /// - Returns: An EvolutionDelta describing the change.
    public func compare(old: ProjectSnapshot, new: ProjectSnapshot) -> EvolutionDelta {
        let daysBetween = Calendar.current.dateComponents(
            [.day],
            from: old.date,
            to: new.date
        ).day ?? 0

        let period = daysBetween == 1 ? "1 day" : "\(daysBetween) days"

        // Compute file changes
        let fileDiff = new.fileCount - old.fileCount
        let filesAdded = max(0, fileDiff)
        let filesRemoved = max(0, -fileDiff)

        // Compute line changes
        let lineDiff = new.totalLines - old.totalLines
        let linesAdded = max(0, lineDiff)
        let linesRemoved = max(0, -lineDiff)

        // Find new languages
        let oldLanguages = Set(old.languageBreakdown.keys)
        let newLanguages = Set(new.languageBreakdown.keys)
        let addedLanguages = Array(newLanguages.subtracting(oldLanguages)).sorted()

        // Build summary
        let summary = buildSummary(
            period: period,
            fileDiff: fileDiff,
            lineDiff: lineDiff,
            addedLanguages: addedLanguages,
            testDelta: new.testFileCount - old.testFileCount,
            docDelta: new.docFileCount - old.docFileCount
        )

        return EvolutionDelta(
            period: period,
            filesAdded: filesAdded,
            filesRemoved: filesRemoved,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved,
            newLanguages: addedLanguages,
            summary: summary
        )
    }

    /// Compute a trend from a series of snapshots.
    ///
    /// - Parameter snapshots: Chronologically ordered snapshots (oldest first).
    /// - Returns: A ProjectTrend reflecting the overall direction.
    public func trend(snapshots: [ProjectSnapshot]) -> ProjectTrend {
        guard snapshots.count >= 2 else {
            return ProjectTrend(
                direction: .stable,
                growthRate: 0.0,
                description: "Not enough data points to determine trend"
            )
        }

        // Compute per-interval growth rates
        var growthRates: [Double] = []
        for i in 1..<snapshots.count {
            let prev = snapshots[i - 1]
            let curr = snapshots[i]
            guard prev.fileCount > 0 else { continue }
            let rate = Double(curr.fileCount - prev.fileCount) / Double(prev.fileCount)
            growthRates.append(rate)
        }

        guard !growthRates.isEmpty else {
            return ProjectTrend(
                direction: .stable,
                growthRate: 0.0,
                description: "No measurable file count changes"
            )
        }

        let avgRate = growthRates.reduce(0.0, +) / Double(growthRates.count)
        let percentRate = avgRate * 100.0

        let direction: TrendDirection
        let description: String

        if avgRate > 0.05 {
            direction = .growing
            description = String(format: "Project is growing at %.1f%% per interval (%d snapshots analyzed)",
                                 percentRate, snapshots.count)
        } else if avgRate < -0.05 {
            direction = .shrinking
            description = String(format: "Project is shrinking at %.1f%% per interval (%d snapshots analyzed)",
                                 abs(percentRate), snapshots.count)
        } else {
            direction = .stable
            description = String(format: "Project is stable (%.1f%% change per interval, %d snapshots)",
                                 percentRate, snapshots.count)
        }

        return ProjectTrend(
            direction: direction,
            growthRate: avgRate,
            description: description
        )
    }

    // MARK: - Internal

    private func estimateTestFiles(workspace: WorkspaceIndex) -> Int {
        // Rough heuristic: ~15% of files in a well-tested project are tests
        let hasTests = workspace.testCommand != nil
        return hasTests ? max(1, workspace.fileCount / 7) : 0
    }

    private func estimateTotalLines(fileCount: Int) -> Int {
        // Rough estimate: ~100 lines per file on average
        return fileCount * 100
    }

    private func buildSummary(
        period: String,
        fileDiff: Int,
        lineDiff: Int,
        addedLanguages: [String],
        testDelta: Int,
        docDelta: Int
    ) -> String {
        var parts: [String] = []
        parts.append("Over \(period)")

        if fileDiff > 0 {
            parts.append("+\(fileDiff) files")
        } else if fileDiff < 0 {
            parts.append("\(fileDiff) files")
        } else {
            parts.append("no file count change")
        }

        if lineDiff > 0 {
            parts.append("+\(lineDiff) lines")
        } else if lineDiff < 0 {
            parts.append("\(lineDiff) lines")
        }

        if !addedLanguages.isEmpty {
            parts.append("new: \(addedLanguages.joined(separator: ", "))")
        }

        if testDelta > 0 {
            parts.append("+\(testDelta) test files")
        }

        if docDelta > 0 {
            parts.append("+\(docDelta) doc files")
        }

        return parts.joined(separator: ", ")
    }
}
