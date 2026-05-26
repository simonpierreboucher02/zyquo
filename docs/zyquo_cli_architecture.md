# Zyquo CLI Architecture

## 1. Executive Summary

Zyquo is a native macOS AI terminal agent runtime written in Swift. It combines the autonomous agent loop architecture of OpenHands, the approval-gated diff workflow of Cline, and the terminal-native UX of OpenCode into a single, fast, beautiful, and safe binary.

Core differentiators:

- **Swift-native performance.** Cold start under 120 ms, first LLM token under 800 ms. No Python, no Node.js, no Electron in the hot path. Binary size under 25 MB.
- **Terminal-first rendering.** A virtual-buffer ANSI renderer with truecolor support, diff-based flush, theme hot-swap, and responsive layout. The terminal is treated as a first-class rendering target, not an afterthought.
- **Patch-gated file editing.** Every file write passes through a snapshot-diff-approve-apply pipeline. Every applied patch is reversible. No silent writes.
- **Tiered risk classification.** Shell commands are classified into SAFE / MODERATE / DANGEROUS / CRITICAL tiers using rule-based analysis (not LLM judgment). Approvals are scoped (once / session / workspace / global) and persisted.
- **Persistent structured memory.** Session memory, project memory, architecture memory, and decision memory survive restarts. Retrieval is BM25-backed in V1, hybrid vector in V2.
- **macOS-native integration.** API keys in Keychain, file watching via FSEvents, notifications via UserNotifications.framework. No cross-platform compromises in V1.

The system is designed as a single executable target (`Zyquo`) backed by a testable library target (`ZyquoCore`), using Swift's structured concurrency throughout. Dependency injection is explicit via `AppContainer`, not a framework. External dependencies are minimal and audited.

---

## 2. Architecture Overview

```
                            +----------------------------+
                            |     CLI Entry Point        |
                            |  (ArgumentParser commands) |
                            +-------------+--------------+
                                          |
                    +---------------------+---------------------+
                    |                     |                     |
            +-------+-------+    +-------+-------+    +-------+--------+
            | InteractiveCmd|    | RunCommand    |    | AskCommand     |
            | (REPL loop)   |    | (agentic run) |    | (single-shot)  |
            +-------+-------+    +-------+-------+    +-------+--------+
                    |                     |                     |
                    +---------------------+---------------------+
                                          |
                    +---------------------+---------------------+
                    |                                           |
            +-------+--------+                         +-------+--------+
            |  Agent Runtime |                         | TerminalRenderer|
            |                |                         |                 |
            | AgentLoop      |  <--- UI events --->    | CellBuffer      |
            | Planner        |                         | LayoutEngine    |
            | Executor       |                         | ThemeEngine     |
            | Verifier       |                         | Panel / Box     |
            | ContextAssembr |                         | DiffView        |
            | TokenBudget    |                         | CommandCard     |
            | Summarizer     |                         | TimelineView    |
            | StopConditions |                         | PromptInput     |
            +-------+--------+                         +----------------+
                    |
        +-----------+-----------+
        |           |           |
+-------+--+ +-----+----+ +----+------+
| ToolReg  | | Provider | | Memory    |
|          | | Layer    | | System    |
| ShellTool| |          | |           |
| FileRead | | Anthropic| | Session   |
| FilePatch| | OpenRtr  | | Project   |
| GitTool  | | Router   | | Decision  |
| SearchTl | | Streaming| | Retrieval |
| MemoryTl | | Pricing  | | Compress  |
+-------+--+ +-----+----+ +----+------+
        |           |           |
+-------+--+ +-----+----+ +----+------+
| Shell    | | Security | | Persist   |
| Executor | |          | |           |
|          | | Keychain | | SQLite    |
| Process  | | RiskClass| | (GRDB)    |
| PTYHost  | | Boundary | | Sessions  |
| EnvMask  | | AuditLog | | Patches   |
| DangerRul| | Sandbox  | | Snapshots |
+----------+ +----------+ +-----------+
```

The system is organized into 13 modules, each with clear ownership and a narrow public interface. Communication between modules happens through typed Swift protocols and `AsyncStream`-based event channels. There are no singletons; all dependencies flow through `AppContainer`.

---

## 3. Module Boundaries

### 3.1 Commands (CLI surface)

**Owns:** Argument parsing, subcommand dispatch, global flag handling, exit codes.
**Public interface:** Each command conforms to `AsyncParsableCommand` (Swift ArgumentParser). Commands construct the relevant service from `AppContainer` and invoke it.
**Key types:** `InteractiveCommand`, `RunCommand`, `AskCommand`, `DoctorCommand`, `ConfigCommand`, etc.
**Rule:** Commands contain zero business logic. They parse args, call a service, and translate the result into an exit code.

### 3.2 Agent (runtime core)

