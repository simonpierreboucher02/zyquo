import XCTest
@testable import Zyquo

final class RiskClassifierTests: XCTestCase {

    // Use a temp directory as workspace root so tests are self-contained.
    private var workspaceRoot: URL!
    private var classifier: RiskClassifier!

    override func setUp() {
        super.setUp()
        workspaceRoot = URL(fileURLWithPath: "/tmp/zyquo-test-workspace")
        classifier = RiskClassifier(workspaceRoot: workspaceRoot)
    }

    // MARK: - SAFE Commands

    func testSafeCommands() {
        let safeCommands = [
            "ls",
            "ls -la",
            "cat file.txt",
            "git status",
            "git log --oneline -20",
            "git diff",
            "git diff HEAD~1",
            "swift test",
            "swift build",
            "rg pattern",
            "rg -n 'function' src/",
            "echo hello",
            "pwd",
            "whoami",
            "uname -a",
            "wc -l file.txt",
            "head -20 README.md",
            "tail -f output.log",
            "grep -r 'TODO' .",
            "find . -name '*.swift'",
            "tree -L 2",
            "which swift",
            "env",
            "date",
        ]

        for command in safeCommands {
            let assessment = classifier.classify(command)
            XCTAssertEqual(
                assessment.tier, .safe,
                "Expected '\(command)' to be SAFE, got \(assessment.tier.rawValue). Rationale: \(assessment.rationale)"
            )
        }
    }

    // MARK: - MODERATE Commands

    func testModerateCommands() {
        let moderateCommands: [(String, String)] = [
            ("git commit -m \"fix bug\"", "git commit"),
            ("git commit --amend", "git commit"),
            ("git checkout main", "git checkout/switch/branch"),
            ("git switch feature-branch", "git checkout/switch/branch"),
            ("git branch new-feature", "git checkout/switch/branch"),
            ("npm install", "npm install"),
            ("npm i express", "npm install"),
            ("npm ci", "npm install"),
            ("yarn install", "yarn install"),
            ("yarn add lodash", "yarn install"),
            ("pnpm install", "pnpm install"),
            ("pnpm add react", "pnpm install"),
            ("cargo install ripgrep", "cargo install"),
            ("echo data > output.txt", "redirect write"),
            ("echo data >> output.txt", "redirect write"),
            ("git stash", "git stash"),
            ("git merge feature", "git merge"),
            ("git rebase main", "git rebase"),
            ("git pull origin main", "git pull"),
            ("git fetch origin", "git fetch"),
            ("git tag v1.0.0", "git tag"),
            ("touch newfile.txt", "touch"),
            ("mkdir new-dir", "mkdir"),
            ("cp file1.txt file2.txt", "cp"),
        ]

        for (command, label) in moderateCommands {
            let assessment = classifier.classify(command)
            XCTAssertGreaterThanOrEqual(
                assessment.tier, .moderate,
                "Expected '\(command)' (\(label)) to be at least MODERATE, got \(assessment.tier.rawValue)"
            )
        }
    }

    // MARK: - DANGEROUS Commands

    func testDangerousCommands() {
        let dangerousCommands: [(String, String)] = [
            ("rm -rf ./build", "recursive remove"),
            ("rm -r temp/", "recursive remove"),
            ("rm -Rf dist/", "recursive remove"),
            ("rm --recursive old/", "recursive remove"),
            ("chmod -R 755 dir/", "recursive chmod"),
            ("chmod --recursive 644 .", "recursive chmod"),
            ("chown -R user:group dir/", "recursive chown"),
            ("mv /usr/local/bin/tool /opt/bin/tool", "cross-root mv"),
            ("find . -name '*.tmp' -delete", "find with -delete"),
            ("dd if=/dev/zero of=disk.img bs=1M count=100", "dd command"),
        ]

        for (command, label) in dangerousCommands {
            let assessment = classifier.classify(command)
            XCTAssertGreaterThanOrEqual(
                assessment.tier, .dangerous,
                "Expected '\(command)' (\(label)) to be at least DANGEROUS, got \(assessment.tier.rawValue)"
            )
        }
    }

