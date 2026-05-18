# <u>Enable-[Claude](https://github.com/Kirchlive/Enable-Claude-Fork-Agent)-Fork-Agent</u>

Full setup switches Claude Code's default subagent dispatch with flawed improvisation behavior due to a lack of context to **Fork Agent mode with full session context** and Claude skill set for correct use and operation.

<img src="https://i.imgur.com/lAlbdZv.png" alt="IMG" width="750">

```
git clone https://github.com/Kirchlive/Enable-Claude-Fork-Agent.git
cd Enable-Claude-Fork-Agent

# macOS / Linux / WSL / Git Bash
bash install.sh

# Windows (PowerShell 7+)
.\install.ps1
```

After installation and claude code restart, a new command `/fork` is now available and the bundled skills (`prefer-fork-agents`, `fork-fan-out`) are listed under `/skills`. Once activated, every new agent will start with full session context by default.

---

## What this repo does

Three things, automated by the installer for your platform:

1. **Sets `CLAUDE_CODE_FORK_SUBAGENT=1`** in your `~/.claude/settings.json` (merged safely into the existing `env` block, or created if absent). This activates the fork mechanism.
2. **Installs two skills** to `~/.claude/skills/`:
   - **`prefer-fork-agents`** — the *decision* policy: when to fork vs. when to use a named subagent (default-deny mindset for named, with four documented exceptions)
   - **`fork-fan-out`** — the *operational* patterns: how to coordinate multiple parallel forks (lifecycle, worktree hygiene, registry, reporting contract, federation pattern)
3. **Backs up your existing `settings.json`** before any modification — rollback is one `cp` (or `Copy-Item`) away.

The two skills are complementary. `prefer-fork-agents` handles the single-task decision; `fork-fan-out` handles the multi-task coordination. Install scripts auto-discover any skill directory under `skills/`, so future additions don't require script changes.

---

## Installation

Two native installers, same outcome — pick the one for your platform.

### macOS / Linux / WSL / Git Bash

```
bash install.sh
```

Requires `python3` (for safe JSON merging). The script will:

- Verify Claude Code version (≥ v2.1.117 required)
- Back up `~/.claude/settings.json` to a timestamped backup
- Merge `CLAUDE_CODE_FORK_SUBAGENT=1` into the `env` block (preserving everything else)
- Install all bundled skills under `~/.claude/skills/`
- Print verification steps and the `.claude/worktrees/` gitignore recommendation

### Windows (PowerShell 7+)

```
.\install.ps1
```