**Owns:** The agent loop, planning, execution, verification, context assembly, token budgeting, summarization, stop condition evaluation.
**Public interface:**

```swift
public actor AgentRuntime {
    func run(intent: String, workspace: Workspace) -> AsyncStream<AgentEvent>
    func cancel()
    func resume(sessionId: SessionID) -> AsyncStream<AgentEvent>
}

public enum AgentEvent: Sendable {
    case statusChanged(AgentStatus)
    case planProduced(Plan)
    case stepStarted(AgentStep)
    case toolProposed(ToolCall, RiskLevel)
    case approvalRequired(ToolCall, RiskLevel)
    case toolExecuted(ToolCall, ToolResult)
    case observationRecorded(Observation)
    case verificationCompleted(StepID, Verdict)
    case contextCompacted(tokensBefore: Int, tokensAfter: Int)
    case sessionPersisted(SessionID)
    case finished(SessionSummary)
    case error(ZyquoError)
}
```

**Dependencies:** ToolRegistry, LLMProvider (via ModelRouter), MemoryRetriever, Workspace, SessionStore.

### 3.3 Tools

**Owns:** Tool protocol, registry, individual tool implementations, tool result formatting.
**Public interface:**

```swift
public protocol Tool: Sendable {
    var name: String { get }
    var summary: String { get }
    var documentation: String { get }
    var inputSchema: JSONSchema { get }
    var defaultRisk: RiskLevel { get }
    var isMutating: Bool { get }

    func execute(
        input: ToolInput,
        context: ToolContext
    ) async throws -> ToolResult
}

public final class ToolRegistry: Sendable {
    func register(_ tool: any Tool)
    func tool(named: String) -> (any Tool)?
    func allTools(filteredBy: ToolFilter) -> [any Tool]
    func schemas() -> [ToolSchema]  // For LLM tool_use parameter
}
```

**Key tools (V1):** `shell.run`, `file.read`, `file.write`, `file.patch`, `file.list`, `file.search`, `git.status`, `git.diff`, `git.commit`, `git.branch`, `memory.read`, `memory.write`, `task.plan`, `task.verify`, `notify.user`.

### 3.4 Shell

**Owns:** Process execution, stdio streaming, environment masking, PTY hosting, command history.
**Public interface:**

```swift
public actor ShellExecutor {
    func execute(
        command: String,
        cwd: URL,
        env: [String: String],
        timeout: Duration,
        mode: ExecutionMode   // .pipe | .pty
    ) -> AsyncThrowingStream<ShellEvent, Error>
    func cancel(jobId: JobID)
}

public enum ShellEvent: Sendable {
    case stdout(Data)
    case stderr(Data)
    case exited(code: Int32, signal: Int32?)
}
```

**Rule:** `ShellExecutor` never classifies risk. It executes what it is told. Risk classification happens in `RiskClassifier` before the executor is invoked.

### 3.5 Workspace

**Owns:** Workspace root detection, project detection (language, framework, package manager, test command), file indexing, .gitignore + .zyquoignore parsing, boundary enforcement, FSEvents watching.
**Public interface:**

```swift
public actor Workspace {
    let root: URL
    func scan() async throws -> WorkspaceIndex
    func isInsideBoundary(_ path: URL) -> Bool
    func detect() -> ProjectDescriptor
    var onChange: AsyncStream<FileChangeEvent> { get }
}
```

### 3.6 Diff

**Owns:** Diff computation (Myers algorithm), patch generation, patch application (atomic write via temp+rename), three-way merge, conflict resolution, changeset grouping.
**Public interface:**

```swift
public struct DiffEngine {
    static func diff(old: String, new: String) -> UnifiedDiff
    static func threeWayMerge(base: String, ours: String, theirs: String)
        -> MergeResult
}

public struct PatchEngine {
    static func apply(_ diff: UnifiedDiff, to content: String)
        throws -> String
    static func reverse(_ diff: UnifiedDiff) -> UnifiedDiff
}
```

### 3.7 Models (Provider Layer)

**Owns:** LLM provider protocol, Anthropic client, OpenRouter client, model routing, streaming event decoding, token usage tracking, pricing.
**Public interface:** See section 7 below.

### 3.8 Memory

**Owns:** Session memory, project memory, decision memory, memory compression, memory retrieval (BM25 in V1).
**Public interface:**

```swift
public protocol MemoryRetriever: Sendable {
    func recall(
        query: String,
        scope: MemoryScope,
        limit: Int
    ) async throws -> [MemoryChunk]
}
```

### 3.9 UI (Terminal Rendering)

**Owns:** Virtual buffer, ANSI emission, theme engine, all visual components (Panel, Box, DiffView, CommandCard, etc.), layout engine, input handling.
**Public interface:** See section 11 below.

### 3.10 Persistence

