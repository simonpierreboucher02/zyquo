# OpenHands

## Overview

OpenHands (formerly OpenDevin) is an AI-driven development platform built primarily in Python (backend) and React/TypeScript (frontend). It positions itself as an autonomous software engineering agent that can write code, run commands, browse the web, and interact with external services. The project has evolved into a multi-package architecture: the core agent runtime lives in a separately published **Software Agent SDK** (`openhands-sdk`), the execution server is published as **`openhands-agent-server`**, and tool definitions live in **`openhands-tools`**. The main repository (`OpenHands/OpenHands`) contains the **App Server** (FastAPI-based REST API), the **React frontend**, **skills/microagents** (prompt-based knowledge modules), and the **enterprise** layer (auth, billing, integrations).

The system runs inside Docker containers ("sandboxes") that isolate the agent's execution environment. Each conversation spawns or reuses a sandbox, inside which the agent-server process manages the actual agent loop. The app-server orchestrates sandbox lifecycle, user authentication, conversation management, and event streaming via webhooks and SSE.

Key metrics: SWE-Bench score of 77.6%, MIT-licensed (except enterprise), supports Claude, GPT, and other LLMs via LiteLLM, with MCP (Model Context Protocol) support for external tool servers.

## Architecture diagram (ASCII)

```
                        +--------------------+
                        |   React Frontend   |
                        |  (SPA, WebSocket)  |
                        +---------+----------+
                                  |
                                  | REST / WebSocket / SSE
                                  v
                        +--------------------+
                        |   App Server       |
                        |   (FastAPI)        |
                        |                    |
                        | - Conversations    |
                        | - Sandbox mgmt     |
                        | - Settings/Auth    |
                        | - Event callbacks  |
                        | - Skills loading   |
                        | - Git integrations |
                        +----+----------+----+
                             |          |
              +--------------+          +----------------+
              v                                          v
    +--------------------+                    +--------------------+
    | Docker Sandbox     |                    | Docker Sandbox     |
    | (per conversation) |                    | (per conversation) |
    |                    |                    |                    |
    | +----------------+ |                    | +----------------+ |
    | | Agent Server   | |                    | | Agent Server   | |
    | | (SDK runtime)  | |                    | | (SDK runtime)  | |
    | |                | |                    | |                | |
    | | - Agent Loop   | |                    | | - Agent Loop   | |
    | | - LLM calls    | |                    | | - LLM calls    | |
    | | - Tool exec    | |                    | | - Tool exec    | |
    | | - Condenser    | |                    | | - Condenser    | |
    | | - Security     | |                    | | - Security     | |
    | +----------------+ |                    | +----------------+ |
    |                    |                    |                    |
    | - bash (tmux)     |                    | - bash (tmux)     |
    | - Jupyter kernel  |                    | - Jupyter kernel  |
    | - Browser (PW)    |                    | - Browser (PW)    |
    | - VSCode server   |                    | - VSCode server   |
    +--------------------+                    +--------------------+
```

## Module map

The repository is organized into these primary areas:

**`openhands/app_server/`** -- The FastAPI application server (V1):
- `app_conversation/` -- Conversation lifecycle, agent construction, skill/hook loading, start/stop/resume logic. Key files: `live_status_app_conversation_service.py` (1500+ lines, the nerve center), `app_conversation_service_base.py` (git setup, skill merging), `skill_loader.py`, `hook_loader.py`.
- `sandbox/` -- Sandbox service abstractions and implementations: `docker_sandbox_service.py` (Docker-backed), `process_sandbox_service.py` (process-backed, for development), `remote_sandbox_service.py` (cloud-hosted).
- `event/` -- Event storage, retrieval, streaming. Events are the primary communication primitive between agent-server and app-server.
- `event_callback/` -- Webhook router and callback processors (e.g., `set_title_callback_processor.py` for auto-titling conversations).
- `settings/` -- User settings persistence, LLM profiles, agent settings validation.
- `secrets/` -- Secret storage with blocked-name validation (see `constants.py`).
- `integrations/` -- GitHub, GitLab, Bitbucket, Azure DevOps, Forgejo, Jira, Linear service abstractions.
- `config.py` -- Dependency injection root (~500 lines), wires all services together.

