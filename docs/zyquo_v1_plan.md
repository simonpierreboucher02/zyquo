# Zyquo V1 Implementation Plan

## Objective

Build a production-quality native macOS AI terminal agent with: interactive UI, shell execution, repo understanding, diff review, memory, approvals, persistent sessions.

V1 ships when all 10 phases pass their acceptance criteria, performance budgets, and test matrices. No phase is skippable. Each phase builds on the previous.

---

## Dependency Graph

```
Phase 1 (Foundation)
    |
    +---> Phase 2 (Terminal Engine)
    |         |
    |         +---> Phase 7 (Diff System) ----+
    |         |                                |
    |         +---> Phase 6 (Risk Engine) ----+|
    |                   |                      ||
    +---> Phase 3 (Providers)                  ||
    |         |                                ||
    |         +---> Phase 8 (Agent Runtime) <--+|
    |                   |                       |
    +---> Phase 4 (Workspace)                   |
    |         |                                 |
    |         +---> Phase 8 (Agent Runtime)     |
    |                                           |
    +---> Phase 5 (Shell Execution)             |
              |                                 |
              +---> Phase 6 (Risk Engine)       |
              |                                 |
              +---> Phase 8 (Agent Runtime) <---+
                          |
                          +---> Phase 9 (Persistence & Memory)
                                    |
                                    +---> Phase 10 (Polish & Packaging)
```

Phases 2, 3, 4, and 5 can be worked in parallel after Phase 1. Phase 6 depends on Phase 5 (shell). Phase 7 depends on Phase 2 (renderer). Phase 8 depends on Phases 2-7. Phase 9 depends on Phase 8. Phase 10 depends on all.

---

## Phase 1: Foundation and CLI Runtime

### Goal

Establish the base Swift CLI architecture, dependency injection, configuration, logging, error taxonomy, and signal handling.

### Deliverables

| File | Purpose |
|------|---------|
| `Package.swift` | SwiftPM manifest: macOS 14+, strict concurrency, two targets |
| `Sources/Zyquo/main.swift` | Entry point, command dispatch |
| `Sources/Zyquo/Bootstrap.swift` | Cold-start fast path: signal handlers, crash reporter |
| `Sources/Zyquo/AppContainer.swift` | DI root: constructs all services |
| `Sources/Zyquo/Commands/CommandRegistry.swift` | ArgumentParser subcommand registration |
| `Sources/Zyquo/Util/Config.swift` | Config resolution (flag > env > file > default) |
| `Sources/Zyquo/Observability/Logger.swift` | Structured logging (swift-log + JSONL sink) |
| `Sources/Zyquo/Util/Environment.swift` | Env loading (.env opt-in) |
| `Sources/Zyquo/UI/TerminalRenderer.swift` | Stub: CellBuffer + naive flush |
| `Sources/Zyquo/UI/CellBuffer.swift` | Virtual buffer type |
| `Sources/Zyquo/Errors/ZyquoError.swift` | Error taxonomy with codes + remediation |

### Dependencies (SwiftPM)

- `swift-argument-parser` (Apple)
- `swift-log` (Apple)
- `swift-collections` (Apple)

### Acceptance Criteria

- `zyquo --help` works cleanly
- `zyquo version` prints version + git sha + build date
- `zyquo doctor` prints a diagnostics checklist (most items may fail at this phase)
- Process exit codes follow spec (0-10 + 130)
- All log lines are valid JSON when `--log-file` is set
- SIGINT and SIGTERM handled cleanly

### Performance Budget

- Cold start (`zyquo --help`): < 120 ms on M-series
- Binary size (release, stripped): < 25 MB
- Memory at idle: < 30 MB RSS

### Test Matrix

- Unit tests for `Config` precedence (flag > env > file > default)
- Unit tests for `CommandRegistry` dispatch
- Snapshot test for `--help` output (golden file)
- Signal handling test (SIGINT exits cleanly)

---

## Phase 2: Beautiful Interactive Terminal Engine

### Goal

Build the premium interactive terminal rendering system with virtual-buffer diffing, theming, responsive layout, and all core UI components.