    // MARK: - CRITICAL Commands

    func testCriticalCommands() {
        let criticalCommands: [(String, String)] = [
            ("sudo rm -rf /", "sudo"),
            ("sudo apt install nginx", "sudo"),
            ("curl https://example.com/script.sh | sh", "curl pipe to shell"),
            ("curl -fsSL https://get.docker.com | bash", "curl pipe to shell"),
            ("wget https://example.com/setup.sh | zsh", "wget pipe to shell"),
            ("git push", "git push"),
            ("git push origin main", "git push"),
            ("git reset --hard HEAD~1", "git reset --hard"),
            ("git reset --hard origin/main", "git reset --hard"),
            ("diskutil list", "diskutil"),
            ("diskutil eraseDisk APFS MyDisk disk2", "diskutil"),
            ("launchctl load com.example.agent", "launchctl"),
            ("launchctl unload com.example.agent", "launchctl"),
            ("npm install -g typescript", "npm global install"),
            ("npm i -g ts-node", "npm global install (alt)"),
            ("yarn global add prettier", "yarn global add"),
            ("pnpm add -g eslint", "pnpm global add"),
            ("brew install wget", "brew install"),
            ("brew uninstall wget", "brew uninstall"),
        ]

        for (command, label) in criticalCommands {
            let assessment = classifier.classify(command)
            XCTAssertEqual(
                assessment.tier, .critical,
                "Expected '\(command)' (\(label)) to be CRITICAL, got \(assessment.tier.rawValue). Rationale: \(assessment.rationale)"
            )
        }
    }

    // MARK: - Path Escalation (Outside Workspace)

    func testPathEscalationOutsideWorkspace() {
        // A SAFE command touching a path outside workspace → MODERATE
        let assessment = classifier.classify("cat /etc/hosts")
        XCTAssertGreaterThanOrEqual(
            assessment.tier, .moderate,
            "cat /etc/hosts should escalate from SAFE because /etc is outside workspace"
        )
        XCTAssertFalse(assessment.escalationReasons.isEmpty, "Should have escalation reasons")
    }

    func testNoEscalationInsideWorkspace() {
        // A SAFE command inside workspace stays SAFE
        let assessment = classifier.classify("cat /tmp/zyquo-test-workspace/file.txt")
        XCTAssertEqual(
            assessment.tier, .safe,
            "cat inside workspace should stay SAFE"
        )
    }

    func testModerateEscalatesToDangerousOutsideWorkspace() {
        // MODERATE command touching outside workspace → DANGEROUS
        let assessment = classifier.classify("cp /tmp/zyquo-test-workspace/f.txt /opt/dest.txt")
        XCTAssertGreaterThanOrEqual(
            assessment.tier, .dangerous,
            "cp touching /opt should escalate from MODERATE to at least DANGEROUS"
        )
    }

    // MARK: - Sensitive Path Escalation

