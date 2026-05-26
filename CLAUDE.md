# CLAUDE.md — Zyquo CLI

## Native macOS Terminal Agent

### Inspired by OpenHands, Cline, and OpenCode

**Author:** Simon-Pierre Boucher
**Project:** Zyquo
**Platform:** macOS 14+ (Sonoma, Sequoia, Sequoia+)
**Primary Language:** Swift 5.10+ / Swift 6 strict concurrency
**Architecture Style:** Native terminal-first AI runtime
**License:** Apache-2.0 (suggested)
**Distribution:** Homebrew tap + signed/notarized universal binary (arm64 + x86_64)

---

## 0. Document Conventions

Throughout this document:

- `MUST`, `MUST NOT`, `SHOULD`, `MAY` follow RFC 2119 semantics.
- Code blocks marked `swift` are normative when in interface/protocol sections.
- Code blocks marked `text` are illustrative UI mockups — actual ANSI output
  may differ slightly per theme.
- File paths use macOS absolute conventions (`~/.zyquo`, `~/Library/...`).
- `[V1]` / `[V2]` tags indicate scope. V1 is the foundation; V2 is the
  agentic runtime evolution.

---

## 1. Mission

You are Claude Code acting as principal architect and implementation agent
for **Zyquo CLI**.

Your first task is to deeply analyze these repositories:

```bash
mkdir -p research/repos
cd research/repos

git clone https://github.com/OpenHands/OpenHands
git clone https://github.com/cline/cline
git clone https://github.com/anomalyco/opencode
```

You MUST inspect them in depth and then design a superior native macOS
terminal agent inspired by their strongest ideas.

Zyquo must combine:

- **OpenHands** — autonomous agent architecture, action/observation loop,
  sandboxed runtime
- **Cline** — approval-gated diff workflow, plan/act modes, file editing
  ergonomics
- **OpenCode** — terminal-native UX, TUI ergonomics, provider-agnostic
  design

while being:

- Swift-native (no Electron, no Python runtime in hot path)
- macOS-native (Keychain, Spotlight, Notification Center, Accessibility)
- terminal-first (TTY is the primary surface, GUI is later)
- fast (cold start under 120 ms, first token under 800 ms on warm cache)
- beautiful (premium ANSI rendering, custom themes, fluid animations)
- safe (no unintended writes, no surprise network calls, no silent shells)
- persistent (sessions survive restarts, sleep, crashes)
- agentic (genuine multi-step reasoning, not single-shot completion)

---

## 2. Core Philosophy

### 2.1 Zyquo is NOT

- a web app
- an Electron wrapper
- a VSCode extension
- a browser IDE
- a toy CLI around `curl` to an LLM
- a Python prototype later "ported" to Swift
- a chat box with shell access
- a vibe-coded clone of any existing tool

### 2.2 Zyquo IS

> A native Swift terminal agent runtime for macOS.
> The shell is the primary execution substrate.

Everything eventually becomes:

```text
Intent
  → planning
  → context assembly
  → tool proposal
  → risk classification
  → human-in-the-loop approval (when required)
  → execution (shell / fs / git / memory)
  → observation
  → verification
  → memory update
  → next step or termination
```

### 2.3 First Principles

1. **Transparency by default.** Every action the agent takes is renderable,
   reviewable, and revertible.
2. **Approval over autonomy.** Autonomy is earned per session via explicit
   trust escalation, never assumed.
3. **Locality over remoteness.** State lives on disk under `.zyquo/` and
   `~/Library/Application Support/Zyquo/`. The cloud is a tool, not a home.
4. **Composition over magic.** Tools are small, composable, typed, and
   sandboxable. The agent is a planner over tools, not a monolith.
5. **macOS is the substrate.** We do not pretend to be cross-platform in
   V1. We exploit Process, Keychain, FSEvents, XPC, Metal, and Foundation.
6. **The terminal is the canvas.** ANSI is a serious rendering target.
   Treat it like SwiftUI: declarative, theme-driven, responsive.

---

## 3. Required Research Phase

Before building Zyquo, you MUST deeply analyze:

- **OpenHands** — `github.com/All-Hands-AI/OpenHands` (formerly OpenDevin)
- **Cline** — `github.com/cline/cline`
- **OpenCode** — `github.com/sst/opencode` (and variants)

### 3.1 Inspection Procedure

For each repo:

```bash
cd research/repos/<repo>

# 1. Topology
find . -maxdepth 4 -type f \
  -not -path '*/node_modules/*' \
  -not -path '*/.git/*' \
  -not -path '*/dist/*' \
  -not -path '*/build/*' \
  | sort > ../../docs/research/<repo>_files.txt

# 2. Entry points
rg -n 'fn main|def main|func main|export default|module.exports' \
  > ../../docs/research/<repo>_entrypoints.txt

# 3. Prompt surfaces
rg -n 'system_prompt|SYSTEM_PROMPT|systemPrompt|<system>' \
  > ../../docs/research/<repo>_prompts.txt

# 4. Tool surfaces
rg -n 'tool|action|function_call|tool_use' \
  --type-add 'web:*.{ts,tsx,js,jsx}' \
  -t web -t py -t rust -t go \
  > ../../docs/research/<repo>_tools.txt
```

### 3.2 What to Read in Each Repo

- README and root-level docs
- architecture / design docs (often `/docs`, `/architecture`)
- source structure and module boundaries
- the tool system (registry, schemas, execution)
- the prompt system (system prompts, planner prompts, summarizers)
- the runtime loop (action selector, observation handler)
- the shell execution layer (sandboxing, streaming, kill semantics)
- state persistence (session format, replay capabilities)
- context handling (token budgeting, summarization, retrieval)
- memory handling (short-term, long-term, project, decision)
- approval logic (auto-approve lists, dangerous-command detection)
- patch system (diff generation, application, conflicts)
- terminal UX (renderer, theme, keymap)
- session handling (resume, fork, branch)
- provider abstraction (which LLMs, how routed)
- failure recovery (retries, fallback, rollback)
- sandboxing (Docker? VM? plain Process?)

### 3.3 What to Extract per Repo

For every repo produce a structured doc with the schema in §4. Be specific.
Cite filenames and line numbers. Quote sparingly (≤15 words). Paraphrase
liberally. The goal is *engineering intelligence*, not summary.

---

## 4. Research Output Files

You MUST generate:

```text
docs/research/OpenHands.md            # deep dive, ~3–5k words
docs/research/Cline.md                # deep dive, ~3–5k words
docs/research/OpenCode.md             # deep dive, ~3–5k words
docs/research/comparative_matrix.md   # the matrix in §5
docs/research/<repo>_files.txt        # one per repo
docs/research/<repo>_entrypoints.txt
docs/research/<repo>_prompts.txt
docs/research/<repo>_tools.txt
docs/zyquo_cli_architecture.md        # synthesized architecture
docs/zyquo_v1_plan.md                 # phase-by-phase V1 plan
docs/zyquo_v2_plan.md                 # phase-by-phase V2 plan
docs/zyquo_threat_model.md            # security model (§32)
docs/zyquo_prompts.md                 # canonical system prompts (§35)
docs/zyquo_tool_schemas.md            # JSON schemas for every tool
```

Each research doc MUST follow this schema:

```markdown
# <Repo Name>

## Overview
## Architecture diagram (ASCII)
## Module map
## Agent loop (sequence)
## Tool system
## Prompt surfaces
## Memory & context
## Shell execution
## Safety model
## Persistence
## UX surface
## Strengths (what Zyquo should reuse)
## Weaknesses (what Zyquo should avoid)
## Open questions
## Quotes / references (≤15 words each, with file:line)
```

---

## 5. Comparative Analysis

Create a detailed matrix in `docs/research/comparative_matrix.md`:

| Feature                   | OpenHands | Cline | OpenCode | **Zyquo Decision** |
| ------------------------- | --------- | ----- | -------- | ------------------ |
| Agent loop                |           |       |          |                    |
| Shell execution           |           |       |          |                    |
| Sandbox model             |           |       |          |                    |
| Context handling          |           |       |          |                    |
| Token budgeting           |           |       |          |                    |
| Summarization strategy    |           |       |          |                    |
| Diff review               |           |       |          |                    |
| Patch application         |           |       |          |                    |
| Rollback                  |           |       |          |                    |
| Tool system               |           |       |          |                    |
| Tool schema format        |           |       |          |                    |
| Memory architecture       |           |       |          |                    |
| Long-term memory          |           |       |          |                    |
| Session persistence       |           |       |          |                    |
| Session resume / branch   |           |       |          |                    |
| UX model                  |           |       |          |                    |
| TUI quality               |           |       |          |                    |
| Theming                   |           |       |          |                    |
| Safety / risk model       |           |       |          |                    |
| Approval ergonomics       |           |       |          |                    |
| macOS suitability         |           |       |          |                    |
| Performance (cold start)  |           |       |          |                    |
| Performance (first token) |           |       |          |                    |
| Multi-agent support       |           |       |          |                    |
| Local model support       |           |       |          |                    |
| Plugin / skill system     |           |       |          |                    |
| Observability             |           |       |          |                    |
| Failure recovery          |           |       |          |                    |

For each row explain in prose:

- **Reuse** — concepts, patterns, even structural ideas worth adopting
- **Redesign** — the right idea, wrong execution; Zyquo's variation
- **Avoid** — anti-patterns to explicitly reject

---

## 6. Zyquo Product Vision

Zyquo must feel like:

> Claude Code + Cline + OpenCode + Warp + Raycast + a Git-aware AI shell +
> a macOS-native developer cockpit.

The user experience must feel **premium and highly interactive**, on the
order of native Apple tooling — not a Python script with colored text.

### 6.1 Persona Targets

- **The Staff Engineer.** Wants control, diffs, surgical edits, no
  surprises. Lives in `nvim` + `tmux` + `lazygit`.
- **The Founder/CTO.** Wants velocity, scaffolding, refactors, "explain
  this repo I inherited."
- **The Researcher.** Wants reproducibility, transcripts, exportable
  sessions, citations.
- **The Indie Mac Dev.** Wants beauty, native polish, Keychain integration,
  zero config to start.

### 6.2 Non-Goals (V1)

- Cross-platform (Linux/Windows) parity — V2+
- Web UI / browser surface — V2+
- IDE plugin — V2+
- Cloud sync of memory — V2+
- Multi-user collaboration — V2+

---

## 7. Interactive Terminal Requirement

Zyquo MUST support:

```bash
zyquo                  # launches interactive REPL in cwd
zyquo interactive      # explicit form
zyquo chat             # alias
zyquo --resume <id>    # resume a previous session
zyquo --new            # force new session, ignore last
```

This launches a beautiful full interactive terminal UI.

The interface MUST include:

- colored boxes with rounded Unicode borders
- bordered panels with titles
- command cards with risk badges
- live streaming output (token-by-token for LLM, line-by-line for shell)
- syntax highlighting (TextMate grammars or tree-sitter, see §31)
- diff visualization (unified + side-by-side modes)
- task timelines with elapsed time and status
- status indicators (planning / executing / waiting / blocked / done)
- keyboard shortcuts (vim-style + emacs-style, configurable)
- interactive approval prompts (`[y]es / [n]o / [a]lways / [e]dit / [?]explain`)
- smooth rendering (no flicker, partial redraws, double-buffered)
- beautiful spacing (8 px grid analog: 1-col gutter, 2-col panel padding)
- responsive resizing (SIGWINCH handling, re-layout under 16 ms)

### 7.1 Rendering Contract

- All output goes through `TerminalRenderer`. Never `print()` directly
  outside the renderer.
- Renderer maintains a virtual buffer; diffs against the previous frame;
  emits only the minimal ANSI to converge.
- Renderer respects `NO_COLOR`, `CLICOLOR`, `TERM`, and `COLORTERM`.
- Renderer detects terminal capabilities (truecolor, 256-color, 16-color,
  monochrome) and degrades gracefully.

---

## 8. Interactive UI Style

Visual inspiration:

- **Warp** — command blocks, suggestion chips, modern typography feel
- **Claude Code** — calm spacing, surgical density, color discipline
- **lazygit** — panel choreography, keymap, status density
- **btop** — live data, smooth refresh, color gradients
- **modern TUIs** — `helix`, `gitui`, `zellij`
- **Raycast** — discoverability, keyboard-first, smart prompts
- **Apple terminal polish** — restraint, alignment, no clutter

### 8.1 Visual Discipline

- No emojis in default theme. (Themes MAY enable them; default does not.)
- No more than 3 hues + 2 neutrals + accent on any single frame.
- Box-drawing only via Unicode (`╭ ─ ╮ │ ╰ ╯`). No ASCII art fallback in
  modern terms; degrade to plain bars on `TERM=dumb`.
- Status badges are **single-word**, padded to fixed width per session for
  alignment stability.

---

## 9. Example Interactive Layout

```text
╭──────────────────────── Zyquo Agent ────────────────────────╮
│ Workspace: ~/Projects/MyApp       Model: Claude Sonnet 4.7  │
│ Mode: Interactive                  Status: Planning         │
│ Tokens: 12.4k / 200k              Session: zq_2026_05_a1b2  │
╰──────────────────────────────────────────────────────────────╯

╭─ User Intent ────────────────────────────────────────────────╮
│ Fix the failing tests and explain the issue.                │
╰──────────────────────────────────────────────────────────────╯

╭─ Plan ───────────────────────────────────────────────────────╮
│ 1. Inspect project structure                       [ pending ]│
│ 2. Run tests                                       [ pending ]│
│ 3. Analyze failures                                [ pending ]│
│ 4. Patch code                                      [ pending ]│
│ 5. Re-run tests                                    [ pending ]│
╰──────────────────────────────────────────────────────────────╯

╭─ Proposed Command ───────────────────────────────────────────╮
│ $ swift test                                                 │
│ Risk: SAFE                Estimated: ~12s                    │
│ Reason: read-only test execution within workspace            │
│ Approve? [y]es  [n]o  [a]lways for `swift test`  [?]explain  │
╰──────────────────────────────────────────────────────────────╯

╭─ Timeline ───────────────────────────────────────────────────╮
│ 0.0s  ▸ workspace scan                              done     │
│ 0.4s  ▸ context assembly                            done     │
│ 1.1s  ▸ plan synthesized                            done     │
│ 1.2s  ▸ step 1 / 5                                  active   │
╰──────────────────────────────────────────────────────────────╯
```

---

## 10. Slash Commands

Inside interactive mode, the prompt accepts slash commands. Slash commands
MUST be parseable before any LLM call and SHOULD NOT consume tokens.

### 10.1 Canonical Commands

| Command           | Purpose                                                              |
| ----------------- | -------------------------------------------------------------------- |
| `/help`           | Show command reference and current keymap                            |
| `/plan`           | Force replan with current context                                    |
| `/status`         | Show agent state, tokens, cost, active tools                         |
| `/memory`         | Open memory inspector (project / session / decisions)                |
| `/memory edit`    | Open project memory file in `$EDITOR`                                |
| `/diff`           | Show pending patches                                                 |
| `/apply [n]`      | Apply pending patch n (or all if omitted)                            |
| `/reject [n]`     | Reject pending patch n (or all if omitted)                           |
| `/model <name>`   | Switch model mid-session                                             |
| `/provider <id>`  | Switch provider                                                      |
| `/theme <name>`   | Switch theme                                                         |
| `/clear`          | Clear screen but preserve session state                              |
| `/reset`          | Reset agent state for next turn (keep memory)                        |
| `/history`        | Show command + tool history for session                              |
| `/session save`   | Force flush session to disk                                          |
| `/session fork`   | Branch current session into a new id                                 |
| `/session resume` | Pick a prior session to resume                                       |
| `/tools`          | List registered tools with risk levels                               |
| `/tools enable`   | Enable a tool for this session                                       |
| `/tools disable`  | Disable a tool for this session                                      |
| `/trust <scope>`  | Elevate trust (e.g. `/trust git push` for current repo)             |
| `/untrust`        | Revert all session trust elevations                                  |
| `/cancel`         | Cancel the in-flight tool / LLM call                                 |
| `/cost`           | Show cumulative token + dollar cost for session                      |
| `/export <fmt>`   | Export transcript (`md`, `json`, `jsonl`)                            |
| `/exit`           | Save session and exit                                                |

