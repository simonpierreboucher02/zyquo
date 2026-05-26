# Cline

## Overview

Cline is a VSCode extension that functions as an autonomous coding agent. Originally built as a VS Code sidebar panel communicating with a webview, it has evolved into a substantial codebase (374+ source files at depth 4) supporting 35+ LLM providers, native and XML-based tool calling, plan/act mode switching, checkpoint-based undo, subagent orchestration, and a modular prompt system with model-family-specific variants. The project is TypeScript throughout, using gRPC-like proto communication between the extension host and the webview, and ships as both a VS Code extension and a standalone CLI.

Cline's defining contribution to the agent landscape is its approval-gated workflow: every file write, command execution, and tool use can be individually approved, auto-approved, or rejected by the user, with the LLM's proposed changes streamed live into a diff editor before execution. It also introduced a "YOLO mode" for fully autonomous operation and a plan/act mode toggle that lets users discuss strategy before the agent begins modifying files.

The codebase lives primarily in `apps/vscode/src/`, organized into `core/` (agent loop, tools, prompts, context, storage), `integrations/` (editor, terminal, checkpoints, browser), `services/` (MCP, search, telemetry, tree-sitter), and `shared/` (types, proto conversions, utilities).

## Architecture diagram (ASCII)

```
                        +------------------+
                        |   VSCode Host    |
                        |   (Extension)    |
                        +--------+---------+
                                 |
                    gRPC-style proto msgs
                                 |
                        +--------v---------+
                        |    Controller    |
                        |  (state, cmds)   |
                        +--------+---------+
                                 |
              +------------------+------------------+
              |                  |                  |
     +--------v------+  +-------v-------+  +-------v-------+
     |  StateManager |  |     Task      |  | McpHub / MCP  |
     | (globalState) |  | (agent loop)  |  |   servers     |
     +---------------+  +-------+-------+  +---------------+
                                |
           +--------------------+--------------------+
           |                    |                    |
   +-------v-------+   +-------v-------+   +--------v-------+
   | ToolExecutor   |   | StreamResp.   |   | ContextManager |
   | Coordinator    |   | Handler       |   | (truncation)   |
   +-------+-------+   +---------------+   +----------------+
           |
   +-------v-----------------+
   | Tool Handlers (24+)     |
   | - ExecuteCommand        |
   | - WriteToFile           |
   | - ApplyPatch            |
   | - ReadFile              |
   | - SearchFiles           |
   | - BrowserAction         |
   | - AttemptCompletion     |
   | - PlanModeRespond       |
   | - Subagent              |
   | - WebFetch/WebSearch    |
   | - UseMcpTool            |
   | ...                     |
   +-------------------------+
           |
   +-------v-----------------+
   | Provider Layer (35+)    |
   | Anthropic, OpenRouter,  |
   | Gemini, OpenAI, Ollama, |
   | Bedrock, DeepSeek, ...  |
   +-------------------------+
```

## Module map