If you get an execution-policy error, run once: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` and re-run.

Requires PowerShell 7 or later (`pwsh`). Install via:

- Windows: `winget install --id Microsoft.Powershell`
- macOS: `brew install --cask powershell`
- Linux: see [Microsoft's install guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)

The PowerShell installer uses native JSON handling (no Python dependency) and produces the same result as the bash version: backup, merged settings, installed skills.

### Manual installation (3 steps)

If you prefer not to run either script, do it by hand.

**1.** Edit `~/.claude/settings.json` — add or extend the `env` block:

```json
{
  "env": {
    "CLAUDE_CODE_FORK_SUBAGENT": "1"
  }
}
```

If you already have keys in `env`, add `CLAUDE_CODE_FORK_SUBAGENT` alongside them. **Do not create a second top-level `env` key** — JSON silently overwrites duplicates and you'll lose the setting.

**2.** Copy both skills.

macOS / Linux / WSL / Git Bash:

```bash
mkdir -p ~/.claude/skills/prefer-fork-agents ~/.claude/skills/fork-fan-out
cp skills/prefer-fork-agents/SKILL.md ~/.claude/skills/prefer-fork-agents/
cp skills/fork-fan-out/SKILL.md ~/.claude/skills/fork-fan-out/
```

Windows (PowerShell):

```powershell
New-Item -ItemType Directory -Path "$HOME\.claude\skills\prefer-fork-agents" -Force
New-Item -ItemType Directory -Path "$HOME\.claude\skills\fork-fan-out" -Force
Copy-Item "skills\prefer-fork-agents\SKILL.md" "$HOME\.claude\skills\prefer-fork-agents\"
Copy-Item "skills\fork-fan-out\SKILL.md" "$HOME\.claude\skills\fork-fan-out\"
```

**3.** Restart Claude Code (close and reopen — settings are read at process startup).

---

## Recommended: project-level `.gitignore`

If your project uses parallel fork fan-outs with worktree isolation, add this line to the project's `.gitignore` **before** the first fan-out:

```
.claude/worktrees/
```

Worktree-isolated forks materialize as nested directories with their own `.git` references. Without this entry, every fan-out dirties the parent index with embedded repositories. The fix is one line; missing it is a recurring cleanup cost. The `fork-fan-out` skill enforces this as a precondition.

---

## Verification

After installation, in a Claude Code session:

```
/skills
```

Should list both `prefer-fork-agents` and `fork-fan-out` as available.

```
/fork
```

Should be available as a slash command (typing `/fo` should autocomplete).

Then test:

```
Start an agent that researches GitHub for AI coding tools.
```

In the agent status indicator, you should see `◯ fork` as the agent type — not `◯ general-purpose` or another named subagent. The agent will inherit your full conversation context and the briefing prompt will be noticeably shorter.

---

## Behavior changes after installation

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

The `prefer-fork-agents` skill makes fork the default, but it deliberately reserves four cases where named subagents remain correct:

1. **Unbiased verdict required** — security audit, design critique, adversarial code review where the parent's framing would prejudice the result
2. **Lightweight read-only search** — use `Explore` (Haiku-backed, cheap and fast)
3. **Plan-only mode** — use `Plan` for read-only architectural analysis
4. **Specialized custom subagent** — a deliberately curated persona that should NOT inherit the parent's framing

For these cases, Claude continues to use named subagents and writes full briefings. See the skill's Decision Rule section for details.

---

## Caveats

The skills encode these, but worth knowing upfront:

- **Concurrency: 6–8 practical, ~10 scheduler-cap.** The scheduler accepts roughly 10 simultaneous forks, but the planning-vs-execution gap grows beyond 5–6. Soft cap at 6 parallel forks; sequentialize larger batches into waves.
- **No recursion:** a fork cannot spawn further forks. For two-layer parallelism, use the Federation pattern (fork → named subagent fan-out) from `fork-fan-out`.
- **Compaction inheritance:** if the parent has auto-compacted, the fork inherits the compacted (lossy) state. Dispatch forks early, ideally under 60% context utilization.
- **Incompatible with coordinator mode** and `claude --print` (headless) mode.
- **Cost scales with session length** — each fork carries the full parent history; long sessions with many forks accumulate tokens even with cache discounts.
- **Edit fan-outs need `isolation: "worktree"`** — without it, parallel forks share the same working directory and risk overwriting each other's edits. Combine with the `.claude/worktrees/` gitignore recommendation above.

---

## Optional: hook-based hard enforcement

The skills are soft policies — they teach Claude to prefer fork and to follow operational patterns. For environments where you want hard enforcement (block named-subagent dispatches at the tool level), a `PreToolUse` hook on the `Task` tool can do that. Not included here for compactness, but easy to add if needed. The skills alone have been sufficient in practice.

---

## Validation

The patterns this repo encodes are not theoretical. They are derived from production usage on a real Claude Code tooling project:

| Metric | Value |
|---|---|
| Observation window | 13 days (May 6 – May 18, 2026) |
| Documented fork dispatches | 20+ |
| Sessions | 8 |
| Aggregate discovery-token volume | ~145,000 |
| Peak parallel fan-out | 7 worktree-isolated forks |
| Largest delivered release | 16 new operations, 90 tests, 2,116 insertions in a ~45-minute session sequence |

Behaviors that emerged from this usage — the 6-8 practical concurrency cap, the parent-prepares→fan-out→parent-merges sequence, the embedded-repo gitignore lesson, the federation pattern for two-layer parallelism — are codified in the `fork-fan-out` skill rather than left as tribal knowledge.

---

## Uninstall

macOS / Linux / WSL / Git Bash:

```bash
# Restore the original settings.json (use your actual backup filename — the installer prints it)
cp ~/.claude/settings.json.pre-fork-backup-<TIMESTAMP> ~/.claude/settings.json

