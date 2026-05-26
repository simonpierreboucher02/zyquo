import XCTest
@testable import Zyquo

final class IgnoreTests: XCTestCase {
    func testSimplePattern() {
        let rules = IgnoreRules(patterns: IgnoreRules.parse("node_modules\n.env").compactMap { $0 })
        XCTAssertTrue(rules.isIgnored("node_modules"))
        XCTAssertTrue(rules.isIgnored("src/node_modules"))
        XCTAssertTrue(rules.isIgnored(".env"))
        XCTAssertFalse(rules.isIgnored("src/app.ts"))
    }

    func testWildcardPattern() {
        let rules = IgnoreRules(patterns: IgnoreRules.parse("*.pem\n*.key").compactMap { $0 })
        XCTAssertTrue(rules.isIgnored("server.pem"))
        XCTAssertTrue(rules.isIgnored("certs/ca.key"))
        XCTAssertFalse(rules.isIgnored("README.md"))
    }

    func testDirectoryPattern() {
        let rules = IgnoreRules(patterns: IgnoreRules.parse("build/\nDerivedData/").compactMap { $0 })
        XCTAssertTrue(rules.isIgnored("build"))
        XCTAssertTrue(rules.isIgnored("DerivedData"))
    }

    func testComments() {
        let rules = IgnoreRules(patterns: IgnoreRules.parse("# comment\n*.log\n  # another").compactMap { $0 })
        XCTAssertTrue(rules.isIgnored("error.log"))
        XCTAssertFalse(rules.isIgnored("app.swift"))
    }

    func testEmptyRules() {
        let rules = IgnoreRules()
        XCTAssertFalse(rules.isIgnored("anything"))
    }
}

final class BoundaryGuardTests: XCTestCase {
    func testPathInsideWorkspace() {
        let guard_ = BoundaryGuard(workspaceRoot: URL(fileURLWithPath: "/tmp/project"))
        XCTAssertTrue(guard_.isInside("/tmp/project/src/main.swift"))
        XCTAssertTrue(guard_.isInside("/tmp/project"))
    }

    func testPathOutsideWorkspace() {
        let guard_ = BoundaryGuard(workspaceRoot: URL(fileURLWithPath: "/tmp/project"))
        let result = guard_.validate("/etc/passwd")
        XCTAssertFalse(result.isAllowed)
    }

    func testRelativePath() {
        let guard_ = BoundaryGuard(workspaceRoot: URL(fileURLWithPath: "/tmp/project"))
        XCTAssertTrue(guard_.isInside("src/main.swift"))
    }

    func testSensitivePath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let guard_ = BoundaryGuard(workspaceRoot: URL(fileURLWithPath: home))
        let result = guard_.validate(home + "/.ssh/id_rsa")
        if case .sensitive = result {
            // Expected
        } else {
            XCTFail("Expected sensitive result for .ssh path")
        }
    }
}

final class ProjectDetectorTests: XCTestCase {
    func testLanguageFromExtension() {
        XCTAssertEqual(Language.from(extension: "swift"), .swift)
        XCTAssertEqual(Language.from(extension: "py"), .python)
        XCTAssertEqual(Language.from(extension: "ts"), .typescript)
        XCTAssertEqual(Language.from(extension: "tsx"), .typescript)
        XCTAssertEqual(Language.from(extension: "rs"), .rust)
        XCTAssertEqual(Language.from(extension: "go"), .go)
        XCTAssertEqual(Language.from(extension: "rb"), .ruby)
        XCTAssertEqual(Language.from(extension: "ex"), .elixir)
        XCTAssertEqual(Language.from(extension: "java"), .java)
        XCTAssertEqual(Language.from(extension: "kt"), .kotlin)
        XCTAssertEqual(Language.from(extension: "c"), .c)
        XCTAssertEqual(Language.from(extension: "cpp"), .cpp)
        XCTAssertEqual(Language.from(extension: "m"), .objectiveC)
        XCTAssertEqual(Language.from(extension: "sh"), .shell)
        XCTAssertNil(Language.from(extension: "xyz"))
    }

    func testDetectLanguagesFromFiles() {
        let files = [
            FileSnapshot(path: "/p/a.swift", relativePath: "a.swift", size: 1000, modificationDate: Date(), isDirectory: false),
            FileSnapshot(path: "/p/b.swift", relativePath: "b.swift", size: 2000, modificationDate: Date(), isDirectory: false),
            FileSnapshot(path: "/p/c.py", relativePath: "c.py", size: 500, modificationDate: Date(), isDirectory: false),
        ]
        let detector = ProjectDetector()
        let desc = detector.detect(at: URL(fileURLWithPath: "/nonexistent"), files: files)
        XCTAssertEqual(desc.primaryLanguage, .swift)
        XCTAssertTrue(desc.languages.count >= 2)
    }

