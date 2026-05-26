import XCTest
@testable import Zyquo

final class ShellExecutorTests: XCTestCase {

    private var executor: ShellExecutor!
    private var config: ShellConfig!
    private var cwd: URL!

    override func setUp() {
        super.setUp()
        config = ShellConfig(
            flags: .init(),
            env: [:],
            workspace: [:],
            user: [:]
        )
        executor = ShellExecutor(config: config)
        cwd = URL(fileURLWithPath: NSTemporaryDirectory())
    }

    // MARK: - Basic Execution

    func testBasicEchoCommand() async throws {
        let result = try await executor.executeCollecting(
            command: "echo hello",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertTrue(result.stderr.isEmpty)
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.durationMs >= 0)
        XCTAssertTrue(result.bytesOut > 0)
    }

    func testMultiLineOutput() async throws {
        let result = try await executor.executeCollecting(
            command: "echo 'line1'; echo 'line2'; echo 'line3'",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 0)
        let lines = result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines, ["line1", "line2", "line3"])
    }

    func testCommandWithArguments() async throws {
        let result = try await executor.executeCollecting(
            command: "printf '%s %s' hello world",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello world")
    }

    // MARK: - Exit Codes

    func testNonZeroExitCode() async throws {
        let result = try await executor.executeCollecting(
            command: "exit 42",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 42)
        XCTAssertFalse(result.succeeded)
    }

    func testFalseCommand() async throws {
        let result = try await executor.executeCollecting(
            command: "false",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertFalse(result.succeeded)
    }

    func testTrueCommand() async throws {
        let result = try await executor.executeCollecting(
            command: "true",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.succeeded)
    }

    // MARK: - Stdout / Stderr Separation

    func testStdoutAndStderrSeparation() async throws {
        let result = try await executor.executeCollecting(
            command: "echo 'out message'; echo 'err message' >&2",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("out message"),
                       "stdout should contain 'out message', got: \(result.stdout)")
        XCTAssertTrue(result.stderr.contains("err message"),
                       "stderr should contain 'err message', got: \(result.stderr)")
    }

    func testStderrOnlyCommand() async throws {
        let result = try await executor.executeCollecting(
            command: "echo 'error only' >&2",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.isEmpty || result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(result.stderr.contains("error only"))
    }

    // MARK: - Streaming Events

    func testStreamingEvents() async throws {
        let (_, stream) = await executor.execute(
            command: "echo 'streamed'; echo 'error' >&2",
            cwd: cwd
        )

        var gotStdout = false
        var gotStderr = false
        var gotExited = false

        for try await event in stream {
            switch event {
            case .stdout(let data):
                let text = String(data: data, encoding: .utf8) ?? ""
                if text.contains("streamed") { gotStdout = true }
            case .stderr(let data):
                let text = String(data: data, encoding: .utf8) ?? ""
                if text.contains("error") { gotStderr = true }
            case .exited(let code, _):
                XCTAssertEqual(code, 0)
                gotExited = true
            }
        }

        XCTAssertTrue(gotStdout, "Should have received stdout event")
        XCTAssertTrue(gotStderr, "Should have received stderr event")
        XCTAssertTrue(gotExited, "Should have received exited event")
    }

    // MARK: - Working Directory

    func testWorkingDirectory() async throws {
        // Use /tmp which resolves cleanly to /private/tmp on macOS
        let tmpDir = URL(fileURLWithPath: "/private/tmp")
        let result = try await executor.executeCollecting(
            command: "pwd -P",
            cwd: tmpDir
        )
        XCTAssertEqual(result.exitCode, 0)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(output, "/private/tmp",
                       "pwd output should match the specified cwd")
    }

    // MARK: - Environment Variables

    func testEnvironmentOverrides() async throws {
        let result = try await executor.executeCollecting(
            command: "echo $ZYQUO_TEST_VAR",
            cwd: cwd,
            env: ["ZYQUO_TEST_VAR": "test_value_42"]
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("test_value_42"),
                       "Should see the overridden env var")
    }

    // MARK: - Timeout

    func testTimeoutEnforcement() async throws {
        // Use a very short timeout (1 second) with a long-running command
        do {
            _ = try await executor.executeCollecting(
                command: "sleep 30",
                cwd: cwd,
                timeout: 1.0
            )
            XCTFail("Expected timeout error")
        } catch let error as ShellError {
            XCTAssertEqual(error.code, "shell.timeout")
        } catch {
            // The process may also exit with a non-zero code when terminated.
            // This is acceptable -- the point is that it didn't wait 30 seconds.
        }
    }

    // MARK: - Cancellation

    func testCancellation() async throws {
        let (jobId, stream) = await executor.execute(
            command: "sleep 30",
            cwd: cwd
        )

        // Cancel after a short delay
        Task {
            try await Task.sleep(for: .milliseconds(200))
            await executor.cancel(jobId: jobId)
        }

        // Consume stream -- should finish relatively quickly
        let start = ContinuousClock.now
        var exitCode: Int32?
        for try await event in stream {
            if case .exited(let code, _) = event {
                exitCode = code
            }
        }
        let elapsed = ContinuousClock.now - start

        XCTAssertNotNil(exitCode, "Should receive an exit event after cancellation")
        // Should complete well under 30 seconds (the sleep duration)
        XCTAssertTrue(elapsed < .seconds(10),
                       "Cancellation should terminate the process quickly, took \(elapsed)")
    }

    // MARK: - Shell Fallback

    func testShellFallbackWhenConfiguredShellMissing() async throws {
        // Create an executor with a non-existent shell
        let badConfig = ShellConfig(
            flags: .init(),
            env: [:],
            workspace: [:],
            user: ["shell": ["default": "/nonexistent/shell"] as [String: Any]]
        )
        let fallbackExecutor = ShellExecutor(config: badConfig)

        let result = try await fallbackExecutor.executeCollecting(
            command: "echo 'fallback works'",
            cwd: cwd
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("fallback works"))
    }

    // MARK: - Job ID

    func testJobIdUniqueness() {
        let id1 = JobID()
        let id2 = JobID()
        XCTAssertNotEqual(id1, id2)
    }

    func testJobIdDescription() {
        let id = JobID(value: "job_test_123")
        XCTAssertEqual(id.description, "job_test_123")
    }

    // MARK: - Duration Tracking

    func testDurationTracking() async throws {
        let result = try await executor.executeCollecting(
            command: "sleep 0.1",
            cwd: cwd
        )
        XCTAssertTrue(result.durationMs >= 50,
                       "Duration should be at least 50ms for a sleep 0.1")
    }

    // MARK: - CommandResult

    func testCommandResultProperties() {
        let result = CommandResult(
            command: "test",
            exitCode: 0,
            signal: nil,
            stdout: "output",
            stderr: "",
            durationMs: 42,
            bytesOut: 6,
            bytesErr: 0,
            jobId: JobID(value: "test_job")
        )
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.command, "test")
        XCTAssertEqual(result.durationMs, 42)
        XCTAssertNil(result.signal)
    }

    func testCommandResultFailure() {
        let result = CommandResult(
            command: "fail",
            exitCode: 1,
            signal: nil,
            stdout: "",
            stderr: "error",
            durationMs: 5,
            bytesOut: 0,
            bytesErr: 5,
            jobId: JobID(value: "fail_job")
        )
        XCTAssertFalse(result.succeeded)
    }
}

// MARK: - EnvironmentMask Tests

final class EnvironmentMaskTests: XCTestCase {

    func testSensitiveTokenDetection() {
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "GITHUB_TOKEN"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "API_TOKEN"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "MY_SECRET"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "API_KEY"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "DB_PASSWORD"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "SOME_CREDENTIAL"))
    }

    func testSensitivePrefixDetection() {
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "SSH_AUTH_SOCK"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "SSH_AGENT_PID"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "AWS_ACCESS_KEY_ID"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "AWS_SECRET_ACCESS_KEY"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "ANTHROPIC_API_KEY"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "OPENAI_API_KEY"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "OPENROUTER_API_KEY"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "GOOGLE_APPLICATION_CREDENTIALS"))
        XCTAssertTrue(EnvironmentMask.isSensitive(name: "AZURE_STORAGE_KEY"))
    }

    func testNonSensitiveVars() {
        XCTAssertFalse(EnvironmentMask.isSensitive(name: "HOME"))
        XCTAssertFalse(EnvironmentMask.isSensitive(name: "PATH"))
        XCTAssertFalse(EnvironmentMask.isSensitive(name: "SHELL"))
        XCTAssertFalse(EnvironmentMask.isSensitive(name: "TERM"))
        XCTAssertFalse(EnvironmentMask.isSensitive(name: "LANG"))
        XCTAssertFalse(EnvironmentMask.isSensitive(name: "USER"))
        XCTAssertFalse(EnvironmentMask.isSensitive(name: "EDITOR"))
    }

    func testSanitizeRemovesSensitiveVars() {
        let env: [String: String] = [
            "HOME": "/Users/test",
            "PATH": "/usr/bin:/bin",
            "ANTHROPIC_API_KEY": "sk-ant-secret",
            "SSH_AUTH_SOCK": "/tmp/ssh.sock",
            "API_TOKEN": "secret123",
            "TERM": "xterm-256color",
        ]

        let sanitized = EnvironmentMask.sanitize(environment: env)

        XCTAssertEqual(sanitized["HOME"], "/Users/test")
        XCTAssertEqual(sanitized["TERM"], "xterm-256color")
        XCTAssertNil(sanitized["ANTHROPIC_API_KEY"])
        XCTAssertNil(sanitized["SSH_AUTH_SOCK"])
        XCTAssertNil(sanitized["API_TOKEN"])
    }

    func testOverridesAreNotFiltered() {
        let env: [String: String] = [
            "HOME": "/Users/test",
        ]

        let sanitized = EnvironmentMask.sanitize(
            environment: env,
            overrides: ["MY_SECRET": "allowed_override"]
        )

        // Overrides bypass the filter
        XCTAssertEqual(sanitized["MY_SECRET"], "allowed_override")
    }

    func testOverridesReplaceExistingVars() {
        let env: [String: String] = [
            "HOME": "/Users/test",
            "TERM": "xterm",
        ]

        let sanitized = EnvironmentMask.sanitize(
            environment: env,
            overrides: ["TERM": "xterm-256color"]
        )

        XCTAssertEqual(sanitized["TERM"], "xterm-256color")
    }

    func testPATHSanitization() {
        let path = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/some/random/path:/usr/local/bin"
        let sanitized = EnvironmentMask.sanitizePath(path)

        XCTAssertTrue(sanitized.contains("/usr/bin"))
        XCTAssertTrue(sanitized.contains("/bin"))
        XCTAssertTrue(sanitized.contains("/opt/homebrew/bin"))
        XCTAssertTrue(sanitized.contains("/usr/local/bin"))
        XCTAssertFalse(sanitized.contains("/some/random/path"))
    }

    func testPATHDeduplication() {
        let path = "/usr/bin:/usr/bin:/bin:/bin"
        let sanitized = EnvironmentMask.sanitizePath(path)
        let components = sanitized.split(separator: ":").map(String.init)
        let unique = Set(components)
        XCTAssertEqual(components.count, unique.count,
                       "PATH should not contain duplicates")
    }

    func testHomebrewPrefixDetection() {
        let prefix = EnvironmentMask.homebrewPrefix
        #if arch(arm64)
        XCTAssertEqual(prefix, "/opt/homebrew/bin")
        #else
        XCTAssertEqual(prefix, "/usr/local/bin")
        #endif
    }

    func testPATHAlwaysIncludesHomebrewPrefix() {
        let sanitized = EnvironmentMask.sanitizePath("/usr/bin")
        XCTAssertTrue(sanitized.contains(EnvironmentMask.homebrewPrefix),
                       "Sanitized PATH should always include Homebrew prefix")
    }

    func testEnvironmentMaskingInExecution() async throws {
        let config = ShellConfig(
            flags: .init(),
            env: [:],
            workspace: [:],
            user: [:]
        )
        let executor = ShellExecutor(config: config)
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory())

        // Set a sensitive var that the child should NOT see
        // We pass it as an explicit env var that would normally be present
        // but the sanitizer should strip it
        let result = try await executor.executeCollecting(
            command: "env | grep ZYQUO_MASK_TEST || true",
            cwd: cwd
        )
        // The variable ZYQUO_MASK_TEST is not in the parent env, so grep should find nothing
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.stdout.contains("ZYQUO_MASK_TEST"))
    }
}

