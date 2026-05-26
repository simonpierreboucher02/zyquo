# Comparative Matrix: OpenHands vs Cline vs OpenCode vs Zyquo

This document is the central design-decision artifact for Zyquo V1. Every row represents an engineering surface where OpenHands, Cline, and OpenCode made a choice. For each, we assess what Zyquo should **Reuse** (adopt directly), **Redesign** (right idea, wrong execution), or **Avoid** (anti-pattern to reject). The table provides a summary; the prose sections below expand each row with rationale and implementation notes.

---

## Summary Matrix

| Feature | OpenHands | Cline | OpenCode | **Zyquo Decision** |
|---|---|---|---|---|
| **Agent loop** | Recursive action/observation cycle inside Docker sandbox; agent-server drives the loop with condenser-triggered compression. Max 500 iterations. | `recursivelyMakeClineRequests()` while-loop; streams LLM response, executes tools, feeds results back as next user message. Mistake counter and loop detection. | `processor.ts` stream-event loop; Effect-wrapped tool execution with Deferred promises for sync. Doom-loop detector at 3 failures. | **Redesign.** Adopt OpenHands' typed action/observation model and Cline's loop detection, but implement as a structured `AgentLoop` with explicit `Planner -> Executor -> Verifier` pipeline instead of a single recursive function. |
| **Shell execution** | Docker-isolated via tmux + pexpect inside containers. Process sandbox fallback for dev. Configurable timeout (120s). | VSCode terminal integration or background exec via `StandaloneTerminalManager`. Streaming output, model-specific output fixes. | Effect `ChildProcess` with tree-sitter command parsing for permission extraction. Detached process groups, SIGTERM then SIGKILL after 3s. | **Redesign.** Adopt OpenCode's tree-sitter command parsing for risk analysis. Use Foundation `Process` directly (no Docker, no VSCode dependency). PTY mode for interactive commands. Streaming stdout/stderr with configurable timeout and cancellation. |
| **Sandbox model** | Docker containers per conversation; strong process/filesystem isolation. Process sandbox as lightweight dev alternative. | No sandbox. Relies on VSCode workspace boundaries plus `.clineignore` for path restriction. | No sandbox. Workspace boundary checks via tree-sitter-parsed path resolution. Permission rules for external directory access. | **Redesign.** No Docker in V1 (native macOS execution). Implement `BoundaryGuard` with hard workspace-root enforcement, path-based escalation, and symlink-escape detection. V2 adds Apple Sandbox profiles for plugins via XPC. Avoid OpenHands' Docker requirement; avoid Cline's lack of boundary enforcement. |
| **Context handling** | Pluggable condenser system (noop, observation_masking, recent, llm, amortized, llm_attention). RecallAction injects workspace context at session start. | `ContextManager` with truncation (older messages masked) and compaction (structured summarize_task prompt). Context window buffers subtract 27-40k from model limit. | Full message history loaded from SQLite. Compaction triggered at configurable threshold (~20k minimum). Structured summary template with 7 sections. | **Reuse** OpenHands' pluggable condenser architecture (multiple strategies selectable per session). **Reuse** OpenCode's structured summary template (goals, constraints, progress, decisions, next steps, critical context, files). Implement as `TokenBudget` + `Summarizer` with strategy pattern. |
| **Token budgeting** | `max_budget_per_task` cost cap. Condenser triggers on context overflow. History truncation as fallback. | Effective window = model window minus buffer (27-40k). Compaction at ~80% of effective window. Uses previous API response token counts (lagging indicator). | Tracks input/output/reasoning/cache tokens per session. `PRUNE_MINIMUM = 20_000`, `PRUNE_PROTECT = 40_000` thresholds. Per-model pricing from models.dev catalog. | **Redesign.** Combine all three approaches: cost cap (OpenHands), proactive percentage-based trigger (Cline), and granular token tracking with cache awareness (OpenCode). Add local token estimation to avoid Cline's lagging-indicator problem. Budget is a first-class `TokenBudget` struct on `AgentState`. |
| **Summarization strategy** | LLM-based condenser with dedicated cheaper model. Amortized condenser for intelligent forgetting. Observation masking preserves structure while hiding content. | `summarize_task` prompt with 10-section structured output (request, concepts, files, problems, pending tasks, evolution, current work, next steps, files, context). Replaces truncated history. | Compaction agent with 7-section template (goal, constraints, progress, decisions, next steps, critical context, files). Replaces compressed messages, prunes tool outputs over 2000 chars. | **Redesign.** Merge Cline's and OpenCode's section schemas into a unified template. Adopt OpenHands' strategy of using a cheaper model for summarization. Preserve verbatim: decisions, errors, user instructions (never summarize these). Implement as `Summarizer` with configurable model routing via `ModelRouter`. |
| **Diff review** | No diff review workflow. File edits are str_replace operations applied directly. `undo_edit` is the only reversal mechanism. | Live-streaming diff editor in VSCode. User sees edits forming in real-time. Approve/reject at tool-call level. Side-by-side via VSCode native diff. | Snapshot-based diff via shadow git repo. `patch()` generates diffs, `restore()` reverts. No interactive review flow -- diffs are shown in TUI but not approval-gated per-hunk. | **Redesign.** Cline's live-streaming diff is the gold standard for UX, but it requires VSCode. Zyquo must replicate this in the terminal: render unified diffs with syntax highlighting and intra-line word-level highlighting inside a `DiffView` component. All writes go through the patch workflow. Adopt OpenCode's shadow-git snapshot concept for pre-image tracking. **Avoid** OpenHands' lack of diff review entirely. |
| **Patch application** | `str_replace` with exact string matching. No patch format. `undo_edit` reverses last edit per file. | `write_to_file` (full file) and `replace_in_file` (SEARCH/REPLACE blocks with exact line matching). `apply_patch` for GPT-5 V4A format. | `edit` tool (old_string/new_string replacement). `apply_patch` for unified diffs with GPT models. `write` for full file creation. | **Redesign.** Adopt Cline's SEARCH/REPLACE model (resilient to concurrent edits) as the primary edit path. All writes normalize to unified diffs via `DiffEngine` (Myers algorithm). Atomic writes via temp+rename (Cline's pattern). Reverse patches recorded for every applied patch. No raw file overwrites -- everything is a patch. |
| **Rollback** | `undo_edit` per file (single level). No multi-file rollback. No changeset concept. | Git-based checkpoints. Commits created at key points enable full workspace rollback. Checkpoint restore reverts all files. | Shadow git `restore(hash)` reverts files to a snapshot state. 7-day snapshot retention. No explicit user-facing rollback command. | **Redesign.** Combine Cline's checkpoint concept with a first-class rollback UX. Every applied patch produces a reverse patch (stored in `PatchStore`). `/reject <id>` after apply triggers reverse apply. Multi-file changesets roll back atomically. Snapshots are content-addressed and compressed (gzip). **Avoid** OpenHands' single-level undo and OpenCode's buried revert mechanism. |
| **Tool system** | LLM function-calling schemas. Tools loaded from `openhands-tools` package. Two presets: default (full) and planning (restricted). MCP for extensibility. | `ClineDefaultTool` enum (24 tools). `ToolExecutorCoordinator` maps names to handler factories. Handlers implement `IToolHandler` or `IFullyManagedTool`. MCP hub for extensions. | `Tool.define(id, Effect<Init>)` with lazy initialization. Effect Schema for parameters (auto-derives JSON Schema). Plugin tools from `.opencode/tool/*.ts` and npm packages. | **Redesign.** Adopt OpenCode's `Tool.define` pattern translated to Swift protocol (`Tool` protocol with `name`, `inputSchema`, `defaultRisk`, `execute`). Use `ToolRegistry` with explicit boot-time registration. JSON Schema for both validation and LLM tool description. Per-session enable/disable. MCP support in V1+ for extensibility. **Avoid** OpenHands' cross-package fragmentation and Cline's monolithic coordinator. |
| **Tool schema format** | JSON Schema in LLM function-calling format. Schemas live in the `openhands-tools` package, not co-located with implementations. | `ClineToolSpec` drives both prompt text and native tool schemas. Converted to OpenAI/Anthropic/Google formats via adapters. Model-family variants for tool descriptions. | Effect `Schema.Struct` with automatic JSON Schema derivation. Tool descriptions loaded from separate `.txt` files. | **Reuse** Cline's single-definition-multiple-output pattern. Define each tool's schema once in Swift (JSON Schema struct); derive both the LLM tool description and the input validator from the same definition. Store documentation as embedded strings (not separate files). Model-specific description variants via `ModelRouter` context. |
| **Memory architecture** | Session-scoped only. No persistent memory. `agent_memory.md` skill suggests creating `.openhands/microagents/repo.md` as manual project memory. | No memory system. Each task starts fresh. Cross-session learning does not exist. `.clinerules` provide static instructions but not learned memory. | Session-scoped via SQLite. `.opencode/*.md` files for project-level instructions. Skills as on-demand knowledge injection. No decision log or architecture memory. | **Redesign.** This is Zyquo's major differentiator. Three-layer memory: Session (per-session tool calls and observations), Project (persistent, human-editable `project.md`), and Decision (append-only ADR-like log). Memory stored in `.zyquo/memory/`. `MemoryCompressor` runs post-session and on demand. `MemoryRetriever` with SQLite FTS5 for recall. **Avoid** all three repos' lack of structured persistent memory. |
| **Long-term memory** | None. Manual workaround via `repo.md` microagent file that persists across conversations. | None. | None. `.opencode/*.md` files provide static instructions but are not agent-updated. | **Redesign.** Build from scratch. Compressed long-term memory via `MemoryCompressor` (cluster events by file/tool/topic, summarize per cluster, preserve decisions/errors/user instructions verbatim). V1: FTS5-based retrieval. V2: hybrid FTS5 + local embeddings. `project.md` is sacred -- agent proposes patches, never overwrites. |
| **Session persistence** | SQL database (PostgreSQL/SQLite via Alembic). Events stored per conversation (filesystem, S3, or GCS backends). Full trajectory recording as JSON. | Task directories with `api_conversation_history.json`, `ui_messages.json`, `context_history.json`, `task_metadata.json`. Atomic writes via temp+rename. | SQLite via Drizzle ORM. Sessions, messages, and parts stored as structured records. ULID-based session IDs. Sync events for change tracking. | **Reuse** OpenCode's SQLite approach (via GRDB.swift in Zyquo). JSONL append log for real-time persistence plus SQLite index for queries. Atomic writes via temp+rename (Cline's pattern). Content-addressed snapshots in `.zyquo/snapshots/`. Session IDs as `zq_<yyyymmdd>_<short-uuid>`. |
| **Session resume / branch** | Conversations can be paused (Docker pause) and resumed. Sub-conversations (forks) supported. Export as ZIP. | `resumeTaskFromHistory()` loads saved messages, strips incomplete partials, presents resume prompt. No fork capability. | Session resume via ULID lookup in SQLite. Fork creates new session with copied messages to a specified point. | **Reuse** OpenCode's fork model (copy messages to a branch point). Implement resume as checkpoint-based restoration of `AgentState` (plan, steps, context, trust grants). Add explicit `/session fork` and `/session resume` slash commands. Crash recovery resumes from last `task.checkpoint`. |
| **UX model** | React SPA (web-first). Chat interface with collapsible action/observation cards. VSCode-in-browser integration. Terminal view secondary. | VSCode sidebar webview. gRPC-like proto communication. Inline diff editor. Approval buttons in webview. CLI mode is bolted on. | SolidJS + opentui TUI in separate worker process. HTTP + SSE server for desktop/web clients. Non-interactive `run` mode for CI. | **Redesign.** Terminal-first, no web dependency. All output through `TerminalRenderer` with virtual buffer and diff-based ANSI flush. Components: Panel, Box, CommandCard, DiffView, TimelineView, PromptInput, ModalPicker. Responsive to SIGWINCH. **Avoid** OpenHands' web-first model and Cline's VSCode coupling. Learn from OpenCode's TUI ambition but execute with in-process rendering (no worker). |
| **TUI quality** | No TUI. Web interface only. | No TUI. VSCode webview only. CLI mode is minimal text output. | SolidJS + opentui with reactive rendering. Tab switching, streaming markdown, diff display, session browser. Theming support. Keyboard-driven with Ctrl+P palette. | **Redesign.** OpenCode is the only reference with a real TUI, but its quality is limited by the opentui framework and worker-process architecture. Zyquo must surpass it: premium ANSI rendering, Unicode box drawing, syntax-highlighted code blocks, animated spinners, smooth streaming, double-buffered rendering, responsive layout engine. Build the renderer as first-party strategic infrastructure. |
| **Theming** | No theming. Fixed web UI styles. | No theming. VSCode theme integration (inherits editor theme). | TOML-based themes in `.opencode/themes/`. Supports custom color definitions. | **Reuse** OpenCode's TOML theme format. Ship 3+ themes (`zyquo-dark`, `minimal`, `high-contrast`). Theme defines: bg, fg, border, accent, syntax colors, diff colors. Hot-swap via `/theme <name>` with full repaint under 100ms. Themes stored in `~/.zyquo/themes/`. Capability-aware degradation (truecolor, 256-color, 16-color, monochrome). |
| **Safety / risk model** | `confirmation_mode` with `AlwaysConfirm`, `ConfirmRisky`, `NeverConfirm` policies. LLM-based or rule-based security analyzer. Per-action `security_risk` field. | LLM-driven `requires_approval` boolean on commands. Per-category auto-approval (read/edit/execute). YOLO mode for full autonomy. `.clineignore` for file access. Loop detection (3/5 thresholds). | Wildcard-pattern permission rules (permission, pattern, action). Last-match-wins across layered rulesets. Tree-sitter command parsing for pattern extraction. No formal risk tiers. | **Redesign.** None of the three have proper tiered risk classification. Implement `RiskClassifier` with four tiers: SAFE, MODERATE, DANGEROUS, CRITICAL. Rules encoded in `DangerRules.swift` (regex-based, see spec section 19.2). Path-based escalation (outside workspace = +1 tier). System paths always CRITICAL. Combine with OpenCode's tree-sitter parsing for precise command analysis and Cline's per-category approval persistence. |
| **Approval ergonomics** | Binary confirm/reject. No "always approve" persistence. No scoped trust. Confirmation mode is a global toggle, not per-action. | `[y]es / [n]o` with auto-approval settings persisted in VSCode global state. YOLO mode as escape hatch. Per-path scoping (local vs external). Reject with text feedback. | `allow / deny / ask` with wildcard patterns. "Always" approval persisted as session rules. Agent-level permission rulesets. | **Redesign.** Best-in-class approval UX: `[y]es / [n]o / [a]lways / [e]dit / [?]explain`. Approval scopes: once, session, workspace (persisted in `.zyquo/trust.json`), global (persisted in `~/.zyquo/trust.json`). CRITICAL tier never qualifies for global trust. `/trust` and `/untrust` slash commands. Revocable, listed in `/status`. Adopt Cline's reject-with-feedback pattern. |
| **macOS suitability** | Poor. Requires Docker Desktop. Python runtime. Web-first UX. No native macOS integration (no Keychain, no Notification Center, no FSEvents). | Moderate. VSCode runs on macOS but the extension has no macOS-specific integration. Keys stored in VSCode settings (plaintext JSON). | Poor. Node.js/Bun runtime. No Keychain (keys in config files or env vars). No FSEvents (uses chokidar). No Notification Center. Cross-platform compromises (PowerShell support adds complexity). | **Avoid** all three. Zyquo is macOS-native by design. Security.framework for Keychain API key storage. FSEvents for workspace watching. UserNotifications for system alerts. Foundation Process for shell execution. os.log/os.signpost for tracing. No cross-platform compromises in V1. |
| **Performance (cold start)** | Slow. Docker container creation + Python process boot + health checks + repository cloning. Seconds to minutes for first interaction. | Moderate. VSCode extension activation is fast (~500ms) but relies on VSCode already running. Standalone CLI cold start not optimized. | Moderate. Bun cold start ~200-400ms. Full TUI boot with SQLite migration, plugin loading, worker spawning: 1-2s. | **Avoid** all three's startup overhead. Zyquo budget: `zyquo --help` < 120ms on M-series. `zyquo interactive` first paint < 200ms. Lazy tool initialization. AOT-friendly Swift binary. No container creation, no VM boot, no runtime interpreter startup. |
| **Performance (first token)** | Slow. Sandbox boot + agent construction + LLM call. Multiple seconds before first LLM token appears. | Moderate. After activation, first token depends on provider latency. No significant Cline-side overhead beyond prompt assembly. | Moderate. System prompt assembly + SQLite query + LLM call. Overhead is primarily provider-bound. | **Redesign.** Target < 800ms p50 first-token on warm cache (Claude Sonnet). Minimize pre-LLM overhead: cached workspace index, pre-assembled context, streaming connection reuse. Provider is the bottleneck, not Zyquo. |
| **Multi-agent support** | Sub-agents via `enable_sub_agents` flag. Agent definitions in SDK. Planning agent as a separate agent type. | Subagent tool (`use_subagents`) creates child tasks. Plan/Act mode is a soft agent split (same instance, different tool sets). | `task` tool creates child sessions with own permission scopes. 7 agent definitions: build, plan, explore, general, compaction, title, summary. | **Redesign.** V1: single agent with plan/execute/verify phases (not separate agents). V2: specialized agents (Architect, Coder, Reviewer, Shell, Verifier, Research) coordinated by Orchestrator. Adopt OpenCode's child-session model for agent isolation. Shared memory with actor-based locking. |
| **Local model support** | None in open-source version. LiteLLM supports local endpoints but no embedded inference. | None natively. Ollama provider for local API endpoints. No embedded inference. | None. All 25+ providers are cloud-based. No local inference path. | **Avoid** all three's cloud-only approach. V2: llama.cpp integration via Swift wrapper with Metal acceleration. GGUF model management (download, verify, prune). Hybrid routing: local for summarization/small tasks, cloud for complex reasoning. V2+: Apple Foundation Models when API stabilizes. |
| **Plugin / skill system** | Skills: keyword-triggered markdown prompts loaded from multiple sources (public, user, org, project). MCP for external tool servers. Hooks for pre/post tool use. | Workflows in `.clinerules/workflows/`. MCP hub for external tools. Hooks (PreToolUse, PostToolUse, TaskResume). No formal plugin system. | Skills: markdown instruction injection. Plugin tools from `.opencode/tool/*.ts` and npm packages via `@opencode-ai/plugin` SDK. No plugin signing. | **Redesign.** V1: Skills as YAML + markdown files (OpenCode/OpenHands pattern). Load from `.zyquo/skills/` and `~/.zyquo/skills/`. V2: Signed plugin bundles with Apple Sandbox profiles. Plugin manifest declares permissions. Unsigned plugins fail to load. MCP support for external tool servers. **Avoid** OpenCode's unsigned plugin loading. |
| **Observability** | Trajectory recording (full JSON). Event streaming via webhooks/SSE. Log redaction for secrets. Enterprise-grade (Sentry, tracing). | Task metadata (provider, model, timing). No structured logging. No audit trail separate from conversation. Basic telemetry (opt-in). | Per-session token/cost tracking. Sync events for session changes. No structured logging framework. No tracing. | **Redesign.** Local-first observability. Structured JSONL logs (swift-log + file sink). Per-session logs in `.zyquo/logs/`. Rotating global log at `~/Library/Logs/Zyquo/`. PII/secret redaction at log boundary. swift-metrics counters (steps, tool invocations, tokens, cost, approvals). Crash reporter writes structured JSON to `~/Library/Logs/Zyquo/crash/`. Adopt OpenHands' trajectory recording concept as session replay. |
| **Failure recovery** | Max iterations (500). Max budget. User cancellation. Sandbox pause/resume. No automatic retry on tool failure. | `consecutiveMistakeCount` triggers user intervention. Loop detection (3 soft, 5 hard). YOLO mode auto-fails at threshold. Checkpoint restore for workspace rollback. | Doom-loop detector at 3 failures. Abort signal propagation. Session resume from SQLite. No automatic replan on failure. | **Redesign.** Layered recovery: (1) Per-step retry with exponential backoff (max 3). (2) Replan with failure context after tool error. (3) Loop detection: same toolCall hash repeated 3x in window of 5 triggers soft stop. (4) Hard stops: max steps (40), max cost, user cancel, boundary violation, 3 consecutive failures on same step. (5) Crash recovery: resume from last `task.checkpoint`. Adopt Cline's checkpoint concept for workspace-level recovery. |