| Module path                         | Purpose                                                    |
|--------------------------------------|------------------------------------------------------------|
| `core/task/index.ts`                 | Main `Task` class: agent loop, ask/say, recursivelyMakeClineRequests |
| `core/task/ToolExecutor.ts`          | Routes tool calls through auto-approve + coordinator       |
| `core/task/tools/ToolExecutorCoordinator.ts` | Handler registry, maps tool names to handler classes |
| `core/task/tools/handlers/`          | 24+ individual tool handler implementations                |
| `core/task/tools/autoApprove.ts`     | Auto-approval logic (YOLO, per-tool, per-path)             |
| `core/task/StreamResponseHandler.ts` | SSE/streaming response parsing, tool-use delta handling    |
| `core/task/TaskState.ts`             | Mutable state bag for a running task                       |
| `core/task/loop-detection.ts`        | Detects repeated identical tool calls                      |
| `core/task/focus-chain/`             | Task progress / TODO list tracking                         |
| `core/prompts/system-prompt/`        | Modular system prompt: components, variants, templates     |
| `core/prompts/system-prompt/tools/`  | Per-tool prompt definitions with model-family variants     |
| `core/prompts/system-prompt/registry/` | PromptRegistry, PromptBuilder, ClineToolSet              |
| `core/prompts/contextManagement.ts`  | Summarize-task prompt for context compaction                |
| `core/prompts/responses.ts`          | Formatted response templates (errors, resumption, etc.)    |
| `core/api/index.ts`                  | ApiHandler interface + provider factory                    |
| `core/api/providers/`               | 35+ provider implementations                               |
| `core/api/transform/`               | Format adapters (Anthropic, OpenAI, Gemini, Ollama, etc.)  |
| `core/context/context-management/`   | ContextManager: truncation, compaction, token tracking     |
| `core/context/context-tracking/`     | File, model, and environment context trackers              |
| `core/context/instructions/`         | User instructions: .clinerules, skills, workflows          |
| `core/controller/`                   | VSCode extension controller, state, UI, commands           |
| `core/storage/`                      | StateManager, disk persistence, atomic file writes         |
| `core/ignore/`                       | ClineIgnoreController (.clineignore support)               |
| `core/permissions/`                  | CommandPermissionController (env-var based allow/deny)      |
| `core/hooks/`                        | Lifecycle hooks (PreToolUse, PostToolUse, TaskResume, etc.) |
| `core/slash-commands/`               | Slash command parsing (/newtask, /compact, /reportbug)     |
| `integrations/checkpoints/`          | Git-based checkpoint/undo system                           |
| `integrations/editor/`              | DiffViewProvider, FileEditProvider                          |
| `integrations/terminal/`            | Terminal management, shell integration                      |
| `integrations/notifications/`        | System notifications                                       |
| `services/browser/`                 | Puppeteer browser session, URL fetching                     |
| `services/mcp/`                     | Model Context Protocol hub                                  |
| `services/tree-sitter/`             | Code definition extraction via tree-sitter                  |
| `services/ripgrep/`                 | Ripgrep integration for file search                         |
| `shared/tools.ts`                   | ClineDefaultTool enum (24 tools), READ_ONLY_TOOLS list      |

## Agent loop (sequence)

Cline's agent loop is a recursive request-response cycle centered on `Task.recursivelyMakeClineRequests()`:

```
1. User submits intent (text, images, files)
   |
2. startTask() or resumeTaskFromHistory()
   |-- parseMentions() -> resolve @file, @url, @folder references
   |-- parseSlashCommands() -> /newtask, /compact, /deep-planning, etc.
   |-- Assemble userContent (text + images + file context + environment_details)
   |
3. initiateTaskLoop(userContent)
   |-- while (!abort):
   |     |
   |     recursivelyMakeClineRequests(userContent):
   |       |-- Check consecutiveMistakeCount (pause if >= threshold)
   |       |-- Check shouldCompact -> trigger summarize_task if context near limit
   |       |-- Build system prompt via PromptRegistry.get(context)
   |       |-- Append environment_details to userContent
   |       |-- Call api.createMessage(systemPrompt, messages, tools)
   |       |-- Stream response chunks via StreamChunkCoordinator
   |       |-- Parse assistant content blocks (text, tool_use, thinking)
   |       |-- For each tool_use block:
   |       |     |-- presentAssistantMessage() -> show in webview
   |       |     |-- ToolExecutor.executeTool(block)
   |       |       |-- AutoApprove.shouldAutoApproveTool(name)
   |       |       |-- If not auto-approved: ask(type, text) -> wait for user
   |       |       |-- ToolExecutorCoordinator.execute(config, block)
   |       |       |-- Collect ToolResponse -> append to userMessageContent
   |       |-- If attempt_completion: present result, ask user
   |       |-- If no tools used: return didEndLoop=false
   |       |
   |     if didEndLoop: break
   |     else: userContent = formatResponse.noToolsUsed()
   |           consecutiveMistakeCount++
```