    func testDetectSwiftPM() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zyquo-test-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try? "".write(to: tmp.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let detector = ProjectDetector()
        let desc = detector.detect(at: tmp, files: [])
        XCTAssertTrue(desc.frameworks.contains(.swiftPM))
        XCTAssertEqual(desc.packageManager, .swiftPM)
        XCTAssertEqual(desc.testCommand, "swift test")
        XCTAssertEqual(desc.buildCommand, "swift build")
    }

    func testDetectNodeProject() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zyquo-test-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let pkg = "{\"dependencies\":{\"react\":\"^18.0.0\"},\"scripts\":{\"test\":\"jest\"}}"
        try? pkg.write(to: tmp.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try? "".write(to: tmp.appendingPathComponent("yarn.lock"), atomically: true, encoding: .utf8)

        let detector = ProjectDetector()
        let desc = detector.detect(at: tmp, files: [])
        XCTAssertTrue(desc.frameworks.contains(.node))
        XCTAssertTrue(desc.frameworks.contains(.react))
        XCTAssertEqual(desc.packageManager, .yarn)
    }

    func testDetectCargoProject() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zyquo-test-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try? "".write(to: tmp.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)

        let detector = ProjectDetector()
        let desc = detector.detect(at: tmp, files: [])
        XCTAssertTrue(desc.frameworks.contains(.cargo))
        XCTAssertEqual(desc.packageManager, .cargo)
        XCTAssertEqual(desc.testCommand, "cargo test")
    }

    func testDetectGoProject() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zyquo-test-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try? "".write(to: tmp.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)

        let detector = ProjectDetector()
        let desc = detector.detect(at: tmp, files: [])
        XCTAssertTrue(desc.frameworks.contains(.goMod))
        XCTAssertEqual(desc.packageManager, .goMod)
        XCTAssertEqual(desc.testCommand, "go test ./...")
    }
}

final class RepoAnalyzerTests: XCTestCase {
    func testGitStatusOnThisRepo() {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let analyzer = RepoAnalyzer()

        let gitDir = cwd.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else { return }

        let status = analyzer.analyzeGit(at: cwd)
        XCTAssertNotNil(status)
        XCTAssertNotNil(status?.branch)
    }

    func testReadREADME() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zyquo-test-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try? "# My Project\nHello world".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let analyzer = RepoAnalyzer()
        let readme = analyzer.readREADME(at: tmp)
        XCTAssertNotNil(readme)
        XCTAssertTrue(readme?.contains("My Project") ?? false)
    }

    func testFindDocumentation() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zyquo-test-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try? "".write(to: tmp.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try? "".write(to: tmp.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)

        let analyzer = RepoAnalyzer()
        let docs = analyzer.findDocumentation(at: tmp)
        XCTAssertTrue(docs.contains("README.md"))
        XCTAssertTrue(docs.contains("CLAUDE.md"))
    }
}

final class WorkspaceIndexTests: XCTestCase {
    func testSummaryCard() {
        let index = WorkspaceIndex(
            root: URL(fileURLWithPath: "/tmp/myproject"),
            languages: [(.swift, 0.8), (.python, 0.2)],
            frameworks: [.swiftPM],
            packageManager: .swiftPM,
            testCommand: "swift test",
            buildCommand: "swift build",
            gitStatus: GitStatus(
                branch: "main", upstream: "origin", ahead: 0, behind: 0,
                isClean: true, stagedCount: 0, unstagedCount: 0, untrackedCount: 0,
                hasMergeInProgress: false, hasRebaseInProgress: false
            ),
            fileCount: 42,
            totalSize: 1_048_576,
            lastFullScan: Date(),
            documentation: ["README.md"]
        )

        let card = index.summaryCard
        XCTAssertTrue(card.contains("myproject"))
        XCTAssertTrue(card.contains("Swift"))
        XCTAssertTrue(card.contains("SwiftPM"))
        XCTAssertTrue(card.contains("swift test"))
        XCTAssertTrue(card.contains("main"))
        XCTAssertTrue(card.contains("clean"))
        XCTAssertTrue(card.contains("42"))
    }
}