---

## Detailed Analysis by Feature

### 1. Agent Loop

**OpenHands**: The agent loop runs inside a Docker sandbox as a separate process. The app-server orchestrates sandbox lifecycle and streams events back via webhooks/SSE. The loop is action-selection -> security-classification -> approval -> execution -> observation -> condenser -> repeat. Max 500 iterations with budget cap. The CodeActAgent selects actions via LLM; the Planning Agent is restricted to PLAN.md editing.

**Cline**: A single recursive function (`recursivelyMakeClineRequests`) drives the loop. Each iteration: build system prompt, call LLM, stream response, parse tool-use blocks, route to approval, execute, collect results, feed back as next user message. `consecutiveMistakeCount` and loop detection prevent degenerate behavior. The function is ~3500 lines in the Task class -- a clear architectural debt.

**OpenCode**: The processor uses an Effect-based stream-event loop. Tool calls are tracked with `Deferred` promises. A doom-loop detector fires after 3 consecutive identical failures. The loop continues across multiple LLM calls until the model stops emitting tool calls, the user cancels, or overflow triggers compaction.

**Zyquo Decision -- Redesign**: The right pattern is OpenHands' typed action/observation model combined with Cline's loop detection, but decomposed into explicit phases: `Planner.plan()` -> `Executor.execute()` -> `Verifier.verify()` -> memory update -> stop check. Each phase is a separate type with a clear responsibility. The loop lives in `AgentLoop.swift`, orchestrating typed `AgentStep` structs. Every state transition emits a UI event. No 3500-line god class.