The loop is fundamentally a while-loop in `initiateTaskLoop` that repeatedly calls `recursivelyMakeClineRequests`. Each call sends the accumulated conversation to the LLM, processes its response, executes approved tools, and either terminates (via `attempt_completion`) or continues by feeding tool results back as the next user message. If the LLM responds with text only and no tool calls, a "no tools used" reminder is injected to nudge it back toward action.

Key state is tracked in `TaskState`: streaming flags, content indices, ask/response handshake, file read cache, consecutive mistake counts, loop detection counters, and abort signals.

## Tool system

### Tool enum and registration

Tools are defined in `shared/tools.ts` as the `ClineDefaultTool` enum with 24 values:
`ask_followup_question`, `attempt_completion`, `execute_command`, `replace_in_file`, `read_file`, `write_to_file`, `search_files`, `list_files`, `list_code_definition_names`, `browser_action`, `use_mcp_tool`, `access_mcp_resource`, `load_mcp_documentation`, `new_task`, `plan_mode_respond`, `act_mode_respond`, `focus_chain`, `web_fetch`, `web_search`, `condense`, `summarize_task`, `report_bug`, `apply_patch`, `generate_explanation`, `use_skill`, `use_subagents`.

Registration is centralized in `ToolExecutorCoordinator`, which maps each enum value to a handler factory function. Handlers implement either `IToolHandler` (execute only) or `IFullyManagedTool` (execute + partial block streaming).

### Tool specs (prompt integration)

Each tool has prompt definitions in `core/prompts/system-prompt/tools/`, with model-family variants (GENERIC, NATIVE_GPT_5, NATIVE_NEXT_GEN, GEMINI_3, XS, etc.). The `ClineToolSpec` interface defines: `variant`, `id`, `name`, `description`, `parameters[]`, and optional `contextRequirements` functions. Specs are converted to OpenAI, Anthropic, or Google native tool schemas via `toolSpecFunctionDefinition()`, `toolSpecInputSchema()`, and `toolSpecGoogleFunctionDeclaration()` in `spec.ts`.

### Tool execution flow

1. `ToolExecutor` receives a parsed `ToolUse` block
2. Checks `AutoApprove.shouldAutoApproveTool()` for auto-approval
3. For auto-approved tools: streams partial content, then executes directly
4. For manual-approval tools: calls `ask("tool", ...)` to show diff/command to user
5. User responds: "yesButtonClicked", "noButtonClicked", "messageResponse"
6. On approval: `ToolExecutorCoordinator.execute()` dispatches to handler
7. Handler returns `ToolResponse` (array of text/image content blocks)

### Key tool behaviors

**execute_command**: Has a `requires_approval` boolean parameter that the LLM sets. Safe commands (dev servers, builds) set false; destructive commands (installs, deletions) set true. In YOLO mode, commands auto-execute with configurable timeouts (30s default, 300s for long-running patterns like npm install, cargo build).

**write_to_file / replace_in_file**: Both route through `WriteToFileToolHandler`. `write_to_file` creates/overwrites entire files. `replace_in_file` uses SEARCH/REPLACE blocks with exact line matching. Both stream changes into VSCode's diff editor during partial block processing, letting users see edits form in real-time.

**apply_patch**: A V4A-format diff tool primarily for GPT-5 family models. Uses `*** Begin Patch` / `*** End Patch` markers with `+`/`-` prefixed lines and `@@` scope markers for context.

**attempt_completion**: Signals task completion. Supports a "double-check" mode where the agent must re-verify against original requirements before the completion is accepted.

## Prompt surfaces

### System prompt architecture

The prompt system is highly modular, built on three layers:

1. **Components** (`components/`): Reusable sections like `agent_role`, `capabilities`, `rules`, `editing_files`, `act_vs_plan_mode`, `system_info`, `tool_use`, `mcp`, `skills`, `user_instructions`, `task_progress`, `feedback`, `objective`.

2. **Variants** (`variants/`): Model-family-specific configurations. Each variant has a `config.ts` (tool selection, component overrides) and optional `template.ts` (custom section templates). Variants: `generic`, `next-gen` (Claude 4+), `native-gpt-5`, `native-gpt-5-1`, `native-next-gen`, `gpt-5`, `gemini-3`, `xs` (small/local models), `hermes`, `glm`, `devstral`, `trinity`.

3. **Templates** (`templates/`): A `TemplateEngine` resolves `{{PLACEHOLDER}}` tokens in prompt text using context variables.

The `PromptRegistry` singleton loads all variants at startup and selects the appropriate one based on model ID via matcher functions. The `PromptBuilder` then assembles the full system prompt by iterating through the variant's component list.

### Key prompt sections

**Agent role**: "You are Cline, a highly skilled software engineer with extensive knowledge in many programming languages, frameworks, design patterns, and best practices." (file: `components/agent_role.ts:6-8`)

**Rules**: An extensive ruleset covering: CWD restrictions, search best practices, file editing guidelines, command execution safety, MCP usage, YOLO mode behavior, and anti-patterns to avoid (never start with "Great", "Certainly", etc.).

**ACT vs PLAN mode**: Defines two operational modes. In ACT mode, all tools except `plan_mode_respond` are available. In PLAN mode, the agent gathers information and plans, using `plan_mode_respond` to communicate. Mode is indicated in `environment_details`.

**Editing files**: Detailed guidance on choosing between `write_to_file` (full file) and `replace_in_file` (targeted SEARCH/REPLACE), with instructions about auto-formatting considerations.

### Context summarization

When context approaches the model's window limit, `contextManagement.ts` injects a `summarize_task` prompt that instructs the model to produce a structured summary covering: primary request, key concepts, files examined, problems solved, pending tasks, task evolution, current work, next steps, and required files. This summary replaces the truncated history.

## Memory & context

### Context window management

`ContextManager` tracks modifications to conversation history using a nested map structure keyed by message index. It supports:
- **Truncation**: When token usage approaches limits, older messages are masked via a `conversationHistoryDeletedRange` tuple
- **Context compaction**: Triggered when token usage exceeds ~80% of effective window size (context window minus a model-specific buffer of 27-40k tokens)
- **File read caching**: `TaskState.fileReadCache` maps file paths to read counts and modification times, preventing redundant file reads

Context window budgets (from `context-window-utils.ts`):
- 64k models: 37k effective
- 128k models: 98k effective  
- 200k models: 160k effective
- Other: max(window - 40k, window * 0.8)

### Context tracking

Three trackers monitor context sources:
- `FileContextTracker`: Tracks which files have been read/edited, with warnings for stale context
- `ModelContextTracker`: Records which models/providers were used per task
- `EnvironmentContextTracker`: Captures environment metadata

### User instructions (.clinerules)

Cline loads custom rules from `.clinerules/` directories (local and global), supporting toggleable rule files. It also respects `.cursorrules`, `.windsurfrules`, `AGENTS.md`, and `.claude/` rules for cross-tool compatibility.

## Shell execution

Shell commands are executed through the `ExecuteCommandToolHandler`, which delegates to a `CommandExecutor`. The executor operates in two modes:

1. **VSCode Terminal mode** (`vscodeTerminal`): Uses VSCode's integrated terminal with shell integration for output capture. Supports "Proceed While Running" for long commands.

2. **Background Exec mode** (`backgroundExec`): Uses `StandaloneTerminalManager` for headless execution, suitable for CLI environments.

