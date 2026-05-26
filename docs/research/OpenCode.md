# OpenCode

## Overview

OpenCode is an open-source, terminal-native AI coding agent built as a TypeScript monorepo using Bun as its runtime. Originally created by the SST team (now anomalyco), it has evolved from a Go-based CLI into a full-featured TypeScript application spanning a TUI, desktop app (Electron), web console, and an SDK for third-party integrations. The project uses the Effect library pervasively for structured concurrency, dependency injection, and error handling. It targets all major platforms (macOS, Linux, Windows) and supports 25+ LLM providers through the Vercel AI SDK combined with a custom `@opencode-ai/llm` abstraction layer.

The codebase is a Turborepo-managed monorepo with the core CLI in `packages/opencode`, a shared type/service library in `packages/core`, a custom LLM routing layer in `packages/llm`, a SolidJS-based UI component library in `packages/ui`, and an Electron desktop wrapper in `packages/desktop`. The CLI binary is distributed via npm (`opencode-ai`), Homebrew, Scoop, AUR, and a curl-pipe-bash installer.

Key metrics: ~530 source files (excluding node_modules/dist), v1.15.10 as of this analysis, MIT licensed.

## Architecture diagram (ASCII)

```
                         +---------------------+
                         |   CLI Entry Point    |
                         |  src/index.ts        |
                         |  (yargs commands)    |
                         +----------+----------+
                                    |
                    +---------------+----------------+
                    |               |                |
              +-----+------+  +----+-----+   +------+------+
              | TUI Thread |  | Run Cmd  |   | Other Cmds  |
              | (SolidJS   |  | (non-    |   | (serve,     |
              |  + opentui)|  |  interact|   |  models, ..) |
              +-----+------+  +----+-----+   +------+------+
                    |               |                |
                    +-------+-------+----------------+
                            |
                    +-------+--------+
                    |  Server Layer  |
                    | (HTTP + SSE)   |
                    +-------+--------+
                            |
          +-----------------+-----------------+
          |                 |                 |
   +------+------+  +------+------+  +------+------+
   | Session Svc |  | Provider Svc|  | Tool Reg    |
   | (CRUD,      |  | (model      |  | (builtin +  |
   |  messages,  |  |  resolution,|  |  plugin     |
   |  fork)      |  |  auth)      |  |  tools)     |
   +------+------+  +------+------+  +------+------+
          |                 |                 |
   +------+------+  +------+------+  +------+------+
   | Processor   |  | LLM Service|  | Tools        |
   | (stream     |  | (AI SDK +  |  | (shell, edit,|
   |  handling,  |  |  native    |  |  read, glob, |
   |  tool exec) |  |  LLM pkg)  |  |  grep, task) |
   +------+------+  +------+------+  +------+------+
          |                 |                 |
   +------+------+  +------+------+  +------+------+
   | Storage     |  | Permission  |  | Snapshot     |
   | (SQLite via |  | (wildcard   |  | (git-based   |
   |  Drizzle)   |  |  rulesets)  |  |  tracking)   |
   +--------------+  +-------------+  +--------------+
```

## Module map

The monorepo is organized as follows:

- **`packages/opencode`** -- The main CLI application. Houses the agent loop, tool implementations, session management, TUI, server, storage, and all business logic. This is the heart of the system (~290 source files).
  - `src/session/` -- Session lifecycle, message storage, LLM streaming, compaction, system prompts, retry logic.
  - `src/tool/` -- Tool definitions (shell, edit, read, write, glob, grep, task, webfetch, websearch, skill, apply_patch, question, todo, lsp, plan).
  - `src/cli/cmd/tui/` -- TUI layer built with SolidJS + opentui (SST's terminal UI framework).
  - `src/config/` -- Configuration loading, JSONC parsing, provider/agent/permission/MCP config.
  - `src/permission/` -- Permission evaluation engine (allow/deny/ask with wildcard patterns).
  - `src/provider/` -- Provider resolution, auth, model status tracking.
  - `src/snapshot/` -- Git-based file snapshot tracking for diff/revert.
  - `src/storage/` -- SQLite persistence via Drizzle ORM, JSON migration from legacy format.
  - `src/plugin/` -- Plugin loading from npm packages and filesystem.
  - `src/server/` -- HTTP API server for desktop/web clients and SSE event streaming.
  - `src/agent/` -- Agent definitions (build, plan, explore, general, compaction, title, summary).
  - `src/shell/` -- Shell detection, kill-tree logic, cross-platform shell selection.
  - `src/lsp/` -- Language Server Protocol client integration for diagnostics.
  - `src/skill/` -- Skill system (markdown-based instruction injection).

- **`packages/core`** -- Shared types and services. Effect-based schemas for Agent, Session, Provider, Permission, Plugin, Model. Also contains the GitHub Copilot provider adapter, filesystem abstraction, and utility modules.

- **`packages/llm`** -- Custom LLM routing and protocol layer. Supports Anthropic Messages, OpenAI Chat, OpenAI Responses, Bedrock Converse, and Gemini protocols. Handles streaming, tool call parsing, caching policies, auth, and transport (HTTP + WebSocket).

- **`packages/ui`** -- SolidJS component library for web/desktop UIs (diff viewer, file icons, markdown rendering, etc.). Not used by the TUI directly.

- **`packages/plugin`** -- Plugin SDK (`@opencode-ai/plugin`) for third-party tool extensions.

- **`packages/desktop`** -- Electron wrapper for the desktop app.

## Agent loop (sequence)

OpenCode's agent loop is driven by `session/processor.ts` coordinating with the LLM service:

```
User Message
    |
    v
Session.create / Session.get
    |
    v
SystemPrompt.build (model-specific prompt + environment info + skills)
    |
    v
ContextAssembly (history messages + compaction check)
    |
    v
LLM.stream (AI SDK streamText with tools)
    |
    +---> StreamEvent loop:
    |       |
    |       +-- text-delta --> append TextPart to message
    |       +-- tool-call-start --> create ToolPart (status: pending)
    |       +-- tool-call-input-delta --> accumulate input
    |       +-- tool-call-end --> decode args, permission check, execute
    |       |       |
    |       |       +-- Permission.evaluate(tool, pattern, agent.ruleset)
    |       |       |       --> allow: execute immediately
    |       |       |       --> ask: prompt user via Question service
    |       |       |       --> deny: reject with error
    |       |       |
    |       |       +-- Tool.execute (effect-wrapped, cancellable)
    |       |       +-- Update ToolPart with output + metadata
    |       |
    |       +-- step-finish --> check stop conditions
    |       +-- finish --> determine result (continue/compact/stop)
    |
    v
Compaction check (if context > threshold)
    |
    v
Summary generation (via "title" agent on first user message)
    |
    v
Session.patch (update tokens, cost, title)
```

The processor creates a `ProcessorContext` that tracks all active tool calls with `Deferred` promises for synchronization. A "doom loop" detector fires after 3 consecutive identical tool failures. Stop conditions include: user cancellation (abort signal), max step count per agent, context overflow triggering compaction, and explicit plan-exit tool calls.

The loop continues across multiple LLM calls in a single session turn until either the model stops emitting tool calls, the user cancels, or an overflow/doom-loop is detected.

## Tool system

Tools are registered through a centralized `ToolRegistry` service (`tool/registry.ts`). Each tool is defined using `Tool.define(id, Effect<Init>)`, which creates a lazy-initialized tool with:

- **id**: Stable string identifier (e.g., "bash", "edit", "read", "glob", "grep", "write", "task", "skill")
- **description**: Model-facing documentation (loaded from `.txt` files via import)
- **parameters**: Effect `Schema` (with automatic JSON Schema derivation for the LLM)
- **execute**: `(args, ctx) => Effect<ExecuteResult>` -- the implementation

The registry initializes all tools at instance startup and provides them filtered per-model/per-agent. Key built-in tools:

| Tool | Purpose |
|------|---------|
| `bash` (ShellTool) | Shell command execution with tree-sitter parsing for permission analysis |
| `edit` (EditTool) | String replacement in files (old_string/new_string, like Cline) |
| `write` (WriteTool) | Full file writes |
| `read` (ReadTool) | File reading with offset/limit, binary detection, PDF/image support |
| `glob` (GlobTool) | File pattern matching |
| `grep` (GrepTool) | Ripgrep-backed code search |
| `task` (TaskTool) | Subagent delegation (creates child sessions) |
| `skill` (SkillTool) | Loads specialized instruction sets into context |
| `webfetch` | URL fetching with HTML-to-markdown conversion |
| `websearch` | Web search (provider-dependent) |
| `todowrite` | Task list management for planning |
| `question` | Ask user a question mid-session |
| `apply_patch` | Unified diff application (for GPT models) |
| `lsp` | Language server diagnostics (experimental) |
| `plan` | Enter/exit plan mode (experimental) |

Plugin tools are loaded from `.opencode/tool/*.ts` files and npm packages, using the `@opencode-ai/plugin` SDK which accepts Zod schemas.

Tool output is automatically truncated by the `Truncate` service when it exceeds configurable limits (lines + bytes). Large outputs are written to temporary files and referenced by path.

## Prompt surfaces

OpenCode uses model-specific system prompts stored as `.txt` files under `src/session/prompt/`:

- `anthropic.txt` -- Claude-specific prompt (primary, most polished)
- `gpt.txt` -- GPT-3.5/4o series prompt
- `beast.txt` -- GPT-4/o1/o3 series prompt
- `gemini.txt` -- Gemini-specific prompt
- `codex.txt` -- OpenAI Codex/Responses API prompt
- `default.txt` -- Fallback for unknown models
- `kimi.txt`, `trinity.txt` -- Specialized model prompts

The `SystemPrompt` service (`session/system.ts`) selects the appropriate prompt based on `model.api.id` pattern matching. It builds the system message from:

1. Model-specific base prompt (from the .txt files above)
2. Environment info (`<env>` block with working dir, platform, date, git status)
3. Agent-specific custom prompt (if set on the agent config)
4. Skills description (if skill tool is enabled for the agent)
5. Plugin-injected system prompt transforms
6. Instructions from `.opencode/*.md` files and user config

Each agent can override the prompt via the `prompt` field. Internal agents like `compaction`, `title`, and `summary` have dedicated system prompts for their specific tasks.

## Memory & context

OpenCode's context management operates at two levels:

**Session-level context**: Messages are stored in SQLite (via Drizzle ORM) as structured records with parts (text, tool, reasoning, compaction). The full message history is loaded for each LLM call, limited by the model's context window.

**Compaction system** (`session/compaction.ts`): When context exceeds a threshold (configurable, default ~20k tokens minimum), the system performs "compaction":
1. Identifies which messages to compress (protects recent turns + important tool outputs)
2. Calls the "compaction" agent with a structured summary template
3. The summary includes: Goal, Constraints, Progress (Done/In Progress/Blocked), Key Decisions, Next Steps, Critical Context, Relevant Files
4. Inserts a `compaction` part that replaces the compressed messages
5. Prunes tool outputs exceeding 2000 chars from older messages

There is no dedicated long-term memory system. Project-level knowledge is handled through:
- `.opencode/*.md` files loaded as instructions (similar to CLAUDE.md)
- Skills loaded on demand via the skill tool
- References to external docs fetched via webfetch

**Token tracking**: Each session tracks input/output/reasoning/cache-read/cache-write tokens and computes cost using per-model pricing from the models.dev catalog.

## Shell execution

Shell execution is implemented in `tool/shell.ts` with the `ShellTool`:

1. **Shell detection**: `shell/shell.ts` detects available shells on the system (bash, zsh, dash, sh, PowerShell). Shells like `fish` and `nu` are explicitly denied due to syntax incompatibility. Default is the user's configured shell or system default.

2. **Command parsing**: Before execution, commands are parsed using **tree-sitter** (WASM bindings for bash and PowerShell grammars) to:
   - Extract individual commands from pipelines/compounds
   - Identify file-touching commands (rm, cp, mv, mkdir, etc.)
   - Resolve paths to check workspace boundaries
   - Generate permission patterns for the approval system

3. **Permission check**: The parsed command patterns are evaluated against the agent's permission ruleset. Commands touching paths outside the workspace trigger an `external_directory` permission check.

4. **Execution**: Uses Effect's `ChildProcess` abstraction. The command runs in a forked process group (`detached: true` on Unix) with:
   - Configurable timeout (default 2 minutes)
   - Streaming stdout/stderr capture with byte-level buffering
   - Abort signal propagation from user cancellation
   - SIGTERM then SIGKILL after 3 seconds for cleanup
   - Environment filtering (inherits process.env + plugin-injected vars)

5. **Output handling**: Output is streamed to the UI in real-time via metadata updates. Large outputs are written to temporary files. The final result includes the tail of the output (capped at configurable max lines/bytes).

6. **Kill tree**: `shell/shell.ts` implements `killTree()` using process group signals on Unix and `taskkill /f /t` on Windows.

## Safety model

OpenCode's safety model centers on a **wildcard-pattern permission system**:

**Permission rules** are triples of `(permission, pattern, action)` where:
- `permission`: Tool name or category (e.g., "bash", "edit", "read", "external_directory")
- `pattern`: Wildcard-matchable string (file paths, command patterns)
- `action`: "allow" | "deny" | "ask"

**Evaluation**: `evaluate(permission, pattern, ...rulesets)` finds the last matching rule across all rulesets. This means later rules override earlier ones, allowing users to override agent defaults.

**Agent-level permissions**: Each agent has a permission ruleset. The "build" agent allows most operations. The "plan" agent denies edits. The "explore" subagent denies writes but allows reads.

**Default safety rules**:
- All tools default to "allow" for the build agent
- `doom_loop` detection triggers "ask" after 3 consecutive failures
- `external_directory` access requires approval
- Reading `.env` files requires approval
- The `question` tool is denied by default (enabled per-client)

**Permission persistence**: Approvals can be "always" (persisted as rules for the session) or one-time. Sessions can have their own permission overrides.

**No formal risk classification**: Unlike Zyquo's planned SAFE/MODERATE/DANGEROUS/CRITICAL tiers, OpenCode uses a flat allow/deny/ask model. There is no static risk scoring of commands -- the tree-sitter parsing extracts command patterns, and the permission ruleset decides the action.

## Persistence

**Primary storage**: SQLite database at `~/.local/share/opencode/opencode.db` (XDG-compliant), managed via Drizzle ORM. Tables include:
- Sessions (id, project, directory, title, agent, model, tokens, cost, timestamps)
- Messages (session_id, role, content parts as JSON)
- Parts (session_id, message_id, type-discriminated JSON)
- Projects (id, worktree path, name)
- Workspaces (experimental multi-worktree support)
- Sync events (event sourcing for session/message changes)

**Migration system**: The codebase includes both SQL migrations (under `migration/`) and a `json-migration.ts` that converts from a legacy JSON-file-based storage format to SQLite.

**Snapshot system** (`snapshot/index.ts`): Uses a **shadow git repository** for tracking file changes:
- `git init` in a temp directory, adds workspace files
- `track()` creates a commit, returns the hash
- `patch(hash)` generates a diff from the snapshot
- `restore(hash)` reverts files to snapshot state
- `diffFull(from, to)` computes file-level diffs with addition/deletion counts
- Cleanup prunes snapshots older than 7 days

**Session resume**: Sessions are identified by descending ULIDs. Resuming loads the session row and its message history from SQLite. Forking creates a new session with copied messages up to a specified point.

**Project-local storage**: `.opencode/` directory holds config, agent prompts, custom tools, skills, and themes. The directory also stores plans as markdown files.

## UX surface

OpenCode's TUI is built with **SolidJS + opentui** (SST's own terminal UI framework):

