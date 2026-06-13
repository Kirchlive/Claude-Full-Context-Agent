---
name: fan-out-fork-agents
description: Operational patterns for orchestrating multiple parallel forks in Claude Code. Covers the parent-prepares → async-dispatch → parent-merges lifecycle, worktree hygiene (including the .claude/worktrees/ gitignore lesson), the practical 6-8 concurrency limit (vs. ~10 scheduler-cap), fork-registry tracking, mandatory reporting contracts, and the federation pattern (fork-then-named-subagent for unbiased two-layer parallelism). Apply this skill EVERY time you are about to dispatch 2+ forks in the same turn, EVERY time a fan-out returns and needs reconciliation, and BEFORE the first fan-out in a new project (to set up gitignore). Complements prefer-fork-agents which decides WHEN to fork; this skill governs HOW to coordinate fork fan-outs.
when_to_use: User says "parallel agents", "multiple forks", "fan-out", "spawn N agents", "investigate X, Y, and Z in parallel", "worktree", "in worktree", or whenever you are about to dispatch 2+ forks in the same conversation turn. Also: after any fan-out returns, before declaring work complete. Also: at the very start of any project that will use fork fan-outs (for gitignore hygiene).
---

# Fork Fan-Out

## Self-check: are you the fork?

**Before applying any fan-out rule below, check your own role.** If a `‹fork-boilerplate›` block is in your prompt, you were told "you ARE the fork", or your session has `fork-context-ref` / `attributionAgent: fork` — you are a fork-worker. The entire fan-out machinery in this skill (dispatch lifecycle, registry, worktree isolation, federation pattern) applies ONLY to the parent/top-level session. As a fork you must execute your task directly with existing tools and not spawn any further agents — the runtime `‹fork-boilerplate›` directive forbids any `Agent`-tool spawn from inside a fork. See `prefer-fork-agents` → "Self-check: are you the fork?" for the full rationale.

This skill covers the *operational* layer of multi-fork dispatch — what to do when fanning out to multiple parallel forks. Decision criteria for "fork vs named subagent" live in `prefer-fork-agents`. This skill assumes that decision is already made, forks have been chosen, and the dispatcher is the parent session.

## If a fork dispatch errors (fork mode not enabled)

Fork mode needs `CLAUDE_CODE_FORK_SUBAGENT=1` in `~/.claude/settings.json`, read at startup. A plugin can't set it. If a fork dispatch errors with this unset, tell the user to run `/Claude-Full-Context-Agent:doctor` — it runs the bundled installer for their OS (sets the var, installs skills) — then restart Claude Code. One-time; later sessions already have it.

## The fan-out lifecycle

Parallel fork dispatch follows a three-stage sequence. The whole sequence is structured to maximize the prompt-cache-share benefit forks provide: the parent loads phase context once, all forks inherit it via cache, the parent reconciles results. Skipping or compressing stages produces integration failures, redundant per-fork work, and silent regressions.

### Stage 1: Parent prepares

Before issuing any fork in a fan-out batch, the parent session does the following:

1. **Pre-load all phase relevant code.** In the parent session right before dispatching the fork agents, re-read every code and source file the forks will modify or reference for phase execution. Fork agents inherit the parent's prompt cache, so the actual newest code state becomes available to all forks at zero overhead cost.
2. **Define the brief template.** What output format every fork must produce, what files they may touch, what they must NOT touch. Shared conventions go here once, not repeated per fork.
3. **Identify shared-file conventions.** If forks will produce schemas, configs, or registry entries, define the canonical filename and merge expectation upfront. Forks produce *candidates*; the parent reconciles.
4. **Provision worktrees.** For edit fan-outs, conceptually allocate isolated worktrees per fork — `.claude/worktrees/agent-<id>/` is the conventional path. Each `isolation: "worktree"` dispatch materializes one.
5. **Open the fork registry.** A markdown table tracking active forks (see "Fork registry" below). Even a 3-fork batch benefits from it.

### Stage 2: Async dispatch

Dispatch forks as a single batch, not sequentially. Each fork gets:

- A focused brief referencing the shared conventions (don't re-explain them per fork)
- Its own worktree for edit forks
- A fork-id recorded in the registry

```
Agent(description="<task-3-5-words>",
      subagent_type="fork",
      isolation="worktree",
      prompt="<focused brief with output contract>")
```

**`subagent_type: "fork"` is required** (verified in Claude Code v2.1.177). Omitting it silently dispatches a `general-purpose` subagent without inherited context — the fan-out would lose its cache-share advantage and each worker would need a full briefing. The load-bearing verification is the first line of the sidechain JSONL at `~/.claude/projects/<project>/<session>/subagents/agent-<id>.jsonl`: if `type == "fork-context-ref"`, it's a real fork. Fork-originated assistant turns also carry `"attributionAgent":"fork"`, but the first transcript line is the cheapest single check.

For read-only fan-outs (research, analysis, reporting) worktree isolation is unnecessary — forks share the parent's working directory in read-only mode and produce no merge conflicts.

### Stage 3: Parent merges

When forks return:

1. **Update the registry** — mark each fork's status (completed, failed, partial)
2. **Apply post-dispatch verification** from `prefer-fork-agents` (read summaries, diff for overlap, run integration suite, spot-check systematics)
3. **Merge shared files** — forks produce *patches or canonical-candidate files*, the parent integrates them. Forks must NOT write directly to the canonical shared file.
4. **Run integration tests/build** — fork-level success does not imply combined success
5. **Spot-check for systematic errors** across forks

The parent is the serialization point for shared files. This is by design: parallel writes to a single canonical file would race or silently overwrite.

## Worktree hygiene

When using `isolation: "worktree"`, worktrees materialize as nested directories with their own `.git` references. These will pollute the parent's git status and index unless excluded.

**Before the first fan-out in any project, add this line to the project's `.gitignore`:**

```
.claude/worktrees/
```

Without this entry, every worktree-fork run dirties the parent index with nested repositories. The fix is one line; missing it is a recurring cleanup cost on every fan-out.

If you are dispatching a fan-out in a project that does not yet have this entry, add it first. Treat it as a precondition, not an afterthought.

## Practical concurrency limit: 6-8, not 10

The scheduler accepts up to ~10 concurrent forks, but **the planning-vs-execution gap grows beyond 5-6**. At 7+ parallel tracks, retroactive auditing tends to replace actual orchestration — you discover what forks did rather than directing them.

**Soft cap at 6 parallel forks.** If the task needs more, sequentialize into waves of 4-6.

This is an empirical limit derived from production usage, not architectural. The scheduler does not enforce 6 — your operational discipline does. Reasons the gap grows:

- More forks = more independent briefs to track mentally
- Shared-file merge complexity scales roughly with K² (pairwise diff checks)
- Fork-registry coherence becomes harder to maintain

If a task seems to need 10+ parallel workers, the issue is usually decomposition: there are dependencies you haven't surfaced yet, or the slices are too small.

## Fork registry

Maintain a markdown table per session that tracks active forks. Update on dispatch and on return.

```
| Fork ID | Task                                | Worktree                          | Status      |
|---------|-------------------------------------|-----------------------------------|-------------|
| a1b2c3  | IssueReopenOp + IssueEditOp         | .claude/worktrees/agent-a1b2c3/   | completed   |
| d4e5f6  | RunRerunOp + WatchPrChecksOp        | .claude/worktrees/agent-d4e5f6/   | completed   |
| g7h8i9  | query_my_dashboard + notifications  | .claude/worktrees/agent-g7h8i9/   | in-progress |
```

Without this, forks become invisible mid-flight, integration becomes guesswork, and "lost forks" (dispatched but never reconciled) become a real failure mode.

The registry is for your own orchestration tracking. The user does not need to see it unless they ask, but you should reference fork-ids consistently in your narration so the user can trace which slice produced which result.

## Reporting contract

Every fork must end its work product with two things:

1. **A `result:` line** — single-line summary of what was produced, decided, or found
2. **A verification reference** — pointer to a test run, file diff, or other concrete artifact proving the result

Include this requirement in every fork brief:

```
Your output MUST end with:
result: <one-line summary>
verification: <test command or file path proving the result>
```

Without an enforced contract, fork outputs drift in shape and the parent's verification step becomes manual interpretation rather than structural check. The contract is a small upfront cost that compounds in reliability across many fan-outs.

## Federation pattern: fork-then-named for unbiased fan-out

When a fan-out needs both inherited methodology AND independent unbiased sub-processing per slice, use a two-layer pattern:

- **Layer 1:** parent dispatches K forks. Each inherits context, owns a research/implementation slice, applies the parent's methodology.
- **Layer 2:** each Layer 1 fork dispatches N named sub-agents. Each gets a fresh blank brief, executes parallel sub-work, returns to its Layer 1 fork.

Total effective workers = K × N. This is *not* fork recursion (forks cannot spawn forks); it is forks dispatching *named subagents* downstream, which is allowed.

Use Federation when:

- Each top-level slice benefits from inherited methodology (Layer 1 = fork)
- Each slice's internal work needs unbiased parallel discovery without parent framing (Layer 2 = named)
- The product is research/discovery rather than convergent implementation

Do NOT use Federation when:

- Layer 2 work would itself benefit from inherited context (just dispatch more Layer 1 forks instead)
- K × N exceeds 6-8 effective concurrent workers (you're past the practical cap)
- The work is convergent implementation rather than divergent exploration

Example: research project where 5 forks each investigate a domain (databases, search, identity, schema, composability), and each fork dispatches 2 sub-researchers (one for surveying existing solutions, one for evaluating fit). That's 5 × 2 = 10 effective workers, with the K=5 forks inheriting the project's research methodology and the N=2 sub-agents getting unbiased blank briefs.

## When this skill is most actionable

Whenever you are about to dispatch the second fork in a single turn, this skill applies. Specifically:

1. **Before the first fork in a new project:** ensure `.claude/worktrees/` is in `.gitignore`.
2. **Before the first fork in a batch:** pre-load all phase-relevant code into the parent session (highest-leverage step — see Stage 1), prepare brief template, define shared-file conventions, open registry.
3. **At each dispatch:** assign fork-id, record in registry, ensure worktree isolation for edits, include reporting contract in brief.
4. **At each return:** update registry, run post-dispatch verification, merge shared files at parent, run integration tests.
5. **Always:** respect the 6-fork soft cap; sequentialize beyond it into waves.

Apply silently. Reference fork-ids consistently in narration; surface the registry only on request.