**`openhands/server/`** -- Legacy server (V0), still hosts the WebSocket-based session protocol. Being superseded by V1.

**`frontend/`** -- React SPA with TypeScript. Uses TanStack Query for data fetching, Zustand for state, i18n. Key type definitions in `frontend/src/types/core/` (V0 actions/observations) and `frontend/src/types/v1/core/` (V1 event model).

**`skills/`** -- Markdown files with YAML frontmatter defining domain expertise (knowledge agents) and repository-specific instructions (repo agents). 27 skill files covering GitHub, Docker, Kubernetes, code review, security, SSH, etc.

**`enterprise/`** -- Source-available enterprise features: Keycloak auth, Stripe billing, Jira/Linear/Slack integrations, PostgreSQL persistence, RBAC.

**External packages** (published separately on PyPI):
- `openhands-sdk` -- Core agent runtime: Agent class, AgentContext, LLM abstraction, condensers, security analyzers, workspace abstractions, skill/plugin system.
- `openhands-agent-server` -- The execution server that runs inside each sandbox, managing the agent loop.
- `openhands-tools` -- Tool presets (`get_default_tools`, `get_planning_tools`), tool definitions for bash, file editor, browser, etc.

## Agent loop (sequence)

The agent loop is implemented in the SDK package (not directly visible in this repo), but the orchestration pattern is clear from the app-server code:

```
1. User sends message via REST API or WebSocket
2. App-server resolves sandbox (start/resume Docker container)
3. App-server builds Agent:
   a. Load user settings (LLM model, condenser, agent type)
   b. Configure LLM (via LiteLLM, with model routing)
   c. Load tools (get_default_tools or get_planning_tools)
   d. Load MCP config (external tool servers)
   e. Build AgentContext (skills, secrets, system_message_suffix)
   f. Create Agent via AgentSettings.create_agent()
   g. Apply server-only overrides (system prompt, tracing metadata)
   h. Load workspace skills from agent-server
   i. Load hooks from .openhands/hooks.json
4. App-server creates StartConversationRequest
5. Request is sent to agent-server inside the sandbox
6. Agent-server runs the agent loop:
   a. Agent receives user message
   b. Agent selects action (tool call) via LLM
   c. Action is classified for security risk
   d. If confirmation required, agent pauses for user approval
   e. Action is executed (bash, file edit, browser, etc.)
   f. Observation is produced and appended to history
   g. Condenser may compress history if too large
   h. Loop continues until FinishAction or max iterations
7. Events are streamed back via webhooks/SSE to app-server
8. App-server forwards events to frontend via WebSocket
```

The agent has two modes:
- **Default agent** (CodeActAgent): Full tool access, code execution, file editing
- **Planning agent**: Restricted to PLAN.md editing, no code execution. Uses `system_prompt_planning.j2` template.

Max iterations default is 500 (`config.template.toml:57`). Budget cap is configurable via `max_budget_per_task`. Stop conditions include FinishAction from agent, max iterations, max budget, and user cancellation.

## Tool system

Tools in OpenHands are represented as LLM function-calling schemas. The tool registry lives in `openhands-tools` package. From the app-server, tools are loaded via two entry points:

- `get_default_tools(enable_browser, enable_sub_agents)` -- Returns the standard tool set for the CodeActAgent.
- `get_planning_tools(plan_path)` -- Returns a restricted tool set for the planning agent (only PLAN.md editing).

From the frontend V1 type definitions (`frontend/src/types/v1/core/base/action.ts`), the canonical tool set includes:

| Tool | Type | Purpose |
|------|------|---------|
| `ExecuteBashAction` | Shell | Execute bash command with timeout, reset, is_input flags |
| `TerminalAction` | Shell | Terminal command execution (V1 variant) |
| `FileEditorAction` | File | view, create, str_replace, insert, undo_edit operations |
| `StrReplaceEditorAction` | File | Same operations, alternate implementation |
| `PlanningFileEditorAction` | File | PLAN.md-specific editor for planning agent |
| `GlobAction` | Search | Glob pattern file search |
| `GrepAction` | Search | Regex pattern search in file contents |
| `BrowserNavigateAction` | Browser | URL navigation with new_tab support |
| `BrowserClickAction` | Browser | Click element by index |
| `BrowserTypeAction` | Browser | Type text into element |
| `BrowserGetStateAction` | Browser | Get page state with optional screenshot |
| `BrowserGetContentAction` | Browser | Extract page content with link extraction |
| `BrowserScrollAction` | Browser | Scroll up/down |
| `BrowserGoBackAction` | Browser | Navigate back |
| `BrowserListTabsAction` | Browser | List open tabs |
| `BrowserSwitchTabAction` | Browser | Switch to tab by ID |
| `BrowserCloseTabAction` | Browser | Close tab by ID |
| `MCPToolAction` | MCP | Call any MCP-registered tool |
| `ThinkAction` | Meta | Log a thought (no side effects) |
| `FinishAction` | Meta | End the conversation with final message |
| `TaskTrackerAction` | Planning | View/update task list |