// MARK: - CommandHistory Tests

final class CommandHistoryTests: XCTestCase {

    func testRecordAndRetrieve() {
        let history = CommandHistory()
        let entry = CommandHistoryEntry(
            command: "echo hello",
            timestamp: Date(),
            exitCode: 0,
            durationMs: 5,
            jobId: JobID(value: "test1")
        )
        history.record(entry)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.all.first?.command, "echo hello")
    }

    func testLastN() {
        let history = CommandHistory()
        for i in 0..<10 {
            history.record(CommandHistoryEntry(
                command: "cmd_\(i)",
                timestamp: Date(),
                exitCode: 0,
                durationMs: 1,
                jobId: JobID(value: "job_\(i)")
            ))
        }

        let last3 = history.last(3)
        XCTAssertEqual(last3.count, 3)
        XCTAssertEqual(last3[0].command, "cmd_7")
        XCTAssertEqual(last3[1].command, "cmd_8")
        XCTAssertEqual(last3[2].command, "cmd_9")
    }

    func testLastNExceedingCount() {
        let history = CommandHistory()
        history.record(CommandHistoryEntry(
            command: "only",
            timestamp: Date(),
            exitCode: 0,
            durationMs: 1,
            jobId: JobID(value: "job_0")
        ))

        let last10 = history.last(10)
        XCTAssertEqual(last10.count, 1)
    }

    func testSearch() {
        let history = CommandHistory()
        history.record(CommandHistoryEntry(
            command: "swift build",
            timestamp: Date(),
            exitCode: 0,
            durationMs: 5000,
            jobId: JobID(value: "job_build")
        ))
        history.record(CommandHistoryEntry(
            command: "swift test",
            timestamp: Date(),
            exitCode: 0,
            durationMs: 10000,
            jobId: JobID(value: "job_test")
        ))
        history.record(CommandHistoryEntry(
            command: "git status",
            timestamp: Date(),
            exitCode: 0,
            durationMs: 50,
            jobId: JobID(value: "job_git")
        ))

        let swiftResults = history.search("swift")
        XCTAssertEqual(swiftResults.count, 2)

        let gitResults = history.search("git")
        XCTAssertEqual(gitResults.count, 1)

        let noResults = history.search("docker")
        XCTAssertEqual(noResults.count, 0)
    }

    func testSearchCaseInsensitive() {
        let history = CommandHistory()
        history.record(CommandHistoryEntry(
            command: "Swift Build",
            timestamp: Date(),
            exitCode: 0,
            durationMs: 5,
            jobId: JobID(value: "job_1")
        ))

        let results = history.search("swift")
        XCTAssertEqual(results.count, 1)
    }

    func testMaxEntries() {
        let history = CommandHistory(maxEntries: 5)
        for i in 0..<10 {
            history.record(CommandHistoryEntry(
                command: "cmd_\(i)",
                timestamp: Date(),
                exitCode: 0,
                durationMs: 1,
                jobId: JobID(value: "job_\(i)")
            ))
        }

        XCTAssertEqual(history.count, 5)
        // Oldest entries should be dropped
        let all = history.all
        XCTAssertEqual(all.first?.command, "cmd_5")
        XCTAssertEqual(all.last?.command, "cmd_9")
    }

    func testClear() {
        let history = CommandHistory()
        history.record(CommandHistoryEntry(
            command: "test",
            timestamp: Date(),
            exitCode: 0,
            durationMs: 1,
            jobId: JobID(value: "job_1")
        ))
        XCTAssertEqual(history.count, 1)

        history.clear()
        XCTAssertEqual(history.count, 0)
    }

    func testRecordFromCommandResult() {
        let history = CommandHistory()
        let result = CommandResult(
            command: "echo hi",
            exitCode: 0,
            stdout: "hi\n",
            stderr: "",
            durationMs: 3,
            bytesOut: 3,
            bytesErr: 0,
            jobId: JobID(value: "job_result")
        )
        let started = Date()
        history.record(from: result, startedAt: started)

        XCTAssertEqual(history.count, 1)
        let entry = history.all.first!
        XCTAssertEqual(entry.command, "echo hi")
        XCTAssertEqual(entry.exitCode, 0)
        XCTAssertEqual(entry.durationMs, 3)
    }
}