### 10.2 Parsing Rules

- Slash commands MUST be the *first* non-whitespace token of the line.
- Arguments after `--` are passed literally (no glob expansion).
- Unknown slash commands MUST NOT be forwarded to the LLM; show a
  did-you-mean suggestion using Damerau-Levenshtein distance ≤ 2.

---

## 11. Themes

### 11.1 Shipped Themes

| Theme            | Vibe                                            |
| ---------------- | ----------------------------------------------- |
| `zyquo-dark`     | Default. Cool neutral, signal-blue accents.     |
| `glass-terminal` | Translucent feel, low-contrast, muted.          |
| `xcode-dark`     | Xcode 16 palette mapping.                       |
| `minimal`        | Monochrome, single-accent, no boxes.            |
| `solarized`      | Solarized Dark canonical mapping.               |
| `nord`           | Nord palette.                                   |
| `tokyonight`     | Tokyo Night Storm mapping.                      |
| `high-contrast`  | Accessibility-first, 7:1 contrast minimum.      |

Default: `zyquo-dark`.

### 11.2 Theme Schema

Themes are TOML files under `~/.zyquo/themes/<name>.toml`:

```toml
name = "zyquo-dark"
truecolor = true

[colors]
bg            = "#0B0F14"
bg_panel      = "#0F141B"
fg            = "#D7DEE7"
fg_muted      = "#7A8693"
border        = "#1F2A37"
accent        = "#5BA8FF"
accent_strong = "#2F80ED"
ok            = "#4ADE80"
warn          = "#F59E0B"
risk          = "#EF4444"
critical      = "#B91C1C"

[syntax]
keyword  = "#9D7CFF"
string   = "#7DD3FC"
number   = "#F0ABFC"
comment  = "#566677"
type     = "#5EEAD4"
function = "#FBBF24"

[diff]
added     = "#163E2F"
added_fg  = "#A7F3D0"
removed   = "#3B1418"
removed_fg= "#FCA5A5"
context   = "#7A8693"
```

### 11.3 Theme Hot-Swap

`/theme <name>` MUST repaint the entire frame within 100 ms. No partial
swaps. No process restart.

---

## 12. UI Components

Build reusable terminal UI components under `Sources/Zyquo/UI/`:

```text
TerminalRenderer        // virtual buffer, diff, ANSI flush
Panel                   // titled, bordered region
Box                     // unfilled bordered region
StatusBadge             // pill-shaped colored label
Spinner                 // braille / dots / arc variants
ProgressBar             // determinate + indeterminate
TimelineView            // step list with elapsed time
CommandCard             // proposed command + risk + approval
DiffView                // unified + side-by-side
SyntaxHighlighter       // TextMate / tree-sitter backed
PromptInput             // line editor: history, completion, multiline
TaskView                // hierarchical task tree
ToolView                // tool invocation card (input/output collapsed)
ThemeEngine             // theme load, hot-swap, contrast checks
MarkdownRenderer        // streaming markdown → ANSI
CodeBlock               // detected + highlighted + line-numbered
Notification            // ephemeral toast in lower-right
ModalPicker             // fuzzy-pick over a list (sessions, tools, themes)
LayoutEngine            // flexbox-ish row/column with grow/shrink
KeymapOverlay           // press `?` to overlay current keymap
```

### 12.1 Component Contract

Every component conforms to:

```swift
public protocol Renderable {
    /// Render into a fixed region, returning the cells produced.
    func render(in region: Region, theme: Theme) -> CellBuffer

    /// Optional preferred size when given an available size.
    func sizeThatFits(_ available: Size) -> Size

    /// Whether the component animates (forces re-render on tick).
    var isAnimated: Bool { get }
}
```

### 12.2 Layout

The `LayoutEngine` MUST support:

- `Row` / `Column` containers with `grow`, `shrink`, `fixed` children
- min/max sizing
- terminal-resize triggered relayout under 16 ms for ≤120-cell width
- z-ordering for modals and notifications (top of stack wins)

---

## 13. Recommended Swift Libraries

Evaluate, then choose minimally:

- **Swift ArgumentParser** — Apple, stable, low risk. Use for CLI parsing.
- **Rainbow** — ANSI color convenience. Acceptable, but the renderer
  SHOULD own ANSI emission; Rainbow is optional sugar only.
- **SwiftTUI** — promising but evolving. Evaluate but do not depend on
  unstable APIs in V1.
- **TermKit** — older, full-featured. Evaluate for inspiration; do not
  ship as a hard dependency.
- **swift-log** — Apple, structured logging.
- **swift-metrics** — Apple, telemetry hooks.
- **swift-collections** — `OrderedDictionary`, `Deque`, `Heap`.
- **swift-system** — POSIX wrappers, file paths.
- **GRDB.swift** — SQLite-backed persistence (sessions, memory, vectors).
- **AsyncAlgorithms** — for streaming combinators.
- **Yams** — YAML parsing for config.
- **swift-toml** — TOML parsing for themes.
- **Highlightr** *or* **Splash** *or* tree-sitter Swift bindings — syntax.

> **Policy:** No dependency that is unmaintained > 18 months. No
> dependency that requires Objective-C runtime fragility. Vendor critical
> code if upstream is fragile.

If necessary: build an internal ANSI rendering engine. The renderer is
strategic infrastructure; treat it as first-party.

---

## 14. Core CLI Commands

```bash
zyquo                              # launch interactive in cwd
zyquo init                         # scaffold .zyquo/ in cwd
zyquo ask "explain this repo"      # single-shot Q&A (no tools)
zyquo run "fix failing tests"      # agentic run (tools enabled)
zyquo plan "add authentication"    # plan-only (no execution)
zyquo diff                         # show pending patches
zyquo apply [--all | <patch-id>]   # apply pending patches
zyquo reject [--all | <patch-id>]  # reject pending patches
zyquo memory                       # open memory inspector
zyquo memory edit                  # open project memory in $EDITOR
zyquo memory compact               # force compression pass
zyquo sessions                     # list sessions
zyquo sessions show <id>           # show a session
zyquo sessions resume <id>         # resume a session
zyquo sessions fork <id>           # fork a session
zyquo doctor                       # diagnostics: keys, perms, providers
zyquo config get <key>             # read config
zyquo config set <key> <value>     # write config
zyquo theme list                   # list themes
zyquo theme set <name>             # set default theme
zyquo tools list                   # list registered tools
zyquo provider list                # list providers
zyquo provider login <id>          # OAuth / API key entry into Keychain
zyquo version                      # version + build + provider versions
zyquo upgrade                      # self-update via Homebrew (if installed)
```

### 14.1 Global Flags

| Flag                  | Effect                                               |
| --------------------- | ---------------------------------------------------- |
| `--workspace <path>`  | Override workspace root                              |
| `--no-color`          | Disable ANSI color (equivalent to `NO_COLOR=1`)      |
| `--json`              | Machine-readable output (for scripting)              |
| `--yes`               | Auto-approve SAFE-tier actions only                  |
| `--dry-run`           | Plan but never execute                               |
| `--model <id>`        | Override session model                               |
| `--provider <id>`     | Override session provider                            |
| `--max-steps <n>`     | Hard cap on agent steps                              |
| `--max-cost <usd>`    | Hard cap on session cost                             |
| `--verbose`           | Increase log verbosity                               |
| `--quiet`             | Suppress non-essential output                        |
| `--log-file <path>`   | Mirror logs to file                                  |

### 14.2 Exit Codes

| Code | Meaning                                              |
| ---: | ---------------------------------------------------- |
|    0 | Success                                              |
|    1 | Generic error                                        |
|    2 | Usage error (invalid flags/args)                     |
|    3 | Config error                                         |
|    4 | Provider error (auth, rate limit, network)           |
|    5 | Tool error                                           |
|    6 | Approval denied / user cancellation                  |
|    7 | Risk budget exceeded                                 |
|    8 | Workspace boundary violation                         |
|    9 | Persistence error                                    |
|   10 | Plugin error                                         |
|  130 | SIGINT (Ctrl-C)                                      |

---

## 15. Project Structure

```text
ZyquoCLI/
├── Package.swift
├── README.md
├── CLAUDE.md
├── LICENSE
├── Makefile
├── .swift-version
├── .swiftformat
├── .swiftlint.yml
│
├── Sources/
│   ├── Zyquo/                          # executable target
│   │   ├── main.swift
│   │   ├── AppContainer.swift          # DI root
│   │   ├── Bootstrap.swift             # cold-start fast path
│   │   │
│   │   ├── Commands/
│   │   │   ├── InitCommand.swift
│   │   │   ├── AskCommand.swift
│   │   │   ├── RunCommand.swift
│   │   │   ├── PlanCommand.swift
│   │   │   ├── DiffCommand.swift
│   │   │   ├── ApplyCommand.swift
│   │   │   ├── RejectCommand.swift
│   │   │   ├── MemoryCommand.swift
│   │   │   ├── SessionsCommand.swift
│   │   │   ├── DoctorCommand.swift
│   │   │   ├── ConfigCommand.swift
│   │   │   ├── ThemeCommand.swift
│   │   │   ├── ToolsCommand.swift
│   │   │   ├── ProviderCommand.swift
│   │   │   └── InteractiveCommand.swift
│   │   │
│   │   ├── Agent/
│   │   │   ├── AgentLoop.swift
│   │   │   ├── AgentState.swift
│   │   │   ├── AgentStep.swift
│   │   │   ├── Planner.swift
│   │   │   ├── Executor.swift
│   │   │   ├── Verifier.swift
│   │   │   ├── Orchestrator.swift
│   │   │   ├── ContextAssembler.swift
│   │   │   ├── TokenBudget.swift
│   │   │   ├── Summarizer.swift
│   │   │   └── StopConditions.swift
│   │   │
│   │   ├── Tools/
│   │   │   ├── Tool.swift              # protocol
│   │   │   ├── ToolRegistry.swift
│   │   │   ├── ToolSchema.swift
│   │   │   ├── ShellTool.swift
│   │   │   ├── FileReadTool.swift
│   │   │   ├── FileWriteTool.swift
│   │   │   ├── FilePatchTool.swift
│   │   │   ├── FileListTool.swift
│   │   │   ├── SearchTool.swift        # ripgrep wrapper
│   │   │   ├── GitTool.swift
│   │   │   ├── MemoryTool.swift
│   │   │   ├── PlanTool.swift
│   │   │   ├── VerifyTool.swift
│   │   │   └── NotifyTool.swift
│   │   │
│   │   ├── Shell/
│   │   │   ├── ShellExecutor.swift
│   │   │   ├── CommandResult.swift
│   │   │   ├── ShellSession.swift
│   │   │   ├── PTYHost.swift           # PTY-backed exec for TUIs
│   │   │   ├── RiskClassifier.swift
│   │   │   ├── DangerRules.swift
│   │   │   ├── CommandHistory.swift
│   │   │   └── EnvironmentMask.swift
│   │   │
│   │   ├── Workspace/
│   │   │   ├── Workspace.swift
│   │   │   ├── WorkspaceIndex.swift
│   │   │   ├── ProjectDetector.swift
│   │   │   ├── RepoAnalyzer.swift
│   │   │   ├── FileSnapshot.swift
│   │   │   ├── Ignore.swift            # .gitignore + .zyquoignore
│   │   │   └── BoundaryGuard.swift
│   │   │
│   │   ├── Memory/
│   │   │   ├── SessionMemory.swift
│   │   │   ├── ProjectMemory.swift
│   │   │   ├── DecisionMemory.swift
│   │   │   ├── MemoryCompressor.swift
│   │   │   ├── MemoryRetriever.swift
│   │   │   └── MemorySchema.swift
│   │   │
│   │   ├── Models/
│   │   │   ├── LLMProvider.swift       # protocol
│   │   │   ├── AnthropicProvider.swift
│   │   │   ├── OpenRouterProvider.swift
│   │   │   ├── LocalProvider.swift     # V2
│   │   │   ├── ModelRouter.swift
│   │   │   ├── ModelCatalog.swift
│   │   │   ├── Pricing.swift
│   │   │   └── StreamingDecoder.swift
│   │   │
│   │   ├── Diff/
│   │   │   ├── DiffEngine.swift
│   │   │   ├── PatchEngine.swift
│   │   │   ├── ChangeSet.swift
│   │   │   ├── HunkParser.swift
│   │   │   └── ConflictResolver.swift
│   │   │
│   │   ├── UI/
│   │   │   ├── TerminalRenderer.swift
│   │   │   ├── CellBuffer.swift
│   │   │   ├── Region.swift
│   │   │   ├── Panel.swift
│   │   │   ├── Box.swift
│   │   │   ├── Theme.swift
│   │   │   ├── ThemeEngine.swift
│   │   │   ├── CommandCard.swift
│   │   │   ├── DiffView.swift
│   │   │   ├── Spinner.swift
│   │   │   ├── ProgressBar.swift
│   │   │   ├── TimelineView.swift
│   │   │   ├── StatusBadge.swift
│   │   │   ├── SyntaxHighlighter.swift
│   │   │   ├── MarkdownRenderer.swift
│   │   │   ├── CodeBlock.swift
│   │   │   ├── PromptInput.swift
│   │   │   ├── ModalPicker.swift
│   │   │   ├── Notification.swift
│   │   │   ├── KeymapOverlay.swift
│   │   │   └── LayoutEngine.swift
│   │   │
│   │   ├── Persistence/
│   │   │   ├── SessionStore.swift
│   │   │   ├── MemoryStore.swift
│   │   │   ├── ConfigStore.swift
│   │   │   ├── PatchStore.swift
│   │   │   ├── SnapshotStore.swift
│   │   │   └── DB.swift                # GRDB wrapper
│   │   │
│   │   ├── Security/
│   │   │   ├── Keychain.swift
│   │   │   ├── Sandbox.swift
│   │   │   ├── Redaction.swift         # PII / secret scrubbing
│   │   │   └── AuditLog.swift
│   │   │
│   │   ├── Observability/
│   │   │   ├── Logger.swift
│   │   │   ├── Metrics.swift
│   │   │   ├── Tracing.swift
│   │   │   └── CrashReporter.swift
│   │   │
│   │   ├── Util/
│   │   │   ├── AsyncStreams.swift
│   │   │   ├── Throttle.swift
│   │   │   ├── Backoff.swift
│   │   │   ├── Diffable.swift
│   │   │   └── Clock.swift
│   │   │
│   │   └── Errors/
│   │       ├── ZyquoError.swift
│   │       ├── ProviderError.swift
│   │       ├── ToolError.swift
│   │       └── ShellError.swift
│   │
│   └── ZyquoCore/                      # library target (testable, reusable)
│
├── Tests/
│   ├── ZyquoTests/
│   ├── ZyquoCoreTests/
│   └── Snapshots/                      # snapshot tests for TUI frames
│
├── docs/
│   ├── research/
│   ├── zyquo_cli_architecture.md
│   ├── zyquo_v1_plan.md
│   ├── zyquo_v2_plan.md
│   ├── zyquo_threat_model.md
│   ├── zyquo_prompts.md
│   └── zyquo_tool_schemas.md
│
├── research/
│   └── repos/                          # cloned source for analysis
│
├── scripts/
│   ├── build-release.sh
│   ├── sign-and-notarize.sh
│   ├── bench.sh
│   └── update-models.sh
│
└── Resources/
    ├── themes/                         # shipped TOML themes
    ├── grammars/                       # tree-sitter grammars
    └── prompts/                        # canonical prompts (markdown)
```

---

## 16. Agent Runtime

### 16.1 Canonical Loop

```text
intent
  ↓
workspace scan (cached, invalidated by FSEvents)
  ↓
context assembly (project memory + session memory + retrieved chunks)
  ↓
token budget check (compress / drop / summarize if over budget)
  ↓
planning (Planner.plan(intent, context) -> Plan)
  ↓
for step in plan.steps:
    tool proposal (Planner.propose(step, state) -> ToolCall)
      ↓
    risk classification (RiskClassifier.classify(toolCall) -> RiskLevel)
      ↓
    approval gate (skip if SAFE && auto-approve; else prompt)
      ↓
    execution (Executor.execute(toolCall) -> Observation)
      ↓
    observation appended to state
      ↓
    verification (Verifier.verify(step, observation) -> VerdictE)
      ↓
    memory update (session + decisions)
      ↓
    stop check (success / blocked / budget / user cancel)
  ↓
summarization (Summarizer.finalize(state) -> SessionSummary)
  ↓
persist (SessionStore.flush, MemoryStore.flush)
```