**Owns:** SQLite (GRDB) database, session store, memory store, config store, patch store, snapshot store.
**Public interface:** Each store is a protocol with a GRDB-backed implementation, injectable via `AppContainer`.

### 3.11 Security

**Owns:** Keychain access, risk classification, danger rules, workspace boundary guard, PII/secret redaction, audit log.
**Public interface:**

```swift
public struct RiskClassifier: Sendable {
    func classify(_ command: String, workspace: Workspace)
        -> RiskAssessment
}

public struct RiskAssessment: Sendable {
    let tier: RiskLevel          // .safe, .moderate, .dangerous, .critical
    let rationale: String
    let matchedRules: [DangerRule]
    let escalationReasons: [String]
}
```

### 3.12 Observability

**Owns:** Structured logging (JSONL), metrics (swift-metrics shaped), tracing, crash reporting.
**Rule:** All log output passes through redaction before being written. Secrets never appear in logs.

### 3.13 Errors

**Owns:** `ZyquoError` taxonomy, structured error formatting, remediation hints.

---

## 4. Data Flow

A user intent flows through the system as follows:

```
User types: "Fix the failing tests and explain the issue"
    |
    v
[InteractiveCommand] parses input, detects it is not a slash command
    |
    v
[AgentRuntime.run(intent:workspace:)] begins
    |
    v
[Workspace.scan()] returns WorkspaceIndex (cached if warm, < 200 ms)
    |
    v
[ContextAssembler.assemble(intent, workspace, memory)]
    |-- MemoryRetriever.recall(intent, scope: .all)
    |-- WorkspaceIndex.summary()
    |-- ProjectMemory.read()
    |-- TokenBudget.check() -> compress/drop if over 70%
    |
    v
[Planner.plan(intent, context)] -> LLM call with planner prompt
    |-- Returns Plan { steps: [Step { goal, successCriteria }] }
    |-- UI emits: AgentEvent.planProduced(plan)
    |
    v
For each step in plan:
    |
    [Planner.propose(step, state)] -> LLM call -> ToolCall
        |
        v
    [RiskClassifier.classify(toolCall)] -> RiskAssessment
        |
        v
    [ApprovalGate.check(toolCall, risk, trust)]
        |-- If SAFE && auto_approve_safe: proceed
        |-- If trust covers this: proceed
        |-- Else: UI emits AgentEvent.approvalRequired(...)
        |       User responds: yes / no / always / edit
        |       "always" -> TrustGrant persisted at chosen scope
        |
        v
    [Executor.execute(toolCall)] -> calls Tool.execute(input, context)
        |-- ShellTool: ShellExecutor.execute(...) streams output to UI
        |-- FilePatchTool: SnapshotStore.snapshot() -> DiffEngine.diff()
        |       -> DiffView renders in UI -> approval -> PatchEngine.apply()
        |       -> PatchStore.record()
        |-- FileReadTool: read content, return summary + payload
        |
        v
    [Observation recorded, appended to AgentState.steps]
        |
        v
    [Verifier.verify(step, observation)] -> LLM call -> Verdict
        |-- pass: continue
        |-- fail: replan with failure context
        |-- unclear: mark, continue cautiously
        |
        v
    [MemoryStore.appendSession(step)]
    [StopConditions.check(state)]
        |-- max steps? max cost? user cancel? 3 consecutive failures?
        |-- Loop detected (same toolCall hash 3x in window of 5)?
    |
    v (loop ends)
[Summarizer.finalize(state)] -> SessionSummary
[SessionStore.flush(state)]
[MemoryStore.flush()]
UI emits: AgentEvent.finished(summary)
```

Every state transition produces an `AgentEvent` that the UI layer consumes for rendering. The agent never writes directly to stdout; all output flows through `TerminalRenderer`.

---

## 5. Concurrency Model

Zyquo uses Swift's structured concurrency exclusively. No GCD queues, no OperationQueues, no manual threading.

### 5.1 Actors

| Actor | Purpose | Isolation boundary |
|-------|---------|-------------------|
| `AgentRuntime` | Owns `AgentState`, serializes plan/execute/verify steps | Mutable agent state |
| `ShellExecutor` | Owns running processes, job table | Process lifecycle |
| `Workspace` | Owns workspace index, FSEvents watcher | Index mutations |
| `SessionStore` | Owns SQLite write connection | Database writes |
| `MemoryStore` | Owns memory write path | Memory mutations |
| `TerminalRenderer` | Owns the virtual buffer and ANSI output | Screen state |

### 5.2 Structured concurrency patterns