### Deliverables

| Component | File | Purpose |
|-----------|------|---------|
| TerminalRenderer | `UI/TerminalRenderer.swift` | Virtual buffer, diff flush, ANSI emission |
| CellBuffer | `UI/CellBuffer.swift` | Cell grid with color, style, char |
| Region | `UI/Region.swift` | Rectangular region for component rendering |
| Panel | `UI/Panel.swift` | Titled, bordered region with Unicode borders |
| Box | `UI/Box.swift` | Unfilled bordered region |
| Theme | `UI/Theme.swift` | Color definitions, syntax colors, diff colors |
| ThemeEngine | `UI/ThemeEngine.swift` | TOML loader, hot-swap, capability degradation |
| StatusBadge | `UI/StatusBadge.swift` | Pill-shaped colored label |
| Spinner | `UI/Spinner.swift` | Braille, dots, arc variants |
| ProgressBar | `UI/ProgressBar.swift` | Determinate + indeterminate |
| TimelineView | `UI/TimelineView.swift` | Step list with elapsed time |
| CommandCard | `UI/CommandCard.swift` | Proposed command + risk badge + approval |
| DiffView | `UI/DiffView.swift` | Unified + side-by-side diff rendering |
| MarkdownRenderer | `UI/MarkdownRenderer.swift` | CommonMark subset -> ANSI |
| CodeBlock | `UI/CodeBlock.swift` | Syntax-highlighted code region |
| PromptInput | `UI/PromptInput.swift` | Line editor: history, completion, multiline |
| ModalPicker | `UI/ModalPicker.swift` | Fuzzy-pick over a list |
| Notification | `UI/Notification.swift` | Ephemeral toast |
| KeymapOverlay | `UI/KeymapOverlay.swift` | Press `?` to overlay keymap |
| LayoutEngine | `UI/LayoutEngine.swift` | Row/Column with grow/shrink/fixed |
| SyntaxHighlighter | `UI/SyntaxHighlighter.swift` | Language detection + highlight |

### Additional Dependencies

- `Yams` or `swift-toml` (TOML parsing for themes)
- `Splash` or tree-sitter bindings (syntax highlighting)

### Acceptance Criteria

- `zyquo interactive` launches a premium interface with bordered panels
- Terminal resize triggers full relayout within 16 ms
- Pressing `?` overlays the keymap
- `Ctrl-C` cancels current op without exiting (unless at idle)
- `q` / `Ctrl-D` at idle exits cleanly and restores terminal state
- Raw mode is restored on exit (even after crash, via `atexit` + signal traps)
- Snapshot tests for >= 20 frames pass byte-for-byte
- Three themes ship: `zyquo-dark`, `minimal`, `high-contrast`

### Performance Budget

- First paint after launch: < 200 ms
- Frame render (no LLM): < 8 ms p95
- Streaming append: < 2 ms per token
- Memory at interactive idle: < 60 MB RSS

### Test Matrix

- Snapshot tests per component (80x24 default region)
- Terminal capability fuzz (TERM=dumb, vt100, xterm-256color, xterm-truecolor)
- Unicode width tests (CJK, emoji, ZWJ, combining marks)
- SIGWINCH stress test (100 resizes/sec for 1 s)
- Theme hot-swap test (full repaint within 100 ms)

---

## Phase 3: Model Provider Layer

### Goal

Build the unified LLM abstraction with Anthropic and OpenRouter providers, streaming, retry, cancellation, pricing, and model routing.

### Deliverables

| File | Purpose |
|------|---------|
| `Models/LLMProvider.swift` | Provider protocol + LLMEvent enum |
| `Models/AnthropicProvider.swift` | Anthropic Messages API client (SSE streaming) |
| `Models/OpenRouterProvider.swift` | OpenRouter client (catalog-aware) |
| `Models/ModelRouter.swift` | Task-class routing policy |
| `Models/ModelCatalog.swift` | Model descriptors, context windows, pricing |
| `Models/Pricing.swift` | Per-model cost tracking |
| `Models/StreamingDecoder.swift` | SSE parser, partial JSON buffering |
| `Security/Keychain.swift` | Keychain read/write for API keys |

