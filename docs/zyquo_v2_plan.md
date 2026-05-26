# Zyquo V2 Implementation Plan

## Objective

Transform Zyquo from an AI terminal assistant into a persistent agentic operating runtime. V2 extends V1 with multi-agent orchestration, semantic code intelligence, local models, plugin system, parallel execution, and distributed runtime.

V2 phases are independent features that can be developed and shipped incrementally. Each phase ships as a minor version. There is no monolithic V2 release.

---

## Dependency Graph

```
V1 Complete
    |
    +---> Phase 1 (Multi-Agent)
    |         |
    |         +---> Phase 7 (Parallel Execution)
    |
    +---> Phase 2 (Semantic Intelligence)
    |         |
    |         +---> Phase 3 (Embeddings & Vectors)
    |                   |
    |                   +---> Phase 4 (Background Runtime)
    |
    +---> Phase 5 (Advanced Tools)
    |         |
    |         +---> Phase 6 (Skill System)
    |
    +---> Phase 8 (Local Models)
    |
    +---> Phase 9 (Distributed Runtime) --- depends on Phase 1, 7
    |
    +---> Phase 10 (Runtime Evolution) --- depends on Phase 1, 3, 6
```

Phases 1, 2, 5, and 8 can begin independently after V1. Later phases have explicit prerequisites.

---

## Phase 1: Multi-Agent Orchestration

### Goal

Create specialized internal agents that decompose complex tasks into subtasks, each handled by the best-suited agent.

### Prerequisites

V1 complete (agent loop, tool system, memory, persistence).

### Agents

| Agent | Role | Tool whitelist |
|-------|------|---------------|
| `ArchitectAgent` | Long-horizon design, ADRs, structural refactors | file.read, file.search, memory.*, task.*, workspace.* |
| `CoderAgent` | Per-task implementation, narrow scope, fast loop | All V1 tools |
| `ShellAgent` | Build/test/CI orchestration | shell.*, file.read, git.* |
| `ReviewerAgent` | Diff review, style, conventions, regression scanning | file.read, file.search, git.diff, code.lint |
| `ResearchAgent` | Doc + web search, citation, knowledge extraction | web.*, file.read, memory.* |
| `VerifierAgent` | Test execution, output parsing, success/failure proof | shell.run, file.read, test.run |

### Deliverables

| Component | Purpose |
|-----------|---------|
| `Agent/Orchestrator.swift` (extended) | Task delegation graph, subtask tracking |
| `Agent/SubAgent.swift` | Agent protocol with scoped tool whitelist |
| `Agent/AgentMessage.swift` | Typed inter-agent message protocol |
| `Agent/ChangeSetMerge.swift` | Result merge with conflict detection |
| Agent-specific system prompts | Under `Resources/prompts/agents/` |
| Agent-specific tool whitelists | Declared per agent, enforced by registry |

### Acceptance Criteria

- A 3-agent task (Architect -> Coder -> Verifier) completes without manual intervention on a fixture refactor
- Conflicts between Coder outputs are detected and surfaced to user
- Each agent's tool usage is restricted to its declared whitelist
- Inter-agent messages are visible in the timeline UI
- Memory is shared across agents within a session (with actor isolation)
- Agent selection is visible and explainable ("delegating to CoderAgent because...")

### Test Matrix

- Fixture: multi-file refactor requiring Architect + Coder + Verifier
- Conflict detection test: two Coder agents proposing conflicting edits
- Tool whitelist enforcement: agent attempt to use non-whitelisted tool fails
- Memory sharing: data written by ArchitectAgent readable by CoderAgent

---

## Phase 2: Semantic Repository Intelligence

### Goal

Deep semantic code understanding via tree-sitter AST parsing, symbol extraction, call graphs, and semantic search.

### Prerequisites

V1 complete (workspace indexing, file tools).

### Deliverables