Every action MUST be visible in the terminal. No hidden autonomous
behavior. The agent MUST emit a UI event for every state transition.

### 16.2 Agent State

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
    public var status: AgentStatus      // planning, executing, blocked, done
    public var startedAt: Date
    public var updatedAt: Date
}

public struct AgentStep: Sendable, Identifiable {
    public let id: StepID
    public let index: Int
    public let goal: String
    public var toolCall: ToolCall?
    public var observation: Observation?
    public var verdict: Verdict?
    public var risk: RiskLevel?
    public var approvedBy: ApprovalSource?
    public var startedAt: Date?
    public var finishedAt: Date?
}
```

### 16.3 Stop Conditions

Hard stops (cannot be overridden in-session):

- max steps reached (`--max-steps`, default 40)
- max cost reached (`--max-cost`)
- user cancellation (`Ctrl-C`, `/cancel`, `/exit`)
- workspace boundary violation detected
- 3 consecutive tool failures on the same step

Soft stops (agent may ask to continue):

- plan completed with all verifications passing
- 5 consecutive low-confidence verifications
- detected loop (same toolCall hash repeated 3× in window of 5)

---

## 17. Tool System

### 17.1 Core Tools (V1)

| Tool                | Risk default | Purpose                                       |
| ------------------- | ------------ | --------------------------------------------- |
| `shell.run`         | per-command  | Execute shell command (zsh by default)        |
| `file.read`         | SAFE         | Read file (size-capped, encoding-detected)    |
| `file.write`        | MODERATE     | Write/overwrite file (always via patch)       |
| `file.patch`        | MODERATE     | Apply unified diff                            |
| `file.list`         | SAFE         | List dir (gitignore-aware)                    |
| `file.search`       | SAFE         | Ripgrep-backed search                         |
| `git.status`        | SAFE         | Read git status                               |
| `git.diff`          | SAFE         | Read git diff                                 |
| `git.commit`        | MODERATE     | Stage + commit (never push by default)        |
| `git.branch`        | MODERATE     | Create/switch branches                        |
| `workspace.index`   | SAFE         | Trigger / inspect index                       |
| `memory.read`       | SAFE         | Read project/session memory                   |
| `memory.write`      | SAFE         | Append to project/session memory              |
| `task.plan`         | SAFE         | Replan with current state                     |
| `task.verify`       | SAFE         | Verify a step's success criteria              |
| `notify.user`       | SAFE         | Post a UI notification / question             |

### 17.2 Tool Protocol

```swift
public protocol Tool: Sendable {
    /// Stable identifier, e.g. "shell.run".
    var name: String { get }

    /// Human-readable single sentence shown in /tools list.
    var summary: String { get }

    /// Longer markdown shown in help, hover, and prompts.
    var documentation: String { get }

    /// JSON Schema for the input — used both to validate calls and to
    /// populate the LLM tool schema.
    var inputSchema: JSONSchema { get }

    /// Static default risk; per-call risk may be elevated.
    var defaultRisk: RiskLevel { get }

    /// Whether the tool mutates filesystem, network, or workspace state.
    var isMutating: Bool { get }

    /// Execute the tool. Implementations MUST be cancellable via Task.
    func execute(
        input: ToolInput,
        context: ToolContext
    ) async throws -> ToolResult
}

public struct ToolContext: Sendable {
    public let workspace: Workspace
    public let session: SessionID
    public let logger: Logger
    public let approval: ApprovalGate
    public let metrics: Metrics
    public let clock: any Clock
}

public struct ToolResult: Sendable {
    public let summary: String          // 1-3 lines for UI + LLM
    public let payload: JSONValue       // structured output
    public let artifacts: [Artifact]    // produced files, diffs, etc.
    public let durationMs: Int
    public let tokenHint: Int           // estimated tokens if echoed
}
```

### 17.3 Tool Registry

- Registration is explicit at boot via `AppContainer`.
- Tools are looked up by stable name; missing tools fail loudly.
- Per-session enable/disable mutates a session-scoped view, never the
  global registry.
- V2 plugin tools register through a sandboxed loader (§30).

### 17.4 Tool Result Echoing Policy

- LLM sees `summary` always, `payload` only if `tokenHint < budget.tail`.
- Large payloads are stored as artifacts and referenced by ID.
- Binary outputs are never echoed; only metadata.

---

## 18. Shell Execution

### 18.1 Execution Stack

```text
ShellTool
  └── ShellExecutor
        └── Process (Foundation)
              ├── stdin Pipe
              ├── stdout Pipe (line-buffered, streamed)
              ├── stderr Pipe (line-buffered, streamed)
              └── env (allow-list + masks via EnvironmentMask)
```

### 18.2 Capabilities

- stdout streaming (line + byte modes)
- stderr streaming
- combined output preservation order
- cancellation via `Task.cancel` → `SIGTERM` → `SIGKILL` after 5 s
- timeout (default 120 s, configurable per call)
- environment control (allow-list; never inherit `SSH_*`, `*_TOKEN`,
  `*_SECRET`, `*_KEY` unless explicitly granted)
- cwd isolation (must be inside workspace unless explicitly approved)
- exit code + signal capture
- structured command log (entry, exit, duration, bytes, signal)

### 18.3 Shell Selection

- Default: `/bin/zsh -c -l <command>`
- Fallback: `/bin/bash -c <command>` if zsh unavailable
- Profile loading is **off by default** to avoid env pollution; opt-in via
  `tool.shell.load_profile = true`
- PATH is sanitized: user PATH ∩ allow-list, plus Homebrew prefix
  detection (`/opt/homebrew/bin` on arm64, `/usr/local/bin` on x86_64)

### 18.4 PTY Mode

For interactive subcommands (e.g. `vim`, `htop`, `npm init`), Zyquo MUST
support PTY-backed execution via `PTYHost`. PTY mode disables LLM
observation streaming during the foreground attach and resumes after
detach.

---

## 19. Dangerous Command Detection

### 19.1 Risk Tiers

| Tier        | Examples                                                |
| ----------- | ------------------------------------------------------- |
| `SAFE`      | `ls`, `cat`, `git status`, `swift test`, `rg`           |
| `MODERATE`  | `git commit`, `npm install` (local), file writes        |
| `DANGEROUS` | `rm -rf <path>`, `chmod -R`, `mv` across paths, `find ... -delete` |
| `CRITICAL`  | `sudo`, `curl ... \| sh`, `git push`, `diskutil`, `launchctl`, global installs |

### 19.2 Detection Rules

Encoded in `Shell/DangerRules.swift`. Examples (regex, illustrative):

```text
CRITICAL:
  ^\s*sudo\b
  \bcurl\s+[^|]*\|\s*(sh|bash|zsh)\b
  \bwget\s+[^|]*\|\s*(sh|bash|zsh)\b
  \bgit\s+push\b
  \bgit\s+reset\s+--hard\b
  \bdiskutil\b
  \blaunchctl\b
  \bnpm\s+install\s+-g\b
  \byarn\s+global\s+add\b
  \bpnpm\s+add\s+-g\b
  \bbrew\s+install\b

DANGEROUS:
  \brm\s+-[rR]f?\b
  \bchmod\s+-R\b
  \bchown\s+-R\b
  \bmv\s+/[^ ]+\s+/[^ ]+
  \bfind\b.*-delete\b
  >\s*/dev/(disk|rdisk)
  \bdd\s+if=

MODERATE:
  \bgit\s+commit\b
  \bgit\s+(checkout|switch|branch)\b.*-D?\b
  \bnpm\s+install\b
  \byarn\s+install\b
  \bpnpm\s+install\b
  \bcargo\s+install\b
  \bpip\s+install\b
  >\s*[^ &|]+        # any redirect-write
  >>\s*[^ &|]+
```

### 19.3 Path-Based Escalation

Any command touching a path **outside** `Workspace.root` is escalated by
one tier (SAFE→MODERATE, MODERATE→DANGEROUS, …).

Any command touching `~/Library`, `~/.ssh`, `~/.aws`, `~/.config`, or
system paths (`/System`, `/Library`, `/private`, `/usr` excl. `/usr/local`)
is `CRITICAL` regardless of other rules.

### 19.4 Approval Persistence

Approvals are scoped:

- `once` — this invocation only
- `session` — until session ends
- `workspace` — persisted in `.zyquo/trust.json`
- `global` — persisted in `~/.zyquo/trust.json` (CRITICAL never qualifies)

Trust grants are revocable via `/untrust` and listed in `/status`.

---

## 20. File Editing Model

Inspired heavily by Cline. **All writes go through patches.**

### 20.1 Workflow

```text
proposed write
  ↓
snapshot pre-image (SnapshotStore)
  ↓
generate unified diff (DiffEngine)
  ↓
render diff (DiffView)
  ↓
risk classify (per file: SAFE for new, MODERATE for modify, DANGEROUS for delete)
  ↓
approval gate
  ↓
apply patch (PatchEngine.apply, atomic write via temp + rename)
  ↓
record patch (PatchStore: id, files, hunks, applied_at)
  ↓
update workspace index
  ↓