### Acceptance Criteria

- `zyquo ask "hello"` returns a streamed response, token-by-token
- `zyquo provider login anthropic` stores a key in Keychain
- `zyquo doctor` reports provider auth status without revealing secrets
- Rate limit (HTTP 429) triggers backoff with visible UI status
- Cancellation via `Ctrl-C` aborts the HTTP stream within 200 ms
- Token usage and cost are tracked per-request

### Performance Budget

- First-token latency on warm cache (Sonnet): < 800 ms p50
- Streaming throughput: provider-bound (Zyquo overhead < 1% CPU)
- HTTP layer memory: < 5 MB per active stream

### Test Matrix

- Replay tests against recorded SSE fixtures (happy path)
- Retry tests with injected 429/500/503 responses
- Timeout tests (request timeout + idle stream timeout)
- Token-counting tests against known prompts
- Cancellation propagation test (Task.cancel -> URLSession cancel)

---

## Phase 4: Workspace and Repository Intelligence

### Goal

Enable Zyquo to deeply understand any repository it opens: language, framework, package manager, test command, git status, file tree, and boundaries.

### Deliverables

| File | Purpose |
|------|---------|
| `Workspace/Workspace.swift` | Actor: root detection, scan, boundary check, FSEvents |
| `Workspace/WorkspaceIndex.swift` | Struct: scan results, queryable index |
| `Workspace/ProjectDetector.swift` | Language, framework, package manager detection |
| `Workspace/RepoAnalyzer.swift` | Git status, README extraction, architecture summary |
| `Workspace/Ignore.swift` | .gitignore + .zyquoignore parser and evaluator |
| `Workspace/BoundaryGuard.swift` | Path boundary enforcement with symlink resolution |
| `Workspace/FileSnapshot.swift` | File metadata (path, size, mtime, hash) |

### Languages MUST Detect

Swift, Python, TypeScript, JavaScript, Rust, Go, Ruby, Elixir, Java, Kotlin, C, C++, Objective-C, Shell.

### Acceptance Criteria

- `zyquo init` scaffolds `.zyquo/` with default config and ignore files
- Opening a workspace shows an intelligent repo analysis card within 3 s
- `WorkspaceIndex` is queryable via in-process API for tools
- `.zyquoignore` is respected (generated dirs excluded from index)
- FSEvents updates index within 50 ms of filesystem change
- Boundary violations are rejected with a clear error message
- Symlink escape attempts are caught

### Performance Budget

- Cold scan 50k files: < 3 s
- Warm scan: < 200 ms
- Index DB size: < 2% of repo size

### Test Matrix

- Detection tests across 20+ fixture repos (Swift, TS, Python, Rust, Go, etc.)
- Gitignore + zyquoignore precedence tests
- Large-repo (synthetic 200k files) scale test
- Symlink loop test (circular symlinks)
- FSEvents batch update test

---

## Phase 5: Shell Runtime and Execution Engine

### Goal

Build the secure shell execution layer with streaming output, cancellation, environment masking, and PTY support.

### Deliverables

| File | Purpose |
|------|---------|
| `Shell/ShellExecutor.swift` | Actor: Process wrapper, stdout/stderr pipes, streaming |
| `Shell/CommandResult.swift` | Struct: exit code, signal, output, timing |
| `Shell/ShellSession.swift` | Per-session shell state (env, cwd) |
| `Shell/CommandHistory.swift` | Per-session + persistent command log |
| `Shell/EnvironmentMask.swift` | Allow-list + mask for child env vars |
| `Shell/PTYHost.swift` | PTY-backed execution for interactive commands |

### Acceptance Criteria

- Commands execute with streaming output to UI
- Default timeout: 120 s (configurable per call)
- `Ctrl-C` interrupts within 200 ms (SIGTERM) and within 5 s hard (SIGKILL)
- Env masks hide `*_TOKEN`, `*_SECRET`, `*_KEY`, `SSH_*` from child processes
- PTY mode hands off (e.g., `vim` open/save/quit) and recovers cleanly
- zsh primary, bash fallback
- PATH is sanitized: user PATH intersected with allow-list + Homebrew prefix