| Component | Purpose |
|-----------|---------|
| Tree-sitter grammars | Swift, TypeScript, Python, Rust, Go, Ruby (under `Resources/grammars/`) |
| `Workspace/ASTParser.swift` | Tree-sitter parsing pipeline |
| `Workspace/SymbolExtractor.swift` | Definition/reference extraction |
| `Workspace/SemanticChunker.swift` | Function-level, class-level chunking |
| `Workspace/DependencyGraph.swift` | Import + call graph construction |
| `Workspace/ArchitectureGraph.swift` | Module-level dependency view |
| `workspace.semanticSearch` tool | Natural language -> ranked code chunks |
| `workspace.symbols` tool | Symbol lookup by name/kind |
| `workspace.refs` tool | Find all references to a symbol |
| `workspace.callgraph` tool | Call chain analysis |
| `workspace.depgraph` tool | Module dependency visualization |

### Acceptance Criteria

- `workspace.semanticSearch("auth flow")` returns relevant call chains, not just text matches
- Symbol extraction works for all 6 target languages
- Renaming a symbol via `file.patch` is preceded by ref-aware preview
- Call graph visualizes in the terminal as an ASCII tree
- Incremental updates: re-parse only changed files (< 200 ms for single file change)

### Test Matrix

- Symbol extraction accuracy across 6 languages (fixture repos)
- Semantic search relevance vs lexical search (labeled benchmark, >= 20% improvement at recall@10)
- Call graph correctness on known codebases
- Incremental parse performance (single file change < 200 ms)
- Large codebase scale test (100k+ LOC repo)

---

## Phase 3: Embeddings and Local Vector Memory

### Goal

Add persistent semantic memory via embeddings, enabling long-term recall that outlasts context windows.

### Prerequisites

Phase 2 (semantic chunking provides the input for embeddings).

### Deliverables

| Component | Purpose |
|-----------|---------|
| `Memory/EmbeddingPipeline.swift` | Chunk -> embed -> store pipeline |
| `Memory/LocalEmbedder.swift` | Local embedding model (bge-small via Core ML) |
| `Memory/CloudEmbedder.swift` | Cloud embedding (OpenAI, Voyage, Cohere) |
| `Memory/VectorStore.swift` | SQLite + sqlite-vec extension |
| `Memory/HybridRetriever.swift` | BM25 + cosine hybrid ranking |
| Vector quantization | Size control for large codebases |
| Incremental update pipeline | FSEvents -> re-embed changed chunks |

### Storage

`.zyquo/index/vectors.sqlite` with `sqlite-vec` extension.

### Acceptance Criteria

- Long-term semantic memory survives restarts
- Recall@10 on a labeled benchmark beats lexical-only (V1) by >= 20%
- Embedding pipeline processes 10k chunks in < 60 s (local model)
- Incremental updates: re-embed only changed files
- Vector DB size < 10% of source code size (after quantization)

### Test Matrix

- Retrieval quality: labeled query set with expected results
- Local vs cloud embedding quality comparison
- Incremental update correctness (edit file, re-embed, verify updated results)
- Vector DB size vs source size ratio
- Cold-start embedding pipeline performance

---

## Phase 4: Background Intelligence Runtime

### Goal

Continuous workspace awareness via a background daemon that maintains the index, watches for changes, and keeps memory current.

### Prerequisites

Phase 3 (embeddings for the background indexer to maintain).

### Deliverables

| Component | Purpose |
|-----------|---------|
| `zyquod` (daemon binary) | Background indexer as launchd agent |
| XPC service | Communication between CLI and daemon |
| FSEvents watcher | File change detection, batched updates |
| Git monitor | Branch changes, commit detection |
| Incremental summarizer | Background memory compression |
| Stale memory cleanup | Prune orphaned memory chunks |
| `launchd` plist | Auto-start, resource limits |

### Acceptance Criteria

- `zyquod` runs as a launchd agent (`zyquo daemon enable`)
- Index lag after edit: < 500 ms p95
- Daemon CPU at idle: < 1%
- Daemon memory at idle: < 50 MB RSS
- CLI communicates with daemon via XPC (shared index, no duplicate work)
- `zyquo daemon status` shows health metrics

### Test Matrix