The agent settings control which tool categories are enabled (`config.template.toml:105-126`):
- `enable_browsing` -- Browser tools
- `enable_editor` -- str_replace_editor
- `enable_llm_editor` -- LLM-based editor (alternative)
- `enable_jupyter` -- IPython execution
- `enable_cmd` -- Command execution
- `enable_think` -- Think tool
- `enable_finish` -- Finish tool
- `enable_condensation_request` -- Manual condensation trigger

MCP (Model Context Protocol) support extends tools dynamically. Configuration in `config.template.toml:348-383` supports SSE, Streamable HTTP, and stdio transports. The `default-tools.md` skill registers a default MCP fetch server via stdio.

## Prompt surfaces

System prompts are Jinja2 templates stored in the SDK package:
- `system_prompt.j2` -- Default agent system prompt (referenced but not in this repo)
- `system_prompt_planning.j2` -- Planning agent variant (`live_status_app_conversation_service.py:1063`)

Prompt injection points:
1. **System prompt template** -- Selected based on agent type (default vs planning)
2. **System message suffix** -- Appended to system prompt; includes planning boundaries instruction, web host context, and user-provided suffixes
3. **Skills/Microagents** -- Loaded from multiple sources (public, user, org, project) and injected into `AgentContext.skills`. Knowledge agents are triggered by keywords; repo agents always load.
4. **Recall observations** -- Provide workspace context (repo name, directory, instructions, runtime hosts, secrets descriptions, microagent knowledge) to the agent at conversation start.
5. **Planning agent instruction** -- A hard-coded boundary prompt (`PLANNING_AGENT_INSTRUCTION` at `live_status_app_conversation_service.py:124-135`) that prevents the planning agent from executing code.

Skills are the primary prompt extension mechanism. They load from:
- `skills/` directory in the OpenHands repo (public, 27 files)
- `~/.openhands/skills/` (user-level)
- `.openhands/skills/` or `.openhands/microagents/` in the target repo (project-level)
- Organization-level skills (via org config)

Each skill file has YAML frontmatter with `name`, `type` (knowledge/repo), `version`, `agent`, `triggers` (keyword list), and optional `mcp_tools`. The body is the prompt text injected when triggered.

## Memory & context

OpenHands uses a **condenser** system for context management, configured in `config.template.toml:239-299`:

| Condenser | Strategy | Key parameters |
|-----------|----------|----------------|
| `noop` | Keep full history (default) | -- |
| `observation_masking` | Mask older observations, keep structure | `attention_window=100` |
| `recent` | Keep only recent events | `keep_first=1`, `max_events=100` |
| `llm` | LLM-based summarization | `llm_config`, `keep_first=1`, `max_size=100` |
| `amortized` | Intelligent forgetting | `keep_first=1`, `max_size=100` |
| `llm_attention` | LLM-scored priority | `llm_config`, `keep_first=1`, `max_size=100` |

The default condenser can be overridden: when `enable_default_condenser=true` (default), an `LLMSummarizingCondenser` is used. The condenser can use a separate, cheaper LLM model.

History truncation is controlled by `enable_history_truncation=true`, which truncates history when hitting LLM context length limits rather than failing.

There is no persistent long-term memory system in the open-source version. Memory is session-scoped. The `agent_memory.md` skill provides a manual workaround: it instructs the agent to create/update `.openhands/microagents/repo.md` as a form of project memory. This file is auto-loaded on subsequent conversations.

The `RecallAction` / `RecallObservation` provide workspace context at conversation start (repo name, structure, instructions, runtime hosts, custom secrets descriptions, knowledge agent content). This is a one-shot context injection, not continuous retrieval.