Key behaviors:
- **Streaming**: Output streams line-by-line to the webview via `command_output` ask messages
- **Timeouts**: Configurable per-command. YOLO mode defaults: 30s standard, 300s for long-running patterns (npm install, cargo build, pytest, docker build, etc.)
- **Cancellation**: User can cancel via the webview; abort flag propagates through TaskState
- **Model-specific fixes**: Gemini output is post-processed via `applyModelContentFixes()` to fix HTML entity encoding issues

### Command permission system

`CommandPermissionController` reads `CLINE_COMMAND_PERMISSIONS` environment variable for enterprise/CI environments. Supports allow/deny glob patterns, redirect blocking, subshell detection, and dangerous character detection (backticks, unicode line separators).

## Safety model

### Auto-approval tiers

The `AutoApprove` class implements a three-tier approval system:

1. **YOLO mode** (`yoloModeToggled`): Auto-approves everything. All tools return `[true, true]` (local + external).

2. **Auto-approve all** (`autoApproveAllToggled`): Same as YOLO but can be toggled independently.

3. **Per-action settings** (`autoApprovalSettings.actions`):
   - `readFiles` / `readFilesExternally`: Read operations (read_file, list_files, search_files)
   - `editFiles` / `editFilesExternally`: Write operations (write_to_file, replace_in_file, apply_patch)
   - `executeSafeCommands` / `executeAllCommands`: Shell commands
   - `useBrowser`: Browser and web tools
   - `useMcp`: MCP tool/resource access

### Path-based scoping

Auto-approval distinguishes between workspace-local and external operations. The `shouldAutoApproveToolWithPath()` method resolves the target path and checks if it falls within the workspace root(s). External operations require separate `Externally` permission flags.

### LLM-driven safety signal

The `execute_command` tool includes a `requires_approval` boolean parameter that the LLM itself sets. Safe operations (reading, building, testing) should be marked false; destructive operations (installs, deletions, config changes) should be marked true. This creates a two-layer safety model: the LLM's judgment plus the user's approval settings.

### .clineignore

`ClineIgnoreController` enforces file access restrictions using `.gitignore`-syntax patterns in `.clineignore`. It watches for file changes via chokidar and reloads patterns automatically. Ignored files are locked with a lock symbol in the UI.

### Loop detection

`loop-detection.ts` tracks consecutive identical tool calls (same name + same params). At 3 repetitions (soft threshold), a warning is injected. At 5 repetitions (hard threshold), the user is escalated or the task fails. Metadata params like `task_progress` are excluded from comparison.

### Mistake limits

`consecutiveMistakeCount` tracks sequential errors (missing params, invalid tool use). At the configurable `maxConsecutiveMistakes` threshold, the user is prompted to intervene or (in YOLO mode) the task fails with an error.

### Checkpoints

Git-based checkpointing (`integrations/checkpoints/`) creates commits at key points, enabling full workspace undo. Supports both single-root and multi-root workspaces. Checkpoint commits are created after the first API request and optionally after each `attempt_completion`.

## Persistence

### Task storage

Each task is persisted to disk in a task directory containing:
- `api_conversation_history.json`: Full Anthropic-format message history (atomic writes via temp+rename)
- `ui_messages.json`: ClineMessage array for webview reconstruction
- `context_history.json`: ContextManager's truncation/update records
- `task_metadata.json`: Provider, model, timing metadata

### State management

`StateManager` wraps VSCode's `globalState` with an in-memory cache. State is partitioned into `GlobalState` (task history, UI preferences) and `Settings` (provider configs, auto-approval settings, model selections). Settings changes propagate through both webview and CLI paths.

### History

Task history is stored as `HistoryItem[]` in global state, each containing: task ID, timestamp, task description, total tokens, total cost, provider/model info. History enables task resumption via `resumeTaskFromHistory()`.

### Session resumption

Resuming a task: loads saved messages, strips incomplete partial messages, presents resume prompt to user, runs TaskResume hook, reconstructs API conversation history, and re-enters `initiateTaskLoop()`. The system handles edge cases like interrupted hook execution, empty conversation history, and stale file context.

