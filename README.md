# <u>Claude-[Full-Context](https://github.com/Kirchlive/Claude-Full-Context-Agent)-Agent</u>

This Plugin switches Claude Code's default subagent process, from flawed context behavior, to fork-agents-mode with full session context, including Claude Skills for correct use of forks and worktrees.

<img src="https://i.imgur.com/tnjhkDJ.png" alt="IMG" width="750">

> **v2.0.0 (2026-06-13) — Critical fix for Claude Code v2.1.177.**
> If you ran v1.0.2 on Claude Code v2.1.177 and saw `Fork is not available inside a forked worker.` on every dispatch, this was an upstream runtime bug triggered by the literal boilerplate tag (`‹fork-boilerplate›`, shown here with Unicode angles so this README itself doesn't poison your session) in the previous skill texts. v2.0.0 escapes the tag everywhere so it no longer false-positive-matches the runtime's recursion guard. See [`UPDATE.md`](UPDATE.md) for the full root-cause and recovery steps for already-poisoned sessions.

**Install:**
```
/plugin marketplace add Kirchlive/Claude-Full-Context-Agent
/plugin install Claude-Full-Context-Agent@Claude-Full-Context-Agent
```

**Verify:**
```
/Claude-Full-Context-Agent:doctor
```

Restart Claude Code.

---

## What this plugin does

1. **Ships two skills**, auto-loaded the moment the plugin is enabled — no copying required:
   - **`prefer-fork-agents`** — the *decision* policy: when to fork vs. when to use a named subagent (default-deny mindset for named, with four documented exceptions).
   - **`fan-out-fork-agents`** — the *operational* patterns: how to coordinate multiple parallel forks (lifecycle, worktree hygiene, registry, reporting contract, federation pattern).
2. **Provides the `/Claude-Full-Context-Agent:doctor` command**, which sets `CLAUDE_CODE_FORK_SUBAGENT=1` in `~/.claude/settings.json` — the one thing a plugin cannot do for itself (see below).

---

## Recommended: project-level `.gitignore`

If your project uses parallel fork fan-outs with worktree isolation, add this line to the project's `.gitignore` **before** the first fan-out:

```
.claude/worktrees/
```

Worktree-isolated forks materialize as nested directories with their own `.git` references. Without this entry, every fan-out dirties the parent index with embedded repositories. The `fan-out-fork-agents` skill enforces this as a precondition.

Anthropic also documents `.worktreeinclude` — a gitignore-syntax **allowlist** that copies otherwise-gitignored files (e.g., `.env`, `.envrc`, local `config.json`) into each new worktree at creation time. See the official [worktrees doc](https://code.claude.com/docs/en/worktrees).

---

## Behavior changes after setup

| Before | After |
| --- | --- |
| Subagents start with zero context; Claude writes summarization briefs | Forks inherit full parent context including active skills |
| Briefs are 200–2000 tokens of recap | Briefs are 50–200 tokens of pure directive |
| Lossy context handoff at every delegation | Cache-shared inheritance, ~7–10× cheaper per delegation |
| Each fork independently re-reads phase source files | Parent pre-loads them once, all forks inherit via cache |
| Each dispatch re-establishes scope and methodology | Methodology and scope inherit automatically |
| Subagents may improvise on inferred context | Forks see what the parent saw |
| Parallel work goes serial or improvised | Coordinated fan-out with registry + reporting contract |

---

## When fork is NOT the right answer

The `prefer-fork-agents` skill makes fork the default but reserves four cases where named subagents remain correct:

1. **Unbiased verdict required** — security audit, design critique, adversarial code review where the parent's framing would prejudice the result.
2. **Lightweight read-only search** — use `Explore` (Haiku-backed, cheap and fast).
3. **Plan-only mode** — use `Plan` for read-only architectural analysis.
4. **Specialized custom subagent** — a deliberately curated persona that should NOT inherit the parent's framing.

See the skill's Decision Rule section for details.

---

## Optional: hook-based hard enforcement

The skills are *soft* policies — they teach Claude to prefer fork. For hard enforcement (logging or blocking named-subagent dispatches at the tool level), this repo ships an example hook at [`hooks/pretooluse-fork-enforce.example.json`](hooks/pretooluse-fork-enforce.example.json).

It is an **example, not active by default**: the filename ends in `.example.json`, so the plugin does not load it. To enable it, either merge its `hooks` block into your `~/.claude/settings.json`, or rename a copy to `hooks/hooks.json` in a local checkout so the plugin loads it automatically (it logs every `Task` dispatch to `~/.claude/fork-policy.log`; the file documents how to upgrade it to a hard block). The skills alone have been sufficient in practice.

---

## Caveats

The skills encode these, but worth knowing upfront:

- **Concurrency:** the author's practical observation is **6 parallel forks** with diminishing returns past 5; the scheduler accepts roughly 10. Independent analysis ([Kumaran Srinivasan, Medium](https://medium.com/@kumaran.isk/how-to-run-10-parallel-claude-agents-without-everything-breaking-5b6346948e59)) suggests a 2–5 sweet spot. Treat 6 as a soft cap; sequentialize larger batches into waves.
- **No recursion:** a fork cannot spawn further forks. For two-layer parallelism, use the Federation pattern (fork → named subagent fan-out) from `fan-out-fork-agents`.
- **Compaction inheritance:** if the parent has auto-compacted, the fork inherits the compacted (lossy) state. Dispatch forks early, ideally under 60% context utilization.
- **Incompatible with coordinator mode** *(per community reports; not in official docs)*. Note: `claude --print` / headless / SDK use was previously incompatible but is **supported since v2.1.121** (2026-04-28) — see [env-vars docs](https://code.claude.com/docs/en/env-vars).
- **Cost scales with session length** — each fork carries the full parent history; long sessions with many forks accumulate tokens even with cache discounts.
- **Edit fan-outs need `isolation: "worktree"`** — without it, parallel forks share the same working directory and risk overwriting each other's edits. Combine with the `.claude/worktrees/` gitignore recommendation above.

### Known upstream bugs (May 2026)

Four open Anthropic issues materially affect any workflow that relies on `isolation: "worktree"`:

- [**#39886**](https://github.com/anthropics/claude-code/issues/39886) — `isolation: "worktree"` silently fails; the agent runs in the main repo instead of an isolated worktree, with no error raised.
- [**#50850**](https://github.com/anthropics/claude-code/issues/50850) — worktrees are branched from `origin/main` rather than the launching session's current HEAD; subagents may operate on stale code without warning.
- [**#51596**](https://github.com/anthropics/claude-code/issues/51596) — the 8-hex `agentId` prefix used for the worktree branch name can collide with a prior session's branch, causing silent reuse with leftover stashes / uncommitted state.
- [**#37258**](https://github.com/anthropics/claude-code/issues/37258) — worktree-isolated subagents can immediately fail authentication because parent credentials are masked under isolation.

These are upstream bugs, not bugs in this plugin. Track them via the linked issues.

---

## Author's production usage (2026-05-06 – 2026-05-18)

The patterns this plugin encodes are derived from the author's own production usage on a Claude Code tooling project during the window above. These are single-user observations, **not** independently reproduced benchmarks — read them as anecdotal validation of feasibility.

| Metric | Value |
|---|---|
| Observation window | 13 days (May 6 – May 18, 2026) |
| Documented fork dispatches | 20+ |
| Sessions | 8 |
| Aggregate discovery-token volume | ~145,000 |
| Peak parallel fan-out | 7 worktree-isolated forks |
| Largest delivered release | 16 new operations, 90 tests, 2,116 insertions in a ~45-minute session sequence |

Behaviors that emerged from this usage — the 6-8 practical concurrency cap, the parent-prepares→fan-out→parent-merges sequence, the embedded-repo gitignore lesson, the federation pattern — are codified in the `fan-out-fork-agents` skill rather than left as tribal knowledge.

---

### Manual (without the marketplace)

If you cloned the repo directly instead of installing via the marketplace:

```
git clone https://github.com/Kirchlive/Claude-Full-Context-Agent.git
cd Claude-Full-Context-Agent

# macOS / Linux / WSL / Git Bash
bash install.sh

# Windows (PowerShell 7+)
.\install.ps1
```

This both sets the env var and copies the skills into `~/.claude/skills/` (so they load without the plugin). Restart Claude Code.

PowerShell users: if you hit an execution-policy error, run once `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` and re-run. Install PowerShell 7+ via `winget install --id Microsoft.Powershell` (Windows) or `brew install --cask powershell` (macOS).


Both back up your `settings.json`, merge `CLAUDE_CODE_FORK_SUBAGENT=1`, and run the verification checks. **Restart Claude Code** afterward — the variable is read only at startup.

---

## Uninstall

**Plugin:**

```
/plugin uninstall Claude-Full-Context-Agent@Claude-Full-Context-Agent
```

This removes the skills and the `/doctor` command. It does **not** remove the env var (a plugin can't touch user settings).

**Remove the env var** — delete the `CLAUDE_CODE_FORK_SUBAGENT` line from the `env` block of `~/.claude/settings.json`, or restore the timestamped backup the installer created (it prints the path):

```bash
# macOS / Linux / WSL / Git Bash
cp ~/.claude/settings.json.pre-fork-backup-<TIMESTAMP> ~/.claude/settings.json
```

```powershell
# Windows
Copy-Item "$HOME\.claude\settings.json.pre-fork-backup-<TIMESTAMP>" "$HOME\.claude\settings.json"
```

If you used the manual (non-marketplace) install, also remove the copied skills:

```bash
rm -rf ~/.claude/skills/prefer-fork-agents ~/.claude/skills/fan-out-fork-agents
```

Restart Claude Code. Behavior reverts to default named-subagent dispatch.

---
---

# Background

The sections above are everything you need to install and use the plugin. What follows is context: why it exists and what Anthropic shipped that makes it work.

## The problem

When Claude Code delegates a task to a subagent via the Task/Agent tool, the subagent starts with **zero conversation context**. Claude writes a briefing prompt summarizing what it thinks the subagent needs to know — but that summarization is lossy. Edge cases, prior decisions, and nuanced reasoning get flattened or lost.

The result: subagents improvise, hallucinate context, and produce code that doesn't match the parent session's intent. The longer and richer the parent session, the worse the loss. Mejba Ahmed documented this exact pattern in [Forked Subagents in Claude Code](https://www.mejba.me/blog/forked-subagents-claude-code-anthropic):

> "The guard at line 47 prevents the race condition you described."
> Except it didn't. The guard I was worried about wasn't in the controller at all. It was in a middleware the subagent had never seen, because its compressed context summary had flattened that middleware into a line that read, roughly, "project uses standard Laravel middleware stack."

This is the **context amnesia** failure mode the community has worked around for over a year.

---

## The landscape

The community built elaborate methodological workarounds for this:

- **[obra/superpowers](https://github.com/obra/superpowers)** — brainstorming → plan → subagent-driven-development pipeline.
- **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)** — Agile-style multi-phase workflow with story files as durable context carriers.
- **[GitHub Spec-Kit](https://github.com/github/spec-kit)** — spec files in version control; agents read specs instead of inheriting state.
- **[Pimzino/claude-code-spec-workflow](https://github.com/Pimzino/claude-code-spec-workflow)** — selective delegation of relevant context slices.
- **[NeoLabHQ/context-engineering-kit](https://github.com/NeoLabHQ/context-engineering-kit)** — Subagent-Driven Development with reflection hooks.
- **PRPs (Product Requirement Prompts)** — implementation blueprints with all-needed-context baked in.

All treat context loss as a **process problem** and solve it with discipline. They work, but layer process complexity on top of the dispatch mechanism.

---

## What Anthropic actually shipped

In Claude Code **v2.1.117** (released **April 22, 2026**), Anthropic shipped an opt-in feature called **forked subagents**: a subagent that inherits the parent's full conversation state — system prompt, message history, active skills, tool definitions, and the prompt cache. Support was extended to the SDK and non-interactive (`claude -p`) sessions in **v2.1.121** (2026-04-28).

The mechanism is **mechanical, not methodological**. Set one environment variable, and the Task/Agent tool gains the ability to dispatch context-inheriting workers when called without an explicit `subagent_type`. The fork shares the parent's prompt cache, making it dramatically cheaper than spawning a fresh subagent for tasks that need the same context.

The feature is **opt-in** via `CLAUDE_CODE_FORK_SUBAGENT=1`, **marked experimental**, and **absent from most tutorials**. Anthropic provided the mechanism; the methodologies remain useful for the cases where fork doesn't apply; and the two skills in this plugin bridge the two by encoding when to prefer which and how to coordinate fan-outs.

**Key references:**

- [Claude Code Subagents documentation](https://code.claude.com/docs/en/sub-agents) — official fork-mode mechanics
- [Issue #16153](https://github.com/anthropics/claude-code/issues/16153) — feature request articulating the underlying need
- [Issue #38443](https://github.com/anthropics/claude-code/issues/38443) — background fork dispatch follow-up
- [Fork Subagents in Claude Code](https://www.buildthisnow.com/blog/guide/mechanics/claude-code-fork-subagent) — empirical analysis of mechanics, cost, and caveats

---

## Credits and references

- **[Anthropic](https://code.claude.com/docs/en/sub-agents)** — for shipping the fork-subagent feature
- **[obra/superpowers](https://github.com/obra/superpowers)** — the parallelization criteria and post-dispatch verification ritual in `prefer-fork-agents` are adapted from the `dispatching-parallel-agents` skill
- **[Issue #16153](https://github.com/anthropics/claude-code/issues/16153)** — for articulating the underlying problem clearly
- **[Build This Now](https://www.buildthisnow.com/blog/guide/mechanics/claude-code-fork-subagent)** — empirical mechanics analysis

---

## License

MIT