## Shell execution

Shell execution runs inside Docker containers. The sandbox architecture provides strong isolation:

**Docker Sandbox** (`docker_sandbox_service.py`):
- Each conversation gets a Docker container based on `nikolaik/python-nodejs:python3.12-nodejs22-slim` (default)
- Container exposes agent-server, VSCode server, and worker ports
- Health checks via `/alive` endpoint
- Supports host network mode, GPU passthrough, KVM, volume mounts
- Sandbox lifecycle: STARTING -> RUNNING -> PAUSED -> MISSING/ERROR

**Process Sandbox** (`process_sandbox_service.py`):
- Alternative for local development without Docker
- Spawns agent-server as a subprocess with dedicated port and directory
- Uses the host system directly (no isolation)

**Shell execution stack** (inside sandbox, from SDK):
- Uses `tmux` for terminal session management (`libtmux` dependency)
- `pexpect` for process interaction
- `bashlex` for shell command parsing
- Jupyter kernel gateway for IPython execution
- Playwright for browser automation

**Execution properties**:
- Commands run via `ExecuteBashAction` with configurable timeout
- `is_input=True` sends input to running process
- `reset=True` creates new terminal session
- `C-c` (Ctrl-C) interrupts running process
- Sandbox timeout default is 120 seconds
- Keep-alive and pause-on-close options for sandbox lifecycle

**Process Sandbox details** (`process_sandbox_service.py:67-80`): Each process sandbox gets a dedicated working directory, unique port, and session API key. The agent-server subprocess is spawned with `subprocess.Popen`.

## Safety model

OpenHands implements a layered security model:

**1. Security Analyzer** (`config.template.toml:226-232`):
- `confirmation_mode` -- Enables approval gates for risky actions
- `security_analyzer` -- Options: `llm` (LLM-based risk assessment) or `invariant` (rule-based)
- `enable_security_analyzer` -- Master toggle

**2. Confirmation Policies** (from SDK, referenced in `app_conversation_service_base.py:36-41`):
- `AlwaysConfirm` -- Every action requires approval
- `ConfirmRisky` -- Only risky actions require approval (default with confirmation mode)
- `NeverConfirm` -- No approvals (autonomous mode)

**3. Action Security Risk** (from frontend types `actions.ts:28-31`):
- Actions carry `security_risk` and `confirmation_state` fields
- States: `confirmed`, `rejected`, `awaiting_confirmation`
- Applied to: `CommandAction`, `IPythonAction`, `FileReadAction`, `FileEditAction`

**4. Secret Protection** (`constants.py:44-170`):
- Blocked secret names (system variables like `OPENVSCODE_SERVER_ROOT`, webhook URLs)
- Blocked prefixes (`LLM_*` to prevent LLM control escape)
- Overridable system secrets (git tokens, AWS credentials)
- Size limits: 50 secrets max, 256 char name max, 64KB value max
- Redaction utilities for logs and API responses (`redact_api_key_literals`, `redact_text_secrets`, `sanitize_config`)

**5. Sandbox Isolation**:
- Docker containers provide process and filesystem isolation
- User ID configurable (`sandbox.user_id`, default 1000)
- Run as `openhands` user by default
- Environment variables are controlled (session API keys, webhook URLs)
- No direct host filesystem access (except explicit volume mounts)

**6. Hooks** (`.openhands/hooks.json`):
- Pre/post tool use hooks for custom validation
- Event types: `stop`, `pre_tool_use`, `post_tool_use`
- Loaded from workspace at conversation start

## Persistence

**Conversation persistence**:
- V1 uses SQL database (PostgreSQL in enterprise, SQLite in OSS via Alembic migrations, see `app_lifespan/alembic/versions/001-009.py`)
- Conversations are stored with metadata: id, sandbox_id, user_id, repository, branch, title, status, timestamps
- Events are stored per-conversation in the event service (filesystem, S3, or Google Cloud backends)

**Trajectory recording**:
- Configurable via `save_trajectory_path` (`config.template.toml:29`)
- Saves full action/observation sequences as JSON
- Replay supported via `replay_trajectory_path` (`config.template.toml:38`)
- Screenshot capture optional (`save_screenshots_in_trajectory`)