- **Agent loop:** Sequential. Each step completes (plan -> propose -> approve -> execute -> verify) before the next begins. This is a `for step in plan.steps` loop inside an async context, not a TaskGroup.
- **LLM streaming:** `AsyncThrowingStream<LLMEvent, Error>` produced by the provider, consumed by the agent. Cancellation propagates via `Task.cancel` -> URLSession task cancellation.
- **Shell output streaming:** `AsyncThrowingStream<ShellEvent, Error>` produced by the executor, consumed by the tool, forwarded to the UI as `AgentEvent`.
- **UI rendering:** The renderer consumes `AgentEvent` on a dedicated `Task`. It never blocks the agent loop.
- **Workspace watching:** FSEvents callback dispatches to the `Workspace` actor. The actor debounces and re-indexes.

### 5.3 Cancellation

`Ctrl-C` triggers a SIGINT handler that calls `AgentRuntime.cancel()`. This:
1. Sets `AgentState.status = .cancelled`
2. Cancels the current `Task` (which propagates to LLM stream or shell process)
3. Flushes session state to disk (checkpoint)
4. Restores terminal state (raw mode off, cursor visible)
5. Returns exit code 130

If idle (no active agent loop), `Ctrl-C` exits immediately after terminal restore.

---

## 6. State Management

### 6.1 AgentState

```swift
public struct AgentState: Sendable {
    public let sessionId: SessionID
    public let intent: String
    public var plan: Plan
    public var steps: [AgentStep]
    public var workspaceSnapshot: WorkspaceSnapshot
    public var context: AssembledContext
    public var tokenBudget: TokenBudget
    public var cost: SessionCost
    public var trust: TrustGrant
    public var status: AgentStatus
    public var startedAt: Date
    public var updatedAt: Date
}
```

Owned exclusively by `AgentRuntime` (actor-isolated). External reads happen through `AgentEvent` emissions, not direct access.

### 6.2 SessionState (persisted)

```swift
public struct SessionRecord: Codable, Sendable {
    let id: SessionID                   // "zq_<yyyymmdd>_<short-uuid>"
    let intent: String
    let plan: Plan
    let steps: [AgentStep]
    let tokenUsage: TokenUsage
    let cost: SessionCost
    let model: String
    let provider: String
    let startedAt: Date
    let finishedAt: Date?
    let status: AgentStatus
    let checkpointHash: String?         // For resume
}
```

Stored in SQLite via GRDB. Session events are appended to a JSONL sidecar file for replay.

### 6.3 WorkspaceState

```swift
public struct WorkspaceIndex: Sendable {
    let root: URL
    let languages: [(Language, Float)]   // Weighted by file count + size
    let frameworks: [Framework]
    let packageManager: PackageManager?
    let testCommand: String?
    let buildCommand: String?
    let gitStatus: GitStatus?
    let fileCount: Int
    let lastFullScan: Date
}
```

Cached in `Workspace` actor. Invalidated by FSEvents. Persisted to `.zyquo/index/workspace.sqlite` for warm restarts.

---

## 7. Provider Abstraction

### 7.1 LLMProvider Protocol

```swift
public protocol LLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var supportedModels: [ModelDescriptor] { get }

    func send(
        request: LLMRequest,
        cancellation: Task<Void, Never>?
    ) -> AsyncThrowingStream<LLMEvent, Error>
}

public struct LLMRequest: Sendable {
    let model: String
    let systemPrompt: String
    let messages: [LLMMessage]
    let tools: [ToolSchema]
    let toolChoice: ToolChoice
    let maxTokens: Int
    let temperature: Float?
    let metadata: [String: String]
}

public enum LLMEvent: Sendable {
    case messageStart(MessageMeta)
    case textDelta(String)
    case toolUseStart(ToolUseMeta)
    case toolUseInputDelta(String)
    case toolUseEnd(ToolUseResult)
    case usage(TokenUsage)
    case messageStop(StopReason)
    case error(LLMError)
}
```

### 7.2 Streaming Implementation

Both `AnthropicProvider` and `OpenRouterProvider` use `URLSession` with SSE (Server-Sent Events) parsing. The `StreamingDecoder` parses the `data:` lines and emits typed `LLMEvent` values into an `AsyncThrowingStream`. The decoder handles:

- Partial JSON chunks (buffered until complete)
- `[DONE]` sentinel
- HTTP 429 (rate limit) -> exponential backoff with jitter, max 3 retries
- HTTP 529 (overloaded) -> same retry policy
- Stream idle timeout (configurable, default 30 s between events)
- Request timeout (configurable, default 120 s total)

### 7.3 ModelRouter

```swift
public actor ModelRouter {
    func resolve(for taskClass: TaskClass) -> (provider: LLMProvider, model: String)
}

public enum TaskClass { case planning, coding, summarization, verification }
```

Default routing policy:
- `planning` -> Claude Opus 4.7
- `coding` -> Claude Sonnet 4.6
- `summarization` -> Claude Haiku 4.5
- `verification` -> Claude Sonnet 4.6