- The TUI runs in a **separate worker process** connected via RPC to the main server process
- `opentui` provides reactive terminal rendering with SolidJS primitives
- Keybindings are configurable via `tui.json` (using `@opentui/keymap`)
- The UI supports theming via `.opencode/themes/` TOML-like config

**Key UX features**:
- Tab-switching between agents (build/plan)
- Streaming text display with markdown rendering
- Diff visualization for file changes
- Tool call display with collapsible output
- Session history browser
- Model/provider selection
- Permission approval prompts
- Ctrl+P for action palette
- Audio feedback (optional)
- Clipboard integration
- Editor integration (Zed-specific support, generic $EDITOR)

**Non-interactive mode**: `opencode run "prompt"` for headless/CI usage with JSON event streaming (`--format json`).

**Desktop app**: Electron wrapper that renders the web UI (`packages/app`) which communicates with the opencode server via HTTP API + SSE.

## Strengths (what Zyquo should reuse)

1. **Provider-agnostic architecture**: The layered provider system (core Plugin.Provider -> llm protocols -> AI SDK adapters) supports 25+ providers seamlessly. The `@opencode-ai/llm` package is particularly well-designed with protocol-specific adapters for Anthropic Messages, OpenAI Chat/Responses, Bedrock, and Gemini.

2. **Tree-sitter command parsing**: Using tree-sitter WASM to parse shell commands before execution is elegant -- it enables precise permission pattern extraction without fragile regex. This is directly applicable to Zyquo's RiskClassifier.