- Daemon startup/shutdown lifecycle
- Index freshness after rapid file changes
- CPU/memory monitoring under idle and active conditions
- XPC communication reliability
- Crash recovery (daemon restarts cleanly after SIGKILL)
- launchd integration test (enable/disable/status)

---

## Phase 5: Advanced Tool Ecosystem

### Goal

Expand the tool surface with web, database, container, and plugin-loaded tools.

### Prerequisites

V1 complete (tool protocol, registry, risk system).

### Deliverables

| Tool | Risk | Purpose |
|------|------|---------|
| `web.search` | SAFE | Search via Tavily/Brave/DuckDuckGo |
| `web.fetch` | MODERATE | URL fetch with readability extraction |
| `http.request` | MODERATE | General HTTP (GET/HEAD default) |
| `docs.search` | SAFE | Provider-aware doc retrieval |
| `docs.fetch` | SAFE | Fetch specific doc pages |
| `db.connect` | MODERATE | Database connection management |
| `db.schema` | SAFE | Schema introspection |
| `db.query` | per-query | SQL execution with verb-based risk |
| `db.explain` | SAFE | Query plan analysis |
| `docker.ps/images/logs` | SAFE | Container read ops |
| `docker.run/exec/build` | MODERATE | Container write ops |
| `docker.compose` | MODERATE | Compose orchestration |
| Plugin loader | -- | Signed bundle loading |
| Plugin sandbox | -- | Apple Sandbox profile + entitlements |
| Plugin manifest | -- | TOML declaration of permissions |

### Plugin Manifest Format

```toml
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

- Unsigned plugins fail to load with clear error
- Plugins cannot exceed declared permissions
- `web.fetch` respects scheme allow-list (https only by default)
- `db.query` risk classification works by SQL verb (SELECT=SAFE, INSERT=DANGEROUS, DDL=CRITICAL)
- `docker.run --privileged` is CRITICAL
- Tool spans visible in `zyquo trace`
- `zyquo tools list` shows all registered tools including plugins

### Test Matrix

- Plugin signature verification (valid, invalid, missing)
- Plugin permission enforcement (attempt to exceed declared perms)
- Web fetch: redirect following, scheme restriction, size cap
- DB query risk classification by SQL verb
- Docker privileged mode escalation test

---

## Phase 6: Skill System

### Goal

Compressed procedural intelligence: versioned, prompted workflows with constrained tool access.

### Prerequisites

Phase 5 (expanded tool ecosystem for skills to leverage).

### Deliverables

| Component | Purpose |
|-----------|---------|
| `Skills/SkillLoader.swift` | YAML + prompt.md loader |
| `Skills/SkillRunner.swift` | Execution engine with scoped tools |
| `Skills/SkillRegistry.swift` | List, search, version management |
| `Skills/SkillMemory.swift` | Per-skill scratch space |
| `skill.list` tool | List available skills |
| `skill.run` tool | Execute a skill by ID |
| `skill.install` tool | Install from registry (V2+) |
| Shipped skills | See catalog below |

### Skill Manifest (YAML)

```yaml
id: fix_swift_build
version: 0.1.0
title: Fix a failing Swift build
inputs:
  - { name: package_path, type: path, required: true }
tools_allowed:
  - shell.run
  - file.read
  - file.patch
  - git.status
  - test.run
  - build.run
prompt: ./prompt.md
verify:
  command: "swift test"
  expect_exit_code: 0
budget:
  max_steps: 25
  max_cost_usd: 1.50