emit UI event
```

### 20.2 Patch IDs

Patch IDs are `zp_<yyyymmdd>_<short-uuid>` and are stable across resume.

### 20.3 Multi-File Patches

A single agent step MAY produce a `ChangeSet` covering multiple files.
Approval is per-changeset, but the user MAY drill into individual file
diffs and reject any subset. Rejecting a subset reduces the changeset and
re-prompts.

### 20.4 Conflict Handling

If the on-disk pre-image hash differs from the recorded pre-image, the
patch is **stale**. Zyquo MUST:

1. Re-snapshot
2. Attempt 3-way merge (`DiffEngine.threeWayMerge`)
3. If clean → re-render and re-approve
4. If conflict → present conflict resolver (`ConflictResolver`)

### 20.5 Rollback

Every applied patch produces a reverse patch persisted next to it.
`/reject <id>` after apply triggers reverse apply.

---

## 21. Diff Rendering

Diffs MUST render beautifully and informatively.

### 21.1 Unified View

```text
╭─ Sources/Auth.swift  ·  ~/Projects/MyApp ────────────────────╮
│ @@ -42,7 +42,7 @@ struct AuthManager {                       │
│                                                              │
│      func login(_ user: String, _ pass: String) async {      │
│  -       let loggedIn = false                                │
│  +       let loggedIn = authManager.isAuthenticated          │
│          notify(.loggedIn(loggedIn))                         │
│      }                                                       │
╰── 1 hunk · −1 / +1 lines ────────────────────────────────────╯
```

### 21.2 Side-by-Side View

Toggleable with `[s]` in the diff modal. Wraps soft at terminal/2.

### 21.3 Coloring

- removed lines: theme `diff.removed` bg + `diff.removed_fg` fg
- added lines: theme `diff.added` bg + `diff.added_fg` fg
- context: theme `diff.context`
- intra-line diff: bolder hue on changed token (use Myers minimal-edit
  on word tokens)

### 21.4 File Summary

Before the hunks, render:

```text
3 files changed · +24 / −12 · 2 risk MODERATE · 1 risk DANGEROUS
```

---

## 22. Workspace Intelligence

When opening a repo, Zyquo MUST detect:

- VCS (`.git`, `.hg`, `.svn`)
- primary language(s) by file count + size weighting
- framework(s):
    - Swift: Package.swift, Xcode project, Tuist, SwiftPM
    - Node: package.json + lockfile flavor (npm / yarn / pnpm / bun)
    - Python: pyproject.toml, requirements.txt, poetry.lock, uv.lock
    - Rust: Cargo.toml, workspaces
    - Go: go.mod, workspaces
    - Ruby: Gemfile
    - Elixir: mix.exs
    - Java/Kotlin: build.gradle(.kts), pom.xml
- package manager
- test command (cached in project memory)
- build command
- format/lint command
- run command(s)
- git status (clean? branch? upstream? ahead/behind?)
- large directories (`node_modules`, `vendor`, `.venv`, `target`,
  `DerivedData`, `Pods`)
- generated code patterns (e.g. `*.pb.go`, `*_generated.swift`)
- documentation (README, ARCHITECTURE.md, CONTRIBUTING.md)

Results are stored in `WorkspaceIndex` and surfaced in:

- `zyquo open .` startup card
- `ProjectMemory` (auto-written on first scan, hand-editable thereafter)

### 22.1 Scan Performance Budget

- Cold scan of a 50k-file repo: < 3 s (without contents, just metadata)
- Warm scan (cache valid): < 200 ms
- Background incremental update via FSEvents: < 50 ms per batch

### 22.2 .zyquoignore

In addition to `.gitignore`, Zyquo respects `.zyquoignore` for paths the
agent should never read or modify. Default content scaffolded by
`zyquo init`:

```gitignore
.env
.env.*
*.pem
*.key
*.p12
*.mobileprovision
Pods/
DerivedData/
.build/
node_modules/
.venv/
target/
```

---

## 23. Memory System

### 23.1 Layout

Project-local:

```text
.zyquo/
├── config.json                 # workspace-scoped config
├── trust.json                  # workspace trust grants
├── memory/
│   ├── project.md              # human-editable, high-signal
│   ├── architecture.md         # auto-generated, hand-edited
│   ├── decisions.md            # append-only ADR-like log
│   └── sessions/
│       └── zq_2026_05_a1b2.jsonl
├── snapshots/
│   └── <sha>.gz                # pre-image content-addressed
├── patches/
│   ├── <patch-id>.patch
│   └── <patch-id>.reverse.patch
├── plans/
│   └── <session-id>.json
├── logs/
│   └── <session-id>.log
└── index/
    └── workspace.sqlite        # GRDB
```

Global:

```text
~/.zyquo/
├── config.toml                 # global config
├── themes/                     # user themes
├── providers.json              # provider metadata
├── trust.json                  # global trust grants
└── ~/Library/Application Support/Zyquo/
    └── keychain-tag.txt        # marker, real secrets live in Keychain
```

### 23.2 Memory Layers

| Layer        | Lifetime          | Source                                        |
| ------------ | ----------------- | --------------------------------------------- |
| **Session**  | Per session       | Tool calls, observations, planner notes       |
| **Project**  | Persistent        | Architecture, conventions, test commands      |
| **Decision** | Append-only       | ADRs the agent (with approval) wrote          |
| **Compressed long-term** | Persistent | Summaries the compressor emits         |

### 23.3 Compression

`MemoryCompressor` runs:

- after each session ends
- on demand via `/memory compact` or `zyquo memory compact`
- when token budget for context > 70 % of model window

Strategy:

1. Cluster events by (file touched, tool, intent topic).
2. Summarize per cluster into ≤ 200 tokens.
3. Preserve verbatim: decisions, errors, user-issued instructions.
4. Replace clustered raw events with summary pointer (`<<see cluster
   id=...>>`).

### 23.4 Retrieval

`MemoryRetriever` exposes:

```swift
public protocol MemoryRetriever: Sendable {
    func recall(
        query: String,
        scope: MemoryScope,         // .session, .project, .decisions, .all
        limit: Int
    ) async throws -> [MemoryChunk]
}
```

V1: lexical (BM25-ish over SQLite FTS5).
V2: hybrid (FTS5 + local embeddings, §30 phase 3).

### 23.5 Hand-Editable Memory

`project.md` is sacred. Zyquo:

- never overwrites it; only proposes patches via the diff workflow
- preserves user comments and order
- treats user-added sections as ground truth (rank > agent-written)

---

## 24. Multi-Agent V2

Future specialized agents (V2 phase 1):

| Agent             | Role                                                    |
| ----------------- | ------------------------------------------------------- |
| `ArchitectAgent`  | Long-horizon design, ADRs, structural refactors         |
| `CoderAgent`      | Per-task implementation, narrow scope, fast loop        |
| `ShellAgent`      | Build/test/CI orchestration                             |
| `ReviewerAgent`   | Diff review, style, conventions, regression scanning    |
| `ResearchAgent`   | Doc + web search, citation, knowledge extraction        |
| `VerifierAgent`   | Test execution, output parsing, success/failure proof   |

The `Orchestrator` decomposes the user intent into subtasks, delegates
each to the appropriate agent, and reconciles results into a single
ChangeSet for approval.

---

## 25. Model Providers

### 25.1 Supported

| Provider      | V1  | Notes                                              |
| ------------- | --- | -------------------------------------------------- |
| Anthropic     | ✅   | Primary. Messages API, streaming, tool use.        |
| OpenRouter    | ✅   | Catalog passthrough, routing, fallback.            |
| OpenAI        | (V1+) | Optional; same shape as Anthropic.              |
| Local (llama.cpp) | V2 | GGUF, Metal acceleration.                        |
| Apple Foundation Models | V2 | When/if API surface is stable on macOS.    |

### 25.2 Provider Protocol

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

### 25.3 Key Storage

API keys MUST live in the macOS Keychain via `Security.framework`:

- Service: `dev.zyquo.cli`
- Account: `<provider-id>` (e.g. `anthropic`, `openrouter`)
- Access: `kSecAttrAccessibleWhenUnlocked`
- Synchronizable: false

Zyquo SHOULD NOT read environment variables for keys by default, to avoid
shell-history leakage. Opt-in flag: `--allow-env-keys`.

`zyquo provider login <id>` prompts and stores via Keychain.
`zyquo provider logout <id>` deletes.
`zyquo doctor` audits Keychain entries without revealing secrets.

### 25.4 Model Routing

`ModelRouter` decides which model to use per-call based on:

- task class (planning vs coding vs summarization vs verification)
- token budget remaining
- cost ceiling
- latency target
- explicit user override (`--model`)

V1 default policy:

```text
planning        → Claude Opus 4.7
coding          → Claude Sonnet 4.6
summarization   → Claude Haiku 4.5
verification    → Claude Sonnet 4.6
```

Routing decisions are logged for transparency.

---

## 26. V1 Scope

Build first:

- interactive terminal UI (§7–§12)
- Anthropic provider (§25)
- OpenRouter provider
- shell execution (§18)
- risk classification (§19)
- approval prompts (§19.4)
- file reads (§17)
- patch proposals (§20)
- diff rendering (§21)
- workspace indexing (§22)
- project memory (§23)
- session persistence (§23, §27)
- beautiful colored interface (§8–§12)
- core slash commands (§10)
- 3 themes minimum (`zyquo-dark`, `minimal`, `high-contrast`)
- Homebrew tap (formula committed; signing + notarization scripts)
- `zyquo doctor` end-to-end
- snapshot tests for TUI frames
- integration tests against a fixture repo

---

## 27. V2 Scope

Later add:

- subagents (§24)
- semantic search (AST + tree-sitter)
- embeddings (local + cloud)
- background indexing (FSEvents-driven)
- local models (llama.cpp / Apple Foundation Models)
- reusable skills (§30 phase 6)
- plugin system (signed, sandboxed)
- distributed execution (cluster, §30 phase 9)
- parallel agents
- Homebrew bottle automation
- web companion (read-only mirror of sessions)
- Raycast extension that talks to a running Zyquo daemon
- macOS menu bar app (status-only, no LLM in process)

---

## 28. Final Requirement

Do not create a toy project.
Do not create a simple chatbot CLI.
Build a real:

> macOS-native AI terminal runtime.

The final product should feel like:

> Claude Code + Cline + OpenCode + Warp + Raycast + native Apple
> engineering quality

with:

- beautiful terminal UI
- persistent memory
- safe execution
- deep repo intelligence
- interactive workflows
- native Swift performance

---

# 29. Zyquo V1 — Ultra Detailed Implementation Phases

V1 objective:

> Build a production-quality native macOS AI terminal agent with:
> interactive UI, shell execution, repo understanding, diff review,
> memory, approvals, persistent sessions. Do NOT rush architecture.
> Build foundations correctly.

Each phase below includes: **Goal**, **Tasks**, **Files**, **Acceptance
Criteria**, **Performance Budget**, and **Test Matrix**.

---

## V1 — Phase 1 · Foundation & CLI Runtime

### Goal

Create the base Swift CLI architecture.

### Tasks

- initialize Swift Package (executable + library targets)
- configure `Package.swift` with platform = macOS 14
- enable strict concurrency (`-strict-concurrency=complete`)
- set up folder structure (§15)
- dependency injection (`AppContainer`)
- config system (TOML + env override + flags)
- structured logging (`swift-log` + JSONL file sink)
- error taxonomy (§39)
- env loading (`.env` opt-in, not default)
- command registry (ArgumentParser subcommands)
- terminal renderer foundation (CellBuffer + naive flush)
- signal handling (SIGINT, SIGTERM, SIGWINCH)
- crash reporter (writes minidump-like JSON to `~/Library/Logs/Zyquo/`)

### Files

```text
Package.swift
Sources/Zyquo/main.swift
Sources/Zyquo/Bootstrap.swift
Sources/Zyquo/AppContainer.swift
Sources/Zyquo/Util/Config.swift
Sources/Zyquo/Observability/Logger.swift
Sources/Zyquo/Util/Environment.swift
Sources/Zyquo/Commands/CommandRegistry.swift
Sources/Zyquo/UI/TerminalRenderer.swift
Sources/Zyquo/UI/CellBuffer.swift
Sources/Zyquo/Errors/ZyquoError.swift
```

### Requirements

- fast startup
- modular architecture
- async-ready
- macOS optimized
- Swift concurrency enabled

### Acceptance Criteria

- `zyquo --help` works cleanly
- `zyquo version` prints version + git sha + build date
- `zyquo doctor` prints a checklist (even if most items fail at this phase)
- Process exit codes follow §14.2
- All log lines are valid JSON when `--log-file` is set

### Performance Budget

- cold start (`zyquo --help`): < 120 ms on M-series, < 250 ms on Intel
- binary size (release, stripped): < 25 MB
- memory at idle (`zyquo` no input): < 30 MB RSS

### Test Matrix

- unit tests for `Config` precedence (flag > env > file > default)
- unit tests for `CommandRegistry` dispatch
- snapshot test for `--help` output (golden file)
- fuzz test for arg parsing

---

## V1 — Phase 2 · Beautiful Interactive Terminal Engine

### Goal

Build the premium interactive terminal system.

### Tasks

- ANSI renderer with truecolor + 256 + 16-color degradation
- virtual buffer + diff flush
- terminal capability detection
- panel renderer with rounded Unicode borders
- box renderer
- color engine bound to theme
- terminal resize (SIGWINCH) with debounced relayout
- raw mode toggle + restore on exit (`atexit` + signal traps)
- keyboard input loop with escape-sequence decoding
- streaming renderer (token-by-token, partial flush)
- cursor management (save/restore, hide/show)
- spinner system (braille, dots, arc, line)
- progress bars (determinate, indeterminate, throbber)
- markdown rendering (CommonMark subset → ANSI)
- syntax highlighting (Splash or tree-sitter)
- diff colors + intra-line highlight
- timeline rendering
- modal picker (fuzzy match over list)
- notification toast
- keymap overlay

### Components

```text
TerminalRenderer · Panel · Box · Theme · StatusBadge ·
Spinner · ProgressBar · TimelineView · DiffView ·
MarkdownRenderer · ModalPicker · Notification · KeymapOverlay ·
LayoutEngine
```

### Acceptance Criteria

- `zyquo interactive` launches a premium interface
- resizing the terminal triggers full relayout within 16 ms
- pressing `?` overlays the keymap
- `Ctrl-C` cancels current in-flight op without exiting (unless at idle)
- `q` / `Ctrl-D` at idle exits cleanly and restores terminal state
- snapshot tests for ≥ 20 frames pass byte-for-byte

### Performance Budget

- first paint after launch: < 200 ms
- frame render (no LLM): < 8 ms p95
- streaming append: < 2 ms per token
- memory at interactive idle: < 60 MB RSS

### Test Matrix

- snapshot tests per component (Region 80×24 default fixture)
- terminal capability fuzz (TERM=dumb, vt100, xterm-256color, xterm-truecolor)
- Unicode width tests (CJK, emoji, ZWJ, combining marks)
- regression test for SIGWINCH storm (resize 100×/sec for 1 s)

---

## V1 — Phase 3 · Model Provider Layer

### Goal

Create unified LLM abstraction layer.

### Tasks

- Anthropic Messages API client (streaming via SSE)
- OpenRouter client (catalog-aware)
- token streaming + structured event emission
- retry with exponential backoff + jitter (max 3 retries)
- timeout handling (per request + per stream-idle)
- request logging (redacted)
- model router policy (§25.4)
- token usage capture (input, output, cache hit/miss)
- pricing tracker (per-model rate × tokens)
- provider failover (Anthropic → OpenRouter Anthropic-shape mirror)
- cancellation propagation (Task → URLSession data task)
- tool-use protocol plumbing (request and response shapes)

### Files

```text
Sources/Zyquo/Models/LLMProvider.swift
Sources/Zyquo/Models/AnthropicProvider.swift
Sources/Zyquo/Models/OpenRouterProvider.swift
Sources/Zyquo/Models/ModelRouter.swift
Sources/Zyquo/Models/ModelCatalog.swift
Sources/Zyquo/Models/Pricing.swift
Sources/Zyquo/Models/StreamingDecoder.swift
```

### Acceptance Criteria

- `zyquo ask "hello"` returns a streamed response, token-by-token, with
  a visible spinner and partial render
- `zyquo provider login anthropic` stores a key in Keychain
- `zyquo doctor` reports provider auth status without revealing secrets
- Rate limit (HTTP 429) triggers backoff with visible UI status
- Cancellation via `Ctrl-C` aborts the HTTP stream within 200 ms

### Performance Budget

- first-token latency on warm cache (Claude Sonnet): < 800 ms p50
- streaming throughput: provider-bound (no Zyquo overhead > 1 % CPU)
- HTTP layer memory: < 5 MB per active stream

### Test Matrix

- replay tests against recorded SSE fixtures
- retry tests with injected 429/500/503
- timeout tests (request + idle stream)
- token-counting tests against known prompts

---

## V1 — Phase 4 · Workspace & Repository Intelligence

### Goal

Allow Zyquo to deeply understand repositories.

### Tasks

- git detection (`.git`, worktrees, submodules)
- language detection by file weight
- framework detection (§22)
- package manager detection
- test command detection (heuristics + cache)
- repo tree indexing (parallel walk, gitignore-aware)
- README extraction (chunked, headings preserved)
- architecture summarization (LLM-powered, cached, hand-editable)
- ignore generated folders (`node_modules`, `.build`, etc.)
- detect large repos (> 100k files) and shift to lazy mode
- FSEvents watcher for incremental updates

### Files

```text
Sources/Zyquo/Workspace/Workspace.swift
Sources/Zyquo/Workspace/RepoAnalyzer.swift
Sources/Zyquo/Workspace/WorkspaceIndex.swift
Sources/Zyquo/Workspace/ProjectDetector.swift
Sources/Zyquo/Workspace/Ignore.swift
Sources/Zyquo/Workspace/BoundaryGuard.swift
Sources/Zyquo/Workspace/FileSnapshot.swift
```

### Languages MUST detect (V1)

Swift, Python, TypeScript, JavaScript, Rust, Go, Node (runtime), Ruby,
Elixir, Java, Kotlin, C, C++, Objective-C, Shell.

### Acceptance Criteria

- `zyquo open .` shows an intelligent repo analysis card within 3 s
- `WorkspaceIndex` is queryable via in-process API for tools
- `.zyquoignore` is respected
- FSEvents updates index within 50 ms of fs change
- Boundary violations are rejected with a clear error

### Performance Budget

- cold scan 50k files: < 3 s
- warm scan: < 200 ms
- index DB size: < 2 % of repo size

### Test Matrix

- detection tests across 20+ fixture repos
- gitignore + zyquoignore precedence tests
- large-repo (synthetic 200k files) scale test
- symlink loop test

---

## V1 — Phase 5 · Shell Runtime & Execution Engine

### Goal

Build secure shell execution layer.

### Tasks

- `Process` wrapper with stdout/stderr pipes
- streaming line decoder (UTF-8 with replacement)
- timeout (per call + idle)
- cancellation (Task → SIGTERM → SIGKILL)
- env control (allow-list + masks)
- cwd isolation enforcement
- command history (per session + persistent)
- execution log (entry/exit/duration/bytes)
- shell profile loading opt-in
- zsh primary, bash fallback

### Files

```text
Sources/Zyquo/Shell/ShellExecutor.swift
Sources/Zyquo/Shell/CommandResult.swift
Sources/Zyquo/Shell/ShellSession.swift
Sources/Zyquo/Shell/CommandHistory.swift
Sources/Zyquo/Shell/EnvironmentMask.swift
Sources/Zyquo/Shell/PTYHost.swift
```

### Acceptance Criteria

- Zyquo can execute commands safely with streaming output
- Commands time out at 120 s by default
- `Ctrl-C` interrupts within 200 ms (SIGTERM) and within 5 s hard (SIGKILL)
- Env masks hide `*_TOKEN`, `*_SECRET`, `*_KEY`, `SSH_*`
- PTY mode hands off and recovers cleanly

### Performance Budget

- launch overhead per command: < 8 ms (fork+exec)
- stream copy overhead: < 1 % CPU at 10 MB/s

### Test Matrix

- streaming correctness vs `cat large.txt`
- cancellation under load
- env mask leak tests (assert masked vars not in child env)
- PTY interactive smoke (`vim` open/save/quit)

---

## V1 — Phase 6 · Risk Engine & Approval Workflow

### Goal

Create powerful safety system.

### Tasks

- dangerous command classifier (§19)
- risk scoring (tier + rationale)
- approval prompts (`[y/n/a/e/?]`)
- workspace boundary checks
- recursive delete detection
- network action detection
- install script detection
- privilege escalation detection
- allowlist system
- approval persistence (once/session/workspace/global)
- visible audit log

### Files

```text
Sources/Zyquo/Shell/RiskClassifier.swift
Sources/Zyquo/Shell/DangerRules.swift
Sources/Zyquo/Security/Sandbox.swift
Sources/Zyquo/Security/AuditLog.swift
Sources/Zyquo/Workspace/BoundaryGuard.swift
```

### Acceptance Criteria

- Every risky command requires approval
- Approval scope is selectable in prompt
- `/trust` and `/untrust` work and are listed in `/status`
- Audit log persists across sessions

### Test Matrix

- 200+ rule unit tests across DANGEROUS / CRITICAL examples
- boundary tests across `..`, symlink escape, `$HOME`, `/`
- false-positive tests (`rm -rf ./build` inside workspace = approved tier)

---

## V1 — Phase 7 · File Editing & Diff System

### Goal

Build Cline-style editing workflow.

### Tasks

- snapshot system (content-addressed gzip)
- patch generation (unified diff via Myers)
- syntax-aware diff rendering
- apply/reject workflow
- rollback (reverse patch)
- patch persistence (PatchStore)
- file conflict handling (3-way merge)
- multi-file patching (ChangeSet)
- edit summaries (counts, risks)

### Files

```text
Sources/Zyquo/Diff/DiffEngine.swift
Sources/Zyquo/Diff/PatchEngine.swift
Sources/Zyquo/Diff/ChangeSet.swift
Sources/Zyquo/Diff/HunkParser.swift
Sources/Zyquo/Diff/ConflictResolver.swift
Sources/Zyquo/Persistence/SnapshotStore.swift
Sources/Zyquo/Persistence/PatchStore.swift
```

### Acceptance Criteria

- Beautiful interactive diffs (§21)
- `/apply` and `/reject` work, including partial changesets
- Rollback restores byte-identical pre-image
- Conflicts surface a resolver UI

### Test Matrix

- round-trip property test: apply(diff(a,b)) on a == b
- conflict reproduction tests
- snapshot tests for diff rendering across themes

---

## V1 — Phase 8 · Agent Runtime Core

### Goal

Create autonomous but controllable runtime.

### Tasks

- planning engine (Planner)
- execution loop (Executor)
- observation model (Observation)
- task state tracking (AgentState)
- retry logic (per step, exponential, capped)
- failure recovery (replan with failure context)
- tool orchestration
- execution summaries
- context assembly (ContextAssembler + token budget)
- step history

### Files

```text
Sources/Zyquo/Agent/AgentLoop.swift
Sources/Zyquo/Agent/Planner.swift
Sources/Zyquo/Agent/Executor.swift
Sources/Zyquo/Agent/Verifier.swift
Sources/Zyquo/Agent/AgentStep.swift
Sources/Zyquo/Agent/AgentState.swift
Sources/Zyquo/Agent/ContextAssembler.swift
Sources/Zyquo/Agent/TokenBudget.swift
Sources/Zyquo/Agent/Summarizer.swift
Sources/Zyquo/Agent/StopConditions.swift
```

### Loop

```text
intent → plan → propose action → approval → execute → observe →
verify → continue or stop
```

### Acceptance Criteria

- Real iterative agent workflow (≥ 5 steps without manual nudging)
- All transitions emit UI events
- Stop conditions in §16.3 enforced
- Resume after `Ctrl-C` restores partial step state

### Performance Budget

- planner overhead per step: < 50 ms outside LLM call
- context assembly: < 100 ms p95 for projects < 10k files

### Test Matrix

- scripted fixture intents with deterministic providers (mock LLM)
- failure injection (tool error mid-loop → replan)
- budget exhaustion tests

---

## V1 — Phase 9 · Persistence & Memory System

### Goal

Create persistent project intelligence.

### Tasks

- session persistence (JSONL append + SQLite index)
- project memory (`.zyquo/memory/project.md`)
- architecture memory (auto + hand-edited)
- decision memory (append-only)
- compressed summaries (Summarizer)
- command memory
- patch history
- searchable memory (SQLite FTS5)
- memory serialization (versioned schema)
- crash recovery (resume from last checkpoint)

### Storage

```text
.zyquo/
├── memory/
├── snapshots/
├── patches/
├── plans/
├── logs/
└── index/workspace.sqlite
```

### Acceptance Criteria

- Sessions survive restarts
- `zyquo sessions resume <id>` restores plan, steps, context
- `zyquo memory` opens an inspector
- FTS5 search returns relevant chunks for a known query

### Test Matrix

- kill -9 mid-session, then resume → state matches checkpoint
- schema migration test across versions
- FTS5 ranking sanity tests

---

## V1 — Phase 10 · Polish, Packaging & Developer Experience

### Goal

Make Zyquo feel production-grade.

### Tasks

- startup optimization (lazy load tools, AOT-friendly init)
- render optimization (partial flush profiling)
- crash handling (structured report + redaction)
- structured logs (JSONL, rotating)
- config file support (TOML + env)
- CLI help system (man page generation via `argument-parser`)
- Homebrew prep (formula + bottle script)
- signing + notarization scripts
- onboarding flow (first-run wizard: provider login, theme pick)
- theme polish (3 shipping themes audited for contrast)
- keyboard shortcuts (vim + emacs presets, configurable)
- markdown docs (user guide, cookbook)
- testing suite (unit + snapshot + integration ≥ 70 % cov on Core)

### Acceptance Criteria

- Production-quality V1
- `brew install zyquo` works from local tap
- `zyquo` first-run wizard completes in < 60 s of user time
- All shipping themes pass WCAG AA contrast for primary text
- CI is green on every PR

### Test Matrix

- end-to-end scenario tests on fixture repos (Swift, TS, Python)
- accessibility audit on themes
- `--json` output schema tests
- man page renders cleanly

---

# 30. Zyquo V2 — Ultra Detailed Implementation Phases

V2 objective:

> Transform Zyquo from "AI terminal assistant" into a **persistent
> agentic operating runtime**.

---

## V2 — Phase 1 · Multi-Agent Orchestration

### Goal

Create specialized internal agents.

### Agents

ArchitectAgent · CoderAgent · ReviewerAgent · ShellAgent ·
VerifierAgent · ResearchAgent

### Tasks

- orchestration engine
- task delegation graph
- subtask tracking
- shared memory with locking
- coordination protocol (typed messages)
- agent messaging
- execution ownership
- result merge (ChangeSet union with conflict detection)
- agent-specific prompts
- agent-specific tool whitelists

### Acceptance Criteria

- A 3-agent task (Architect → Coder → Verifier) completes without manual
  intervention on a fixture refactor
- Conflicts between Coder outputs are detected and surfaced

---

## V2 — Phase 2 · Semantic Repository Intelligence

### Goal

Deep semantic code understanding.

### Tasks

- tree-sitter grammars for Swift, TS, Python, Rust, Go, Ruby
- AST parsing pipeline
- symbol extraction (defs, refs, scopes)
- semantic chunking (function-level, class-level)
- dependency graphing (import + call)
- architecture graph (module-level)
- semantic search API (`workspace.semanticSearch`)
- cross-file linking
- call graph analysis
- import graph analysis
- code-relationship engine

### Acceptance Criteria

- `workspace.semanticSearch("auth flow")` returns relevant call chains,
  not just text matches
- Renaming a symbol via `file.patch` is preceded by ref-aware preview

---

## V2 — Phase 3 · Embeddings & Local Vector Memory

### Goal

Persistent semantic memory.

### Tasks

- embedding pipeline (per chunk)
- local embedding model option (e.g. `bge-small`, `nomic-embed`)
- cloud embedding option
- vector store (SQLite + `sqlite-vec` extension, or Lance)
- incremental updates via FSEvents
- semantic recall
- memory ranking (BM25 + cosine hybrid)
- hybrid retrieval
- vector quantization for size control
- context assembly with retrieval

### Storage

`.zyquo/index/vectors.sqlite` with `sqlite-vec`.

### Acceptance Criteria

- Long-term semantic memory survives restarts
- Recall@10 on a labeled benchmark beats lexical-only by ≥ 20 %

---

## V2 — Phase 4 · Background Intelligence Runtime

### Goal

Continuous workspace awareness.

### Tasks

- background indexer (XPC service)
- git monitoring
- file watchers (FSEvents)
- architecture refresh
- stale memory cleanup
- incremental summaries
- command analytics
- repo health tracking (LOC, test coverage if available, churn)
- project evolution tracking
- auto context refresh

### Acceptance Criteria

- `zyquod` (daemon) runs as a launchd agent
- Index lag after edit: < 500 ms p95
- Daemon CPU at idle: < 1 %

---

## V2 — Phase 5 · Advanced Tool Ecosystem

### Goal

Expand tool capabilities.

### Tools

`browser.search` · `web.fetch` · `docs.index` · `database.query` ·
`docker.run` · `kubernetes.inspect` · `http.request` · `sql.explain`

### Tasks

- plugin loader (signed bundles)
- tool sandboxing (Apple Sandbox profile + entitlements)
- permission system (declared in plugin manifest)
- tool registry extension
- external integrations
- secure execution
- tool tracing (OpenTelemetry-shaped spans)
- dynamic loading
- tool metadata
- capability negotiation

### Plugin Manifest

```toml
# zyquo-plugin.toml
name = "docker"
version = "0.1.0"
publisher = "zyquo"
signature = "sha256:..."
entry = "./bin/zyquo-docker"
permissions = ["network:local", "shell:limited"]

[[tools]]
name = "docker.run"
risk = "MODERATE"
schema = "./schemas/docker.run.json"
```

### Acceptance Criteria

- Unsigned plugins fail to load
- Plugins cannot exceed declared permissions
- Tool spans show in `zyquo trace`

---

## V2 — Phase 6 · Skill System

### Goal

Compressed procedural intelligence.

### Skills (examples)

`fix_swift_build` · `analyze_repo` · `review_pr` · `generate_docs` ·
`port_to_swift_concurrency` · `add_auth_flow`

### Tasks

- skill format (YAML + prompts + tool whitelist)
- skill loader
- skill memory (per-skill scratch)
- parameter injection
- skill chaining
- skill discovery (`zyquo skills list`)
- skill versioning
- local skill registry
- execution tracing
- marketplace-ready architecture (future)

### Skill Schema

```yaml
id: fix_swift_build
version: 0.1.0
title: Fix a failing Swift build
inputs:
  - name: package_path
    type: path
tools_allowed:
  - shell.run
  - file.read
  - file.patch
  - git.status
prompt: |
  You are a focused Swift build doctor. Diagnose the failure, propose
  minimal patches, and verify by re-running tests.
verify:
  command: "swift test"
  expect_exit_code: 0
```

### Acceptance Criteria

- Skills are listable, runnable, and versioned
- A skill run produces a session with the skill id stamped on it

---

## V2 — Phase 7 · Parallel Execution Runtime

### Goal

Parallel agent workflows.

### Tasks

- concurrent subtasks (TaskGroup)
- task scheduler
- dependency graphs (topological execution)
- cancellation propagation
- shared memory locking (actor-based)
- parallel shell sessions
- task priorities
- resource limits
- execution metrics
- orchestration visualization (live DAG view)

### Acceptance Criteria

- DAG with 4 leaves runs concurrently; reconciles cleanly
- Cancellation propagates within 200 ms across all nodes

---

## V2 — Phase 8 · Local Model Runtime

### Goal

Offline local AI execution.

### Tasks

- `llama.cpp` integration (via Swift wrapper)
- GGUF support
- local embeddings
- streaming inference
- quantization support (Q4, Q5, Q8)
- model management (download, verify, prune)
- memory optimization
- Metal acceleration
- automatic model routing (local for small tasks, cloud for hard)
- local/cloud hybrid mode

### Acceptance Criteria

- A 7B Q4 model can drive `zyquo ask` for offline summaries
- Hybrid mode falls back to cloud only when local confidence is low

---

## V2 — Phase 9 · Distributed Agent Runtime

### Goal

Support cluster execution later (MacLustr integration target).

### Tasks

- remote agent nodes (mTLS gRPC)
- distributed tasks
- network coordination
- remote shell execution
- cluster scheduler
- distributed memory (CRDT-friendly schemas)
- secure communication
- node monitoring
- execution balancing
- fault recovery

### Acceptance Criteria

- Two Macs on a LAN can run a single Zyquo session cooperatively
- Loss of one node degrades gracefully, not catastrophically

---

## V2 — Phase 10 · Zyquo Runtime Evolution

### Goal

Transform Zyquo into persistent cognitive runtime.

### Tasks

- long-lived sessions (multi-day)
- autonomous workflows (scheduled `cron`-shaped)
- scheduled tasks
- memory compression at scale
- self-improving summaries
- adaptive planning (policy that learns from outcomes)
- workflow learning (extract reusable skills from successful sessions)
- persistent context graphs
- project evolution intelligence
- long-term agent continuity

### Acceptance Criteria

- A 7-day session preserves coherent state across at least 20 resumes
- Self-extracted skills are reviewable and accept/reject-able

---

# 31. Syntax Highlighting & Code Rendering

### 31.1 Strategy

- V1: `Splash` or `Highlightr` for Swift / common languages.
- V1 → V2: tree-sitter grammars under `Resources/grammars/`.
- Fallback: monochrome with subtle weight changes.

### 31.2 Languages MUST highlight in V1

Swift, TypeScript, JavaScript, Python, Rust, Go, Ruby, Shell,
Markdown, JSON, YAML, TOML, HTML, CSS, SQL.

### 31.3 Diff Highlight

Diffs use syntax highlighting *inside* the changed lines, with the
add/remove background composited under the syntax foreground.

---

# 32. Threat Model (`docs/zyquo_threat_model.md`)

### 32.1 Assets

- API keys (Anthropic, OpenRouter, etc.)
- Source code (the user's)
- Workspace memory (may contain sensitive design notes)
- Shell environment (may contain ambient secrets)

### 32.2 Adversaries

- A malicious LLM output that crafts a destructive command
- A compromised model provider returning malicious tool calls
- A malicious plugin (V2)
- A malicious repo (post-clone, e.g. a `.zyquo/config.json` placed by
  someone else) — must not auto-grant trust
- The user accidentally trusting a workspace they shouldn't

### 32.3 Mitigations

- Risk classification + approval gates (§19, §6)
- Workspace boundary enforcement
- Trust scoping (never `global` for CRITICAL)
- Repo-supplied `.zyquo/trust.json` MUST be ignored unless co-signed by
  a known user signing key (V2)
- Env masks
- Keychain-only secrets
- Audit log
- Plugin signing (V2)
- Sandbox profiles (V2)

### 32.4 Non-Mitigations

- Zyquo does NOT defend against a user who explicitly `/trust`s a
  CRITICAL action. Approval is consent.

---

# 33. Telemetry & Observability

### 33.1 Principles

- **Local-first.** No telemetry leaves the machine without opt-in.
- **Structured.** All logs are JSONL.
- **Redacted.** PII / secrets are redacted at log boundary.

### 33.2 Surfaces

- `~/Library/Logs/Zyquo/zyquo.log` (rotating, JSONL)
- `.zyquo/logs/<session-id>.log` (per session)
- `~/Library/Logs/Zyquo/crash/<timestamp>.json`
- `zyquo trace --session <id>` (replay tool-call spans)

### 33.3 Metrics

`swift-metrics`-shaped counters/histograms:

- `zyquo.agent.steps`
- `zyquo.agent.steps.duration_ms`
- `zyquo.tool.invocations{tool}`
- `zyquo.tool.errors{tool, kind}`
- `zyquo.llm.tokens.in{provider, model}`
- `zyquo.llm.tokens.out{provider, model}`
- `zyquo.llm.cost_usd{provider, model}`
- `zyquo.shell.commands{risk}`
- `zyquo.approvals{decision}`

### 33.4 Opt-in Cloud Telemetry (V2)

Off by default. Aggregates only (no prompts, no code). Endpoint
configurable. Disable: `telemetry.enabled = false`.

---

# 34. Configuration

### 34.1 Precedence

```text
CLI flag > env var > workspace config (.zyquo/config.json)
> user config (~/.zyquo/config.toml) > defaults
```

### 34.2 Global Config (TOML)

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
default_model = "claude-sonnet-4-7"
timeout_s = 120

[providers.openrouter]
default_model = "anthropic/claude-sonnet-4.7"
fallback = true

[shell]
default = "/bin/zsh"
load_profile = false
timeout_s = 120

[memory]
compress_threshold_pct = 70
keep_decisions_verbatim = true

[telemetry]
enabled = false
```

### 34.3 Workspace Config (JSON)

```json
{
  "version": 1,
  "provider": "anthropic",
  "model": "claude-sonnet-4-7",
  "tools": {
    "shell.run": { "enabled": true },
    "git.commit": { "enabled": true },
    "git.push":   { "enabled": false }
  },
  "tests": {
    "command": "swift test",
    "timeout_s": 600
  }
}
```

---

# 35. Canonical System Prompts (`docs/zyquo_prompts.md`)

Prompts are versioned and stored as markdown files under
`Resources/prompts/`. The prompt name is keyed in code; the markdown
file is the source of truth.

### 35.1 Planner Prompt (sketch)

```markdown
You are the Planner inside Zyquo, a native macOS terminal agent. Given a
user intent and an assembled context, produce a numbered plan of small,
verifiable steps. Each step MUST be expressible as one tool call from
the provided tool list. Prefer reading before writing. Prefer
narrow patches over broad rewrites. State preconditions and a
verification check per step.

Constraints:
- Never invent files or symbols. If unsure, read first.
- Never propose CRITICAL shell commands unless the user explicitly
  asked.
- Keep steps under 7 unless the task is genuinely larger; re-plan as you
  learn.
- Output strictly in the schema provided.
```

### 35.2 Executor Prompt (sketch)

```markdown
You are the Executor. Given the current plan and the latest observation,
propose the next single tool call. Return only the tool call in the
required schema. If you believe the plan is wrong, return a re-plan
signal instead.
```

### 35.3 Verifier Prompt (sketch)

```markdown
You are the Verifier. Given a step's stated success criteria and the
observation produced, return a verdict: "pass", "fail", or "unclear",
with a one-sentence rationale.
```

### 35.4 Summarizer Prompt (sketch)

```markdown
You are the Summarizer. Compress the supplied events into a structured
summary that preserves: decisions, errors, file paths touched, commands
run, and verified outcomes. Discard incidental tool chatter.
```

---

# 36. JSON Schemas for Tools (`docs/zyquo_tool_schemas.md`)

Every tool MUST have a JSON Schema for both validation and LLM tool
description. Example for `shell.run`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "shell.run",
  "type": "object",
  "required": ["command"],
  "properties": {
    "command": {
      "type": "string",
      "description": "Shell command to execute via zsh -c."
    },
    "cwd": {
      "type": "string",
      "description": "Working directory; MUST be inside workspace."
    },
    "timeout_s": {
      "type": "integer",
      "minimum": 1,
      "maximum": 3600,
      "default": 120
    },
    "env": {
      "type": "object",
      "additionalProperties": { "type": "string" }
    }
  },
  "additionalProperties": false
}
```

---

# 37. Testing Strategy

### 37.1 Layers

- **Unit** — pure types, parsers, classifiers, summarizers (with mock
  LLM)
- **Snapshot** — TUI frames (per theme × per terminal capability)
- **Integration** — end-to-end on fixture repos with recorded LLM
  transcripts (replay providers)
- **Property** — diff round-trip, patch idempotence, parser invariants
- **Fuzz** — argument parsing, ANSI input, slash command parsing
- **Performance** — startup, render, scan, stream throughput
- **Security** — danger-rule corpus, boundary escapes, env-mask leaks

### 37.2 Coverage Targets (V1)

- `ZyquoCore`: ≥ 75 % line coverage
- Critical paths (RiskClassifier, PatchEngine, ShellExecutor):
  ≥ 90 % line + branch
- Snapshot tests: ≥ 50 frames

### 37.3 CI

- macOS arm64 + macOS x86_64 (via universal slice tests)
- Required checks: build, test, lint, format, snapshot, perf budget
- Nightly: longer integration with real providers behind a secret

---

# 38. Performance Budgets

| Surface                                  | Budget                  |
| ---------------------------------------- | ----------------------- |
| Cold start `zyquo --help`                | < 120 ms (arm64)        |
| First paint `zyquo interactive`          | < 200 ms                |
| Frame render (no LLM activity)           | < 8 ms p95              |
| Streaming token append                   | < 2 ms                  |
| First token (warm cache, Sonnet)         | < 800 ms p50            |
| Workspace cold scan (50k files)          | < 3 s                   |
| Workspace warm scan                      | < 200 ms                |
| FSEvents → index update                  | < 50 ms p95             |
| Approval prompt → execution start        | < 30 ms                 |
| Session persist (flush)                  | < 100 ms p95            |
| Memory at interactive idle               | < 60 MB RSS             |
| Memory under heavy stream                | < 250 MB RSS            |
| Binary size (release, stripped)          | < 25 MB                 |

Regressions of > 10 % must be flagged in CI.

---

# 39. Error Taxonomy

All errors implement `ZyquoError`:

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

Each subcase MUST carry:

- a stable `code` (string, e.g. `provider.rate_limited`)
- a human description
- a remediation hint (one sentence)
- an optional underlying error

UI MUST render errors as a `Notification` with the description + hint,
and log the full structured form to file.

---

# 40. Keymap (Defaults)

| Key                | Action                                  |
| ------------------ | --------------------------------------- |
| `?`                | Toggle keymap overlay                   |
| `Ctrl-C`           | Cancel in-flight op (or exit if idle)   |
| `Ctrl-D`           | Exit at idle                            |
| `Ctrl-L`           | Clear screen (preserve state)           |
| `↑` / `↓`          | Input history nav                       |
| `Tab`              | Completion                              |
| `Esc`              | Close modal / cancel input              |
| `Enter`            | Submit                                  |
| `Shift-Enter`      | Newline in input                        |
| `y` / `n`          | Approve / deny in approval prompt       |
| `a`                | "Always" approve in approval prompt     |
| `e`                | Edit proposed command                   |
| `s`                | Toggle side-by-side in DiffView         |
| `g g` / `G`        | Top / bottom in long views              |
| `/`                | Fuzzy search inside modal pickers       |

Keymap is overridable via `~/.zyquo/keymap.toml`.

---

# 41. Distribution & Packaging

### 41.1 Homebrew Tap

```text
homebrew-zyquo/
└── Formula/
    └── zyquo.rb