3. **Effect-based dependency injection**: The entire codebase uses Effect's Service/Layer pattern for clean dependency management, testability, and structured concurrency. Zyquo can learn from this for its `AppContainer` DI design (translate to Swift's actor/protocol patterns).

4. **Compaction strategy**: The structured summary template for context compression is well-thought-out. The template preserves: goals, constraints, progress, decisions, next steps, critical context, and relevant files.

5. **Permission system design**: The wildcard-pattern ruleset with allow/deny/ask is simple yet expressive. The last-match-wins semantics with layer merging (defaults -> user config -> agent-specific -> session) is composable.

6. **Git-based snapshots**: Using a shadow git repository for file change tracking is clever -- it leverages git's diffing/patching capabilities without polluting the user's repo.

7. **Tool output truncation**: Automatic truncation with file-based overflow is a practical solution that Zyquo should adopt.

8. **Skill system**: Markdown-based instruction injection loaded on-demand keeps the base context lean while allowing domain-specific expertise.

9. **Subagent delegation**: The `task` tool creates child sessions with their own permission scopes -- a clean model for multi-agent work.

10. **Model-specific prompts**: Different system prompts per model family acknowledges that models respond differently to instruction styles.

## Weaknesses (what Zyquo should avoid)

1. **JavaScript/TypeScript runtime overhead**: Bun cold start is ~200-400ms; the full TUI boot including SQLite migration, plugin loading, and worker spawning can take 1-2 seconds. Zyquo's Swift binary should aim for sub-120ms.