### Performance Budget

- Launch overhead per command: < 8 ms (fork+exec)
- Stream copy overhead: < 1% CPU at 10 MB/s

### Test Matrix

- Streaming correctness vs `cat large.txt`
- Cancellation under load (long-running process)
- Env mask leak tests (assert masked vars not in child env)
- PTY interactive smoke test (vim open/save/quit)
- Timeout enforcement test
- Shell fallback test (zsh unavailable -> bash)

---

## Phase 6: Risk Engine and Approval Workflow

### Goal

Build the deterministic risk classification system, approval prompts, trust persistence, and audit logging.

### Depends on

Phase 5 (ShellExecutor for command context).

### Deliverables

| File | Purpose |
|------|---------|
| `Shell/RiskClassifier.swift` | Regex-based risk tier classification |
| `Shell/DangerRules.swift` | ~40 patterns organized by tier |
| `Security/Sandbox.swift` | Workspace boundary enforcement |
| `Security/AuditLog.swift` | JSONL append-only log per session |
| `Security/Redaction.swift` | PII/secret scrubbing at log boundary |
| `Workspace/BoundaryGuard.swift` | Path-based escalation rules (shared with Phase 4) |

### Acceptance Criteria

- Every risky command requires approval before execution
- Approval scope is selectable: `[y]es / [n]o / [a]lways / [e]dit / [?]explain`
- "Always" approval persists at chosen scope (once / session / workspace / global)
- `/trust` and `/untrust` work and are listed in `/status`
- CRITICAL commands never qualify for "always" approval
- Path-based escalation works (outside workspace -> +1 tier)
- System paths (`~/.ssh`, `/System`, etc.) are always CRITICAL
- Audit log persists across sessions and is human-readable JSONL
- Secrets are never present in log output

### Test Matrix

- 200+ rule unit tests covering SAFE, MODERATE, DANGEROUS, CRITICAL examples
- Boundary tests: `..` traversal, symlink escape, `$HOME`, `/`
- False-positive tests: `rm -rf ./build` inside workspace = correct tier
- Path escalation tests: same command inside vs outside workspace
- Trust grant persistence tests: write, read, revoke
- Redaction tests: secrets in various formats are stripped

---

## Phase 7: File Editing and Diff System

### Goal

Build the Cline-inspired patch-gated editing workflow with beautiful diff rendering, apply/reject, rollback, and conflict handling.

### Depends on

Phase 2 (TerminalRenderer, DiffView).

### Deliverables

| File | Purpose |
|------|---------|
| `Diff/DiffEngine.swift` | Myers diff algorithm, intra-line diff |
| `Diff/PatchEngine.swift` | Atomic patch application (temp + rename) |
| `Diff/ChangeSet.swift` | Multi-file grouped changes |
| `Diff/HunkParser.swift` | Unified diff parser |
| `Diff/ConflictResolver.swift` | Three-way merge, conflict UI |
| `Persistence/SnapshotStore.swift` | Content-addressed gzip pre-images |
| `Persistence/PatchStore.swift` | Patch + reverse patch persistence |

### Acceptance Criteria

- Diffs render beautifully with syntax highlighting inside changed lines
- Unified and side-by-side views toggle with `[s]`
- `/apply` and `/reject` work, including partial changeset approval
- Rollback restores byte-identical pre-image
- Conflicts surface a resolver UI with clear conflict markers
- Patch IDs are stable across resume: `zp_<yyyymmdd>_<short-uuid>`
- Multi-file changesets show summary: "3 files changed, +24 / -12"

### Test Matrix

- Round-trip property test: `apply(diff(a, b))` on `a` produces `b`
- Reverse patch test: `apply(reverse(diff(a, b)))` on `b` produces `a`
- Conflict reproduction tests (concurrent edits)
- Snapshot tests for diff rendering across all three themes
- Large diff test (1000+ hunks)
- Binary file detection (refuse to diff, show metadata only)
- Atomic write test (kill during write -> file is either old or new, never corrupt)