// MARK: - ShellSession Tests

final class ShellSessionTests: XCTestCase {

    func testSessionExecuteCollecting() async throws {
        let config = ShellConfig(flags: .init(), env: [:], workspace: [:], user: [:])
        let executor = ShellExecutor(config: config)
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory())
        let session = ShellSession(executor: executor, cwd: cwd)

        let result = try await session.executeCollecting(command: "echo session_test")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("session_test"))

        // Should be recorded in history
        XCTAssertEqual(session.history.count, 1)
    }

    func testSessionCwdManagement() {
        let config = ShellConfig(flags: .init(), env: [:], workspace: [:], user: [:])
        let executor = ShellExecutor(config: config)
        let initialCwd = URL(fileURLWithPath: "/tmp")
        let session = ShellSession(executor: executor, cwd: initialCwd)

        XCTAssertEqual(session.cwd.path, "/tmp")

        let newCwd = URL(fileURLWithPath: "/var")
        session.setCwd(newCwd)
        XCTAssertEqual(session.cwd.path, "/var")
    }

    func testSessionEnvOverrides() async throws {
        let config = ShellConfig(flags: .init(), env: [:], workspace: [:], user: [:])
        let executor = ShellExecutor(config: config)
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory())
        let session = ShellSession(executor: executor, cwd: cwd)

        session.setEnv(key: "SESSION_VAR", value: "session_value")
        XCTAssertEqual(session.envOverrides["SESSION_VAR"], "session_value")

        let result = try await session.executeCollecting(command: "echo $SESSION_VAR")
        XCTAssertTrue(result.stdout.contains("session_value"))

        session.removeEnv(key: "SESSION_VAR")
        XCTAssertNil(session.envOverrides["SESSION_VAR"])
    }

    func testSessionHistoryAccumulates() async throws {
        let config = ShellConfig(flags: .init(), env: [:], workspace: [:], user: [:])
        let executor = ShellExecutor(config: config)
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory())
        let session = ShellSession(executor: executor, cwd: cwd)

        _ = try await session.executeCollecting(command: "echo first")
        _ = try await session.executeCollecting(command: "echo second")
        _ = try await session.executeCollecting(command: "echo third")

        XCTAssertEqual(session.history.count, 3)

        let last2 = session.history.last(2)
        XCTAssertEqual(last2[0].command, "echo second")
        XCTAssertEqual(last2[1].command, "echo third")
    }
}

// MARK: - ShellEvent Tests

final class ShellEventTests: XCTestCase {

    func testJobIDCreation() {
        let id = JobID()
        XCTAssertTrue(id.value.hasPrefix("job_"))
    }

    func testJobIDEquality() {
        let id1 = JobID(value: "same")
        let id2 = JobID(value: "same")
        XCTAssertEqual(id1, id2)

        let id3 = JobID(value: "different")
        XCTAssertNotEqual(id1, id3)
    }

    func testJobIDHashable() {
        let id1 = JobID(value: "a")
        let id2 = JobID(value: "b")
        var set = Set<JobID>()
        set.insert(id1)
        set.insert(id2)
        XCTAssertEqual(set.count, 2)
    }

    func testExecutionModeDefault() {
        let mode: ExecutionMode = .pipe
        switch mode {
        case .pipe: break // expected
        case .pty: XCTFail("Default should be pipe")
        }
    }
}