---

### 2. Shell Execution

**OpenHands**: Strong isolation via Docker. Shell runs inside a container with tmux for session management and pexpect for interaction. This provides genuine sandboxing but at enormous startup cost and operational complexity.

**Cline**: Delegates to VSCode's integrated terminal or a standalone terminal manager. Streaming output works well in the VSCode context but creates a hard dependency on the editor.

**OpenCode**: The most sophisticated approach: tree-sitter WASM parses shell commands before execution to extract individual commands, identify file-touching operations, resolve paths for boundary checks, and generate permission patterns. Execution uses detached process groups with proper signal handling.

**Zyquo Decision -- Redesign**: Adopt OpenCode's tree-sitter pre-parse for risk analysis (translate to Swift tree-sitter bindings or shell out to a WASM-compiled parser). Execute via Foundation `Process` with Pipe-based stdout/stderr streaming. Line-buffered output streamed to UI in real-time. PTY mode via `PTYHost` for interactive subcommands. Cancellation: `Task.cancel` -> SIGTERM -> SIGKILL after 5s. Environment: allow-list + mask sensitive vars. Default zsh, bash fallback.

---

### 3. Sandbox Model

**OpenHands**: Docker containers provide real process and filesystem isolation. Each conversation gets its own container with a full execution environment. This is the strongest model but the heaviest.