    func testSSHPathAlwaysCritical() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let assessment = classifier.classify("cat \(home)/.ssh/id_rsa")
        XCTAssertEqual(
            assessment.tier, .critical,
            "Touching ~/.ssh should always be CRITICAL"
        )
    }

    func testAWSPathAlwaysCritical() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let assessment = classifier.classify("cat \(home)/.aws/credentials")
        XCTAssertEqual(
            assessment.tier, .critical,
            "Touching ~/.aws should always be CRITICAL"
        )
    }

    func testLibraryPathAlwaysCritical() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let assessment = classifier.classify("ls \(home)/Library/Preferences")
        XCTAssertEqual(
            assessment.tier, .critical,
            "Touching ~/Library should always be CRITICAL"
        )
    }

    func testSystemPathAlwaysCritical() {
        let assessment = classifier.classify("ls /System/Library/Frameworks")
        XCTAssertEqual(
            assessment.tier, .critical,
            "Touching /System should always be CRITICAL"
        )
    }

    func testPrivatePathAlwaysCritical() {
        let assessment = classifier.classify("cat /private/etc/passwd")
        XCTAssertEqual(
            assessment.tier, .critical,
            "Touching /private should always be CRITICAL"
        )
    }

    func testUsrLocalNotSensitive() {
        // /usr/local is excepted from the /usr sensitivity
        let assessment = classifier.classify("ls /usr/local/bin")
        // Should be escalated as outside-workspace but NOT as sensitive
        XCTAssertLessThan(
            assessment.tier, .critical,
            "/usr/local should NOT be treated as sensitive (it is /usr exception)"
        )
    }

    func testUsrBinIsSensitive() {
        let assessment = classifier.classify("cat /usr/bin/env")
        XCTAssertEqual(
            assessment.tier, .critical,
            "/usr/bin should be CRITICAL (sensitive system path)"
        )
    }

    func testTildePathExpansion() {
        let assessment = classifier.classify("cat ~/.ssh/known_hosts")
        XCTAssertEqual(
            assessment.tier, .critical,
            "~/.ssh should expand and be CRITICAL"
        )
    }

    // MARK: - RiskLevel Ordering

    func testRiskLevelComparable() {
        XCTAssertLessThan(RiskLevel.safe, RiskLevel.moderate)
        XCTAssertLessThan(RiskLevel.moderate, RiskLevel.dangerous)
        XCTAssertLessThan(RiskLevel.dangerous, RiskLevel.critical)
    }

    func testRiskLevelEscalation() {
        XCTAssertEqual(RiskLevel.safe.escalated(), .moderate)
        XCTAssertEqual(RiskLevel.moderate.escalated(), .dangerous)
        XCTAssertEqual(RiskLevel.dangerous.escalated(), .critical)
        XCTAssertEqual(RiskLevel.critical.escalated(), .critical)
    }

    // MARK: - RiskAssessment

    func testAssessmentHasMatchedRules() {
        let assessment = classifier.classify("sudo rm -rf /")
        XCTAssertFalse(assessment.matchedRules.isEmpty, "Critical command should have matched rules")
        XCTAssertTrue(
            assessment.matchedRules.contains { $0.label == "sudo invocation" },
            "Should match sudo rule"
        )
    }

    func testAssessmentRationaleNotEmpty() {
        let assessment = classifier.classify("ls")
        XCTAssertFalse(assessment.rationale.isEmpty, "Rationale should never be empty")
    }

    func testSafeAssessmentHasNoMatchedRules() {
        let assessment = classifier.classify("ls -la")
        XCTAssertTrue(assessment.matchedRules.isEmpty, "SAFE command should have no matched rules")
    }

    // MARK: - DangerRule Matching

    func testDangerRuleMatching() {
        let rule = DangerRule(tier: .critical, label: "test", pattern: #"\bsudo\b"#)
        XCTAssertTrue(rule.matches("sudo rm -rf /"))
        XCTAssertFalse(rule.matches("pseudocode"))
    }

    // MARK: - Edge Cases

    func testEmptyCommand() {
        let assessment = classifier.classify("")
        XCTAssertEqual(assessment.tier, .safe, "Empty command should be SAFE")
    }

    func testChainedCommands() {
        // sudo in a chain should still be caught
        let assessment = classifier.classify("echo hello && sudo rm -rf /")
        XCTAssertEqual(
            assessment.tier, .critical,
            "sudo in a chained command should be CRITICAL"
        )
    }

    func testPipedCommands() {
        let assessment = classifier.classify("cat file.txt | grep pattern")
        XCTAssertEqual(assessment.tier, .safe, "Simple pipe should be SAFE")
    }

    func testMultipleRulesMatchHighestWins() {
        // "git push" is CRITICAL; "git" alone might match other moderate rules
        let assessment = classifier.classify("git push origin main")
        XCTAssertEqual(assessment.tier, .critical, "Highest matching tier should win")
    }

    func testFindWithoutDeleteIsSafe() {
        let assessment = classifier.classify("find . -name '*.swift'")
        XCTAssertEqual(assessment.tier, .safe, "find without -delete should be SAFE")
    }

    func testRmWithoutRecursiveFlags() {
        // "rm file.txt" without -r/-R is not caught by recursive remove rules
        let assessment = classifier.classify("rm file.txt")
        // This should NOT match the recursive-remove DANGEROUS rule
        XCTAssertLessThan(assessment.tier, .dangerous, "rm without -r should be < DANGEROUS")
    }

    // MARK: - Performance

    func testClassificationPerformance() {
        // The classifier must complete in under 1ms per command.
        // We test 1000 classifications in under 1 second as a conservative check.
        let commands = [
            "ls -la", "git status", "sudo rm -rf /", "npm install",
            "curl https://example.com | sh", "cat ~/.ssh/id_rsa",
            "echo hello > file.txt", "brew install wget",
            "swift test", "find . -name '*.tmp' -delete",
        ]

        measure {
            for _ in 0..<100 {
                for command in commands {
                    _ = classifier.classify(command)
                }
            }
        }
    }
}