2. **Complexity of Effect library**: While powerful, Effect adds significant cognitive overhead. The codebase is dense with Effect patterns (`Effect.gen`, `Layer.effect`, `Schema.Struct`, `Context.Service`) that make casual reading difficult. Zyquo should use Swift's native async/await and protocols instead of an effect system.

3. **No formal risk classification**: The flat allow/deny/ask model lacks nuance. A command like `rm -rf /` gets the same permission type as `npm install`. Zyquo's tiered risk system (SAFE/MODERATE/DANGEROUS/CRITICAL) is superior for user trust.

4. **Worker process TUI architecture**: Running the TUI in a separate Bun worker connected via RPC adds latency and complexity. Zyquo should render directly in-process.

5. **No macOS-native integration**: No Keychain for API keys (stored in config files or env vars), no Notification Center, no FSEvents for file watching (uses chokidar/parcel watcher). Zyquo's native approach is better for macOS.

6. **Monorepo sprawl**: 22 packages for what is fundamentally a CLI tool. The indirection between `packages/core`, `packages/llm`, `packages/opencode`, and `packages/plugin` makes navigation hard. Zyquo should keep a flatter structure.

7. **No explicit rollback UX**: While snapshots exist, there is no `/reject` command or interactive rollback flow like Cline's approve/reject workflow. The revert mechanism is buried in session metadata.