**Cline**: No sandbox at all. `.clineignore` provides path restriction but no enforcement -- the LLM can still propose operations on ignored files, and the protection relies on the tool handler checking the ignore list.

**OpenCode**: No formal sandbox. Tree-sitter-parsed commands trigger `external_directory` permission checks for out-of-workspace paths. The protection is permission-based, not isolation-based.

**Zyquo Decision -- Redesign**: No Docker in V1. Instead, implement `BoundaryGuard` as a hard enforcement layer. Every file path and shell command cwd is validated against `Workspace.root` before execution. Paths outside the workspace trigger tier escalation (SAFE -> MODERATE). System paths (`/System`, `/Library`, `/private`, `/usr` except `/usr/local`) are always CRITICAL. Symlink resolution prevents escape attacks. V2 adds Apple Sandbox profiles (via `sandbox-exec`) for plugin isolation.

---

### 4. Context Handling

**OpenHands**: The condenser system is the most architecturally clean. Multiple strategies (noop, observation_masking, recent, llm, amortized, llm_attention) can be selected per configuration. The amortized condenser is particularly interesting -- it forgets intelligently rather than uniformly. RecallAction provides workspace context at session start.

**Cline**: `ContextManager` tracks conversation modifications with truncation and compaction. Context window buffers are conservative (subtract 27-40k from model limit). Compaction triggers at ~80% of effective window. The summarize_task prompt is well-structured.

**OpenCode**: Simpler thresholds (PRUNE_MINIMUM = 20,000, PRUNE_PROTECT = 40,000). Tool outputs over 2000 chars are pruned from older messages. The compaction template is thorough but the trigger logic is basic.

**Zyquo Decision -- Reuse + Redesign**: Adopt OpenHands' pluggable condenser architecture as `Summarizer` with a strategy pattern. Implement at least three strategies for V1: noop (for debugging), recent (keep last N events), and llm (structured summary). Use the best of Cline's and OpenCode's summary templates: goals, constraints, progress (done/in-progress/blocked), key decisions, next steps, critical context, relevant files. Always preserve decisions, errors, and user instructions verbatim.