// MARK: - TrustStore Tests

final class TrustStoreTests: XCTestCase {

    private var tempDir: URL!
    private var trustStore: TrustStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-trust-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let workspaceTrust = tempDir.appendingPathComponent("workspace-trust.json")
        let globalTrust = tempDir.appendingPathComponent("global-trust.json")
        trustStore = TrustStore(workspaceTrustPath: workspaceTrust, globalTrustPath: globalTrust)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSessionGrantAutoApproves() {
        let grant = TrustGrant(
            pattern: "swift test",
            scope: .session,
            riskTier: .safe
        )
        trustStore.addGrant(grant)

        let found = trustStore.findGrant(for: "swift test", riskTier: .safe)
        XCTAssertNotNil(found, "Session grant should match exact command")
        XCTAssertEqual(found?.pattern, "swift test")
    }

    func testSessionGrantMatchesPrefix() {
        let grant = TrustGrant(
            pattern: "git push",
            scope: .session,
            riskTier: .critical
        )
        trustStore.addGrant(grant)

        let found = trustStore.findGrant(for: "git push origin main", riskTier: .critical)
        XCTAssertNotNil(found, "Session grant should match prefix")
    }

    func testSessionGrantDoesNotMatchDifferentCommand() {
        let grant = TrustGrant(
            pattern: "swift test",
            scope: .session,
            riskTier: .safe
        )
        trustStore.addGrant(grant)

        let found = trustStore.findGrant(for: "swift build", riskTier: .safe)
        XCTAssertNil(found, "Grant for 'swift test' should not match 'swift build'")
    }

    func testCriticalCannotGetWorkspaceScope() {
        let grant = TrustGrant(
            pattern: "sudo rm",
            scope: .workspace,
            riskTier: .critical
        )
        let result = trustStore.addGrant(grant)
        XCTAssertFalse(result, "CRITICAL commands must NOT get workspace scope")
    }

    func testCriticalCannotGetGlobalScope() {
        let grant = TrustGrant(
            pattern: "git push",
            scope: .global,
            riskTier: .critical
        )
        let result = trustStore.addGrant(grant)
        XCTAssertFalse(result, "CRITICAL commands must NOT get global scope")
    }

    func testCriticalCanGetSessionScope() {
        let grant = TrustGrant(
            pattern: "git push",
            scope: .session,
            riskTier: .critical
        )
        let result = trustStore.addGrant(grant)
        XCTAssertTrue(result, "CRITICAL commands CAN get session scope")
    }

    func testClearSessionGrants() {
        trustStore.addGrant(TrustGrant(pattern: "swift test", scope: .session, riskTier: .safe))
        trustStore.addGrant(TrustGrant(pattern: "git status", scope: .session, riskTier: .safe))

        XCTAssertEqual(trustStore.activeSessionGrants.count, 2)

        trustStore.clearSessionGrants()

        XCTAssertEqual(trustStore.activeSessionGrants.count, 0)
        XCTAssertNil(trustStore.findGrant(for: "swift test", riskTier: .safe))
    }