## UX surface

### Webview architecture

Cline renders in a VSCode sidebar panel webview, communicating with the extension host via gRPC-like protobuf messages. The webview is a React application with components for:
- Chat interface (ChatRow, message rendering)
- Settings panel (provider config, auto-approval toggles)
- Task history browser
- Diff visualization (inline via VSCode diff editor)

### Diff visualization

File edits stream into VSCode's native diff editor via `DiffViewProvider` or execute silently via `FileEditProvider` (background edit mode). The user sees changes forming in real-time as the LLM streams `write_to_file` or `replace_in_file` content. Changes can be accepted or rejected at the tool-call level.

### Approval workflow

Each non-auto-approved tool call triggers an `ask()` that renders in the webview with approve/reject buttons. For file operations, the diff editor opens alongside. For commands, the command string and a risk indicator are shown. Users can also provide text feedback when rejecting.

### Mode switching

Plan/Act mode is toggled in the UI. The current mode is injected into `environment_details` in each user message. In Plan mode, the agent can still use read-only tools (read_file, search_files, execute_command for non-destructive commands) but should use `plan_mode_respond` for communication instead of making changes.

### Slash commands

Supported: `/newtask`, `/smol` (alias `/compact`), `/newrule`, `/reportbug`, `/deep-planning`, `/explain-changes`, plus custom workflow-based commands loaded from `.clinerules/workflows/`. Commands are parsed before the LLM call and inject tool-use instructions into the message.

### Notifications

System notifications via `showSystemNotification()` alert users when the agent needs attention (approval prompts, errors, mistake limits). Configurable per auto-approval settings. Hook-based notifications (`notification-hook.ts`) fire when the agent requests user attention.

## Strengths (what Zyquo should reuse)

1. **Approval-gated diff workflow**: The live-streaming diff editor is Cline's killer feature. Seeing edits form in real-time and approving/rejecting at the tool-call level is outstanding UX. Zyquo should replicate this in the terminal with its DiffView component.

2. **Per-tool auto-approval with path scoping**: The granular control (read/edit/execute, local/external) is well-designed. The LLM-driven `requires_approval` parameter on commands is a clever two-layer safety model.

3. **Modular prompt system with model-family variants**: The PromptRegistry + PromptBuilder + component + variant architecture handles the reality of different models needing different prompts. The fallback-to-GENERIC pattern is clean.

4. **Tool spec as source of truth**: `ClineToolSpec` drives both prompt generation and native tool schemas across providers. Single definition, multiple output formats.

5. **Loop detection**: Simple but effective. Signature-based comparison with soft/hard thresholds catches degenerate LLM behavior early.

6. **Context compaction via summarize_task**: The structured summary format preserves essential information across context window boundaries. The 10-section schema is thorough.

7. **Plan/Act mode**: Letting users discuss strategy before execution builds trust. The mode toggle is simple and effective.

8. **Checkpoint-based undo**: Git-commit checkpoints enable full workspace rollback, which is more robust than patch-based undo alone.

9. **SEARCH/REPLACE editing model**: For the `replace_in_file` tool, requiring exact line matches with SEARCH/REPLACE blocks is safer than line-number-based editing. It's resilient to file changes between reads.

10. **Hooks system**: Pre/post tool-use hooks with cancellation support enable enterprise customization and CI integration.

## Weaknesses (what Zyquo should avoid)

1. **Monolithic Task class**: `core/task/index.ts` is a 3500+ line god class managing streaming, UI messaging, context, hooks, checkpoints, and the agent loop. Zyquo should decompose this into separate Planner, Executor, Verifier, and SessionManager types.

2. **No explicit risk classification**: Unlike Zyquo's planned SAFE/MODERATE/DANGEROUS/CRITICAL tiers, Cline relies on the LLM's `requires_approval` boolean and flat per-category auto-approval. There is no rule-based command risk analysis.