---

### 5. Token Budgeting

**OpenHands**: Cost cap via `max_budget_per_task`. The condenser triggers on context overflow. History truncation as a last-resort fallback.

**Cline**: Percentage-based trigger (~80% of effective window). The effective window subtracts a model-specific buffer from the raw context window. The lagging indicator problem (using previous API response token counts) means actual usage can exceed budget before compaction fires.

**OpenCode**: Granular tracking of input/output/reasoning/cache-read/cache-write tokens. Per-model pricing from an external catalog. Threshold-based compaction.

**Zyquo Decision -- Redesign**: `TokenBudget` is a first-class struct on `AgentState`, tracking: input tokens, output tokens, cache hits, cache misses, estimated cost, and budget remaining. Cost cap (`--max-cost`), step cap (`--max-steps`, default 40), and percentage-based compaction trigger (70% of model window). Local token estimation (not relying on lagging API responses) to trigger compaction proactively. Budget is visible in the UI status bar at all times.

---

### 6. Summarization Strategy

**OpenHands**: Pluggable. The LLM condenser uses a separate, cheaper model for summarization. The amortized condenser uses intelligent forgetting. Observation masking preserves structure while hiding content.

**Cline**: 10-section structured summary: primary request, key concepts, files examined, problems solved, pending tasks, task evolution, current work, next steps, required files, context. Replaces the truncated history as a user message.

**OpenCode**: 7-section template: goal, constraints, progress (done/in-progress/blocked), key decisions, next steps, critical context, relevant files. Also prunes large tool outputs from older messages.