    func testWorkspaceGrantPersistence() {
        let grant = TrustGrant(
            pattern: "npm install",
            scope: .workspace,
            riskTier: .moderate
        )
        trustStore.addGrant(grant)

        // Create a new store pointing to the same files to verify persistence
        let workspaceTrust = tempDir.appendingPathComponent("workspace-trust.json")
        let globalTrust = tempDir.appendingPathComponent("global-trust.json")
        let newStore = TrustStore(workspaceTrustPath: workspaceTrust, globalTrustPath: globalTrust)

        let found = newStore.findGrant(for: "npm install", riskTier: .moderate)
        XCTAssertNotNil(found, "Workspace grant should persist across TrustStore instances")
    }

    func testRemoveGrant() {
        trustStore.addGrant(TrustGrant(pattern: "swift test", scope: .session, riskTier: .safe))
        trustStore.removeGrant(pattern: "swift test", scope: .session)

        XCTAssertNil(trustStore.findGrant(for: "swift test", riskTier: .safe))
    }

    func testGrantRequiresMatchingRiskTier() {
        // Grant for SAFE tier
        trustStore.addGrant(TrustGrant(pattern: "npm install", scope: .session, riskTier: .safe))

        // Looking for MODERATE — grant only covers SAFE, so no match
        let found = trustStore.findGrant(for: "npm install", riskTier: .moderate)
        XCTAssertNil(found, "A SAFE-tier grant should not cover MODERATE risk")
    }

    func testGrantCoversLowerRiskTier() {
        // Grant covering MODERATE
        trustStore.addGrant(TrustGrant(pattern: "npm install", scope: .session, riskTier: .moderate))

        // Looking for SAFE — MODERATE grant covers SAFE
        let found = trustStore.findGrant(for: "npm install", riskTier: .safe)
        XCTAssertNotNil(found, "A MODERATE-tier grant should cover SAFE risk")
    }
}

// MARK: - ApprovalGate Tests

final class ApprovalGateTests: XCTestCase {

    private var tempDir: URL!
    private var trustStore: TrustStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-approval-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let workspaceTrust = tempDir.appendingPathComponent("workspace-trust.json")
        let globalTrust = tempDir.appendingPathComponent("global-trust.json")
        trustStore = TrustStore(workspaceTrustPath: workspaceTrust, globalTrustPath: globalTrust)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSafeAutoApprovedWhenEnabled() {
        let gate = ApprovalGate(autoApproveSafe: true)
        let risk = RiskAssessment(tier: .safe, rationale: "No dangerous patterns")

        let decision = gate.check(command: "ls", risk: risk, trustStore: trustStore)

        if case .autoApproved = decision {
            // Pass
        } else {
            XCTFail("SAFE command with auto-approve should be auto-approved")
        }
    }

    func testSafeRequiresApprovalWhenDisabled() {
        let gate = ApprovalGate(autoApproveSafe: false)
        let risk = RiskAssessment(tier: .safe, rationale: "No dangerous patterns")

        let decision = gate.check(command: "ls", risk: risk, trustStore: trustStore)

        XCTAssertEqual(decision, .requiresApproval, "SAFE command without auto-approve should require approval")
    }

    func testModerateRequiresApproval() {
        let gate = ApprovalGate(autoApproveSafe: true)
        let risk = RiskAssessment(tier: .moderate, rationale: "git commit detected")

        let decision = gate.check(command: "git commit -m 'fix'", risk: risk, trustStore: trustStore)

        XCTAssertEqual(decision, .requiresApproval, "MODERATE command should require approval")
    }

    func testCriticalRequiresApproval() {
        let gate = ApprovalGate(autoApproveSafe: true)
        let risk = RiskAssessment(tier: .critical, rationale: "sudo detected")

        let decision = gate.check(command: "sudo rm -rf /", risk: risk, trustStore: trustStore)

        XCTAssertEqual(decision, .requiresApproval, "CRITICAL command should require approval")
    }

