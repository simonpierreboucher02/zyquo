# Zyquo

Native macOS AI terminal agent runtime.

Zyquo is a Swift-native, terminal-first AI agent for macOS. It combines autonomous multi-step reasoning with safe, approval-gated execution -- all rendered in a premium terminal interface.

## Features

- **Terminal-first**: Beautiful ANSI rendering with Unicode panels, syntax highlighting, diff views, and themed output. No Electron, no browser.
- **Patch-gated editing**: All file writes go through a unified diff workflow. Every change is reviewable, approvable, and reversible.
- **Tiered risk classification**: Shell commands are classified as SAFE, MODERATE, DANGEROUS, or CRITICAL. Each tier has distinct approval requirements.
- **Persistent memory**: Project memory, session persistence, and decision logs survive restarts. The agent remembers context across sessions.
- **Agentic runtime**: Plan-execute-verify loop with multi-step reasoning, tool orchestration, and automatic replanning on failure.
- **Swift-native performance**: Cold start under 120ms. No Python or Node.js in the hot path. macOS Keychain for secrets.
- **Provider-agnostic**: Anthropic (primary), OpenRouter, with local model support planned for V2.
- **Deep repo intelligence**: Automatic language, framework, and package manager detection. Git-aware workspace scanning.

## Quick Start

### Build from Source

```bash
git clone https://github.com/your-org/zyquo.git
cd zyquo
swift build -c release
```

### Set Up a Provider

```bash
# Store your Anthropic API key in macOS Keychain
.build/release/zyquo provider login anthropic

# Verify your setup
.build/release/zyquo doctor
```

### Basic Usage

```bash
# Interactive mode (default)
zyquo

# Single-shot question
zyquo ask "explain this repo"

# Agentic run with tools
zyquo run "fix the failing tests"

# Plan without executing
zyquo plan "add authentication"

# Check workspace
zyquo status
```

## Commands

| Command | Purpose |
|---------|---------|
| `zyquo` | Launch interactive REPL (default) |
| `zyquo ask "question"` | Single-shot Q&A (no tools) |
| `zyquo run "intent"` | Agentic run with tools enabled |
| `zyquo plan "intent"` | Plan-only mode (no execution) |
| `zyquo init` | Initialize .zyquo/ workspace |
| `zyquo doctor` | Diagnostics and health check |
| `zyquo status` | Show workspace analysis |
| `zyquo config get/set` | Read or write configuration |
| `zyquo provider login` | Store API key in Keychain |
| `zyquo version` | Version and build info |

### Global Flags

| Flag | Effect |
|------|--------|
| `--no-color` | Disable ANSI color output |
| `--json` | Machine-readable JSON output |
| `--yes` | Auto-approve SAFE-tier actions |
| `--dry-run` | Plan but never execute |
| `--model <id>` | Override session model |
| `--provider <id>` | Override session provider |
| `--max-steps <n>` | Hard cap on agent steps |
| `--max-cost <usd>` | Hard cap on session cost |
| `--verbose` | Increase log verbosity |

## Architecture

```
Sources/Zyquo/
  Commands/      CLI subcommands (ArgumentParser)
  Agent/         Planning, execution, verification loop
  Models/        LLM provider abstraction (Anthropic, OpenRouter)
  Shell/         Subprocess execution with streaming
  Workspace/     Repo detection, indexing, boundary guard
  Diff/          Patch generation, application, conflict resolution
  UI/            Terminal renderer, panels, themes, components
  Security/      Keychain, approval gates, trust store, redaction
  Memory/        Session, project, and decision memory
  Persistence/   SQLite-backed storage
  Observability/ Structured logging, metrics
  Errors/        Typed error taxonomy with remediation hints
```

Key design principles:

1. **Transparency**: Every agent action is rendered, reviewable, and revertible.
2. **Approval over autonomy**: Trust is earned per-session via explicit escalation.
3. **Locality**: State lives on disk under `.zyquo/`. The cloud is a tool, not a home.
4. **Composition**: Tools are small, typed, and schema-validated. No eval.
5. **macOS-native**: Keychain, FSEvents, Process, Foundation. No cross-platform pretense in V1.

## Requirements

- macOS 14+ (Sonoma or later)
- Swift 5.10+
- Xcode 16+ (for building)
- `git` and `rg` (ripgrep) in PATH

## Build from Source

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run tests
swift test

# Install to /usr/local/bin
make install
```

## Configuration

Global config: `~/.zyquo/config.toml`

```toml
[ui]
theme = "zyquo-dark"

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
timeout_s = 120
```

Workspace config: `.zyquo/config.json`

## Themes

Three themes ship by default: `zyquo-dark` (default), `minimal`, and `high-contrast`. Custom themes can be added as TOML files in `~/.zyquo/themes/`.

## License

Apache-2.0. See [LICENSE](LICENSE).

## Author

Simon-Pierre Boucher
