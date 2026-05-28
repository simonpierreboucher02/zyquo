# Zyquo

[![macOS](https://img.shields.io/badge/macOS-14%2B%20Sonoma-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/sonoma/)
[![Swift](https://img.shields.io/badge/Swift-5.10%2B-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.0.0-5BA8FF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo/releases/tag/v1.0.0)
[![Homebrew](https://img.shields.io/badge/Homebrew-tap-FBB040?style=flat-square&logo=homebrew&logoColor=white)](https://github.com/simonpierreboucher02/homebrew-zyquo)
[![Architecture](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-8E8E93?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Claude](https://img.shields.io/badge/Claude-Opus%20%7C%20Sonnet%20%7C%20Haiku-D97706?style=flat-square)](https://anthropic.com)
[![Tools](https://img.shields.io/badge/Tools-8%20built--in-4ADE80?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Agents](https://img.shields.io/badge/Agents-6%20specialized-9D7CFF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Cluster](https://img.shields.io/badge/MacLustr-V2%20planned-8E8E93?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

**Native macOS AI terminal agent runtime.**

Zyquo is a Swift-native, terminal-first AI agent for macOS. It combines autonomous multi-step reasoning with safe, approval-gated execution — all rendered in a premium terminal interface. Inspired by Claude Code, Cline, and OpenCode, rebuilt from scratch in Swift.

---

## Install

```bash
brew tap simonpierreboucher02/zyquo
brew install zyquo
```

Or build from source:

```bash
git clone https://github.com/simonpierreboucher02/zyquo.git
cd zyquo
swift build -c release
cp .build/release/zyquo /usr/local/bin/
```

### First Run

```bash
zyquo provider login anthropic   # Store API key in macOS Keychain
zyquo doctor                     # Verify setup
zyquo                            # Launch interactive mode
```

---

## Features

### Terminal-First UI

[![UI Components](https://img.shields.io/badge/Components-20%2B-5BA8FF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Themes](https://img.shields.io/badge/Themes-4%20built--in-9D7CFF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Rendering](https://img.shields.io/badge/Render-truecolor%20%7C%20256%20%7C%2016%20%7C%20mono-4ADE80?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

- Unicode box-drawing panels with rounded borders (`╭ ─ ╮ │ ╰ ╯`)
- Streaming token-by-token LLM output with live rendering
- Syntax-highlighted code blocks and diff views (unified + side-by-side)
- Animated spinners, progress bars, and timeline views
- Status badges with risk-tier coloring (SAFE/MODERATE/DANGEROUS/CRITICAL)
- Agent panel with step-by-step execution visualization
- Approval panel for interactive risk confirmation
- Splash screen with project branding
- Markdown-to-ANSI rendering (CommonMark subset)
- SIGWINCH handling for responsive terminal resizing
- Automatic capability detection with graceful degradation (truecolor → 256 → 16 → monochrome)
- `NO_COLOR`, `CLICOLOR`, `TERM`, `COLORTERM` environment respect

**UI Components:** Panel, CellBuffer, LayoutEngine, TerminalRenderer, Theme, Spinner, ProgressBar, StatusBar, StatusBadge, SplashScreen, DiffView, MarkdownRenderer, StreamWriter, AgentPanel, ApprovalPanel, CommandCard, CommandOutput, PromptInput, PromptInputController, TimelineView

### Themes

| Theme | Style |
|-------|-------|
| `zyquo-dark` | Default. Cool neutral, signal-blue accents |
| `minimal` | Monochrome, ANSI-16, no boxes |
| `solarized-dark` | Solarized Dark canonical mapping |
| `high-contrast` | Accessibility-first, 7:1 contrast ratio |

Custom themes: add TOML files to `~/.zyquo/themes/`.

---

### Agentic Runtime

[![Agent Loop](https://img.shields.io/badge/Loop-plan%20→%20execute%20→%20verify-F59E0B?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Sub-Agents](https://img.shields.io/badge/Sub--Agents-6%20types-9D7CFF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Stop Conditions](https://img.shields.io/badge/Stop-max%20steps%20%7C%20max%20cost%20%7C%20cancel-EF4444?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

The agent operates in a transparent plan-execute-verify loop:

```
intent → workspace scan → context assembly → token budget check
  → planning → [for each step: propose → risk classify → approve → execute → observe → verify → memory update]
  → summarization → persist
```

Every state transition emits a UI event. No hidden autonomous behavior.

**Sub-Agents** (orchestrated via the Orchestrator):

| Agent | Role | Risk Ceiling |
|-------|------|-------------|
| `architect` | Design analysis, ADRs, structural refactors | DANGEROUS |
| `coder` | Implementation, file editing, narrow scope | DANGEROUS |
| `reviewer` | Code review, style, conventions, regression scanning | MODERATE |
| `verifier` | Test execution, validation, success/failure proof | MODERATE |
| `shell` | Build/test/CI orchestration | MODERATE |
| `deployer` | Release, push, deploy operations | CRITICAL |

**Adaptive Planning:** Plans adjust dynamically based on execution feedback. The planner re-plans on failure with failure context.

**Stop Conditions:**
- Max steps (default 40, `--max-steps`)
- Max cost (configurable, `--max-cost`)
- User cancellation (Ctrl-C, `/cancel`)
- 3 consecutive tool failures
- Detected loops (same tool call repeated 3× in window of 5)

---

### Tool System

[![Tools](https://img.shields.io/badge/Built--in-8%20tools-4ADE80?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Schema](https://img.shields.io/badge/Schema-JSON%20Schema-5BA8FF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

Every tool has a stable name, JSON Schema for input validation, a default risk tier, and async execution.

| Tool | Risk | Mut. | Description |
|------|------|------|-------------|
| `applescript.run` | MODERATE | W | Execute AppleScript to automate macOS apps |
| `applescript.query` | SAFE | R | Read-only AppleScript queries |
| `applescript.info` | SAFE | R | Get AppleScript reference for a macOS app |
| `web.search` | SAFE | R | Search the web via DuckDuckGo |
| `web.fetch` | MODERATE | R | Fetch and read content from a URL |
| `http.request` | MODERATE | R | Make an HTTP request |
| `db.query` | MODERATE | W | Execute SQL queries (SQLite) |
| `docs.search` | SAFE | R | Search developer documentation |

In interactive and agentic modes, the agent also uses core tools: `shell_run`, `file_read`, `file_write`, `file_list` with per-call risk escalation.

---

### AppleScript Automation

[![Apps](https://img.shields.io/badge/Apps-13%20supported-D97706?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Risk](https://img.shields.io/badge/Risk-per--script%20classification-EF4444?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

The agent can automate 13 macOS applications via AppleScript:

| Application | Capabilities |
|-------------|-------------|
| **Safari** | URL navigation, tab management, JavaScript execution |
| **Finder** | File operations, folders, selection, trash, reveal, sort |
| **Mail** | Send/read email, attachments, mailbox rules, signatures |
| **Calendar** | Events, alarms, recurring events, attendees, calendar management |
| **Contacts** | Create/read/modify contacts, groups, search, vCards |
| **Notes** | Create/read/modify notes, folders, HTML content |
| **Music** | Playback control, track info, playlists, volume, shuffle/repeat |
| **Messages** | Send iMessage/SMS, read conversations, group chats |
| **Terminal** | Shell commands, window management, tab creation |
| **System Events** | GUI scripting, keyboard/mouse automation, login items, dark mode, notifications |
| **Keynote** | Create presentations, slides, text items, export to PDF/PPTX |
| **Pages** | Document creation, text formatting, images, export |
| **Numbers** | Spreadsheet operations, cells, formulas, ranges, export |

**Per-script risk classification:**

| Level | Triggers |
|-------|----------|
| SAFE | Property reads, `count`, `exists`, `get` |
| MODERATE | `activate`, `open`, `make new`, `set`, `send`, `do javascript` |
| DANGEROUS | `keystroke`, `click`, `key code`, `delete`, `empty trash` |
| CRITICAL | `do shell script`, `sudo`, `shutdown`, `restart`, `administrator privileges` |

---

### Risk Classification & Safety

[![Tiers](https://img.shields.io/badge/Tiers-4%20levels-EF4444?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Rules](https://img.shields.io/badge/Rules-30%2B%20patterns-F59E0B?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Keychain](https://img.shields.io/badge/Secrets-macOS%20Keychain-000000?style=flat-square&logo=apple)](https://github.com/simonpierreboucher02/zyquo)

All shell commands are classified deterministically (< 1ms) using 30+ regex patterns:

| Tier | Examples | Approval |
|------|----------|----------|
| **SAFE** | `ls`, `cat`, `git status`, `swift test`, `rg` | Auto (with `--yes`) |
| **MODERATE** | `git commit`, `npm install`, file writes, `osascript` | Prompt |
| **DANGEROUS** | `rm -rf`, `chmod -R`, `dd`, `git clean -f`, `killall` | Prompt + warning |
| **CRITICAL** | `sudo`, `curl \| sh`, `git push`, `brew install`, `eval` | Always prompt |

**Path-based escalation:** Commands touching paths outside the workspace root escalate by one tier. Commands touching `~/.ssh`, `~/.aws`, `~/Library`, `/System`, `/Library`, `/private` are always CRITICAL.

**Security features:**
- macOS Keychain for API keys (service: `dev.zyquo.cli`)
- Approval gate with tier-based requirements
- Trust store for remembering past approvals (per-workspace and global)
- Audit log for all tool executions and decisions
- Environment masking (`*_TOKEN`, `*_SECRET`, `*_KEY`, `SSH_*`)
- Workspace boundary enforcement

---

### LLM Providers & Models

[![Anthropic](https://img.shields.io/badge/Anthropic-primary-D97706?style=flat-square)](https://anthropic.com)
[![OpenRouter](https://img.shields.io/badge/OpenRouter-fallback-5BA8FF?style=flat-square)](https://openrouter.ai)
[![OpenAI](https://img.shields.io/badge/OpenAI-optional-4ADE80?style=flat-square)](https://openai.com)
[![Local](https://img.shields.io/badge/Local-GGUF%20%2F%20llama.cpp-8E8E93?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

**Cloud Models:**

| Model | Context | Input | Output | Use Case |
|-------|---------|-------|--------|----------|
| Claude Opus 4.7 | 1M tokens | $5/MTok | $25/MTok | Complex planning, deep reasoning |
| Claude Sonnet 4.6 | 1M tokens | $3/MTok | $15/MTok | Default. Balanced performance |
| Claude Haiku 4.5 | 200K tokens | $1/MTok | $5/MTok | Fast, low-cost tasks |

**Local Models (catalog, V2):**

| Model | Quantization | Size |
|-------|-------------|------|
| Llama 3.2 3B | Q4_K_M | 2.0 GB |
| Phi-3 Mini 4K | Q4_0 | 2.1 GB |
| Gemma 2 2B | Q4_K_M | 1.5 GB |
| Mistral 7B | Q4_K_M | 4.3 GB |

**Model routing:** Planner uses Opus, coding uses Sonnet, summarization uses Haiku. Override with `--model`.

---

### Workspace Intelligence

[![Languages](https://img.shields.io/badge/Languages-15%2B%20detected-5EEAD4?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Frameworks](https://img.shields.io/badge/Frameworks-auto%20detected-FBBF24?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

Zyquo automatically analyzes your repository on open:

- **Language detection** by file count and size weighting (Swift, Python, TypeScript, JavaScript, Rust, Go, Ruby, Elixir, Java, Kotlin, C, C++, Objective-C, Shell, and more)
- **Framework detection** (React, Django, Spring, Rails, SwiftUI, etc.)
- **Package manager** (npm, yarn, pnpm, pip, cargo, bundler, CocoaPods, SPM)
- **Test command** inference and caching
- **Build command** detection
- **Git status** (branch, upstream, ahead/behind, staged/unstaged)
- **Documentation** detection (README, ARCHITECTURE.md, CONTRIBUTING.md)
- **Ignore patterns** via `.gitignore` + `.zyquoignore`
- **Boundary guard** prevents modifications outside workspace root

**Code intelligence (V2):**
- Symbol extraction (functions, classes, constants)
- Dependency graph (imports, call graph)
- Semantic chunking and search
- Full workspace indexing with background daemon

---

### Memory & Persistence

[![Memory](https://img.shields.io/badge/Memory-5%20layers-9D7CFF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Storage](https://img.shields.io/badge/Storage-SQLite%20%2B%20JSONL-5BA8FF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

Sessions and project knowledge survive restarts, crashes, and sleep:

| Layer | Lifetime | Content |
|-------|----------|---------|
| Session | Per session | Conversation history, tool calls, observations, cost |
| Project | Persistent | Architecture notes, conventions, test commands |
| Decisions | Append-only | ADR-style decision records |
| Compressed | Persistent | Summarized historical data |
| Vectors | Persistent | Embeddings for semantic search (V2) |

**Storage layout:**

```
.zyquo/
├── config.json              # workspace config
├── trust.json               # approval grants
├── memory/
│   ├── project.md           # hand-editable project memory
│   ├── decisions.md         # append-only ADR log
│   └── sessions/            # session records (JSONL)
├── snapshots/               # file pre-images (for rollback)
├── patches/                 # unified diffs + reverse patches
├── plans/                   # saved agent plans
├── logs/                    # structured session logs
└── index/                   # SQLite workspace index
```

---

### Skills System

[![Skills](https://img.shields.io/badge/Skills-5%20built--in-FBBF24?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

Reusable, prompted workflows with constrained tool whitelists and budget enforcement:

| Skill | Description |
|-------|-------------|
| `fix_swift_build` | Diagnose and fix Swift build failures |
| `code_review` | Automated code review pass |
| `onboard_repo` | Deep tour of an unfamiliar repository |
| `generate_changelog` | Auto-generate changelog from git history |
| `commit_message` | Craft commit messages from staged changes |

Each skill declares: `tools_allowed`, `risk_ceiling`, `budget` (max steps + cost), `inputs`, and a `verify` command.

Add custom skills to `.zyquo/skills/` or `~/.zyquo/skills/`.

---

### Diff & Patch Workflow

All file writes go through patches. Every change is reviewable, approvable, and reversible.

```
proposed write → snapshot pre-image → generate unified diff → render diff
→ risk classify → approval gate → apply patch (atomic write) → record patch
→ update workspace index → emit UI event
```

- **Unified + side-by-side** diff views with syntax highlighting
- **Intra-line highlighting** using Myers minimal-edit on word tokens
- **Multi-file changesets** with per-file approval
- **3-way merge** for conflict resolution
- **Rollback** via reverse patches

---

### Workflow Scheduling

Schedule recurring agent tasks:

```bash
zyquo workflows create "nightly-review" \
  --schedule "daily@09:00" \
  --intent "review all uncommitted changes" \
  --max-cost 1.00
```

Supported schedules: `5m`, `1h`, `daily@09:00`, `weekly@mon@09:00`.

---

### Cluster Support (MacLustr)

[![Nodes](https://img.shields.io/badge/Nodes-16-EF4444?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![Cores](https://img.shields.io/badge/Cores-250-F59E0B?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)
[![RAM](https://img.shields.io/badge/RAM-720%20GB-5BA8FF?style=flat-square)](https://github.com/simonpierreboucher02/zyquo)

Distributed compute across the MacLustr cluster:

| Node | Cores | RAM | Model |
|------|-------|-----|-------|
| M3U96a, M3U96b | 32 each | 96 GB | Mac Studio |
| M2U64 | 24 | 64 GB | Mac Studio |
| M4M64a, M4M64b | 16 each | 64 GB | Mac Studio |
| M4BP48 | 16 | 48 GB | MacBook Pro |
| M4BP36 | 14 | 36 GB | MacBook Pro |
| M4M36 | 14 | 36 GB | Mac Studio |
| M2M32, M2M32b, M2M32c | 12 each | 32 GB | Mac Studio |
| m4mc | 12 | 24 GB | Mac mini |
| M1M32 | 10 | 32 GB | Mac Studio |
| m4ma | 10 | 24 GB | Mac mini |
| m4mb | 10 | 16 GB | Mac mini |
| M3BA24 | 8 | 24 GB | MacBook Air |

**16 nodes, 250 cores, 720 GB RAM** — core-proportional work distribution, passwordless SSH, fault recovery.

---

## CLI Reference

### Commands

| Command | Description |
|---------|-------------|
| `zyquo` | Launch interactive REPL (default) |
| `zyquo ask "question"` | Single-shot Q&A (no tools) |
| `zyquo run "intent"` | Agentic run with full tool access |
| `zyquo plan "intent"` | Plan-only mode (no execution) |
| `zyquo init` | Scaffold `.zyquo/` workspace |
| `zyquo doctor` | Diagnostics and health check |
| `zyquo status` | Workspace analysis and git info |
| `zyquo config get\|set\|list` | Configuration management |
| `zyquo provider login\|logout\|list\|status` | Provider management |
| `zyquo models list\|local\|info\|remove\|register` | Model management |
| `zyquo tools list` | List registered tools with risk levels |
| `zyquo skills list\|show\|run` | Skill management and execution |
| `zyquo workflows create\|list\|show\|delete\|history` | Scheduled workflows |
| `zyquo sessions list\|show\|resume` | Session management |
| `zyquo memory overview\|edit\|compact` | Project memory inspector |
| `zyquo cluster status\|nodes\|check\|test` | Cluster operations |
| `zyquo daemon status\|start\|stop\|index\|clean` | Background daemon |
| `zyquo version` | Version and build info |

### Global Flags

| Flag | Effect |
|------|--------|
| `--workspace <path>` | Override workspace root |
| `--no-color` | Disable ANSI color output |
| `--json` | Machine-readable JSON output |
| `--yes` | Auto-approve SAFE-tier actions |
| `--dry-run` | Plan but never execute |
| `--model <id>` | Override session model |
| `--provider <id>` | Override session provider |
| `--max-steps <n>` | Hard cap on agent steps (default: 40) |
| `--max-cost <usd>` | Hard cap on session cost |
| `--verbose` | Increase log verbosity |
| `--quiet` | Suppress non-essential output |
| `--log-file <path>` | Mirror logs to file |

### Interactive Slash Commands

| Command | Action |
|---------|--------|
| `/help` | Show command reference |
| `/status` | Session info (tokens, cost, model) |
| `/cost` | Token and dollar cost breakdown |
| `/model [name]` | Show or switch model mid-session |
| `/tools` | List available tools |
| `/history` | Conversation statistics |
| `/reset` | Clear conversation history |
| `/clear` | Clear screen |
| `/version` | Version string |
| `/exit` | Save session and exit |

### Exit Codes

| Code | Meaning |
|-----:|---------|
| 0 | Success |
| 1 | Generic error |
| 2 | Usage error |
| 3 | Config error |
| 4 | Provider error |
| 5 | Tool error |
| 6 | Approval denied |
| 7 | Risk budget exceeded |
| 8 | Workspace boundary violation |
| 9 | Persistence error |
| 10 | Plugin error |
| 130 | SIGINT (Ctrl-C) |

---

## Architecture

```
Sources/Zyquo/
├── Commands/        18 CLI subcommands (ArgumentParser)
├── Agent/           Orchestrator, Planner, Executor, Verifier, SubAgents
├── Models/          LLM providers (Anthropic, OpenRouter, OpenAI, Local)
├── Tools/           8 built-in tools + AppleScript reference
├── Shell/           Subprocess execution, risk classifier, 30+ danger rules
├── Workspace/       Repo detection, indexing, symbol extraction, boundary guard
├── Diff/            Patch generation, application, conflict resolution
├── UI/              20 terminal components, themes, ANSI rendering
├── Security/        Keychain, approval gates, trust store, audit log
├── Memory/          Session, project, decision memory, vector store
├── Persistence/     SQLite-backed session/config/patch/snapshot stores
├── Observability/   Structured logging (swift-log), metrics
├── Errors/          Typed error taxonomy with remediation hints
└── Util/            Config resolution, environment, clock
```

### Design Principles

1. **Transparency** — Every agent action is rendered, reviewable, and revertible
2. **Approval over autonomy** — Trust is earned per-session via explicit escalation
3. **Locality** — State lives on disk under `.zyquo/`. The cloud is a tool, not a home
4. **Composition** — Tools are small, typed, and schema-validated. No eval
5. **macOS-native** — Keychain, FSEvents, Process, Foundation. No cross-platform pretense in V1
6. **The terminal is the canvas** — ANSI is a serious rendering target

### Dependencies

| Package | Purpose |
|---------|---------|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | CLI command parsing |
| [swift-log](https://github.com/apple/swift-log) | Structured logging |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite persistence |
| [swift-collections](https://github.com/apple/swift-collections) | OrderedDictionary, Deque |
| [swift-system](https://github.com/apple/swift-system) | POSIX file paths |
| [swift-async-algorithms](https://github.com/apple/swift-async-algorithms) | Streaming combinators |
| [Yams](https://github.com/jpsim/Yams) | YAML parsing |
| [TOMLKit](https://github.com/LebJe/TOMLKit) | TOML theme/config parsing |

---

## Configuration

### Precedence

```
CLI flag > env var > workspace config (.zyquo/config.json) > user config (~/.zyquo/config.toml) > defaults
```

### User Config (`~/.zyquo/config.toml`)

```toml
[ui]
theme = "zyquo-dark"
animations = true
unicode_borders = true

[agent]
max_steps = 40
max_cost_usd = 5.00
auto_approve_safe = true

[providers]
default = "anthropic"

[providers.anthropic]
default_model = "claude-sonnet-4-6"

[shell]
default = "/bin/zsh"
load_profile = false
timeout_s = 120

[memory]
compress_threshold_pct = 70
keep_decisions_verbatim = true
```

---

## Requirements

- macOS 14+ (Sonoma or later)
- Swift 5.10+ / Xcode 16+ (for building from source)
- `git` and `rg` (ripgrep) — required
- Optional: `swift-format`, `swiftlint`, `prettier`, `fd`, `bat`, `delta`, `jq`, `shellcheck`

---

## Performance

| Surface | Budget |
|---------|--------|
| Cold start (`zyquo --help`) | < 120 ms (arm64) |
| First paint (interactive) | < 200 ms |
| Frame render (no LLM) | < 8 ms p95 |
| Streaming token append | < 2 ms |
| First token (warm cache) | < 800 ms p50 |
| Binary size (stripped) | < 10 MB |
| Memory at idle | < 60 MB RSS |

---

## Roadmap

| Version | Scope |
|---------|-------|
| **V1** (current) | Interactive UI, Anthropic/OpenRouter, shell execution, risk classification, patch workflow, workspace intelligence, memory, AppleScript, skills, sessions |
| **V2** | Multi-agent orchestration, semantic search (tree-sitter), local models (llama.cpp), embeddings, background daemon, plugin system, distributed execution |
| **V3** | Cloud-coordinated sessions, GUI cockpit, public skill marketplace, team workspaces |

---

## License

Apache-2.0. See [LICENSE](LICENSE).

## Author

Simon-Pierre Boucher