**Export**:
- `export_conversation` method creates a ZIP file containing all events as JSON files plus `meta.json`
- Supports full conversation replay

**Sandbox state**:
- Sandboxes can be paused and resumed (Docker pause/unpause)
- `keep_runtime_alive` -- Keep sandbox after session ends
- `pause_closed_runtimes` -- Pause instead of stop
- `close_delay` -- 300 second default before closing idle sandboxes
- Automatic cleanup of old sandboxes based on `max_num_conversations_per_sandbox`

**Settings persistence**:
- User settings stored in database (Settings model in `settings_models.py`)
- Agent settings, conversation settings, LLM profiles, sandbox grouping strategy
- Default persistence directory: `~/.openhands/` (configurable via `OH_PERSISTENCE_DIR`)

## UX surface

**Frontend** (React SPA):
- Chat-based interface with action/observation rendering
- Collapsible UI elements for different action types
- Diff visualization for file edits (`EditObservation` with `diff` field)
- Browser view with screenshots (Playwright-captured)
- VSCode-in-browser integration (via OpenVSCode Server in sandbox)
- Terminal view for command output
- Planner view for PLAN.md editing
- Agent state indicator (planning, executing, awaiting input, stopped, archived)
- i18n support with multiple languages
- TanStack Query for data fetching with cache management

**Agent states** (from frontend `agent-state` type):
- AWAITING_USER_INPUT
- RUNNING
- STOPPED
- ARCHIVED (sandbox missing)
- Error states

**Planning UX**:
- Two agent types selectable: Default (code) and Plan
- Planning agent creates/edits PLAN.md
- "Build" button transitions from plan to execution
- Task tracker with todo/in_progress/done states

**Conversation management**:
- Search, filter, sort conversations
- Resume paused conversations
- Fork conversations (create sub-conversations)
- Export as ZIP
- Delete with optional sandbox cleanup

## Strengths (what Zyquo should reuse)

1. **Action/Observation event model**: The typed event system with distinct action types (CommandAction, FileEditAction, etc.) and their corresponding observations provides a clean, extensible communication protocol. Zyquo should adopt a similar typed event model.

2. **Condenser architecture**: The pluggable condenser system (noop, observation_masking, recent, llm, amortized, llm_attention) is well-designed. The separation of context management from the agent loop is clean. Zyquo should implement a similar layered compression strategy.

3. **Skills/Microagents system**: Keyword-triggered knowledge injection is an elegant pattern. Skills loaded from multiple sources (public, user, org, project) with merge semantics. The YAML frontmatter + markdown body format is simple and effective.

4. **Security risk classification on actions**: Attaching `security_risk` and `confirmation_state` to individual actions rather than globally is granular and user-friendly.

5. **Sandbox isolation model**: Running the agent inside a Docker container provides genuine process isolation. The multi-backend sandbox service (Docker, process, remote) with a common interface is well-abstracted.

6. **MCP tool integration**: Using the Model Context Protocol for external tool servers provides unlimited extensibility without modifying the core tool registry.

7. **Trajectory recording and replay**: The ability to save and replay full conversation trajectories is valuable for debugging, evaluation, and reproducibility.

8. **Planning agent separation**: Having a dedicated planning-only agent mode that cannot execute code forces deliberate plan-then-execute workflows.

9. **Hook system**: Pre/post tool-use hooks loaded from the project directory enable project-specific guardrails without modifying the agent.

10. **Multiple LLM backend via LiteLLM**: Using LiteLLM as the provider abstraction layer gives broad model compatibility with minimal code.

## Weaknesses (what Zyquo should avoid)

1. **Package fragmentation**: Splitting core logic across 4 packages (openhands-ai, openhands-sdk, openhands-agent-server, openhands-tools) makes the codebase hard to navigate, debug, and contribute to. The main repo contains only the orchestration layer; the actual agent loop is invisible. Zyquo should keep the agent core in a single repository.

2. **Docker dependency for all execution**: Requiring Docker even for local development creates friction. The process sandbox is a workaround, not a first-class mode. Zyquo should run natively on macOS without containerization in V1.

3. **Web-first UX**: Despite having a CLI, OpenHands is fundamentally web-oriented. The React SPA is the primary interface, and the terminal experience is secondary. Zyquo must invert this: terminal-first, web-optional.