User overrides via `--model` or `/model` take precedence.

**Design decision rationale:** OpenHands uses LiteLLM for provider abstraction, which gives breadth but adds a Python dependency. Cline has 35+ provider files with substantial duplication. OpenCode layers AI SDK adapters through Effect, which is clean but complex. Zyquo takes the simplest approach: a Swift protocol with two concrete implementations (Anthropic, OpenRouter) in V1, adding more in V2. OpenRouter already provides access to most models, so two providers cover the majority of use cases.

---

## 8. Tool System

### 8.1 Execution Pipeline

```
Agent proposes ToolCall
    |
    v
ToolRegistry.tool(named: toolCall.name)
    |-- Not found? -> ToolError.unknownTool
    |
    v
RiskClassifier.classify(toolCall, workspace)
    |-- Considers: tool.defaultRisk, command content (for shell),
    |   path location (inside/outside workspace), DangerRules matches
    |
    v
ApprovalGate.check(toolCall, risk, currentTrust)
    |-- Auto-approve if: risk == .safe && config.auto_approve_safe
    |-- Auto-approve if: trust grant covers this tool+pattern+scope
    |-- Otherwise: emit approvalRequired, block until user responds
    |
    v
Tool.execute(input, context)
    |-- context.workspace provides boundary checking
    |-- context.approval provides re-approval for escalation
    |-- context.logger logs structured event
    |-- context.metrics records invocation
    |
    v
ToolResult { summary, payload, artifacts, durationMs, tokenHint }
    |
    v
Echoing policy:
    |-- LLM always sees summary (1-3 lines)
    |-- LLM sees payload only if tokenHint < budget.tail
    |-- Large payloads stored as artifacts, referenced by ID
```

### 8.2 Tool Registration

Tools are registered explicitly in `AppContainer.buildToolRegistry()`. There is no runtime discovery, no reflection, no plugin loading in V1. This keeps the tool surface auditable and the startup path fast.

**Design decision rationale:** OpenHands loads tools from an external package (`openhands-tools`), which fragments the codebase. Cline uses a coordinator with factory functions. OpenCode uses Effect-based lazy initialization. Zyquo uses explicit registration because: (a) V1 has a fixed tool set, (b) explicit registration makes auditing trivial, (c) startup is faster without plugin scanning.

---

## 9. Risk and Safety

### 9.1 RiskClassifier Tiers

| Tier | Meaning | Approval behavior |
|------|---------|-------------------|
| SAFE | Read-only, no side effects | Auto-approve if `auto_approve_safe = true` |
| MODERATE | Workspace mutations, local installs | Prompt user; "always" persists per-session |
| DANGEROUS | Destructive ops, recursive deletes | Prompt user; "always" persists per-workspace |
| CRITICAL | sudo, pipe-to-shell, git push, system paths | Always prompt; "always" never available |

### 9.2 DangerRules

`DangerRules.swift` contains ~40 regex patterns organized by tier. Examples:

```
CRITICAL: ^\s*sudo\b, \bcurl.*\|\s*(sh|bash|zsh)\b, \bgit\s+push\b
DANGEROUS: \brm\s+-[rR]f?\b, \bchmod\s+-R\b, \bfind\b.*-delete\b
MODERATE: \bgit\s+commit\b, \bnpm\s+install\b, >\s*[^ &|]+
```

### 9.3 Path-Based Escalation

Any command touching a path outside `Workspace.root` is escalated by one tier. Paths matching `~/.ssh`, `~/.aws`, `~/Library`, `/System`, `/Library`, `/private`, `/usr` (except `/usr/local`) are always CRITICAL.

### 9.4 BoundaryGuard

`BoundaryGuard` enforces that tools cannot read or write outside the workspace root unless explicitly approved at DANGEROUS tier or above. Symlink resolution is applied before boundary checking to prevent escape via symlinks.

### 9.5 Audit Log

Every tool invocation, approval decision, and trust grant is appended to `.zyquo/logs/<session-id>.log` as structured JSONL. The audit log is never cleared by the agent; only the user can delete it.

**Design decision rationale:** OpenHands uses LLM-based security analysis, which is expensive and slow. Cline relies on the LLM's `requires_approval` boolean, which is a judgment call by the model and not trustworthy for safety. OpenCode uses a flat allow/deny/ask model with no risk scoring. Zyquo combines rule-based classification (deterministic, fast, auditable) with tiered approvals (user-friendly) and persistent trust grants (ergonomic for repeated workflows).

---

## 10. File Editing Pipeline

Every file modification follows this pipeline:

```
Agent proposes file content
    |
    v
[SnapshotStore.snapshot(path)]
    |-- Content-addressed gzip under .zyquo/snapshots/<sha>.gz
    |-- Records pre-image SHA-256
    |
    v
[DiffEngine.diff(old: preImage, new: proposed)]
    |-- Myers algorithm, outputs UnifiedDiff
    |-- Intra-line diff on changed tokens for highlighting
    |
    v
[DiffView renders in terminal]
    |-- Unified or side-by-side (toggle with [s])
    |-- Syntax highlighting inside diff lines
    |-- Summary: "3 files changed, +24 / -12, 2 MODERATE"
    |
    v
[ApprovalGate]
    |-- [y]es / [n]o / [a]lways / [e]dit / [?]explain
    |-- Multi-file changesets: approve all or drill into individual files
    |
    v
[PatchEngine.apply(diff, to: preImage)]
    |-- Atomic write: write to temp file, then rename
    |-- Verify post-image hash matches expected
    |
    v
[PatchStore.record(patchId, files, hunks, appliedAt)]
    |-- Patch ID: "zp_<yyyymmdd>_<short-uuid>"
    |-- Reverse patch generated and stored alongside
    |
    v
[WorkspaceIndex updated]
[AgentEvent.toolExecuted emitted]
```

### 10.1 Conflict Handling

If the on-disk content has changed since the snapshot (SHA mismatch), the patch is stale. The system:
1. Re-snapshots the current content
2. Attempts three-way merge via `DiffEngine.threeWayMerge`
3. If clean: re-renders and re-approves
4. If conflicted: opens `ConflictResolver` UI showing conflict markers

### 10.2 Rollback

`/reject <patch-id>` after application triggers `PatchEngine.apply(reversePatch)`. The reverse patch is a pre-computed inverse stored next to the original. Rollback is also atomic (temp + rename).

**Design decision rationale:** Cline's live-streaming diff editor is its best feature, but it requires VSCode's diff infrastructure. OpenHands has no diff review workflow at all -- writes are direct. OpenCode has git-based snapshots but no interactive approval UI. Zyquo reproduces Cline's approval-gated workflow in the terminal using its own DiffView component, with the addition of persistent reverse patches (which neither Cline nor OpenCode provides).

---

## 11. Terminal Rendering

### 11.1 Architecture

```swift
public actor TerminalRenderer {
    private var frontBuffer: CellBuffer
    private var backBuffer: CellBuffer
    private let theme: ThemeEngine
    private let capabilities: TerminalCapabilities

    func render(_ root: any Renderable)
    func flush()   // Diffs back vs front, emits minimal ANSI
}
```

### 11.2 Renderable Protocol

```swift
public protocol Renderable: Sendable {
    func render(in region: Region, theme: Theme) -> CellBuffer
    func sizeThatFits(_ available: Size) -> Size
    var isAnimated: Bool { get }
}
```

Every UI component (Panel, Box, DiffView, CommandCard, Spinner, etc.) conforms to `Renderable`. Components never emit ANSI directly; they produce `CellBuffer` regions that the renderer composites.

### 11.3 Virtual Buffer Diffing

The renderer maintains two buffers (front = what is on screen, back = what should be on screen). On each flush, it diffs cell-by-cell, emitting only the ANSI sequences needed to converge. This eliminates flicker and minimizes bandwidth.

### 11.4 Capability Detection

At startup, the renderer inspects `TERM`, `COLORTERM`, `NO_COLOR`, and `CLICOLOR` to determine:
- Truecolor (24-bit) vs 256-color vs 16-color vs monochrome
- Unicode box-drawing support vs ASCII fallback
- Terminal width/height (via `ioctl` TIOCGWINSZ)

`SIGWINCH` triggers a relayout. The renderer debounces resize events and re-renders the full frame within 16 ms.

### 11.5 Themes

Themes are TOML files loaded by `ThemeEngine`. Hot-swap via `/theme <name>` repaints the full frame within 100 ms. V1 ships three themes: `zyquo-dark` (default), `minimal`, `high-contrast`.

**Design decision rationale:** OpenCode uses opentui (SolidJS-based), which runs in a separate worker process and adds latency. Cline uses VSCode's webview, which is not portable. OpenHands has no terminal UI. Zyquo builds its own renderer as first-party strategic infrastructure because: (a) the terminal is the primary surface, (b) virtual-buffer diffing gives flicker-free rendering, (c) no dependency on an external UI framework means full control over performance and aesthetics.

---

## 12. Memory System

### 12.1 Layers

| Layer | Lifetime | Storage | Content |
|-------|----------|---------|---------|
| Session | Per session | `.zyquo/memory/sessions/<id>.jsonl` | Tool calls, observations, planner notes |
| Project | Persistent | `.zyquo/memory/project.md` | Architecture, conventions, test commands |
| Decision | Append-only | `.zyquo/memory/decisions.md` | ADR-like entries the agent wrote |
| Compressed | Persistent | SQLite | Summaries the compressor emits |

### 12.2 Project Memory Contract