```

### 41.2 Signing & Notarization

- Apple Developer ID Application certificate
- Hardened runtime
- Entitlements: minimal; no JIT; no library validation bypass
- Notarized via `notarytool`; stapled

### 41.3 Universal Binary

- arm64 (primary)
- x86_64 (until Apple deprecates)
- Lipo'd at release build step

### 41.4 Self-Update

`zyquo upgrade` invokes `brew upgrade zyquo` when Homebrew-installed,
otherwise prints the manual update command.

---

# 42. Roadmap Summary

```text
V1 (foundation)             ── §29, Phases 1–10
V2 (agentic runtime)        ── §30, Phases 1–10
V3 (target, not in scope)
    - cloud-coordinated multi-machine sessions
    - first-party GUI cockpit
    - public skill marketplace
    - team workspaces
```

---

# 43. Definition of "Done" (V1)

V1 ships when *all* of the following are true:

1. `zyquo` interactive UI is shippable per §7–§12 and snapshot-tested.
2. All §29 phases pass acceptance criteria and performance budgets.
3. Threat model (§32) controls are implemented or explicitly documented
   as deferred.
4. Documentation (`docs/`) is complete and renders on the Zyquo site
   (or in a `docs.zyquo.dev` placeholder).
5. CI is green on a clean macOS 14 image.
6. Notarized universal binary is downloadable; `brew install zyquo`
   works from the tap.
7. A first-time user can go from `brew install zyquo` to a successful
   `zyquo run "explain this repo"` in under 5 minutes, using a fresh
   Anthropic key.
8. Internal dogfooding for at least 2 weeks with at least 3 engineers
   produces zero P0 issues.

---

# 44. Hard Constraints (Inviolable)

- No silent network calls. Every network surface is declared and
  toggleable.
- No silent file writes. Every write is a patch. Every patch is
  approvable. Every applied patch is reversible.
- No secret in logs. Ever. Redaction is enforced at the log boundary.
- No `eval`-style execution of LLM output. Tool calls are typed and
  schema-validated.
- No Electron. No Node.js runtime. No Python runtime in hot path.
- No vendoring of code you cannot read in a day.
- No feature that cannot be explained in one paragraph to a Staff
  Engineer.

---

# 45. Out-of-Band Notes for the Implementing Agent

When you begin:

1. Start with §3 (Research Phase). Do not skip. The matrix in §5 is the
   single most valuable artifact you will produce in the first day.
2. Write `docs/zyquo_cli_architecture.md` BEFORE writing
   `Sources/Zyquo/main.swift`. The doc is the design review.
3. Build §29 Phase 1 and Phase 2 in parallel only if you keep the
   renderer scoped (CellBuffer + Panel + Theme is enough to begin).
4. Pick the LLM provider abstraction shape in §25 EARLY. Every later
   phase touches it.
5. Treat the RiskClassifier (§19) as a *first-class*, separately tested
   subsystem. It is the single biggest user-trust lever in the product.
6. The diff workflow (§20–§21) is the second biggest trust lever. Build
   it before the agent loop relies on writes.
7. Do not chase V2 ideas in V1. They will be there. V1 is about earning
   the user's trust on a single Mac, in a single repo.
8. When in doubt, render it. The terminal is the canvas. If the user
   cannot see it, the agent should not be doing it.

---

# Appendix A — Exhaustive Tool Registry

Each tool below MUST be implemented as a `Tool` (§17.2) with a stable
`name`, a JSON Schema, a default risk tier, and a per-call cancellation
contract. Columns:

- **Name** — stable identifier (`namespace.verb`)
- **Risk** — default tier (§19.1); per-call may escalate
- **Mut.** — `R` (read-only), `W` (workspace mutation), `N` (network),
  `S` (shell), `M` (memory mutation)
- **Tier** — `V1` (must ship), `V1+` (post-Phase 10), `V2`
- **Deps** — external binaries / system APIs required

> **Schema notation:** input fields are abbreviated. Full schemas live in
> `docs/zyquo_tool_schemas.md`. Every tool MUST return a `summary`
> (≤ 3 lines), a structured `payload`, and an optional `artifacts` list.

---

## A.1 Shell Tools

| Name              | Risk        | Mut. | Tier | Deps                  |
| ----------------- | ----------- | ---- | ---- | --------------------- |
| `shell.run`       | per-command | S    | V1   | `/bin/zsh`, `/bin/bash` |
| `shell.background`| MODERATE    | S    | V2   | launchd               |
| `shell.cancel`    | SAFE        | —    | V1   | —                     |
| `shell.history`   | SAFE        | R    | V1   | —                     |
| `shell.which`     | SAFE        | R    | V1   | —                     |

### `shell.run`
Execute a shell command via zsh.
**Input:** `command` (str, required), `cwd` (path), `timeout_s` (1–3600,
default 120), `env` (map), `pty` (bool, default false), `risk_hint`
(enum override).
**Output:** `exit_code` (int), `signal` (int?), `stdout` (str, capped),
`stderr` (str, capped), `duration_ms` (int), `bytes_out`, `bytes_err`.
**Notes:** classified per-call by `RiskClassifier` (§19). Output is
streamed to UI in real time; the returned `stdout`/`stderr` is the
captured tail (configurable cap, default 256 KB).

### `shell.background`  *(V2)*
Launch a long-lived process under a managed handle. Returns a `job_id`;
output is multiplexed to a session-scoped buffer.

### `shell.cancel`
Cancel an in-flight or background shell command by `job_id`.

### `shell.history`
Return recent commands for the session (or workspace, opt-in).

### `shell.which`
Locate a binary in PATH. Returns absolute path or `null`. Never
invokes the binary.

---

## A.2 Filesystem Tools

| Name              | Risk      | Mut. | Tier | Deps     |
| ----------------- | --------- | ---- | ---- | -------- |
| `file.read`       | SAFE      | R    | V1   | —        |
| `file.list`       | SAFE      | R    | V1   | —        |
| `file.tree`       | SAFE      | R    | V1   | —        |
| `file.stat`       | SAFE      | R    | V1   | —        |
| `file.glob`       | SAFE      | R    | V1   | —        |
| `file.search`     | SAFE      | R    | V1   | `rg`     |
| `file.checksum`   | SAFE      | R    | V1   | —        |
| `file.diff`       | SAFE      | R    | V1   | —        |
| `file.write`      | MODERATE  | W    | V1   | —        |
| `file.patch`      | MODERATE  | W    | V1   | —        |
| `file.touch`      | MODERATE  | W    | V1   | —        |
| `file.move`       | MODERATE  | W    | V1   | —        |
| `file.copy`       | MODERATE  | W    | V1   | —        |
| `file.delete`     | DANGEROUS | W    | V1   | —        |
| `file.symlink`    | DANGEROUS | W    | V2   | —        |
| `file.chmod`      | DANGEROUS | W    | V2   | —        |
| `file.watch`      | SAFE      | R    | V2   | FSEvents |

### `file.read`
**Input:** `path` (workspace-relative or absolute inside workspace),
`encoding` (auto/utf-8/latin-1/binary), `range` (`{startLine, endLine}`,
optional), `max_bytes` (default 512 KB).
**Output:** `content` (str/base64), `encoding_detected`, `truncated`
(bool), `sha256`.
**Notes:** binary files return base64 and a flag. Files exceeding
`max_bytes` are truncated with `truncated=true`; the agent SHOULD use
`range` for follow-ups.

### `file.list`
Directory listing, gitignore-aware, with optional depth.
**Input:** `path`, `depth` (default 1), `include_hidden` (default false),
`ignore_vcs` (default true).
**Output:** array of `{name, type, size, mtime, is_symlink}`.

### `file.tree`
Recursive tree, capped by `max_entries` (default 5 000) and
`max_depth` (default 6).

### `file.stat`
`{exists, type, size, mtime, ctime, sha256?, executable}`.

### `file.glob`
Glob over workspace, gitignore-aware. **Input:** `pattern`, `cwd`,
`limit` (default 1 000).

### `file.search`
Ripgrep-backed search.
**Input:** `query` (str|regex), `path`, `glob` (optional),
`case_sensitive`, `multiline` (default false), `max_results`
(default 200), `before`, `after` (context lines).
**Output:** `matches[]` with `path`, `line`, `column`, `text`,
`context_before`, `context_after`.

### `file.checksum`
SHA-256 of a file or of every file under a path (with `limit`).

### `file.diff`
Compute a unified diff between two paths or between a path and inline
content. Pure read; does not write.

### `file.write`
Write a complete file. **Always passes through the patch workflow**
(§20): a write is internally normalized to a patch against the current
on-disk content. There is no "raw write" path.

### `file.patch`
Apply a unified diff. **Always passes through the patch workflow.**
**Input:** `diff` (str), `expect_pre_sha` (optional, for safety),
`dry_run` (bool).
**Output:** `patch_id`, `files_changed[]`, `added`, `removed`,
`conflicts[]` (if any).

### `file.touch`
Create an empty file (or update mtime). Counts as a write → patch.

### `file.move` / `file.copy` / `file.delete`
Standard semantics. All routed through patch workflow so a reverse
patch is recorded (for `delete`, the reverse patch reinstates content
from snapshot).

### `file.symlink` *(V2)*, `file.chmod` *(V2)*
Reserved for V2; both DANGEROUS by default.

### `file.watch` *(V2)*
Subscribe to FSEvents updates for a path. Returns a stream id; events
emitted via UI/agent channels.

---

## A.3 Git Tools

| Name              | Risk      | Mut. | Tier | Deps  |
| ----------------- | --------- | ---- | ---- | ----- |
| `git.status`      | SAFE      | R    | V1   | `git` |
| `git.diff`        | SAFE      | R    | V1   | `git` |
| `git.show`        | SAFE      | R    | V1   | `git` |
| `git.log`         | SAFE      | R    | V1   | `git` |
| `git.blame`       | SAFE      | R    | V1   | `git` |
| `git.branch`      | MODERATE  | W    | V1   | `git` |
| `git.checkout`    | MODERATE  | W    | V1   | `git` |
| `git.commit`      | MODERATE  | W    | V1   | `git` |
| `git.stash`       | MODERATE  | W    | V1   | `git` |
| `git.tag`         | MODERATE  | W    | V1   | `git` |
| `git.merge`       | MODERATE  | W    | V1   | `git` |
| `git.rebase`      | DANGEROUS | W    | V2   | `git` |
| `git.reset`       | DANGEROUS | W    | V2   | `git` |
| `git.fetch`       | MODERATE  | N    | V1   | `git` |
| `git.pull`        | MODERATE  | W,N  | V1   | `git` |
| `git.push`        | CRITICAL  | N    | V1   | `git` |
| `git.remote`      | SAFE      | R    | V1   | `git` |
| `git.bisect`      | MODERATE  | W    | V2   | `git` |

### `git.status` *(SAFE, R)*
**Output:** `branch`, `upstream`, `ahead`, `behind`, `staged[]`,
`unstaged[]`, `untracked[]`, `merge_in_progress`, `rebase_in_progress`.

### `git.diff` *(SAFE, R)*
**Input:** `range` (e.g. `HEAD~1..HEAD`, `--staged`, `--unstaged`),
`paths[]`.
**Output:** unified diff string + parsed `hunks[]`.

### `git.show`
Show a commit (full diff + metadata).

### `git.log`
**Input:** `range`, `paths[]`, `limit` (default 50), `format`
(short/full/json).

### `git.blame`
**Input:** `path`, `range` (lines).
**Output:** per-line `{sha, author, date, summary, line}`.

### `git.commit` *(MODERATE, W)*
**Input:** `message` (required), `paths[]` (optional), `sign`
(bool), `author` (optional override).
**Notes:** never auto-stages all by default. The agent MUST explicitly
list paths.

### `git.branch`
List / create / delete branches. Delete escalates to DANGEROUS.

### `git.checkout` *(MODERATE)*
Switch branches or restore files. Escalates to DANGEROUS if it would
discard uncommitted changes; in that case requires `--force` and an
elevated approval.

### `git.merge`, `git.rebase`, `git.reset`
All escalate based on the impact. `reset --hard` is CRITICAL.

### `git.push` *(CRITICAL, N)*
Always requires explicit approval. Default-disabled per workspace via
`tools.git.push.enabled = false` in workspace config.

### `git.bisect` *(V2)*
Driven by `task.verify` to find a regression commit.

---

## A.4 Workspace Tools

| Name                          | Risk | Mut. | Tier | Deps         |
| ----------------------------- | ---- | ---- | ---- | ------------ |
| `workspace.index`             | SAFE | R    | V1   | —            |
| `workspace.detect`            | SAFE | R    | V1   | —            |
| `workspace.summary`           | SAFE | R    | V1   | —            |
| `workspace.tree`              | SAFE | R    | V1   | —            |
| `workspace.boundary`          | SAFE | R    | V1   | —            |
| `workspace.tests.detect`      | SAFE | R    | V1   | —            |
| `workspace.semanticSearch`    | SAFE | R    | V2   | tree-sitter  |
| `workspace.symbols`           | SAFE | R    | V2   | tree-sitter  |
| `workspace.refs`              | SAFE | R    | V2   | tree-sitter  |
| `workspace.callgraph`         | SAFE | R    | V2   | tree-sitter  |
| `workspace.depgraph`          | SAFE | R    | V2   | tree-sitter  |
| `workspace.docs.find`         | SAFE | R    | V1   | —            |

### `workspace.index`
Trigger (or query status of) the indexer. **Output:** `files_indexed`,
`last_full_scan`, `incremental_lag_ms`, `index_size_bytes`.

### `workspace.detect`
Run the project detectors (§22) and return the structured result.

### `workspace.summary`
Returns the human-shaped summary card content (language, framework,
test command, README excerpt).

### `workspace.semanticSearch` *(V2)*
**Input:** `query` (natural language), `scope` (file/symbol/module),
`top_k`.
**Output:** ranked `chunks[]` with file, range, score, snippet.

### `workspace.symbols`, `workspace.refs`, `workspace.callgraph`,
### `workspace.depgraph` *(V2)*
Tree-sitter-backed code intelligence. Used by `code.rename`,
`code.extract`, and by the Architect agent.

### `workspace.docs.find`
Locate documentation files (`README.md`, `ARCHITECTURE.md`,
`CONTRIBUTING.md`, `docs/**/*.md`).

---

## A.5 Memory Tools

| Name              | Risk | Mut. | Tier | Deps |
| ----------------- | ---- | ---- | ---- | ---- |
| `memory.read`     | SAFE | R    | V1   | —    |
| `memory.search`   | SAFE | R    | V1   | FTS5 |
| `memory.recall`   | SAFE | R    | V1   | —    |
| `memory.write`    | SAFE | M    | V1   | —    |
| `memory.append`   | SAFE | M    | V1   | —    |
| `memory.decision` | SAFE | M    | V1   | —    |
| `memory.compact`  | SAFE | M    | V1   | LLM  |
| `memory.forget`   | SAFE | M    | V1   | —    |

### `memory.read`
**Input:** `scope` (`session`/`project`/`architecture`/`decisions`),
`section?`.
**Output:** raw markdown / structured records.

### `memory.write`
Propose a write to **agent-owned** memory regions (never overwriting
user-edited sections without a patch + approval, §23.5).

### `memory.append`
Append-only writes to session and decision logs.

### `memory.decision`
Specialized append for ADR-style entries: `{title, context, decision,
consequences, alternatives_considered, status}`.

### `memory.search`
SQLite FTS5 over memory. V2 hybrids in `workspace.semanticSearch`.

### `memory.recall`
High-level retrieval used by `ContextAssembler`. Returns scored chunks
ready for context injection.

### `memory.compact`
Run the compressor (§23.3) on demand.

### `memory.forget`
Tombstone a record (kept for audit; not surfaced to LLM thereafter).
**Notes:** requires explicit user approval.

---

## A.6 Agent / Task Tools

| Name              | Risk | Mut. | Tier | Deps |
| ----------------- | ---- | ---- | ---- | ---- |
| `task.plan`       | SAFE | M    | V1   | LLM  |
| `task.replan`     | SAFE | M    | V1   | LLM  |
| `task.verify`     | SAFE | R    | V1   | LLM  |
| `task.status`     | SAFE | R    | V1   | —    |
| `task.delegate`   | SAFE | M    | V2   | —    |
| `task.parallel`   | SAFE | M    | V2   | —    |
| `task.checkpoint` | SAFE | M    | V1   | —    |

### `task.plan` / `task.replan`
Invoke the Planner with current state. Output is a `Plan` (typed list
of `Step`s with goals + success criteria).

### `task.verify`
Run a Verifier evaluation on a step's success criteria using the
recorded `Observation`.

### `task.delegate` *(V2)*
Hand off a subgoal to a named agent (`coder`, `reviewer`, etc.).

### `task.parallel` *(V2)*
Schedule a DAG of subtasks; respects cancellation propagation.

### `task.checkpoint`
Persist the current `AgentState` synchronously. Used before any risky
multi-step operation so resume is exact.

---

## A.7 UI / Interaction Tools

| Name              | Risk | Mut. | Tier | Deps |
| ----------------- | ---- | ---- | ---- | ---- |
| `notify.user`     | SAFE | —    | V1   | —    |
| `ask.user`        | SAFE | —    | V1   | —    |
| `present.diff`    | SAFE | —    | V1   | —    |
| `present.plan`    | SAFE | —    | V1   | —    |
| `present.table`   | SAFE | —    | V1   | —    |
| `present.code`    | SAFE | —    | V1   | —    |
| `present.image`   | SAFE | —    | V2   | iTerm2/Kitty image protocol |
| `notify.system`   | SAFE | —    | V1   | UserNotifications.framework  |

### `notify.user`
Post a non-blocking toast in the UI.

### `ask.user`
Block the agent loop until the user answers. **Input:** `prompt`,
`choices[]?`, `default?`, `multiline` (bool).
**Output:** `response`.
**Notes:** the agent SHOULD prefer `notify.user` for status; `ask.user`
is for genuine decision points (e.g. "which test framework should I
use?").

### `present.diff`, `present.plan`, `present.table`, `present.code`
Render structured content into the appropriate UI component.

### `present.image` *(V2)*
Inline images via terminal image protocols (Kitty, iTerm2). Detected at
startup; absent in Terminal.app.

### `notify.system`
macOS Notification Center alert (uses `UserNotifications.framework`).
Off by default; opt-in for long-running sessions.

---

## A.8 Code Intelligence Tools

| Name              | Risk      | Mut. | Tier | Deps                      |
| ----------------- | --------- | ---- | ---- | ------------------------- |
| `code.format`     | MODERATE  | W    | V1   | `swift-format`, `prettier`, `ruff`, `gofmt`, `rustfmt` |
| `code.lint`       | SAFE      | R    | V1   | `swiftlint`, `eslint`, `ruff`, `golangci-lint`, `clippy` |
| `code.parse`      | SAFE      | R    | V2   | tree-sitter               |
| `code.symbols`    | SAFE      | R    | V2   | tree-sitter               |
| `code.refs`       | SAFE      | R    | V2   | tree-sitter               |
| `code.rename`     | MODERATE  | W    | V2   | tree-sitter               |
| `code.extract`    | MODERATE  | W    | V2   | tree-sitter               |
| `code.complexity` | SAFE      | R    | V2   | tree-sitter               |
| `code.doc`        | MODERATE  | W    | V2   | tree-sitter + LLM         |
| `code.modernize`  | MODERATE  | W    | V2   | tree-sitter + LLM         |

### `code.format`
Detect formatter for language; run; capture output. Always routes
writes through patch workflow.

### `code.lint`
Run linter; parse output into structured `findings[]`.

### `code.rename`, `code.extract`, `code.doc`, `code.modernize` *(V2)*
Ref-aware refactor primitives. Each produces a `ChangeSet` for review.

### `code.complexity`
Cyclomatic / cognitive complexity per function. Used by Reviewer agent.

---

## A.9 Build / Test / Package Tools

| Name                | Risk      | Mut. | Tier | Deps             |
| ------------------- | --------- | ---- | ---- | ---------------- |
| `build.run`         | per-cmd   | S    | V1   | toolchain        |
| `test.run`          | per-cmd   | S    | V1   | toolchain        |
| `lint.run`          | SAFE      | S    | V1   | linter binaries  |
| `format.run`        | MODERATE  | S,W  | V1   | formatter binaries |
| `package.install`   | MODERATE  | S,W,N| V1   | npm/pnpm/yarn/pip/cargo/swift/brew |
| `package.add`       | MODERATE  | W    | V1   | manifest editors |
| `package.remove`    | MODERATE  | W    | V1   | manifest editors |
| `package.audit`     | SAFE      | S,N  | V2   | `npm audit`, `pip-audit`, `cargo audit` |
| `package.outdated`  | SAFE      | S,N  | V2   | package managers |
| `coverage.run`      | per-cmd   | S    | V2   | language-specific |

### `build.run`
Wrapper that selects the right build command from `workspace.detect`
(or workspace config override). Streams output.

### `test.run`
Same shape, for tests. Parses output where possible into
`failures[]` (per-test) to drive the Verifier.

### `package.install` *(MODERATE → CRITICAL if global)*
Local installs are MODERATE; `-g`/`--global` is CRITICAL.

### `package.audit`, `package.outdated` *(V2)*
Read-only network operations.

---

## A.10 Web / Network Tools  *(V2)*

| Name              | Risk      | Mut. | Tier | Deps  |
| ----------------- | --------- | ---- | ---- | ----- |
| `web.search`      | SAFE      | N    | V2   | search API |
| `web.fetch`       | MODERATE  | N    | V2   | URLSession |
| `http.request`    | MODERATE  | N    | V2   | URLSession |
| `docs.search`     | SAFE      | N    | V2   | provider-specific |
| `docs.fetch`      | SAFE      | N    | V2   | provider-specific |
| `url.parse`       | SAFE      | —    | V2   | —     |

### `web.search` *(V2)*
**Input:** `query`, `limit`, `provider` (DuckDuckGo / Brave / Tavily /
SerpAPI; configurable).
**Output:** `results[]` with title, url, snippet.

### `web.fetch` *(V2)*
**Input:** `url`, `max_bytes` (default 1 MB), `allow_redirects` (max 5),
`render` (`raw`/`readability`).
**Output:** `status`, `headers`, `content`, `final_url`.
**Notes:** scheme allow-list (`https://` only by default); host
allow-list configurable.