# Remove the skills
rm -rf ~/.claude/skills/prefer-fork-agents
rm -rf ~/.claude/skills/fork-fan-out
```

Windows (PowerShell):

```powershell
Copy-Item "$HOME\.claude\settings.json.pre-fork-backup-<TIMESTAMP>" "$HOME\.claude\settings.json"
Remove-Item -Recurse -Force "$HOME\.claude\skills\prefer-fork-agents"
Remove-Item -Recurse -Force "$HOME\.claude\skills\fork-fan-out"
```

Restart Claude Code. Behavior reverts to default named-subagent dispatch.

---
---

# Background

The sections above are everything you need to install, use, and uninstall. What follows is context: why this repo exists, what it relates to in the ecosystem, and what Anthropic actually shipped that makes any of this work.

## The problem

When Claude Code delegates a task to a subagent via the Task/Agent tool, the subagent starts with **zero conversation context**. Claude writes a briefing prompt summarizing what it thinks the subagent needs to know — but that summarization is lossy. Edge cases, prior decisions, and nuanced reasoning get flattened or lost entirely.

The result: subagents improvise, hallucinate context, and produce code that doesn't match the parent session's intent. The longer and richer the parent session, the worse the loss.

A typical failure mode: parent session has read fifteen files and discussed an architecture decision. Subagent gets a 400-token brief about that decision. Subagent confidently implements something based on what it inferred from the brief — and it's wrong, because the actual rationale was in a file the subagent never saw. Mejba Ahmed documented this exact pattern in [Forked Subagents in Claude Code](https://www.mejba.me/blog/forked-subagents-claude-code-anthropic):

> "The guard at line 47 prevents the race condition you described."
> Except it didn't. The guard I was worried about wasn't in the controller at all. It was in a middleware the subagent had never seen, because its compressed context summary had flattened that middleware into a line that read, roughly, "project uses standard Laravel middleware stack."

This is the **context amnesia** failure mode the community has been working around for over a year.

---

## The landscape

The community has built elaborate methodological workarounds for this:

- **[obra/superpowers](https://github.com/obra/superpowers)** — Opinionated framework with brainstorming → plan → subagent-driven-development pipeline. Philosophy: context isolation is good, force the orchestrator to write precise briefs per worker.
- **[BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD)** — Agile-style multi-phase workflow with story files as durable context carriers.
- **[GitHub Spec-Kit](https://github.com/github/spec-kit)** — Spec files in version control; agents read specs instead of inheriting state.
- **[Pimzino/claude-code-spec-workflow](https://github.com/Pimzino/claude-code-spec-workflow)** — Selective delegation: main agent loads full context, passes only relevant slices to sub-agents.
- **[NeoLabHQ/context-engineering-kit](https://github.com/NeoLabHQ/context-engineering-kit)** — Subagent-Driven Development with reflection hooks and self-critique loops.
- **PRPs (Product Requirement Prompts)** — Comprehensive implementation blueprints with all-needed-context baked in.

All of these treat context loss as a **process problem** and solve it with discipline. They work, but they layer process complexity on top of the dispatch mechanism — and they require methodology adoption across a team.

---

## What Anthropic actually shipped

In Claude Code **v2.1.117** (released Q1 2026), Anthropic shipped an opt-in feature called **forked subagents**: a subagent that inherits the parent's full conversation state — system prompt, message history, active skills, tool definitions, and the prompt cache.

The mechanism is **mechanical, not methodological**. Set one environment variable, and the Task/Agent tool gains the ability to dispatch context-inheriting workers when called without an explicit `subagent_type`. The fork shares the parent's prompt cache, making it dramatically cheaper than spawning a fresh subagent for tasks that need the same context.

The feature is:

- **Opt-in** via `CLAUDE_CODE_FORK_SUBAGENT=1`
- **Marked experimental**
- **Absent from most tutorials and quick-start docs**

Many community projects converged on layered methodological solutions before — or in parallel with — this feature shipping. The framing this repo takes: Anthropic provided the mechanism, the methodologies remain useful for the cases where fork doesn't apply, and two small skills bridge the two by encoding when to prefer which and how to coordinate fan-outs.

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
- **[Build This Now](https://www.buildthisnow.com/blog/guide/mechanics/claude-code-fork-subagent)** — empirical mechanics analysis (concurrency, cache, coordinator-mode incompatibility)

---

## License

MIT