---

## Phase 8: Agent Runtime Core

### Goal

Build the autonomous but controllable agent loop: planning, execution, verification, context assembly, and stop conditions.

### Depends on

Phases 2-7 (all foundational components).

### Deliverables

| File | Purpose |
|------|---------|
| `Agent/AgentLoop.swift` | Main loop: intent -> plan -> step* -> summarize |
| `Agent/Planner.swift` | LLM-backed plan generation |
| `Agent/Executor.swift` | Tool dispatch with approval integration |
| `Agent/Verifier.swift` | LLM-backed step verification |
| `Agent/AgentStep.swift` | Step data type: goal, toolCall, observation, verdict |
| `Agent/AgentState.swift` | Session state container (actor-isolated) |
| `Agent/ContextAssembler.swift` | Context building: memory + workspace + history |
| `Agent/TokenBudget.swift` | Token tracking, compression triggers |
| `Agent/Summarizer.swift` | Session summary generation |
| `Agent/StopConditions.swift` | Hard stops (max steps, cost, cancel) + soft stops |
| `Agent/Orchestrator.swift` | Top-level coordinator for agent lifecycle |

### Acceptance Criteria

- Real iterative agent workflow: >= 5 steps without manual nudging
- All state transitions emit UI events (visible in terminal)
- Hard stop conditions enforced: max steps (40), max cost, user cancel, 3 consecutive failures
- Soft stop: plan completed, loop detection (same toolCall hash 3x in window of 5)
- Resume after `Ctrl-C` restores partial step state from checkpoint
- Context assembly completes in < 100 ms for projects < 10k files
- `zyquo run "fix failing tests"` drives a real multi-step workflow

### Performance Budget

- Planner overhead per step: < 50 ms outside LLM call
- Context assembly: < 100 ms p95 for projects < 10k files

### Test Matrix

- Scripted fixture intents with deterministic providers (mock LLM)
- Failure injection: tool error mid-loop triggers replan
- Budget exhaustion tests (max steps, max cost)
- Loop detection tests (repeated identical tool calls)
- Cancellation mid-step test
- Resume from checkpoint test

---

## Phase 9: Persistence and Memory System

### Goal

Build persistent project intelligence: session storage, project memory, decision memory, compressed summaries, and searchable recall.

### Depends on

Phase 8 (AgentState, session lifecycle).

### Deliverables

| File | Purpose |
|------|---------|
| `Persistence/SessionStore.swift` | Session CRUD, resume, fork, JSONL events |
| `Persistence/MemoryStore.swift` | Memory CRUD, FTS5 search |
| `Persistence/ConfigStore.swift` | Config key-value persistence |
| `Persistence/DB.swift` | GRDB wrapper, migrations |
| `Memory/SessionMemory.swift` | Per-session event log |
| `Memory/ProjectMemory.swift` | Persistent project.md management |
| `Memory/DecisionMemory.swift` | Append-only ADR log |
| `Memory/MemoryCompressor.swift` | Cluster + summarize strategy |
| `Memory/MemoryRetriever.swift` | BM25-backed FTS5 retrieval |
| `Memory/MemorySchema.swift` | Versioned schema for memory records |

### Storage Layout

```
.zyquo/
  config.json
  trust.json
  memory/
    project.md          # human-editable
    architecture.md     # auto-generated, hand-editable
    decisions.md        # append-only
    sessions/
      zq_<id>.jsonl     # per-session event log
  snapshots/
    <sha>.gz            # content-addressed pre-images
  patches/
    <patch-id>.patch
    <patch-id>.reverse.patch
  plans/
    <session-id>.json
  logs/
    <session-id>.log    # audit log (JSONL)
  index/
    workspace.sqlite    # GRDB
```

### Additional Dependencies

- `GRDB.swift` (SQLite + FTS5)

### Acceptance Criteria