### `http.request` *(V2)*
General HTTP. Methods restricted to `GET`/`HEAD` unless elevated.

### `docs.search`, `docs.fetch` *(V2)*
Provider-aware retrieval for known doc sources (MDN, Swift docs,
Python docs, package registries).

---

## A.11 Database Tools  *(V2)*

| Name              | Risk      | Mut. | Tier | Deps                |
| ----------------- | --------- | ---- | ---- | ------------------- |
| `db.connect`      | MODERATE  | N    | V2   | driver per dialect  |
| `db.schema`       | SAFE      | R,N  | V2   | driver              |
| `db.query`        | per-query | R/W,N| V2   | driver              |
| `db.explain`      | SAFE      | R,N  | V2   | driver              |
| `db.migrate`      | DANGEROUS | W,N  | V2   | driver              |

### `db.query` *(V2)*
SELECTs are SAFE→MODERATE; INSERT/UPDATE/DELETE are DANGEROUS;
DDL is CRITICAL. Connection strings live in Keychain, never in
config files committed to VCS.

---

## A.12 Container / Cloud Tools  *(V2)*

| Name                  | Risk      | Mut. | Tier | Deps           |
| --------------------- | --------- | ---- | ---- | -------------- |
| `docker.ps`           | SAFE      | R    | V2   | `docker` CLI   |
| `docker.images`       | SAFE      | R    | V2   | `docker` CLI   |
| `docker.logs`         | SAFE      | R    | V2   | `docker` CLI   |
| `docker.run`          | MODERATE  | S    | V2   | `docker` CLI   |
| `docker.exec`         | MODERATE  | S    | V2   | `docker` CLI   |
| `docker.build`        | MODERATE  | S    | V2   | `docker` CLI   |
| `docker.compose`      | MODERATE  | S    | V2   | `docker compose` |
| `k8s.contexts`        | SAFE      | R    | V2   | `kubectl`      |
| `k8s.inspect`         | SAFE      | R,N  | V2   | `kubectl`      |
| `k8s.logs`            | SAFE      | R,N  | V2   | `kubectl`      |
| `k8s.apply`           | DANGEROUS | W,N  | V2   | `kubectl`      |