risk_ceiling: MODERATE
```

### Shipped Skills (V2)

| Category | Skills |
|----------|--------|
| Build/Test Doctor | `fix_swift_build`, `fix_node_build`, `fix_python_build`, `fix_failing_tests` |
| Onboarding | `onboard_repo`, `explain_architecture`, `summarize_module` |
| Code Quality | `code_review`, `find_dead_code`, `security_audit`, `dependency_audit` |
| Refactor | `refactor_extract_module`, `refactor_rename_symbol`, `refactor_split_file` |
| Docs/Release | `generate_docs`, `generate_changelog`, `pr_description`, `commit_message` |

### Acceptance Criteria

- Skills are listable via `zyquo skills list`
- Running a skill creates a session stamped with the skill ID
- Skill tool whitelist is enforced (attempt to use non-whitelisted tool fails)
- Skill budget (max_steps, max_cost) is enforced
- Risk ceiling prevents skill from escalating above declared level
- Verification command runs after skill completion

### Test Matrix

- Skill loading from project `.zyquo/skills/` and global `~/.zyquo/skills/`
- Tool whitelist enforcement
- Budget enforcement (steps and cost)
- Risk ceiling enforcement
- Verification pass/fail handling
- Skill versioning (loading correct version)

---

## Phase 7: Parallel Execution Runtime

### Goal

Enable concurrent agent workflows with dependency-aware scheduling and cancellation propagation.

### Prerequisites

Phase 1 (multi-agent orchestration for parallel subtask delegation).

### Deliverables

| Component | Purpose |
|-----------|---------|
| `Agent/TaskScheduler.swift` | DAG-based task scheduling |
| `Agent/DependencyGraph.swift` | Topological execution ordering |
| `Agent/ParallelExecutor.swift` | TaskGroup-based concurrent execution |
| `Agent/ResourceLimiter.swift` | Concurrent task limits, memory caps |
| `Agent/DAGView.swift` | Live DAG visualization in terminal |
| `task.parallel` tool | Schedule a DAG of subtasks |

### Acceptance Criteria

- DAG with 4 independent leaves runs concurrently; reconciles cleanly
- Cancellation propagates within 200 ms across all active nodes
- Dependency ordering is correct (child waits for parent)
- Resource limits prevent unbounded parallelism
- DAG visualization renders live in the terminal
- Conflict detection when parallel agents touch same files

### Test Matrix

- DAG correctness: topological order preserved
- Parallel execution: 4 independent tasks run concurrently (measure wall time vs sequential)
- Cancellation propagation across DAG
- Conflict detection: two parallel agents edit same file
- Resource limit enforcement (max concurrent tasks)
- Failure handling: one node fails, siblings continue, dependents are cancelled

---

## Phase 8: Local Model Runtime

### Goal

Offline AI execution via local models, with hybrid routing between local and cloud.

### Prerequisites

V1 complete (provider protocol, model router).

### Deliverables

| Component | Purpose |
|-----------|---------|
| `Models/LocalProvider.swift` | Local model provider (llama.cpp Swift wrapper) |
| `Models/GGUFLoader.swift` | GGUF model loading and validation |
| `Models/ModelManager.swift` | Download, verify, prune local models |
| `Models/MetalAccelerator.swift` | Metal GPU acceleration for inference |
| Model routing update | Automatic local/cloud selection by task complexity |
| `zyquo models list` | List available local and cloud models |
| `zyquo models pull <id>` | Download a local model |
| Apple Foundation Models adapter | When/if API surface stabilizes |

### Storage

`~/Library/Application Support/Zyquo/models/` for GGUF files.

### Acceptance Criteria

- A 7B Q4 model can drive `zyquo ask` for offline summaries
- Hybrid mode falls back to cloud only when local confidence is low
- Metal acceleration reduces inference latency by >= 50% vs CPU-only
- Model download shows progress bar, verifies checksums
- `zyquo models list` shows both local (downloaded) and cloud models
- Local model streaming works with the same `AsyncThrowingStream<LLMEvent>` interface

### Test Matrix

- Local model loading and inference (Q4, Q5, Q8 quantizations)
- Metal vs CPU performance comparison
- Hybrid routing: simple query -> local, complex query -> cloud
- Model download integrity (checksum verification)
- Memory usage under local inference (< 8 GB for 7B Q4)
- Cancellation during local inference

---

## Phase 9: Distributed Agent Runtime

### Goal

Enable cooperative execution across multiple Macs on a LAN, targeting MacLustr cluster integration.

### Prerequisites

Phase 1 (multi-agent), Phase 7 (parallel execution).

### Deliverables

| Component | Purpose |
|-----------|---------|
| `Distributed/NodeAgent.swift` | Remote agent node (mTLS gRPC) |
| `Distributed/ClusterScheduler.swift` | Node discovery, task distribution |
| `Distributed/RemoteShell.swift` | Remote shell execution |
| `Distributed/DistributedMemory.swift` | CRDT-friendly shared memory |
| `Distributed/SecureTransport.swift` | mTLS for node communication |
| `Distributed/NodeMonitor.swift` | Health checks, failover |
| `Distributed/FaultRecovery.swift` | Graceful degradation on node loss |

### Acceptance Criteria

- Two Macs on a LAN can run a single Zyquo session cooperatively
- Loss of one node degrades gracefully, not catastrophically
- Task distribution is proportional to node capability (core count)
- mTLS prevents unauthorized node participation
- Distributed memory converges (CRDT semantics)
- `zyquo cluster status` shows node health

### Test Matrix

- Two-node cooperative session (local + remote)
- Node failure mid-task (graceful degradation)
- Network partition handling
- mTLS authentication (valid cert, invalid cert, expired cert)
- Task distribution proportionality
- Memory convergence across nodes

---

## Phase 10: Runtime Evolution

### Goal

Transform Zyquo into a persistent cognitive runtime with long-lived sessions, autonomous workflows, and self-improving behavior.

### Prerequisites

Phase 1 (multi-agent), Phase 3 (embeddings), Phase 6 (skills).

### Deliverables

| Component | Purpose |
|-----------|---------|
| Long-lived sessions | Multi-day sessions with periodic checkpointing |
| Scheduled workflows | Cron-shaped autonomous tasks |
| Adaptive planning | Policy that learns from outcomes |
| Workflow extraction | Extract reusable skills from successful sessions |
| Memory compression at scale | Handle months of accumulated memory |
| Project evolution tracking | LOC, complexity, test coverage trends |
| Self-improving summaries | Summaries that get better as more context accumulates |
| Context graphs | Persistent entity-relationship graphs across sessions |

### Acceptance Criteria

- A 7-day session preserves coherent state across at least 20 resumes
- Self-extracted skills are reviewable and accept/reject-able by user
- Scheduled workflows run via launchd and report results
- Memory compression handles 6+ months of session data
- Adaptive planning shows measurable improvement in plan quality over time
- Project evolution dashboard shows meaningful trends

### Test Matrix

- Long-lived session coherence (simulate 20 resumes over 7 days)
- Skill extraction quality (extracted skill matches manual version)
- Scheduled workflow execution (launchd trigger, run, report)
- Memory compression at scale (100k+ events)
- Adaptive planning evaluation (A/B with baseline policy)

---

## Timeline Summary

| Phase | Description | Estimated effort | Prerequisites |
|-------|-------------|-----------------|---------------|
| 1 | Multi-Agent Orchestration | 3 weeks | V1 |
| 2 | Semantic Intelligence | 3 weeks | V1 |
| 3 | Embeddings & Vectors | 2 weeks | Phase 2 |
| 4 | Background Runtime | 2 weeks | Phase 3 |
| 5 | Advanced Tools | 3 weeks | V1 |
| 6 | Skill System | 2 weeks | Phase 5 |
| 7 | Parallel Execution | 2 weeks | Phase 1 |
| 8 | Local Models | 3 weeks | V1 |
| 9 | Distributed Runtime | 4 weeks | Phase 1, 7 |
| 10 | Runtime Evolution | 4 weeks | Phase 1, 3, 6 |

**Parallel tracks after V1:**
- Track A: Phase 1 -> Phase 7 -> Phase 9
- Track B: Phase 2 -> Phase 3 -> Phase 4 -> Phase 10
- Track C: Phase 5 -> Phase 6 -> Phase 10
- Track D: Phase 8 (independent)

**Estimated total:** 20-28 weeks across all tracks, depending on parallelization. Phases ship incrementally as minor versions (2.1, 2.2, ..., 2.10).
