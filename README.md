<div align="center">

# 🧩 Zyquo

**A native macOS AI terminal agent. Plan-execute-verify with safety gates, a premium TUI, persistent memory, a closed learning loop, and a real tool runtime (ZTP).**

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6%20strict%20concurrency-F05138?logo=swift&logoColor=white)
![Arch](https://img.shields.io/badge/arch-arm64%20%C2%B7%20x86__64-blue)
![Version](https://img.shields.io/badge/version-1.2.0-2F80ED)
![License](https://img.shields.io/badge/license-Apache--2.0-green)
![Notarized](https://img.shields.io/badge/notarized-Developer%20ID-success?logo=apple)

![Source](https://img.shields.io/badge/source-186%20files%20%C2%B7%20~39k%20LOC-7A8693)
![Commands](https://img.shields.io/badge/CLI%20commands-19-9D7CFF)
![UI](https://img.shields.io/badge/TUI%20components-29-5EEAD4)
![Themes](https://img.shields.io/badge/themes-5-F0ABFC)
![Providers](https://img.shields.io/badge/providers-Anthropic%20%C2%B7%20OpenRouter%20%C2%B7%20local-5BA8FF)
![Tools](https://img.shields.io/badge/agent%20tools-shell%20%C2%B7%20fs%20%C2%B7%20git%20%C2%B7%20ZTP%C3%9712-FBBF24)

*Inspired by OpenHands · Cline · OpenCode · Hermes — built Swift-native for macOS.*

</div>

---

## Table of Contents

- [What is Zyquo](#what-is-zyquo)
- [Highlights](#highlights)
- [Install](#install)
- [Quick start](#quick-start)
- [The agent runtime](#the-agent-runtime)
- [Tools](#tools)
- [Premium TUI](#premium-tui)
- [Closed learning loop & user model](#closed-learning-loop--user-model)
- [Memory & sessions](#memory--sessions)
- [Providers & models](#providers--models)
- [CLI reference](#cli-reference)
- [Slash commands](#slash-commands)
- [Safety model](#safety-model)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [Development](#development)
- [License](#license)

---

## What is Zyquo

Zyquo is a **terminal-first AI runtime** for macOS. It is not a chat box with shell access — it is a genuine plan → execute → verify agent with:

```text
intent → workspace scan → context assembly → planning →
  per step: tool proposal → risk classification → approval gate →
            execution → observation → verification → memory update
→ summarize → persist → learn
```

Everything the agent does is **renderable, reviewable, and reversible**. It runs locally; your code and memory live on disk under `.zyquo/` and `~/.zyquo/`.

---

## Highlights

| | |
|---|---|
| 🤖 **Real agent loop** | Plan/execute/verify with stop conditions, retries, and replanning — not single-shot completion. |
| 🛡️ **Safety first** | Rule-based risk classifier, approval gates (`y/n/a/e/?`), workspace boundary guard, trust scopes. |
| 🎨 **Premium TUI** | "Premium Panels + Iris" — filled gradient cards, correct Unicode width, truecolor→mono degradation. |
| 🧠 **Closed learning loop** | Builds a persistent user model, extracts skill candidates, surfaces nudges (Hermes-inspired). |
| 🔌 **Real tool runtime** | Native shell/file/git tools **plus** the full [ZTP](https://github.com/simonpierreboucher02/ztp) suite (Excel, Docx, Slides, Chart, Mail, Message, Browser, macOS). |
| 💾 **Persistent memory** | Project / session / decision memory, session resume, FTS + hybrid retrieval. |
| 🔑 **Keychain-only secrets** | API keys live in the macOS Keychain, never in shell history or files. |

---

## Install

### Homebrew

```bash
brew install simonpierreboucher02/zyquo/zyquo
# or from the notarized release tarball (GitHub Releases):
tar xzf zyquo-1.2.0-macos-arm64.tar.gz && sudo mv zyquo /usr/local/bin/
```

### From source

```bash
git clone https://github.com/simonpierreboucher02/zyquo.git
cd zyquo && swift build -c release
.build/release/zyquo version
```

> **Requirements:** macOS 14+, Swift 6 toolchain (Xcode 16+). Optional: [`ztp`](https://github.com/simonpierreboucher02/ztp), `ripgrep`, `git`.

---

## Quick start

```bash
zyquo provider login anthropic --key sk-ant-...   # store key in Keychain
zyquo                                             # launch the interactive TUI
zyquo run "fix the failing tests and explain why" # agentic run (tools enabled)
zyquo ask  "explain this repo"                    # single-shot Q&A (no tools)
zyquo plan "add an auth flow"                     # plan only (no execution)
```

---

## The agent runtime

The `zyquo run` loop is a true multi-step agent (`Sources/Zyquo/Agent/`):

- **Planner** → numbered, verifiable steps (each one tool call)
- **Executor** → dispatches tool calls through a unified `ToolRegistry` with risk + approval gating
- **Verifier** → pass / fail / unclear verdict per step
- **Stop conditions** → max steps/cost, consecutive failures, loop detection, user cancel
- **Context assembler** → workspace summary + project memory + **user model** + tool guidance, token-budgeted
- **Orchestrator / sub-agents** (V2) → Architect / Coder / Reviewer / Shell / Verifier / Research

Every state transition emits a UI event; nothing happens off-screen.

---

## Tools

The agent and the interactive chat execute through one registry. Tool calls are **typed and schema-validated** — never `eval` of model output.

| Group | Tools |
|---|---|
| 🐚 **Shell** | `shell.run` (zsh, streamed, risk-classified, cancellable) |
| 📁 **Filesystem** | `file.read` · `file.list` · `file.write` · `file.patch` (unified-diff, boundary-checked) |
| 🌿 **Git** | `git.status` · `git.diff` · `git.log` · `git.commit` (never auto-pushes) |
| ⚙️ **ZTP** | `ztp.excel` · `ztp.docx` · `ztp.slides` · `ztp.chart` · `ztp.mail` · `ztp.message` · `ztp.browser` · `ztp.macos` · `ztp.ocr` · `ztp.notes` · `ztp.files` · `ztp.finder` |
| 🌐 **Web** *(V2)* | `web.search` · `web.fetch` · `http.request` · `docs.search` |
| 🍎 **macOS** | `applescript.run` · `applescript.query` · `applescript.info` |

ZTP tools are auto-discovered from the installed `ztp` binary and registered as `ztp.*`, so the agent can generate real Office documents, charts, and emails — and now also run **local OCR** (`ztp.ocr`), read/write **Apple Notes** (`ztp.notes`), manage **files** with search & compression (`ztp.files`), and drive **Finder** (`ztp.finder`) — as part of a task.

---

## Premium TUI

The interactive surface uses a **"Premium Panels + Iris"** design language (`Sources/Zyquo/UI/`):

- 🟦 **Filled gradient cards** — raised panels with iris (blue→violet) gradient titles and vivid rounded borders
- 📐 **Pixel-correct layout** — `DisplayWidth` handles emoji / CJK / combining marks so panels never misalign
- 🌈 **Capability-aware** — truecolor → 256 → 16 → monochrome, honoring `NO_COLOR` / `CLICOLOR` / `TERM`
- ✍️ **Streaming** — token-by-token responses with an iris left-gutter; gradient hairline rules
- 🎛️ **29 components** — panels, diff view, spinners, progress bars, timeline, status badges, markdown renderer, modal picker, keymap overlay…
- 🎨 **5 themes** — `zyquo-dark` (default), `minimal`, `high-contrast`, `solarized-dark`, plus user TOML themes

---

## Closed learning loop & user model

Inspired by Hermes Agent, Zyquo learns across sessions (`Sources/Zyquo/Memory/` + `Runtime/`):

- 🧑 **Persistent user model** — distills durable facts about you (stack, preferences, working style, constraints) with confidence reinforcement + decay; injected into planning. View with `zyquo memory user` or `/whoami`.
- 🧪 **Skill extraction** — successful sessions become reviewable skill candidates (`zyquo skills candidates / accept / reject`).
- 🔧 **Self-improving skills** — usage stats drive refinement proposals (`zyquo skills refine <id>`).
- 💡 **Nudges** — calm, actionable suggestions surfaced after a run (`zyquo nudges`, `/nudges`).

All learning is **best-effort, cost-bounded, and approval-gated** — nothing is auto-promoted or silently written.

---

## Memory & sessions

```text
.zyquo/
├── config.json · trust.json
├── memory/  project.md · architecture.md · decisions.md · sessions/*.json
├── snapshots/ · patches/ · plans/ · logs/
└── index/workspace.sqlite        (~/.zyquo/ holds the global user model & nudges)
```

- Project / architecture / decision memory (project.md is **sacred** — never overwritten, only patched)
- Session persistence + `zyquo sessions resume <id>` / `fork`
- Lexical (FTS) + hybrid retrieval; on-demand compaction (`zyquo memory compact`)

---

## Providers & models

| Provider | Status | Notes |
|---|---|---|
| **Anthropic** | ✅ | Primary — Messages API, streaming, tool use, prompt caching |
| **OpenRouter** | ✅ | Catalog passthrough + fallback |
| **OpenAI** | optional | `zyquo provider login openai` |
| **Local** (llama.cpp / Apple FM) | V2 | GGUF + Metal, hybrid routing |

The `ModelRouter` picks a model per task class (planning → Opus, coding → Sonnet, summarization → Haiku) within a cost/latency budget. Keys are stored in the macOS **Keychain** (`dev.zyquo.cli`).

---

## CLI reference

```text
zyquo                      launch interactive TUI in cwd
zyquo run "<intent>"       agentic run (tools enabled)
zyquo ask "<question>"     single-shot Q&A (no tools)
zyquo plan "<intent>"      plan only (no execution)
zyquo init                 scaffold .zyquo/ in the workspace
zyquo memory [user|compact|edit]    inspect/edit memory + user model
zyquo sessions [show|resume|fork]   manage sessions
zyquo skills [candidates|accept|reject|refine|run]   skill lifecycle
zyquo nudges [list|dismiss]         learning suggestions
zyquo provider [login|logout|list|status]   manage providers (Keychain)
zyquo models · tools · config · theme · status · doctor · version
zyquo workflow · cluster · daemon            (advanced / V2)
```

Global flags: `--workspace`, `--model`, `--provider`, `--max-steps`, `--max-cost`, `--json`, `--yes`, `--no-color`, `--verbose`.

---

## Slash commands

Inside the interactive TUI (parsed locally, no tokens): `/help` · `/status` · `/cost` · `/model` · `/tools` · `/history` · `/whoami` · `/nudges` · `/reset` · `/clear` · `/version` · `/exit`.

---

## Safety model

- ⚖️ **Risk tiers** — SAFE / MODERATE / DANGEROUS / CRITICAL via a deterministic, rule-based classifier (not the LLM).
- ✋ **Approval gates** — `[y]es [n]o [a]lways [e]dit [?]explain`; scopes: once / session / workspace / global (CRITICAL never global).
- 🧱 **Boundary guard** — commands/paths outside the workspace escalate; `~/.ssh`, `~/Library`, `/System` are CRITICAL.
- 🩹 **Diff-first writes** — every file change is a patch; applied patches produce reverse patches (rollback).
- 🙈 **Env masking & redaction** — `*_TOKEN`/`*_SECRET`/`*_KEY`/`SSH_*` never leak to children or logs.

---

## Configuration

`~/.zyquo/config.toml` (precedence: flag > env > workspace `.zyquo/config.json` > user config > defaults):

```toml
[ui]        theme = "zyquo-dark"
[agent]     max_steps = 40
            max_cost_usd = 5.00
            auto_approve_safe = true
[providers] default = "anthropic"
[learning]  enabled = true
            user_model = true
            skill_extraction = true
            nudges = true
```

---

## Architecture

```text
Sources/Zyquo/
├── Agent/        AgentLoop · Planner · Executor · Verifier · Orchestrator · ContextAssembler
├── Tools/        Tool protocol · ToolRegistry · file/git/web/applescript tools
├── ZTP/          ZTPIntegration · ZTPToolBridge · discovery (registers ztp.* tools)
├── Shell/        ShellExecutor · RiskClassifier · DangerRules · PTYHost
├── Models/       Anthropic/OpenRouter/Local providers · ModelRouter · streaming
├── Memory/       Project/Session/Decision memory · UserModel · retrieval · embeddings
├── Runtime/      LearningCoordinator · SkillExtractor/Refiner · NudgeEngine · ScheduledWorkflow
├── Diff/         DiffEngine · PatchEngine · ConflictResolver
├── UI/           TerminalRenderer · PremiumPanel · Gradient · DisplayWidth · 29 components
├── Security/     Keychain · ApprovalGate · TrustStore · Redaction · AuditLog
└── Persistence/  Session/Memory/Patch/Snapshot stores
```

---

## Development

```bash
swift build               # debug
swift test                # unit + snapshot + integration
swift build -c release    # optimized

./scripts/build-release.sh           # universal binary
./scripts/sign-and-notarize.sh release sign zip notarize   # Developer ID + notarytool
```

---

## License

Apache-2.0 © Simon-Pierre Boucher. Companion runtime: [ZTP](https://github.com/simonpierreboucher02/ztp).