    func testTrustGrantAutoApproves() {
        let gate = ApprovalGate(autoApproveSafe: false) // auto-approve off
        let risk = RiskAssessment(tier: .moderate, rationale: "git commit detected")

        // Add a trust grant
        trustStore.addGrant(TrustGrant(pattern: "git commit", scope: .session, riskTier: .moderate))

        let decision = gate.check(command: "git commit -m 'fix'", risk: risk, trustStore: trustStore)

        if case .autoApproved = decision {
            // Pass
        } else {
            XCTFail("Trust grant should auto-approve matching command")
        }
    }

    func testScopeAllowedForRiskTier() {
        XCTAssertTrue(ApprovalGate.isScopeAllowed(.session, forRisk: .critical))
        XCTAssertTrue(ApprovalGate.isScopeAllowed(.once, forRisk: .critical))
        XCTAssertFalse(ApprovalGate.isScopeAllowed(.workspace, forRisk: .critical))
        XCTAssertFalse(ApprovalGate.isScopeAllowed(.global, forRisk: .critical))
        XCTAssertTrue(ApprovalGate.isScopeAllowed(.global, forRisk: .safe))
        XCTAssertTrue(ApprovalGate.isScopeAllowed(.global, forRisk: .moderate))
        XCTAssertTrue(ApprovalGate.isScopeAllowed(.global, forRisk: .dangerous))
    }

    func testMaxScopeForRiskTier() {
        XCTAssertEqual(ApprovalGate.maxScope(forRisk: .safe), .global)
        XCTAssertEqual(ApprovalGate.maxScope(forRisk: .moderate), .global)
        XCTAssertEqual(ApprovalGate.maxScope(forRisk: .dangerous), .global)
        XCTAssertEqual(ApprovalGate.maxScope(forRisk: .critical), .session)
    }
}

// MARK: - AuditLog Tests

final class AuditLogTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-audit-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testAuditLogWritesValidJSONL() {
        let logDir = tempDir.appendingPathComponent("logs")
        let auditLog = AuditLog(logDirectory: logDir, sessionId: "test-session-1")

        auditLog.record(AuditEntry(
            sessionId: "test-session-1",
            event: .commandApproval,
            command: "ls -la",
            riskTier: .safe,
            decision: "auto_approved: SAFE tier",
            source: .autoSafe
        ))

        auditLog.record(AuditEntry(
            sessionId: "test-session-1",
            event: .commandApproval,
            command: "git push origin main",
            riskTier: .critical,
            decision: "requires_approval",
            source: .userApproved,
            context: ["matched_rules": "git push"]
        ))