4. **No persistent agent memory**: The `.openhands/microagents/repo.md` workaround for project memory is manual and fragile. There is no decision log, no architecture memory, no session-crossing recall. Zyquo must build persistent, structured memory from day one.

5. **Monolithic conversation service**: `live_status_app_conversation_service.py` is 1500+ lines handling agent construction, LLM configuration, secret management, skill loading, hook loading, and conversation lifecycle. This conflation makes it fragile. Zyquo should separate these concerns.

6. **No diff review workflow**: File edits are str_replace operations applied directly. There is no patch preview, no approval gate on file changes, no rollback mechanism beyond `undo_edit`. Zyquo must implement Cline-style patch-then-approve.

7. **Weak approval ergonomics**: Confirmation is binary (confirm/reject). There is no "always approve for this command" or workspace-scoped trust. Security analysis is either LLM-based (expensive, slow) or absent. Zyquo should implement tiered trust with persistence.

8. **No terminal rendering quality**: The web frontend renders action results; there is no ANSI/TUI-quality terminal output. Zyquo must own its terminal rendering.

9. **Complex startup path**: Starting a conversation requires sandbox creation, health checks, repository cloning, setup script execution, git hooks, skill loading -- all orchestrated across HTTP calls between app-server and agent-server. This adds latency and failure points. Zyquo should have a sub-second startup path for local execution.

10. **Python performance ceiling**: The hot path (agent loop, LLM streaming, tool execution) is Python. Cold start involves Docker container creation. Zyquo's Swift native implementation should provide dramatically better startup time and memory usage.

## Open questions

1. **Agent loop internals**: The actual agent loop (action selection, observation processing, step management) lives in the SDK package which is not in this repo. How does it handle retries after tool failures? What is the exact prompting strategy for action selection?

2. **Condenser trigger timing**: When exactly does condensation run? On every step? Only when context exceeds a threshold? The `max_size` parameter suggests threshold-based, but the exact trigger logic is in the SDK.

3. **Browser tool reliability**: The Playwright-based browser tools provide 11 distinct actions. How stable is this in practice? What is the failure rate for browser-based tasks?

4. **Sub-agent protocol**: The `enable_sub_agents` flag and `get_registered_agent_definitions()` suggest multi-agent support is implemented. What is the delegation protocol between parent and child agents?

5. **ACP Agent path**: The `ACPAgentSettings` / `_build_acp_start_conversation_request` path suggests an alternative agent runtime (Agent Communication Protocol). What is this and how does it differ from the LLM-based agent?

6. **Plugin system scope**: The `PluginSource` model supports loading plugins from GitHub repos, local paths, and registries. How are plugins sandboxed? What capabilities can they add?

7. **Condenser LLM cost**: Using a separate LLM for summarization (the condenser LLM config) adds cost. What is the typical overhead? Is the amortized condenser significantly cheaper?

## Quotes / references (15 words each, with file:line)

1. "Default agent is CodeActAgent" -- `config.template.toml:74`
2. "Maximum number of iterations 500" -- `config.template.toml:58`
3. "Runtime environment is docker by default" -- `config.template.toml:72`
4. "Sandbox timeout in seconds default 120" -- `config.template.toml:151`
5. "LLM summarizing condenser used as default condenser" -- `config.template.toml:86-88`
6. "You are a Planning Agent that can ONLY create plans" -- `live_status_app_conversation_service.py:125`
7. "Skills are specialized prompts enhancing domain-specific knowledge" -- `skills/README.md:1`
8. "Blocked secret names reserved for internal use" -- `constants.py:44`
9. "Agent server health check on /alive endpoint" -- `sandbox_service.py:143`
10. "Keep runtime alive after session ends option" -- `config.template.toml:189`
11. "Confirmation mode for headless and CLI only" -- `config.template.toml:229`
12. "Event types stop pre_tool_use post_tool_use for hooks" -- `app_conversation_router.py:1250-1251`
13. "Process sandbox spawns separate agent server processes" -- `process_sandbox_service.py:1-5`
14. "Conversation max age seconds 864000 which is 10 days" -- `config.template.toml:94`
15. "Tools preset default and planning imported from openhands-tools" -- `live_status_app_conversation_service.py:110-116`
