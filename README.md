# Enable Claude Fork-Agent

> A one-shot setup that switches Claude Code's default subagent dispatch from "fresh context with lossy briefing" to **fork-mode with inherited context** — and teaches Claude to keep it that way through a lightweight skill.

```bash
git clone https://github.com/Kirchlive/Enable-Claude-Fork-Agent.git
cd Enable-Claude-Fork-Agent

# macOS / Linux / WSL / Git Bash
bash install.sh

# Windows (PowerShell 7+)
.\install.ps1
```

After installation, every subagent Claude Code dispatches will inherit your full conversation context by default. Verify with `/skills` (the `prefer-fork-agents` skill should be listed) and `/fork` (the slash command should be available).

---

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

Many community projects converged on layered methodological solutions before — or in parallel with — this feature shipping. The framing this repo takes: Anthropic provided the mechanism, the methodologies remain useful for the cases where fork doesn't apply, and a single small skill bridges the two by encoding when to prefer which.

**Key references:**
- [Claude Code Subagents documentation](https://code.claude.com/docs/en/sub-agents) — official fork-mode mechanics
- [Issue #16153](https://github.com/anthropics/claude-code/issues/16153) — feature request articulating the underlying need
- [Issue #38443](https://github.com/anthropics/claude-code/issues/38443) — background fork dispatch follow-up
- [Fork Subagents in Claude Code](https://www.buildthisnow.com/blog/guide/mechanics/claude-code-fork-subagent) — empirical analysis of mechanics, cost, and caveats

---

## What this repo does

Three things, automated by the installer for your platform:

1. **Sets `CLAUDE_CODE_FORK_SUBAGENT=1`** in your `~/.claude/settings.json` (merged safely into existing `env` block, or created if absent). This activates the fork mechanism.
2. **Installs the `prefer-fork-agents` skill** to `~/.claude/skills/prefer-fork-agents/`. The skill auto-loads on relevant triggers and biases Claude toward fork dispatch by default, with explicit exceptions for the cases where named subagents remain correct.
3. **Backs up your existing `settings.json`** before any modification — rollback is one `cp` (or `Copy-Item`) away.

The skill itself encodes a default-deny policy: fork unless one of four documented exceptions applies (unbiased verdict, lightweight read-only search, plan-only mode, specialized custom subagent). It also covers parallelization criteria, worktree isolation for edit fan-outs, and post-dispatch verification.

---

## Installation

Two native installers, same outcome — pick the one for your platform.

### macOS / Linux / WSL / Git Bash

```bash
bash install.sh
```

Requires `python3` (for safe JSON merging). The script will:

- Verify Claude Code version (≥ v2.1.117 required)
- Back up `~/.claude/settings.json` to a timestamped backup
- Merge `CLAUDE_CODE_FORK_SUBAGENT=1` into the `env` block (preserving everything else)
- Copy the skill folder to `~/.claude/skills/prefer-fork-agents/`
- Print verification steps

### Windows (PowerShell 7+)

```powershell
.\install.ps1
```

If you get an execution-policy error, run once: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` and re-run.

Requires PowerShell 7 or later (`pwsh`). Install via:
- Windows: `winget install --id Microsoft.Powershell`
- macOS: `brew install --cask powershell`
- Linux: see [Microsoft's install guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)

The PowerShell installer uses native JSON handling (no Python dependency) and produces the same result as the bash version: backup, merged settings, installed skill.

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

**2.** Copy the skill.

macOS / Linux / WSL / Git Bash:

```bash
mkdir -p ~/.claude/skills/prefer-fork-agents
cp skills/prefer-fork-agents/SKILL.md ~/.claude/skills/prefer-fork-agents/
```

Windows (PowerShell):

```powershell
New-Item -ItemType Directory -Path "$HOME\.claude\skills\prefer-fork-agents" -Force
Copy-Item "skills\prefer-fork-agents\SKILL.md" "$HOME\.claude\skills\prefer-fork-agents\"
```

**3.** Restart Claude Code (close and reopen — settings are read at process startup).

---

## Verification

After installation, in a Claude Code session:

```
/skills
```

Should list `prefer-fork-agents` as available.

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
|---|---|
| Subagents start with zero context; Claude writes summarization briefs | Forks inherit full parent context including active skills |
| Briefs are 200–2000 tokens of recap | Briefs are 50–200 tokens of pure directive |
| Lossy context handoff at every delegation | Cache-shared inheritance, ~7–10× cheaper per delegation |
| Each dispatch re-establishes scope and methodology | Methodology and scope inherit automatically |
| Subagents may improvise on inferred context | Forks see what the parent saw |

---

## When fork is NOT the right answer

The skill makes fork the default, but it deliberately reserves four cases where named subagents remain correct:

1. **Unbiased verdict required** — security audit, design critique, adversarial code review where the parent's framing would prejudice the result
2. **Lightweight read-only search** — use `Explore` (Haiku-backed, cheap and fast)
3. **Plan-only mode** — use `Plan` for read-only architectural analysis
4. **Specialized custom subagent** — a deliberately curated persona that should NOT inherit the parent's framing

For these cases, Claude continues to use named subagents and writes full briefings. See the skill's Decision Rule section for details.

---

## Caveats

The skill encodes these, but worth knowing upfront:

- **Concurrency cap:** approximately 10 simultaneous forks; the scheduler queues the rest
- **No recursion:** a fork cannot spawn further forks
- **Compaction inheritance:** if the parent has auto-compacted, the fork inherits the compacted (lossy) state. Dispatch forks early, ideally under 60% context utilization
- **Incompatible with coordinator mode** and `claude --print` (headless) mode
- **Cost scales with session length** — each fork carries the full parent history; long sessions with many forks accumulate tokens even with cache discounts
- **Edit fan-outs need `isolation: "worktree"`** — without it, parallel forks share the same working directory and risk overwriting each other's edits

---

## Optional: hook-based hard enforcement

The skill is a soft policy — it teaches Claude to prefer fork. For environments where you want hard enforcement (block named-subagent dispatches at the tool level), a `PreToolUse` hook on the `Task` tool can do that. Not included here for compactness, but easy to add if needed. The skill alone has been sufficient in practice.

---

## Uninstall

macOS / Linux / WSL / Git Bash:

```bash
# Restore the original settings.json (use your actual backup filename — the installer prints it)
cp ~/.claude/settings.json.pre-fork-backup-<TIMESTAMP> ~/.claude/settings.json

# Remove the skill
rm -rf ~/.claude/skills/prefer-fork-agents
```

Windows (PowerShell):

```powershell
Copy-Item "$HOME\.claude\settings.json.pre-fork-backup-<TIMESTAMP>" "$HOME\.claude\settings.json"
Remove-Item -Recurse -Force "$HOME\.claude\skills\prefer-fork-agents"
```

Restart Claude Code. Behavior reverts to default named-subagent dispatch.

---

## Credits and references

- **[Anthropic](https://code.claude.com/docs/en/sub-agents)** — for shipping the fork-subagent feature
- **[obra/superpowers](https://github.com/obra/superpowers)** — the parallelization criteria and post-dispatch verification ritual in the skill are adapted from the `dispatching-parallel-agents` skill
- **[Issue #16153](https://github.com/anthropics/claude-code/issues/16153)** — for articulating the underlying problem clearly
- **[Build This Now](https://www.buildthisnow.com/blog/guide/mechanics/claude-code-fork-subagent)** — empirical mechanics analysis (concurrency, cache, coordinator-mode incompatibility)

---

## License

MIT