### `docker.run` *(V2)*
Mounts restricted by default to workspace; running with
`--privileged` is CRITICAL.

### `k8s.apply` *(V2)*
Always shows a dry-run diff first. CRITICAL on production contexts
(heuristic: context contains `prod`).

---

## A.13 Plugin / Skill Tools  *(V2)*

| Name              | Risk      | Mut. | Tier | Deps |
| ----------------- | --------- | ---- | ---- | ---- |
| `plugin.list`     | SAFE      | R    | V2   | —    |
| `plugin.load`     | MODERATE  | M    | V2   | code signing |
| `plugin.unload`   | SAFE      | M    | V2   | —    |
| `plugin.invoke`   | per-plugin| varies | V2 | plugin |
| `skill.list`      | SAFE      | R    | V2   | —    |
| `skill.run`       | per-skill | varies | V2 | skill registry |
| `skill.install`   | MODERATE  | M    | V2   | network + signing |

---

## A.14 Observability Tools

| Name              | Risk | Mut. | Tier | Deps |
| ----------------- | ---- | ---- | ---- | ---- |
| `log.tail`        | SAFE | R    | V1   | —    |
| `log.search`      | SAFE | R    | V1   | —    |
| `trace.show`      | SAFE | R    | V1   | —    |
| `metrics.get`     | SAFE | R    | V1   | —    |
| `cost.summary`    | SAFE | R    | V1   | —    |

---

## A.15 Risk Aggregation Rules

Several tools have **per-call** risk that depends on inputs:

- `shell.run` — classified by `RiskClassifier` (§19).
- `file.write`, `file.patch` — MODERATE for in-workspace; DANGEROUS for
  touching > 50 files; CRITICAL for paths matching
  `~/.ssh`, `~/.aws`, `~/Library`, `/System`, `/usr`, `/private`.
- `file.delete` — DANGEROUS in-workspace; CRITICAL outside.
- `git.*` writes — MODERATE except `push` (CRITICAL) and
  `reset --hard`/`rebase` rewriting public history (CRITICAL).
- `package.install` — MODERATE local; CRITICAL global / system.
- `docker.run` — MODERATE; CRITICAL if `--privileged`, host networking,
  or host volume mounts outside workspace.
- `k8s.apply` — DANGEROUS; CRITICAL on prod-like contexts.
- `db.query` — by SQL verb (see A.11).

---

# Appendix B — Skill Catalog (V2)

Skills are versioned, prompted workflows with a constrained tool
whitelist. They live under `~/.zyquo/skills/<id>/` and may be
project-overridden via `.zyquo/skills/<id>/`. Each skill MUST declare
its `tools_allowed`, `inputs`, and `verify`.

### B.1 Build / Test Doctor

| ID                   | Title                                          |
| -------------------- | ---------------------------------------------- |
| `fix_swift_build`    | Diagnose & fix a failing Swift build           |
| `fix_node_build`     | Diagnose & fix a failing Node build            |
| `fix_python_build`   | Diagnose & fix a failing Python build          |
| `fix_rust_build`     | Diagnose & fix a failing Rust build            |
| `fix_go_build`       | Diagnose & fix a failing Go build              |
| `fix_failing_tests`  | Localize & fix failing tests                   |
| `bisect_regression`  | `git bisect`-driven regression localization    |

### B.2 Onboarding / Explanation

| ID                    | Title                                       |
| --------------------- | ------------------------------------------- |
| `onboard_repo`        | First-time deep tour of an unfamiliar repo  |
| `explain_architecture`| Produce / refresh `ARCHITECTURE.md`         |
| `find_entrypoints`    | Locate runnable entrypoints                 |
| `summarize_module`    | Summarize a directory or module             |
| `summarize_pr`        | Plain-English summary of a PR diff          |