        // Read back and verify
        let entries = auditLog.readEntries()
        XCTAssertEqual(entries.count, 2, "Should have 2 audit entries")
        XCTAssertEqual(entries[0].command, "ls -la")
        XCTAssertEqual(entries[0].riskTier, .safe)
        XCTAssertEqual(entries[0].event, .commandApproval)
        XCTAssertEqual(entries[1].command, "git push origin main")
        XCTAssertEqual(entries[1].riskTier, .critical)
    }

    func testAuditLogIsAppendOnly() {
        let logDir = tempDir.appendingPathComponent("logs")
        let auditLog = AuditLog(logDirectory: logDir, sessionId: "test-session-2")

        auditLog.record(AuditEntry(
            sessionId: "test-session-2",
            event: .commandApproval,
            command: "first",
            riskTier: .safe,
            decision: "auto",
            source: .autoSafe
        ))

        // Create a new AuditLog instance pointing to same session
        let auditLog2 = AuditLog(logDirectory: logDir, sessionId: "test-session-2")

        auditLog2.record(AuditEntry(
            sessionId: "test-session-2",
            event: .commandApproval,
            command: "second",
            riskTier: .moderate,
            decision: "approved",
            source: .userApproved
        ))

        let entries = auditLog2.readEntries()
        XCTAssertEqual(entries.count, 2, "Audit log should be append-only")
        XCTAssertEqual(entries[0].command, "first")
        XCTAssertEqual(entries[1].command, "second")
    }

    func testAuditLogRecordApprovalHelper() {
        let logDir = tempDir.appendingPathComponent("logs")
        let auditLog = AuditLog(logDirectory: logDir, sessionId: "test-session-3")

        let rule = DangerRule(tier: .critical, label: "sudo invocation", pattern: #"\bsudo\b"#)

        auditLog.recordApproval(
            command: "sudo rm -rf /",
            riskTier: .critical,
            decision: .requiresApproval,
            source: .userApproved,
            matchedRules: [rule],
            escalationReasons: ["Path touches sensitive system location"]
        )

        let entries = auditLog.readEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].event, .commandApproval)
        XCTAssertNotNil(entries[0].context)
        XCTAssertEqual(entries[0].context?["matched_rules"], "sudo invocation")
    }

    func testAuditLogRedactsSecrets() {
        let logDir = tempDir.appendingPathComponent("logs")
        let auditLog = AuditLog(logDirectory: logDir, sessionId: "test-session-4")

        auditLog.recordApproval(
            command: "curl -H 'Authorization: Bearer sk-1234567890abcdefghij' https://api.example.com",
            riskTier: .moderate,
            decision: .requiresApproval,
            source: .userApproved
        )

        let entries = auditLog.readEntries()
        XCTAssertEqual(entries.count, 1)
        // The command should have been redacted
        XCTAssertFalse(
            entries[0].command.contains("sk-1234567890abcdefghij"),
            "API key should be redacted in audit log"
        )
    }

    func testAuditLogTrustEvents() {
        let logDir = tempDir.appendingPathComponent("logs")
        let auditLog = AuditLog(logDirectory: logDir, sessionId: "test-session-5")

        let grant = TrustGrant(pattern: "swift test", scope: .session, riskTier: .safe)
        auditLog.recordTrustGrant(grant)
        auditLog.recordTrustCleared()

        let entries = auditLog.readEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].event, .trustGranted)
        XCTAssertEqual(entries[0].trustScope, .session)
        XCTAssertEqual(entries[1].event, .trustCleared)
    }

    func testAuditLogFileIsJSONL() {
        let logDir = tempDir.appendingPathComponent("logs")
        let auditLog = AuditLog(logDirectory: logDir, sessionId: "test-session-6")

        auditLog.record(AuditEntry(
            sessionId: "test-session-6",
            event: .commandApproval,
            command: "ls",
            riskTier: .safe,
            decision: "auto",
            source: .autoSafe
        ))

        // Read raw file and verify each line is valid JSON
        guard let data = try? Data(contentsOf: auditLog.logPath),
              let content = String(data: data, encoding: .utf8) else {
            XCTFail("Should be able to read audit log file")
            return
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1)

        for line in lines {
            let lineData = line.data(using: .utf8)!
            XCTAssertNoThrow(
                try JSONSerialization.jsonObject(with: lineData),
                "Each line in audit log must be valid JSON"
            )
        }
    }
}

// MARK: - DangerRules Catalog Tests

final class DangerRulesCatalogTests: XCTestCase {

    func testAllRulesCompile() {
        // Verify that all regex patterns compile (they're force-unwrapped in init)
        XCTAssertGreaterThan(DangerRuleCatalog.allRules.count, 30,
                             "Should have at least 30 rules")
    }

    func testRulesOrderedByTier() {
        let rules = DangerRuleCatalog.allRules
        var lastTier = RiskLevel.critical

        for rule in rules {
            if rule.tier != lastTier {
                XCTAssertLessThanOrEqual(rule.tier, lastTier,
                                         "Rules should be ordered CRITICAL > DANGEROUS > MODERATE")
                lastTier = rule.tier
            }
        }
    }

    func testCriticalRuleCount() {
        XCTAssertGreaterThanOrEqual(DangerRuleCatalog.critical.count, 10,
                                    "Should have at least 10 CRITICAL rules")
    }

    func testDangerousRuleCount() {
        XCTAssertGreaterThanOrEqual(DangerRuleCatalog.dangerous.count, 7,
                                    "Should have at least 7 DANGEROUS rules")
    }

    func testModerateRuleCount() {
        XCTAssertGreaterThanOrEqual(DangerRuleCatalog.moderate.count, 10,
                                    "Should have at least 10 MODERATE rules")
    }