3. **VSCode coupling**: Deep dependency on VSCode APIs (terminals, diff editors, webview, globalState) makes the core non-portable. The CLI/standalone mode is a recent addition and feels bolted on. Zyquo's terminal-first approach avoids this.

4. **No structured plan persistence**: Plans exist only in LLM conversation context. There is no `Plan` data structure, no step tracking, no plan visualization with progress. Plan mode is just a conversation mode, not a planning engine.

5. **Polling-based ask/response**: The `ask()` method uses `pWaitFor` with 100ms polling intervals to wait for user responses. This is wasteful compared to proper async/await with event-based signaling.

6. **No workspace boundary enforcement**: Unlike Zyquo's planned BoundaryGuard, Cline has `.clineignore` but no hard workspace boundary that blocks operations outside the project root (just path-based auto-approval scoping).

7. **No audit log**: Tool executions and approvals are not persisted in a reviewable audit trail separate from the conversation history.

8. **Token counting is approximate**: Context window management uses model-reported token counts from previous API responses rather than local tokenization. This creates a lag where the actual token count may exceed the budget before compaction triggers.

9. **No memory system**: No project-level persistent memory, no architecture memory, no decision memory. Each task starts fresh unless resumed. Cross-session learning does not exist.

10. **Provider explosion without abstraction**: 35+ provider files with significant duplication. The `createHandlerForProvider` switch statement is 200+ lines. Zyquo should use a proper protocol/trait with adapter pattern.

## Open questions

1. How does Cline handle concurrent tool execution? The `isParallelToolCallingEnabled` flag suggests support, but the `presentAssistantMessage` lock and sequential tool processing in the loop suggest it is limited to model-level parallelism, not runtime parallelism.

2. What is the actual token counting mechanism? The `ContextManager.shouldCompactContextWindow` checks previous API response usage, but how accurate is this for predicting the next request's size?

3. How does the checkpoint system handle conflicts when the user edits files during agent execution? The `FileContextTracker` has pending warnings, but the checkpoint commit/restore workflow is unclear.

4. The subagent system (`tools/subagent/`) appears to support delegating tasks to sub-instances. How isolated are these from the parent task's state and approval scope?

5. How does the `condense` tool (auto-condense for next-gen models) differ from the `summarize_task` compaction flow? Both seem to address context limits but through different mechanisms.

## Quotes / references (15 words each, with file:line)

- "You are Cline, a highly skilled software engineer" - `components/agent_role.ts:6`
- "YOLO MODE: Task failed, too many consecutive mistakes" - `core/task/index.ts:2386`
- "Soft threshold: inject warning, giving LLM one chance" - `loop-detection.ts:19`
- "Atomically write data using temp file plus rename pattern" - `core/storage/disk.ts:22`
- "In ACT MODE, use tools to accomplish user task" - `components/act_vs_plan_mode.ts:9`
- "Default to replace_in_file for most changes, safer option" - `components/editing_files.ts:63`
- "Set requires_approval true for potentially impactful operations" - `tools/execute_command.ts:21`
- "YOLO mode auto-approves everything, returns true true tuple" - `tools/autoApprove.ts:43-55`
- "Commands timeout at 30 seconds default in YOLO mode" - `handlers/ExecuteCommandToolHandler.ts:19`
- "Consecutive mistake count triggers user intervention at threshold" - `core/task/index.ts:2382`
- "READ_ONLY_TOOLS safe to run parallel with initial checkpoint" - `shared/tools.ts:55`
- "PromptRegistry selects variant via matcher, falls back to generic" - `registry/PromptRegistry.ts:43-57`
- "Context window buffer: 200k models get 160k effective size" - `context-window-utils.ts:28`
- "File read cache prevents model endlessly reading same files" - `TaskState.ts:51`
- "No config equals allow everything for backward compatibility" - `CommandPermissionController.ts:79`