**Zyquo Decision -- Redesign**: Merge the best sections from both Cline and OpenCode into a unified template. Use the cheaper model for summarization (OpenHands' pattern) via `ModelRouter` routing to Haiku for summarization tasks. Preserve verbatim: decisions, errors, user-issued instructions (these are never summarized). The compressor clusters events by (file touched, tool, intent topic), summarizes per cluster into 200-token chunks, and replaces raw events with summary pointers.

---

### 7. Diff Review

**OpenHands**: No diff review. File edits are applied directly via str_replace. The only reversal is `undo_edit` which undoes the last edit per file. This is a significant trust gap -- the user never sees what will change before it changes.

**Cline**: The gold standard. File edits stream into VSCode's native diff editor in real-time. The user watches the edit form token by token, then approves or rejects. The side-by-side diff is VSCode's built-in, which is excellent. However, this is deeply coupled to VSCode's diff editor API.

**OpenCode**: Snapshots via shadow git enable diff generation, but there is no interactive approval flow. Diffs are displayed in the TUI but the user does not approve individual hunks or file changes.

**Zyquo Decision -- Redesign**: Replicate Cline's live-streaming diff experience in the terminal. The `DiffView` component renders unified diffs with: syntax highlighting inside changed lines, intra-line word-level diff (Myers on word tokens), theme-driven colors (added/removed/context), hunk headers, file summary (`3 files changed, +24 / -12, 2 risk MODERATE`). Side-by-side mode toggleable with `[s]`. All writes route through the patch workflow: snapshot pre-image -> generate diff -> render -> risk classify -> approve -> apply atomically -> record in PatchStore.

---

### 8. Patch Application

**OpenHands**: `str_replace` with exact string matching. Simple but fragile -- if the file changed between read and write, the match can fail silently or match the wrong location.

**Cline**: Two paths: `write_to_file` for full file creation/overwrite, and `replace_in_file` with SEARCH/REPLACE blocks requiring exact line matches. The SEARCH/REPLACE model is more resilient than line-number-based editing because it matches content, not position. `apply_patch` for GPT-5 V4A format patches.

**OpenCode**: `edit` tool with old_string/new_string replacement (adopted from Cline). `apply_patch` for unified diffs with GPT models. `write` for full file creation.

**Zyquo Decision -- Redesign**: Adopt Cline's SEARCH/REPLACE as the LLM-facing edit interface (content-based matching is resilient to concurrent changes). Internally, all edits normalize to unified diffs via `DiffEngine` (Myers algorithm). Application is atomic: write to temp file, verify patch applies cleanly, rename into place. Every applied patch records a reverse patch in `PatchStore`. Conflict detection: if on-disk pre-image hash differs from recorded, attempt 3-way merge; if conflict, surface `ConflictResolver`.

---

### 9. Rollback

**OpenHands**: Single-level `undo_edit` per file. No multi-file rollback. No changeset concept. Practically useless for complex multi-file operations.

**Cline**: Git-based checkpoints. Commits created after the first API request and after each `attempt_completion`. Full workspace rollback by reverting to a checkpoint commit. This is robust but operates at the workspace level, not the patch level.

**OpenCode**: Shadow git `restore(hash)` reverts files to a snapshot state. 7-day retention. No user-facing rollback command -- the mechanism exists but is not exposed as a first-class UX operation.

**Zyquo Decision -- Redesign**: Two-level rollback. (1) **Patch-level**: Every applied patch has a reverse patch. `/reject <patch-id>` applies the reverse patch. Multi-file changesets roll back atomically. (2) **Session-level**: Periodic snapshots (content-addressed, gzip-compressed) in `.zyquo/snapshots/`. Snapshots are created before each step's execution and enable workspace-level recovery. Adopt Cline's checkpoint timing but store snapshots independently of the user's git repo. The rollback UX is explicit and discoverable via `/diff`, `/reject`, and `/apply`.

---

### 10. Tool System

**OpenHands**: Tools are LLM function-calling schemas loaded from a separate package. Two presets (default and planning). MCP extends the tool surface. The fragmentation across packages makes the tool system hard to modify.

**Cline**: 24 tools in a `ClineDefaultTool` enum. `ToolExecutorCoordinator` maps names to handler factories. Handlers are well-typed with `IToolHandler` and `IFullyManagedTool` interfaces. MCP hub for extensions.

**OpenCode**: `Tool.define(id, Effect<Init>)` with lazy initialization and Effect Schema for parameters (auto-derives JSON Schema). Plugin tools extend the registry at runtime. Clean separation between tool definition and execution.

**Zyquo Decision -- Redesign**: Swift `Tool` protocol with: `name` (stable identifier), `inputSchema` (JSON Schema), `defaultRisk` (RiskLevel), `isMutating` (Bool), `execute(input:context:)` (async throws -> ToolResult). Registration is explicit at boot via `AppContainer`. Tools are looked up by stable name. Per-session enable/disable via a session-scoped view. `ToolResult` carries `summary` (1-3 lines for UI + LLM), `payload` (structured output), `artifacts` (files, diffs), and `tokenHint` (estimated tokens if echoed). LLM sees `summary` always; `payload` only if within budget.

---

### 11. Tool Schema Format

**OpenHands**: JSON Schema in standard LLM function-calling format. Schemas are separate from implementations (in the `openhands-tools` package), creating a maintenance burden.

**Cline**: `ClineToolSpec` is the single source of truth. It drives both the prompt text (for XML-based tool calling) and native tool schemas (for function-calling models). Model-family variants customize descriptions. Conversion functions emit OpenAI, Anthropic, and Google formats.

**OpenCode**: Effect `Schema.Struct` auto-derives JSON Schema. Tool descriptions live in separate `.txt` files imported at build time.

**Zyquo Decision -- Reuse Cline's pattern**: Define each tool's schema once in Swift. A `ToolSchema` struct contains the JSON Schema definition, human-readable documentation, and model-specific description variants. The same schema drives: LLM tool descriptions (for tool-use API calls), input validation (before execution), and documentation (`/tools` output and help text). No separate files, no cross-package splits.

---

### 12. Memory Architecture

**OpenHands**: Session-scoped only. The `agent_memory.md` skill instructs the agent to create `.openhands/microagents/repo.md` -- a manual workaround that demonstrates the need but does not satisfy it.

**Cline**: No memory. Each task starts fresh. `.clinerules` provide static instructions but cannot be agent-updated.

**OpenCode**: Session-scoped via SQLite. `.opencode/*.md` files serve as project-level instructions but are not structured as memory -- they are static input, not dynamic knowledge.

**Zyquo Decision -- Redesign**: This is Zyquo's strongest differentiator. Three memory layers: **Session** (per-session tool calls, observations, planner notes -- stored as JSONL), **Project** (`project.md` -- human-editable, agent-proposable via patch workflow, high-signal), **Decision** (append-only ADR-like log in `decisions.md`). `MemoryCompressor` runs post-session to create compressed long-term summaries. `MemoryRetriever` provides FTS5-backed recall. The agent can read and propose writes to memory via `memory.read` and `memory.write` tools, but user-edited sections in `project.md` are sacred and rank higher than agent-written content.

---

### 13. Long-term Memory

All three repos lack genuine long-term memory. OpenHands' `repo.md` microagent is the closest -- it persists across conversations but is manually maintained. Cline and OpenCode have nothing.

**Zyquo Decision -- Redesign from scratch**: `MemoryCompressor` clusters events by topic and produces compressed summaries. Decisions and errors are never compressed -- they persist verbatim. V1 uses SQLite FTS5 for lexical retrieval. V2 adds hybrid retrieval (FTS5 + local embeddings via `sqlite-vec`). Memory survives across sessions, restarts, and updates. This is the foundation for Zyquo's "persistent cognitive runtime" aspiration.

---

### 14. Session Persistence

**OpenHands**: SQL database with event storage backends (filesystem, S3, GCS). Trajectory recording for full replay. Enterprise-grade but complex.

**Cline**: File-based persistence with separate JSON files per concern (API history, UI messages, context history, metadata). Atomic writes via temp+rename.

**OpenCode**: SQLite via Drizzle ORM. Structured records with typed parts. ULID-based IDs. Sync events for change tracking.

**Zyquo Decision -- Reuse OpenCode's SQLite approach**: GRDB.swift for SQLite persistence. Schema: sessions, messages, memory chunks, patches, snapshots. JSONL append log for crash recovery (write events as they happen; rebuild SQLite index if corrupted). Atomic writes for all persistence operations. Versioned schema with migration support.

---

### 15. Session Resume / Branch

**OpenHands**: Docker containers can be paused/resumed. Sub-conversations (forks) are supported. Full conversation export as ZIP.

**Cline**: Resume loads saved messages, strips incomplete partials, runs TaskResume hook. No fork capability.

**OpenCode**: Resume via session lookup in SQLite. Fork copies messages to a specified point into a new session.

**Zyquo Decision -- Reuse + Redesign**: Adopt OpenCode's fork model: `/session fork` creates a new session with copied state up to the current point. Resume restores the full `AgentState`: plan, completed steps, trust grants, token budget, and workspace snapshot. Crash recovery: the last `task.checkpoint` persists `AgentState` synchronously; resume after kill -9 restores from this checkpoint. Export via `/export <fmt>` in markdown, JSON, or JSONL.

---

### 16. UX Model

**OpenHands**: Web-first. React SPA with WebSocket/SSE communication. The terminal is not a first-class surface.

**Cline**: VSCode-first. The extension webview is the primary surface. CLI mode exists but is minimal.

**OpenCode**: TUI-first with web/desktop as secondary surfaces. SolidJS + opentui in a separate worker process. HTTP + SSE server for desktop clients.

**Zyquo Decision -- Redesign**: Terminal-first with no external dependencies. All rendering through `TerminalRenderer`. No web server in V1 (V2 adds a read-only web mirror). No VSCode dependency. The terminal is the primary and only surface in V1. The UX must feel like Warp + Raycast + lazygit: premium, keyboard-driven, fast, beautiful. Every agent action is visible. No hidden autonomous behavior.

---

### 17. TUI Quality

**OpenHands**: N/A. No TUI.

**Cline**: N/A. No TUI.

**OpenCode**: The only reference with a real TUI. SolidJS + opentui provides reactive rendering. Features: tab switching, streaming markdown, diff display, session history, model selection, approval prompts, Ctrl+P palette. However, the worker-process architecture adds latency, and the TUI quality is functional rather than premium.

**Zyquo Decision -- Redesign**: OpenCode proves the TUI approach is viable but Zyquo must dramatically exceed its quality. Build the renderer as first-party infrastructure: virtual buffer with diff-based ANSI flush (minimal escape sequences per frame), Unicode box drawing (`U+256x` rounded corners), syntax highlighting (tree-sitter or Splash), animated spinners (braille/dots/arc), smooth token-by-token streaming, double-buffered rendering, terminal capability detection (truecolor/256/16/mono degradation). No framework dependency -- own the rendering stack entirely.

---

### 18. Theming

**OpenHands**: No theming.

**Cline**: Inherits VSCode theme. No independent theme system.

**OpenCode**: TOML-based themes in `.opencode/themes/`. Custom color definitions for UI elements.

**Zyquo Decision -- Reuse OpenCode's TOML format**: Themes are TOML files under `~/.zyquo/themes/<name>.toml`. Schema defines: colors (bg, fg, border, accent, status), syntax (keyword, string, number, comment, type, function), and diff (added, removed, context) with foreground and background variants. Ship 3 themes: `zyquo-dark` (cool neutral, signal-blue accents), `minimal` (monochrome, single accent), `high-contrast` (7:1 contrast minimum, WCAG AA). Hot-swap via `/theme <name>` with full repaint under 100ms.

---

### 19. Safety / Risk Model

**OpenHands**: Three-level global policy (AlwaysConfirm, ConfirmRisky, NeverConfirm). LLM-based or rule-based security analyzer. Per-action security_risk field is well-designed but the approval UX is binary.

**Cline**: LLM-driven `requires_approval` boolean creates a two-layer model (LLM judgment + user settings). Per-category auto-approval (read/edit/execute). YOLO mode as full autonomy escape. Loop detection catches degenerate behavior. But no formal risk classification beyond the boolean.

**OpenCode**: Flat allow/deny/ask with wildcard patterns. Tree-sitter command parsing extracts precise patterns. Agent-level rulesets provide role-based control. But no tiered risk -- `rm -rf /` gets the same permission type as `npm install`.

**Zyquo Decision -- Redesign**: None of the three implement proper tiered risk classification. Zyquo's `RiskClassifier` assigns SAFE/MODERATE/DANGEROUS/CRITICAL based on regex rules in `DangerRules.swift`. Path-based escalation: commands touching paths outside `Workspace.root` escalate by one tier. System paths (`~/Library`, `~/.ssh`, `~/.aws`, `/System`, `/Library`, `/private`, `/usr` except `/usr/local`) are always CRITICAL. Adopt OpenCode's tree-sitter parsing for precise command decomposition. Adopt Cline's loop detection (signature comparison with soft/hard thresholds). The RiskClassifier is the single biggest user-trust lever -- it must be exhaustively tested (200+ rule unit tests).

---

### 20. Approval Ergonomics

**OpenHands**: Binary confirm/reject. No persistence, no scoping. If you confirm `git push` once, you must confirm it again next time. This creates approval fatigue.

**Cline**: Better. Per-category auto-approval persisted in VSCode settings. YOLO mode for full autonomy. Path scoping (local vs external). Reject with text feedback is nice UX. But still flat categories, not per-command.

**OpenCode**: Wildcard-pattern "always" approval persisted as session rules. This is more granular than Cline's categories but less discoverable. No interactive approval prompt with multiple options.

**Zyquo Decision -- Redesign**: Best-in-class approval: `[y]es / [n]o / [a]lways / [e]dit / [?]explain`. `[e]dit` lets the user modify the proposed command before execution. `[?]explain` asks the agent to justify the action. Trust scopes: `once` (this invocation), `session` (until session ends), `workspace` (persisted in `.zyquo/trust.json`), `global` (persisted in `~/.zyquo/trust.json`). CRITICAL actions never qualify for global trust. Grants are revocable via `/untrust` and visible in `/status`.

---

### 21. macOS Suitability

**OpenHands**: Poor. Docker Desktop is required. Python runtime overhead. Web-first UX. No integration with macOS security or UX primitives.

**Cline**: Moderate. Runs on macOS via VSCode. But no macOS-specific features -- keys in plaintext JSON, no Notification Center, no Keychain.

**OpenCode**: Poor for macOS. Bun/Node runtime. Keys in config files or environment variables. File watching via chokidar (not FSEvents). Cross-platform compromises add unnecessary complexity on macOS.

**Zyquo Decision -- Avoid all three**: Zyquo exploits macOS as its substrate. `Security.framework` for Keychain API key storage (service: `dev.zyquo.cli`, access: `kSecAttrAccessibleWhenUnlocked`). `CoreServices` FSEvents for file watching. `UserNotifications.framework` for system alerts. Foundation `Process` for shell execution. `os.log` and `os.signpost` for structured logging and tracing. `NSWorkspace` for `open` integration. No cross-platform compromises in V1.

---

### 22. Performance (Cold Start)

**OpenHands**: Docker container creation dominates. Even with pre-built images, cold start is seconds to minutes.

**Cline**: Relies on VSCode already being open. Extension activation is ~500ms. Not a standalone metric.

**OpenCode**: Bun cold start ~200-400ms. Full boot (SQLite migration, plugin loading, worker spawning) takes 1-2s.

**Zyquo Decision -- Avoid all overhead**: Swift AOT binary. No interpreter startup. No container creation. No migration at boot (migrations run lazily on first access). Lazy tool initialization. Target: `zyquo --help` < 120ms on M-series, < 250ms on Intel. `zyquo interactive` first paint < 200ms. Binary size < 25MB stripped. Memory at idle < 30MB RSS.

---

### 23. Performance (First Token)

**OpenHands**: Multiple seconds due to sandbox boot, agent construction, and LLM call latency.

**Cline**: After activation, overhead is primarily provider latency. System prompt assembly is fast. Reasonable first-token times.

**OpenCode**: System prompt assembly + SQLite history query + LLM call. Overhead is provider-bound.

**Zyquo Decision -- Redesign**: Minimize pre-LLM overhead so the provider is the only bottleneck. Cached workspace index (warm: < 200ms). Pre-assembled system prompt template (fill-in-the-blanks, not rebuild from scratch). Streaming connection reuse where provider supports it. Target: < 800ms p50 first-token latency on warm cache with Claude Sonnet.

---

### 24. Multi-Agent Support

**OpenHands**: Sub-agents via flag. Planning agent as separate type. Agent definitions in SDK package.

**Cline**: Subagent tool creates child tasks within the same extension instance. Plan/Act mode is a soft split (same agent, different tool sets).

**OpenCode**: `task` tool creates child sessions with own permission scopes. 7 agent definitions cover different roles (build, plan, explore, general, compaction, title, summary).

**Zyquo Decision -- Redesign**: V1 is single-agent with explicit phases (plan, execute, verify). The agent loop has Planner, Executor, and Verifier as separate components but they are not independent agents. V2 introduces specialized agents (ArchitectAgent, CoderAgent, ReviewerAgent, ShellAgent, VerifierAgent, ResearchAgent) coordinated by an Orchestrator. Adopt OpenCode's child-session model for agent isolation. Shared memory with actor-based locking prevents conflicts. Agent communication via typed messages.

---

### 25. Local Model Support

All three repos lack embedded local model inference. OpenHands and OpenCode are cloud-only. Cline supports Ollama for local API endpoints but not embedded inference.

**Zyquo Decision -- Avoid cloud-only lock-in**: V2 adds llama.cpp integration via Swift wrapper with Metal acceleration. GGUF model support (Q4, Q5, Q8 quantization). Model management (download, verify, prune). `ModelRouter` hybrid mode: local for summarization and small tasks, cloud for complex reasoning. V2+ explores Apple Foundation Models when the API surface stabilizes. Local embeddings for vector memory.

---

### 26. Plugin / Skill System

**OpenHands**: Skills are keyword-triggered markdown prompts from multiple sources. MCP for external tools. Hooks for pre/post tool use. The skill system is elegant for knowledge injection.

**Cline**: Workflows in `.clinerules/workflows/`. MCP hub for external tools. Hooks with cancellation. No formal plugin SDK.

**OpenCode**: Skills as markdown instruction injection. Plugin tools from filesystem and npm packages via `@opencode-ai/plugin` SDK. No signing -- any file in `.opencode/tool/` becomes a tool.

**Zyquo Decision -- Redesign**: V1: Skills as YAML manifests + markdown prompt files. Load from `.zyquo/skills/` (project) and `~/.zyquo/skills/` (user). Each skill declares `tools_allowed`, `inputs`, `verify`, `budget`, and `risk_ceiling`. V2: Signed plugin bundles with manifest (`zyquo-plugin.toml`). Plugins cannot exceed declared permissions. Unsigned plugins fail to load. MCP support for external tool servers in V1+. Adopt OpenHands' keyword-triggered knowledge injection for skills.

---

### 27. Observability

**OpenHands**: Most comprehensive. Full trajectory recording as JSON. Event streaming via webhooks/SSE. Log redaction. Enterprise telemetry (Sentry integration). But enterprise-only for most features.

**Cline**: Basic. Task metadata captures provider, model, and timing. No structured logging framework. No separate audit trail.

**OpenCode**: Per-session token/cost tracking. Sync events for change propagation. No structured logging. No tracing.

**Zyquo Decision -- Redesign**: Local-first observability. (1) Structured JSONL logs via swift-log with rotating file sink at `~/Library/Logs/Zyquo/zyquo.log`. (2) Per-session logs in `.zyquo/logs/<session-id>.log`. (3) Crash reports as structured JSON at `~/Library/Logs/Zyquo/crash/`. (4) PII/secret redaction enforced at log boundary -- no secret in logs, ever. (5) swift-metrics counters: agent steps, tool invocations by tool, tool errors by kind, LLM tokens in/out, cost by provider, approval decisions. (6) `zyquo trace --session <id>` for tool-call span replay. No telemetry leaves the machine without opt-in.

---

### 28. Failure Recovery

**OpenHands**: Hard limits (max iterations 500, max budget). Sandbox pause/resume. No automatic retry on individual tool failures. Recovery requires user intervention or a new conversation.

**Cline**: `consecutiveMistakeCount` triggers user intervention at a configurable threshold. Loop detection (3 soft warning, 5 hard stop). YOLO mode auto-fails at threshold. Checkpoint restore enables workspace-level rollback.

**OpenCode**: Doom-loop detector at 3 consecutive identical failures. Abort signal propagation. Session resume from SQLite state. No automatic replan.

**Zyquo Decision -- Redesign**: Layered failure recovery:

1. **Per-step retry**: Exponential backoff with jitter, max 3 retries per step. Retries are logged and visible in the timeline.
2. **Replan on failure**: After a tool error, the Planner is re-invoked with failure context. The agent can choose a different approach.
3. **Loop detection**: Same toolCall hash repeated 3 times in a window of 5 triggers a soft stop (agent may ask to continue).
4. **Hard stops**: Max steps (40, configurable), max cost (`--max-cost`), user cancellation, workspace boundary violation, 3 consecutive tool failures on the same step.
5. **Crash recovery**: `task.checkpoint` persists `AgentState` synchronously. Resume after kill -9 restores from the last checkpoint. JSONL append log enables state reconstruction if SQLite is corrupted.
6. **Workspace recovery**: Snapshot-based rollback to any pre-step state via `/reject`.

---

## Cross-Cutting Themes

### What Zyquo takes from each project

**From OpenHands**:
- Typed action/observation event model
- Pluggable condenser architecture
- Skills as keyword-triggered knowledge injection
- Trajectory recording for replay
- Planning agent as a distinct mode
- The lesson that Docker isolation is the right idea but too heavy for a local tool

**From Cline**:
- Approval-gated diff workflow (the defining UX pattern)
- SEARCH/REPLACE editing model (content-based, not line-number-based)
- Per-tool auto-approval with path scoping
- Loop detection with soft/hard thresholds
- Context compaction via structured summary
- Checkpoint-based workspace rollback
- Plan/Act mode toggle
- Reject-with-feedback pattern

**From OpenCode**:
- Tree-sitter command parsing for risk analysis
- SQLite persistence via ORM (GRDB.swift for Zyquo)
- TOML-based theming
- Git-based snapshot system
- Wildcard-pattern permission rules (composable, layered)
- Tool output truncation with file-based overflow
- Fork (branch) sessions
- Structured compaction template
- Provider-agnostic architecture with protocol adapters

### What Zyquo rejects from all three

- **Web-first UX** (OpenHands). The terminal is the canvas.
- **VSCode coupling** (Cline). No IDE dependency.
- **Docker requirement** (OpenHands). Native macOS execution.
- **No persistent memory** (all three). Memory is Zyquo's differentiator.
- **No formal risk classification** (Cline, OpenCode). SAFE/MODERATE/DANGEROUS/CRITICAL tiers with regex rules and path-based escalation.
- **God-class agent loop** (Cline's 3500-line Task). Decompose into Planner, Executor, Verifier.
- **Cross-platform compromises** (OpenCode). macOS-only in V1.
- **Unsigned plugins** (OpenCode). Signed bundles with declared permissions in V2.
- **Plaintext key storage** (Cline, OpenCode). Keychain only.
- **Runtime interpreter overhead** (all three). Swift AOT binary, sub-120ms cold start.