    func testSensitivePathsIncludeSSH() {
        XCTAssertTrue(
            DangerRuleCatalog.sensitivePaths.contains { $0.hasSuffix("/.ssh") },
            "Sensitive paths should include ~/.ssh"
        )
    }

    func testSensitivePathsIncludeAWS() {
        XCTAssertTrue(
            DangerRuleCatalog.sensitivePaths.contains { $0.hasSuffix("/.aws") },
            "Sensitive paths should include ~/.aws"
        )
    }
}

// MARK: - Integration Tests

final class RiskEngineIntegrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zyquo-integration-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testFullWorkflowSafeAutoApproved() {
        let workspaceRoot = tempDir
        let classifier = RiskClassifier(workspaceRoot: workspaceRoot!)
        let workspaceTrust = tempDir.appendingPathComponent("workspace-trust.json")
        let globalTrust = tempDir.appendingPathComponent("global-trust.json")
        let trustStore = TrustStore(workspaceTrustPath: workspaceTrust, globalTrustPath: globalTrust)
        let gate = ApprovalGate(autoApproveSafe: true)
        let auditLog = AuditLog(logDirectory: tempDir.appendingPathComponent("logs"), sessionId: "integration-1")

        let command = "ls -la"
        let risk = classifier.classify(command)
        let decision = gate.check(command: command, risk: risk, trustStore: trustStore)

        auditLog.recordApproval(
            command: command,
            riskTier: risk.tier,
            decision: decision,
            source: .autoSafe,
            matchedRules: risk.matchedRules,
            escalationReasons: risk.escalationReasons
        )

        XCTAssertEqual(risk.tier, .safe)
        if case .autoApproved = decision {} else {
            XCTFail("Should be auto-approved")
        }

        let entries = auditLog.readEntries()
        XCTAssertEqual(entries.count, 1)
    }

    func testFullWorkflowCriticalRequiresApproval() {
        let workspaceRoot = tempDir
        let classifier = RiskClassifier(workspaceRoot: workspaceRoot!)
        let workspaceTrust = tempDir.appendingPathComponent("workspace-trust.json")
        let globalTrust = tempDir.appendingPathComponent("global-trust.json")
        let trustStore = TrustStore(workspaceTrustPath: workspaceTrust, globalTrustPath: globalTrust)
        let gate = ApprovalGate(autoApproveSafe: true)

        let command = "sudo shutdown -h now"
        let risk = classifier.classify(command)
        let decision = gate.check(command: command, risk: risk, trustStore: trustStore)

        XCTAssertEqual(risk.tier, .critical)
        XCTAssertEqual(decision, .requiresApproval)
    }

    func testFullWorkflowTrustGrantFlow() {
        let workspaceRoot = tempDir
        let classifier = RiskClassifier(workspaceRoot: workspaceRoot!)
        let workspaceTrust = tempDir.appendingPathComponent("workspace-trust.json")
        let globalTrust = tempDir.appendingPathComponent("global-trust.json")
        let trustStore = TrustStore(workspaceTrustPath: workspaceTrust, globalTrustPath: globalTrust)
        let gate = ApprovalGate(autoApproveSafe: false) // auto-approve OFF

        let command = "npm install"
        let risk = classifier.classify(command)

        // First check: requires approval
        let decision1 = gate.check(command: command, risk: risk, trustStore: trustStore)
        XCTAssertEqual(decision1, .requiresApproval)

        // User grants session trust
        trustStore.addGrant(TrustGrant(pattern: "npm install", scope: .session, riskTier: .moderate))

        // Second check: auto-approved via trust
        let decision2 = gate.check(command: command, risk: risk, trustStore: trustStore)
        if case .autoApproved = decision2 {} else {
            XCTFail("Should be auto-approved after trust grant")
        }

        // Clear session trust
        trustStore.clearSessionGrants()

        // Third check: requires approval again
        let decision3 = gate.check(command: command, risk: risk, trustStore: trustStore)
        XCTAssertEqual(decision3, .requiresApproval)
    }
}