`project.md` is sacred. The agent:
- Never overwrites it; only proposes patches via the diff workflow
- Preserves user comments and section order
- Treats user-added sections as ground truth (higher rank than agent-written)

### 12.3 Compression

`MemoryCompressor` runs after each session ends, on demand via `/memory compact`, or when token budget for context exceeds 70% of the model window. Strategy:

1. Cluster events by (file touched, tool, intent topic)
2. Summarize per cluster into 200 tokens or fewer
3. Preserve verbatim: decisions, errors, user instructions
4. Replace clustered raw events with summary pointer

### 12.4 Retrieval

V1 uses SQLite FTS5 (full-text search) for recall. The `MemoryRetriever` scores chunks by BM25 relevance and returns the top-k results for context injection.

V2 adds hybrid retrieval: FTS5 + local embeddings via `sqlite-vec`.

**Design decision rationale:** OpenHands has no persistent memory -- the `repo.md` workaround is manual and fragile. Cline has no memory system at all; each task starts fresh. OpenCode has `.opencode/*.md` files as instructions but no structured recall. Zyquo builds persistent, layered memory from day one because: (a) memory is what makes an agent genuinely useful across sessions, (b) the compression strategy prevents unbounded growth, (c) FTS5 gives acceptable recall without the complexity of embeddings in V1.

---

## 13. Persistence

### 13.1 Storage Technology

SQLite via GRDB.swift. Single database at `.zyquo/index/workspace.sqlite` for workspace data. Session data stored as JSONL files (append-friendly) indexed by SQLite for search and resume.

### 13.2 Stores

| Store | Purpose | Schema |
|-------|---------|--------|
| SessionStore | Session CRUD, resume, fork | sessions, session_events |
| MemoryStore | Memory CRUD, FTS5 search | memory_chunks, memory_fts |
| ConfigStore | Workspace + global config | config_kv |
| PatchStore | Patch CRUD, rollback lookup | patches, patch_files |
| SnapshotStore | Content-addressed pre-images | snapshots (sha -> gzip path) |

### 13.3 Crash Recovery

Session state is checkpointed to SQLite after every completed step. On crash, `zyquo sessions resume <id>` loads the last checkpoint and reconstructs `AgentState` from the persisted steps. The JSONL event log provides a replay mechanism for debugging.

---

## 14. Configuration

### 14.1 Precedence Chain

```
CLI flag  >  environment variable  >  workspace config (.zyquo/config.json)
          >  user config (~/.zyquo/config.toml)  >  compiled defaults
```

### 14.2 Resolution

The `Config` type resolves each key through the chain at startup. The result is immutable for the lifetime of the process. Hot-reloadable settings (theme, trust) are handled outside `Config` by their respective engines.

### 14.3 Env Loading

`.env` files are NOT loaded by default (to prevent shell-history leakage of secrets). Opt-in via `--allow-env-keys` or `config.set shell.allow_env_keys true`.

---

## 15. Error Handling

### 15.1 ZyquoError Taxonomy

```swift
public enum ZyquoError: Error, Sendable, CustomStringConvertible {
    case config(ConfigError)
    case provider(ProviderError)
    case tool(ToolError)
    case shell(ShellError)
    case workspace(WorkspaceError)
    case persistence(PersistenceError)
    case approval(ApprovalError)
    case risk(RiskError)
    case plugin(PluginError)
    case cancelled
    case userExit
}
```

### 15.2 Structured Error Shape

Every error subcase carries:
- `code`: Stable string (e.g., `provider.rate_limited`)
- `description`: Human-readable message
- `remediation`: One-sentence fix suggestion (e.g., "Check your API key with `zyquo doctor`")
- `underlying`: Optional wrapped error

### 15.3 UI Rendering

Errors are rendered as `Notification` toasts with description + remediation. The full structured form is logged to the JSONL log file. Non-recoverable errors set exit codes per the table in the spec (1-10 + 130 for SIGINT).

---

## 16. Key Design Decisions

### 16.1 Single-repo, single-binary

**Decision:** Keep agent core, tools, UI, and persistence in one repository. Ship as one universal binary.
**Rationale:** OpenHands fragments across 4 packages, making the agent loop invisible from the main repo. OpenCode has 22 Turborepo packages for a CLI. Fragmentation hurts debuggability and contribution. Zyquo uses two targets (executable + library) in one SwiftPM package.

### 16.2 Rule-based risk classification over LLM judgment

**Decision:** Use regex-based `DangerRules` for command risk, not LLM-based security analysis.
**Rationale:** OpenHands offers LLM-based security analysis, which adds latency and cost. Cline trusts the LLM's `requires_approval` boolean, which is a model judgment and not reliable for safety-critical decisions. Rules are deterministic, fast (< 1 ms), auditable, and testable with a 200+ test corpus.