8. **Heavy dependencies**: 130+ direct dependencies including tree-sitter WASM, multiple AI SDK providers, Drizzle ORM, SolidJS, etc. The install size is substantial. Zyquo should minimize dependencies.

9. **Limited offline capability**: No local model support in the current architecture (all providers are cloud-based).

10. **Cross-platform compromises**: Windows PowerShell support adds significant complexity to the shell tool. Zyquo's macOS-only V1 avoids this entirely.

## Open questions

1. **How does opentui compare to building a custom ANSI renderer?** The framework is closed-source enough that Zyquo cannot easily adopt it. Zyquo should build its own terminal renderer as first-party infrastructure.

2. **What is the actual token budget strategy?** The compaction threshold logic (`PRUNE_MINIMUM = 20_000`, `PRUNE_PROTECT = 40_000`) is relatively simple. Does this work well with 200K-context models? How does it interact with prompt caching?

3. **How are MCP servers managed?** The `mcp/` module supports Model Context Protocol servers but the integration depth is unclear -- how does it compose with the permission system?

4. **What is the plugin signing/security model?** Plugins are loaded from the filesystem and npm packages without any signature verification. This is a potential attack vector.

5. **How does the experimental workspace system work?** The `control-plane/workspace.ts` and `worktree/` modules suggest multi-worktree support, but it is behind a feature flag.

6. **What is the "ACP" (Agent Client Protocol)?** The `acp/` and `acp-next/` directories suggest a protocol for external agent clients, but documentation is sparse.

## Quotes / references (15 words each max, with file:line)

- "You are OpenCode, the best coding agent on the planet." -- `packages/opencode/src/session/prompt/anthropic.txt:1`
- "Tree-sitter WASM for bash and PowerShell grammar parsing" -- `packages/opencode/src/tool/shell.ts:308-332`
- "Permission rules: triples of permission, pattern, action" -- `packages/core/src/permission.ts:9-12`
- "Compaction summary template preserves goals, decisions, and file paths" -- `packages/opencode/src/session/compaction.ts:42-77`
- "Tools filtered per-model: apply_patch for GPT, edit for others" -- `packages/opencode/src/tool/registry.ts:324-326`
- "Shadow git repo for snapshot tracking with 7-day prune" -- `packages/opencode/src/snapshot/index.ts:33`
- "Agent definitions: build, plan, explore, general, compaction, title, summary" -- `packages/opencode/src/agent/agent.ts:129-281`
- "SQLite via Drizzle ORM for session/message persistence" -- `packages/opencode/src/storage/db.ts`
- "DOOM_LOOP_THRESHOLD = 3 consecutive identical tool failures" -- `packages/opencode/src/session/processor.ts:32`
- "SolidJS + opentui framework for terminal UI rendering" -- `CONTRIBUTING.md:74`
- "Kill tree: SIGTERM then SIGKILL after 200ms timeout" -- `packages/opencode/src/shell/shell.ts:9,28`
- "Tool output auto-truncated, large outputs saved to temp files" -- `packages/opencode/src/tool/truncate.ts`
- "25+ LLM providers via AI SDK and custom protocol adapters" -- `packages/opencode/package.json:77-95`
- "Edit tool sourced from Cline's diff-apply approach" -- `packages/opencode/src/tool/edit.ts:1-4`
- "Config from .opencode/opencode.jsonc with JSON Schema validation" -- `.opencode/opencode.jsonc:1`