### B.3 Code Quality

| ID                       | Title                                       |
| ------------------------ | ------------------------------------------- |
| `code_review`            | Reviewer-agent pass over staged changes     |
| `find_dead_code`         | Locate unused symbols / files               |
| `find_duplicate_code`    | Locate near-duplicate code blocks           |
| `accessibility_audit`    | A11y audit (web/iOS, per detected stack)    |
| `security_audit`         | Static security audit                       |
| `dependency_audit`       | Dependency vulnerability + outdated audit   |
| `performance_audit`      | Hotspot localization via profiler outputs   |
| `ts_strict_mode`         | Move a TS project to strict mode            |
| `python_typing_audit`    | mypy/pyright clean-up                       |
| `swift_modernize`        | Adopt Swift Concurrency / typed throws      |

### B.4 Refactor

| ID                            | Title                                  |
| ----------------------------- | -------------------------------------- |
| `refactor_extract_module`     | Extract a module from a monolith       |
| `refactor_rename_symbol`      | Project-wide rename                    |
| `refactor_split_file`         | Split a large file by responsibility   |
| `refactor_merge_files`        | Merge two files cleanly                |
| `refactor_introduce_interface`| Insert protocol/interface boundary     |

### B.5 Docs / Release

| ID                    | Title                                       |
| --------------------- | ------------------------------------------- |
| `generate_docs`       | Generate inline docs for symbols            |
| `generate_readme`     | Generate or refresh `README.md`             |
| `generate_changelog`  | Generate CHANGELOG since last tag           |
| `release_notes`       | Customer-facing release notes               |
| `pr_description`      | Draft a PR description from a diff          |
| `commit_message`      | Draft a commit message from a staged diff   |
| `branch_name`         | Suggest a branch name from an intent        |

### B.6 Features / Migrations

| ID                          | Title                                  |
| --------------------------- | -------------------------------------- |
| `add_auth_flow`             | Scaffold an auth flow                  |
| `add_feature_flag`          | Add a feature flag with rollout hooks  |
| `migrate_database_schema`   | Author + apply a DB migration          |
| `migrate_framework_version` | Major-version framework upgrade        |
| `upgrade_dependencies`      | Safe dependency upgrade campaign       |
| `internationalize`          | i18n scaffold for detected stack       |
| `generate_tests`            | Generate test scaffolds for a target   |
| `generate_migration`        | Generate ORM migration                 |

### B.7 Skill Manifest (canonical)

```yaml
id: fix_swift_build
version: 0.1.0
title: Fix a failing Swift build
authors: [zyquo]
inputs:
  - { name: package_path,   type: path,   required: true }
  - { name: test_filter,    type: string, required: false }
tools_allowed:
  - shell.run        # restricted to: swift build, swift test, xcodebuild
  - file.read
  - file.search
  - file.patch
  - git.status
  - git.diff
  - test.run
  - build.run
prompt: ./prompt.md
verify:
  command: "swift test"
  expect_exit_code: 0
budget:
  max_steps: 25
  max_cost_usd: 1.50
risk_ceiling: MODERATE   # skill cannot escalate above this
```

---

# Appendix C — External APIs

For each external API: protocol, auth, scopes, V1/V2, failure modes,
known rate limits. All keys live in Keychain (§25.3) unless noted.

## C.1 LLM Providers

### Anthropic — `api.anthropic.com`  *(V1, primary)*
- **Protocol:** HTTPS, JSON; streaming via SSE.
- **Endpoints:** `POST /v1/messages` (with `stream=true`),
  `GET /v1/models`.
- **Auth:** `x-anthropic-api-key`, `anthropic-version` header.
- **Tool use:** native (`tools`, `tool_choice`, `tool_use` blocks).
- **Failure modes:** 401 (auth), 429 (rate), 529 (overloaded), 5xx.
- **Retry:** exp backoff with jitter on 429/529/5xx, max 3.

### OpenRouter — `openrouter.ai`  *(V1)*
- **Protocol:** HTTPS, JSON; SSE for streaming.
- **Endpoint:** `POST /api/v1/chat/completions` (OpenAI-shape) and
  `POST /api/v1/messages` (Anthropic-shape passthrough where supported).
- **Auth:** `Authorization: Bearer <key>`.
- **Notes:** acts as fallback in `ModelRouter`. Catalog cached locally.

### OpenAI — `api.openai.com`  *(V1+, optional)*
- **Endpoint:** `POST /v1/chat/completions`, `POST /v1/responses`.
- **Auth:** `Authorization: Bearer <key>`.
- **Notes:** disabled unless user logs in via `zyquo provider login openai`.

### Apple Foundation Models *(V2, local)*
- Native Swift framework; no network.
- Used opportunistically by `ModelRouter` for short summarizations.

### llama.cpp / GGUF *(V2, local)*
- In-process via Swift wrapper, Metal-accelerated.
- No API; binary + model files under
  `~/Library/Application Support/Zyquo/models/`.

## C.2 Embeddings  *(V2)*

| Provider                  | Endpoint                                       | Auth        |
| ------------------------- | ---------------------------------------------- | ----------- |
| OpenAI Embeddings         | `POST /v1/embeddings`                         | Keychain    |
| Voyage AI                 | `POST /v1/embeddings`                         | Keychain    |
| Cohere                    | `POST /v1/embed`                              | Keychain    |
| Local (`bge-small`, etc.) | in-process via Core ML / llama.cpp            | none        |

## C.3 Code Hosting

### GitHub — `api.github.com`  *(V1+)*
- **Auth:** PAT or GitHub App; OAuth device flow preferred.
- **Endpoints used:**
  - `GET /repos/{o}/{r}` — repo metadata
  - `GET /repos/{o}/{r}/issues` — issues
  - `GET /repos/{o}/{r}/pulls/{n}` — PR detail
  - `GET /repos/{o}/{r}/pulls/{n}/files` — PR diff
  - `POST /repos/{o}/{r}/issues/{n}/comments` — comment (MODERATE)
  - `POST /repos/{o}/{r}/pulls` — create PR (MODERATE)
  - `GET /repos/{o}/{r}/actions/runs` — CI status
- **Rate limit:** 5 000 req/h authenticated; respect
  `X-RateLimit-Remaining`.

### GitLab — `gitlab.com/api/v4`  *(V2)*
- **Auth:** PAT.
- **Endpoints:** projects, merge_requests, pipelines.

### Bitbucket — `api.bitbucket.org/2.0`  *(V2)*

## C.4 Search Providers  *(V2)*

| Provider     | Endpoint                                    | Auth        |
| ------------ | ------------------------------------------- | ----------- |
| Tavily       | `POST https://api.tavily.com/search`        | Keychain    |
| Brave Search | `GET  https://api.search.brave.com/res/v1`  | Keychain    |
| DuckDuckGo   | `GET  https://api.duckduckgo.com/`          | none        |
| SerpAPI      | `GET  https://serpapi.com/search`           | Keychain    |
| Kagi         | `GET  https://kagi.com/api/v0`              | Keychain    |

## C.5 Documentation Sources  *(V2)*

| Source              | Method                                        |
| ------------------- | --------------------------------------------- |
| MDN Web Docs        | Search index + fetch HTML                     |
| Swift Documentation | DocC archive parse + fetch                    |
| Python Docs         | objects.inv (Sphinx) + fetch                  |
| Rust Docs           | rustdoc JSON + fetch                          |
| npm                 | `https://registry.npmjs.org`                  |
| PyPI                | `https://pypi.org/pypi/{pkg}/json`            |
| crates.io           | `https://crates.io/api/v1/crates/{pkg}`       |
| pkg.go.dev          | `https://api.godoc.org` (legacy) / scrape     |

## C.6 Package Registries

| Registry       | Endpoint                                      | V1/V2 |
| -------------- | --------------------------------------------- | ----- |
| npm            | `registry.npmjs.org`                          | V2    |
| PyPI           | `pypi.org/pypi`                               | V2    |
| crates.io      | `crates.io/api/v1`                            | V2    |
| Swift Package Index | `swiftpackageindex.com/api`              | V2    |
| RubyGems       | `rubygems.org/api/v1`                         | V2    |
| Maven Central  | `search.maven.org/solrsearch/select`          | V2    |

## C.7 Telemetry / Crash *(V2, opt-in)*

| Service         | Endpoint            | Auth        | Default |
| --------------- | ------------------- | ----------- | ------- |
| OpenTelemetry   | configurable OTLP   | bearer      | OFF     |
| Sentry          | configurable DSN    | DSN-derived | OFF     |

## C.8 Update Channel

| Service        | Endpoint                                      | Use      |
| -------------- | --------------------------------------------- | -------- |
| Homebrew tap   | git tap (no key)                              | primary  |
| Sparkle feed   | `https://updates.zyquo.dev/appcast.xml`       | optional |

## C.9 Common Network Policies

- All requests use TLS 1.2+ (`URLSession` defaults).
- Redirects max 5; cross-host redirects re-authenticated.
- All outbound hosts MUST appear in `~/.zyquo/network_allowlist.toml`
  for non-LLM, non-update traffic in V2.

---

# Appendix D — macOS System APIs

| API / Framework            | Use                                                       | V1/V2 |
| -------------------------- | --------------------------------------------------------- | ----- |
| `Security.framework`       | Keychain Services for API keys, OAuth tokens              | V1    |
| `Foundation` (Process)     | Shell execution, subprocess management                    | V1    |
| `Foundation` (Pipe)        | stdio plumbing                                            | V1    |
| `Foundation` (URLSession)  | HTTPS to providers and web                                | V1    |
| `Foundation` (FileManager) | Workspace I/O, snapshots                                  | V1    |
| `os.log`                   | System log integration (signposts for tracing)            | V1    |
| `os.signpost`              | Tracing                                                   | V1    |
| FSEvents (`CoreServices`)  | Workspace file watcher                                    | V1    |
| `Network.framework`        | Connectivity checks, future P2P                           | V2    |
| `UserNotifications`        | Notification Center alerts                                | V1    |
| `Sandbox`                  | App-Sandbox profile for plugins                           | V2    |
| `XPC`                      | Daemon ↔ CLI ↔ plugins isolation                         | V2    |
| `launchd` / SMAppService   | `zyquod` background indexer                               | V2    |
| `CoreSpotlight` / `mdfind` | Workspace metadata + spotlight integration                | V2    |
| `Metal` / `MetalPerformanceShaders` | Local model acceleration                         | V2    |
| `Accelerate`               | Vector ops for embeddings                                 | V2    |
| Apple Foundation Models    | On-device LLM (when API ships)                            | V2    |
| `Combine` / `AsyncAlgorithms` | Streaming pipelines                                    | V1    |
| `swift-log` / `swift-metrics` | Structured logs + counters                             | V1    |
| `OSAtomic` / `os.lock`     | Low-level concurrency primitives                          | V1    |
| `AppKit` (NSPasteboard)    | `/copy` integration for export                            | V1+   |
| `AppKit` (NSWorkspace)     | `open` URLs / files                                       | V1    |
| `Accessibility` APIs       | Reserved (no use without explicit consent)                | —     |

## D.1 Permissions / Entitlements

- **No** Camera, Mic, Contacts, Calendar, Photos, Location.
- **No** Accessibility entitlement.
- **No** Full Disk Access by default; user MAY grant manually if they
  want Zyquo to act outside `~/Documents`, `~/Projects`, etc.
- **No** background mode unless `zyquod` (V2) is explicitly enabled
  via `zyquo daemon enable`.

---

# Appendix E — Binary Dependencies

Zyquo prefers shelling out to battle-tested CLIs over reimplementing
them. Each dependency is **detected** at startup; missing tools produce
graceful degradation, not hard failures.

| Binary           | Used By                                  | Required | Auto-detect path           |
| ---------------- | ---------------------------------------- | -------- | -------------------------- |
| `git`            | all `git.*` tools                        | Yes      | system + brew              |
| `rg` (ripgrep)   | `file.search`                            | Yes      | brew (`/opt/homebrew/bin`) |
| `fd`             | optional faster `file.glob`              | No       | brew                       |
| `bat`            | optional pretty `cat` fallback (UI)      | No       | brew                       |
| `delta`          | optional fancy diff piping (UI)          | No       | brew                       |
| `jq`             | JSON shell ergonomics in user commands   | No       | brew                       |
| `swift-format`   | `code.format` for Swift                  | No       | brew / Xcode               |
| `swiftlint`      | `code.lint` for Swift                    | No       | brew                       |
| `prettier`       | `code.format` for JS/TS/MD/YAML          | No       | npm / brew                 |
| `eslint`         | `code.lint` for JS/TS                    | No       | npm                        |
| `tsc`            | TS compile checks                        | No       | npm                        |
| `ruff`           | `code.format`/`code.lint` for Python     | No       | brew / pip                 |
| `mypy`/`pyright` | Python type-check                        | No       | pip / npm                  |
| `gofmt`          | `code.format` for Go                     | No       | go toolchain               |
| `golangci-lint`  | `code.lint` for Go                       | No       | brew                       |
| `rustfmt`        | `code.format` for Rust                   | No       | rustup                     |
| `clippy`         | `code.lint` for Rust                     | No       | rustup                     |
| `xcodebuild`     | Xcode-driven projects                    | No       | Xcode                      |
| `docker`         | `docker.*` tools                         | No (V2)  | Docker Desktop / colima    |
| `kubectl`        | `k8s.*` tools                            | No (V2)  | brew                       |
| `helm`           | optional k8s charting                    | No (V2)  | brew                       |
| `gh` (GitHub CLI)| optional fallback path for GitHub        | No       | brew                       |
| `glab` (GitLab CLI)| optional fallback for GitLab           | No (V2)  | brew                       |
| `sqlite3`        | optional `db.query` for SQLite           | No (V2)  | system                     |
| `psql`           | `db.query` for Postgres                  | No (V2)  | brew                       |
| `redis-cli`      | optional Redis introspection             | No (V2)  | brew                       |
| `shellcheck`     | shell snippet lint in proposals          | No       | brew                       |
| `tree`           | optional `file.tree` fallback            | No       | brew                       |
| `notarytool`     | release pipeline                         | release  | Xcode CLT                  |
| `codesign`       | release pipeline                         | release  | Xcode CLT                  |

## E.1 Detection Procedure

At startup, `Bootstrap` runs `shell.which` for each known binary,
caches results in `~/Library/Caches/Zyquo/binaries.json` with a 24 h
TTL, and exposes them through `BinaryRegistry`. Tools that depend on
a missing binary MUST fail with a structured `tool.missing_dep` error
whose `remediation` field tells the user *exactly* how to install it
(e.g. `brew install ripgrep`).

## E.2 Path Resolution

PATH is composed as:

```text
(workspace bin dir)
+ Homebrew prefix (arm64: /opt/homebrew/bin, x86_64: /usr/local/bin)
+ Xcode CLT toolchain
+ user PATH ∩ allow-list
```

Never inherits arbitrary user PATH wholesale.

---

# Appendix F — API & Tool Surface Quick Reference

| Layer            | Count (V1) | Count (V2 added) |
| ---------------- | ---------- | ---------------- |
| Shell tools      | 4          | +1               |
| Filesystem tools | 13         | +3               |
| Git tools        | 14         | +4               |
| Workspace tools  | 7          | +5               |
| Memory tools     | 8          | 0                |
| Agent tools      | 5          | +2               |
| UI tools         | 6          | +2               |
| Code intel tools | 2          | +8               |
| Build/test tools | 6          | +3               |
| Web tools        | 0          | +6               |
| Database tools   | 0          | +5               |
| Container tools  | 0          | +11              |
| Plugin tools     | 0          | +7               |
| Observability    | 5          | 0                |
| **Total**        | **70**     | **+57**          |

External APIs (V1): 2 LLM providers + Homebrew tap.
External APIs (V2): + GitHub/GitLab, search, embeddings, doc sources,
package registries, telemetry — ~15 surfaces total, all
allow-list-gated.

System APIs (V1): 9 frameworks. (V2): + 9 frameworks.

Binary deps (V1 required): `git`, `rg`. (V1 optional): ~10.
(V2 optional): ~10 more.