### 16.3 Patch-gated writes over direct file mutation

**Decision:** All file writes go through snapshot -> diff -> approve -> apply -> record.
**Rationale:** Cline's diff-preview workflow is its strongest feature. OpenHands applies str_replace directly without preview. OpenCode has git-based snapshots but no approval UI. Zyquo reproduces Cline's workflow in the terminal, adding persistent reverse patches for rollback.

### 16.4 Actors for mutable state, structs for data

**Decision:** Use Swift actors for components that own mutable state (AgentRuntime, ShellExecutor, Workspace, SessionStore, TerminalRenderer). Use value types (structs/enums) for data flowing between them.
**Rationale:** OpenCode uses Effect's Service/Layer pattern (heavyweight). Cline uses mutable class instances with lock contention. Swift's actor model provides thread safety at compile time without runtime overhead.

### 16.5 First-party terminal renderer

**Decision:** Build the ANSI renderer in-house. No dependency on external TUI frameworks.
**Rationale:** OpenCode depends on opentui (closed-source SolidJS framework). No Swift TUI framework is mature enough for production. The renderer is strategic infrastructure; owning it means full control over performance, aesthetics, and capability degradation.

### 16.6 Keychain-only secrets

**Decision:** API keys live in macOS Keychain. Environment variables are not read for keys by default.
**Rationale:** OpenCode stores keys in config files. OpenHands uses environment variables. Both approaches risk leaking secrets via shell history, process listing, or accidental commits. Keychain provides hardware-backed encrypted storage with biometric unlock.

### 16.7 Persistent memory from V1

**Decision:** Build session, project, and decision memory in V1, not V2.
**Rationale:** Neither OpenHands, Cline, nor OpenCode has meaningful persistent memory. This is Zyquo's opportunity to differentiate. Memory is what transforms a tool into an assistant that improves over time.

### 16.8 Condenser-inspired context management

**Decision:** Adapt OpenHands' condenser concept with OpenCode's structured summary template.
**Rationale:** OpenHands' pluggable condenser architecture is well-designed but lives in a separate package. OpenCode's compaction template (goals, constraints, progress, decisions, next steps) preserves high-signal information. Zyquo combines both: a `Summarizer` that uses structured templates, invoked by `TokenBudget` when context exceeds threshold.

---

## 17. Performance Contracts

| Surface | Budget |
|---------|--------|
| Cold start (`zyquo --help`) | < 120 ms (arm64) |
| First paint (`zyquo interactive`) | < 200 ms |
| Frame render (no LLM activity) | < 8 ms p95 |
| Streaming token append | < 2 ms |
| First token (warm cache, Sonnet) | < 800 ms p50 |
| Workspace cold scan (50k files) | < 3 s |
| Workspace warm scan | < 200 ms |
| FSEvents -> index update | < 50 ms p95 |
| Approval prompt -> execution | < 30 ms |
| Session persist (flush) | < 100 ms p95 |
| Memory at interactive idle | < 60 MB RSS |
| Memory under heavy stream | < 250 MB RSS |
| Binary size (release, stripped) | < 25 MB |

Regressions of > 10% are flagged in CI.

---

## 18. Security Model

### 18.1 Assets

- **API keys** (Anthropic, OpenRouter) -- stored in Keychain, never in files or env
- **Source code** (user's workspace) -- protected by workspace boundary
- **Workspace memory** (`.zyquo/`) -- may contain sensitive design notes
- **Shell environment** -- may contain ambient secrets; masked by `EnvironmentMask`

### 18.2 Threat Vectors

| Threat | Mitigation |
|--------|------------|
| Malicious LLM output crafts destructive command | RiskClassifier + approval gate (deterministic, not LLM-judged) |
| Compromised provider returns malicious tool calls | Tool calls are schema-validated; shell commands are risk-classified |
| Malicious `.zyquo/trust.json` in a cloned repo | Repo-supplied trust files are ignored unless co-signed (V2) |
| Shell environment leaks secrets to LLM | `EnvironmentMask` strips `*_TOKEN`, `*_SECRET`, `*_KEY`, `SSH_*` from child processes |
| PII or secrets in logs | Redaction enforced at the log boundary via `Redaction` module |
| Plugin executes arbitrary code | V2; plugins must be signed and sandboxed |

### 18.3 Non-Mitigations

- Zyquo does NOT defend against a user who explicitly `/trust`s a CRITICAL action. Approval is consent.
- Zyquo does NOT defend against a compromised local system (root access). It runs at user privilege level.

### 18.4 Audit Trail

Every tool invocation, risk assessment, approval decision, trust grant, and trust revocation is recorded in the per-session audit log (`.zyquo/logs/<session-id>.log`). The audit log uses JSONL format with ISO 8601 timestamps and is append-only during a session.