- Sessions survive process restarts
- `zyquo sessions resume <id>` restores plan, steps, context
- `zyquo sessions` lists sessions with id, date, intent, status
- `zyquo memory` opens an inspector showing project + decision memory
- FTS5 search returns relevant chunks for a known query
- Memory compression runs after session ends without blocking exit
- `project.md` is never overwritten; only patch-proposed
- Schema migration works across versions (forward-compatible)

### Test Matrix

- Kill -9 mid-session, then resume: state matches last checkpoint
- Schema migration test (v1 -> v2 data preserved)
- FTS5 ranking sanity tests (relevant results rank higher)
- Project memory patch-proposal test (agent proposes, user approves)
- Compression quality test (compressed summary retains key decisions)
- Concurrent write test (two sessions writing to same DB)

---

## Phase 10: Polish, Packaging, and Developer Experience

### Goal

Make Zyquo feel production-grade: startup optimization, onboarding flow, Homebrew packaging, signing, documentation, comprehensive testing.

### Depends on

All previous phases.

### Deliverables

| Deliverable | Purpose |
|-------------|---------|
| Startup optimization | Lazy tool loading, AOT-friendly init, < 120 ms cold start |
| Render optimization | Partial flush profiling, < 8 ms p95 frame |
| Crash handling | Structured JSON report to `~/Library/Logs/Zyquo/` |
| First-run wizard | Provider login, theme pick, workspace scan |
| Homebrew formula | `homebrew-zyquo/Formula/zyquo.rb` |
| `scripts/build-release.sh` | Universal binary (arm64 + x86_64) build |
| `scripts/sign-and-notarize.sh` | Code signing + notarization |
| Onboarding flow | `zyquo` first-run: login -> theme -> scan -> ready |
| Theme audit | All 3 themes pass WCAG AA contrast for primary text |
| Keyboard shortcuts | vim + emacs presets, configurable via `~/.zyquo/keymap.toml` |
| Slash commands | All commands from spec implemented and tested |
| `--json` output | Machine-readable output for scripting |
| Integration tests | End-to-end on fixture repos (Swift, TS, Python) |
| Coverage | >= 75% line coverage on ZyquoCore, >= 90% on critical paths |

### Acceptance Criteria

- `brew install zyquo` works from local tap
- `zyquo` first-run wizard completes in < 60 s of user time
- All shipping themes pass WCAG AA contrast for primary text
- CI is green on every PR (build, test, lint, format, snapshot, perf)
- A first-time user can go from `brew install zyquo` to `zyquo run "explain this repo"` in under 5 minutes using a fresh Anthropic key
- `--json` output validates against a published JSON schema
- No P0 issues from 2 weeks of internal dogfooding

### Test Matrix

- End-to-end scenario tests on fixture repos (Swift, TS, Python)
- Accessibility audit on all themes (contrast ratios)
- `--json` output schema validation tests
- Homebrew install/upgrade test
- Man page rendering test
- Universal binary test (arm64 + x86_64 slices)
- Cold start performance regression test
- Memory leak test (10-minute idle session)

---

## Timeline Summary

| Phase | Description | Estimated effort | Parallelizable with |
|-------|-------------|-----------------|---------------------|
| 1 | Foundation & CLI | 1 week | -- |
| 2 | Terminal Engine | 2 weeks | 3, 4, 5 |
| 3 | Provider Layer | 1.5 weeks | 2, 4, 5 |
| 4 | Workspace Intelligence | 1.5 weeks | 2, 3, 5 |
| 5 | Shell Execution | 1 week | 2, 3, 4 |
| 6 | Risk Engine | 1 week | 7 (after 5) |
| 7 | Diff System | 1.5 weeks | 6 (after 2) |
| 8 | Agent Runtime | 2 weeks | -- |
| 9 | Persistence & Memory | 1.5 weeks | -- |
| 10 | Polish & Packaging | 2 weeks | -- |

**Critical path:** Phase 1 -> Phases 2-5 (parallel) -> Phase 8 -> Phase 9 -> Phase 10

**Estimated total:** 10-12 weeks with aggressive parallelization of Phases 2-5.
