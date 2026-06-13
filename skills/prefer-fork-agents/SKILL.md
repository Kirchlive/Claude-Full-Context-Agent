---
name: prefer-fork-agents
description: Defines the project's subagent delegation policy — prefer fork-mode dispatch (inherits full conversation context, shares prompt cache) over named subagents whenever a delegated task benefits from already-established context. CLAUDE_CODE_FORK_SUBAGENT=1 is active in this environment. Setting `subagent_type: "fork"` explicitly on the Agent/Task call is the trigger for fork mode (verified empirically in Claude Code v2.1.177 — omission falls back to general-purpose). Default-deny mindset for named subagents — if you cannot articulate why a named subagent is required, dispatch a fork. Apply this skill EVERY time you are about to call the Agent/Task tool, EVERY time you reason about subagent_type, EVERY time the user requests delegated/parallel/background agent work, and BEFORE fanning out to multiple agents in parallel. For multi-fork orchestration (worktrees, fan-out coordination, reporting contracts), defer to the fork-fan-out skill.
when_to_use: User says "start an agent", "spawn a researcher", "delegate", "dispatch a subagent", "run a research", "investigate X", "analyze Y in parallel", "agent für", or any phrasing that implies subagent dispatch. Also: any time you are internally considering subagent_type values like general-purpose, researcher, or a custom agent name, or contemplating parallel work across multiple problems.
---

# Prefer Fork Agents

## What a fork agent is

A fork agent is a Claude Code subagent that inherits the parent's full conversation state — system prompt, message history, active skills, tool definitions, CLAUDE.md, and the project's prompt cache. It runs with its own fresh 200K context window on top of that inherited state. The schema difference from a normal subagent is `subagent_type: "fork"` on the Agent tool call. Forks cannot spawn further forks (no recursion — a `<fork-boilerplate>` system instruction is injected that explicitly forbids it) and are mutually exclusive with coordinator mode.

## Invocation

**Fork.** Set `subagent_type: "fork"` explicitly:

```
{
  "name": "Agent",
  "input": {
    "description": "Brief label, 3-5 words",
    "subagent_type": "fork",
    "prompt": "Directive: WHAT to do. Do not repeat context the fork already inherits — be terse and scope-focused. The fork has read everything we have read and discussed everything we have discussed."
  }
}
```

**Named subagent (exception case).** Include the named `subagent_type`:

```
{
  "name": "Agent",
  "input": {
    "description": "Brief label",
    "subagent_type": "Explore",
    "prompt": "Full briefing: goal, constraints, expected output format, anything the agent needs to know — it starts with ZERO conversation context."
  }
}
```

**Important — verified in Claude Code v2.1.177:** omitting `subagent_type` does NOT trigger fork mode; it falls back silently to `general-purpose` (a fresh agent with no inherited context). The trigger is the literal string `"fork"` in the `subagent_type` field. Verification signatures of a real fork in the session JSONL: first transcript line is `{"type":"fork-context-ref", ...}`, every assistant turn carries `"attributionAgent":"fork"`, and the first user turn includes a `<fork-boilerplate>` block. If any of those is missing, the dispatch was a named subagent, not a fork.

## If a fork dispatch errors (fork mode not enabled)

Fork mode needs `CLAUDE_CODE_FORK_SUBAGENT=1` in `~/.claude/settings.json`, read at startup. A plugin can't set it. If a fork dispatch errors with this unset, tell the user to run `/Claude-Full-Context-Agent:doctor` — it runs the bundled installer for their OS (sets the var, installs skills) — then restart Claude Code. One-time; later sessions already have it.

## When to parallelize at all

The fork-vs-named decision is downstream of a more fundamental question: should you dispatch multiple agents in parallel at all? Resolve this FIRST.

**Fan out (multiple agents in parallel) when:**

- 3+ independent failures or tasks with genuinely different root causes
- Multiple subsystems to investigate or modify independently
- Each problem is understandable without context from the others
- No shared state or shared files between the workers

**Do NOT fan out when:**

- Tasks are related — solving one might solve others. Investigate sequentially first.
- You need full system state to understand the problem. A single agent with broad scope is better.
- Workers would interfere (editing the same files, racing on shared resources)
- Exploratory debugging where you do not yet know what is broken. Go serial until you have hypotheses.

If the answer is "do not parallelize", dispatch a single agent (still fork by default per the rule below). If the answer is "parallelize", proceed to the fork-vs-named decision below — AND consult the `fork-fan-out` skill for orchestration patterns (worktrees, reporting contracts, parent-merge sequence).

## Decision rule

**Default: fork.** Choose a named `subagent_type` only when one of these applies:

1. **Unbiased verdict required.** Security audit, design critique, adversarial code review — cases where the parent's context would prejudice the result. Use a custom subagent or `general-purpose` with a fresh brief.

2. **Lightweight read-only search.** Use `subagent_type: "Explore"` (runs on Haiku) for "find all files matching X", "where is function Y called", or other simple codebase scans where inherited context provides no benefit but Haiku speed/cost does.

3. **Plan-only mode.** Use `subagent_type: "Plan"` for read-only architectural analysis that must not modify files.

4. **Specialized custom subagent.** A custom agent in `~/.claude/agents/` with a deliberately curated system prompt — e.g. a security auditor or test-engineer persona — that should NOT inherit the parent's framing.

If none of these four cases applies, dispatch a fork. If you cannot articulate which case applies, dispatch a fork. Silence around "why named" is itself the signal that fork is correct.

**For cases 1 and 4:** the named subagent receives ZERO conversation context. Brief it like a stateless worker — focused scope, explicit constraints, specific output format. Do NOT assume it inherits anything from the conversation. The principle is the inverse of fork prompting: write a complete, self-contained briefing.

## Constraints

- **Concurrency: 6-8 practical, ~10 scheduler-cap.** The scheduler accepts roughly 10 simultaneous forks, but the planning-vs-execution gap grows beyond 5-6. At 7+ parallel tracks, retroactive auditing tends to replace actual orchestration. Soft cap at 6; sequentialize larger batches into waves. See `fork-fan-out` skill for the empirical basis.
- **No recursion:** a fork cannot spawn further forks. Forks see an injected directive preventing it. Plan fan-outs as flat, not nested. (For two-layer parallelism, see the Federation pattern in `fork-fan-out`.)
- **Compaction inheritance:** if the parent has auto-compacted before the fork, the fork inherits the compacted (lossy) state — not the original. Dispatch forks early in long sessions, ideally before 60% context utilization.
- **Incompatible with coordinator mode** and with `claude --print` (headless) mode.
- **Cost scales with session length:** each fork carries the full parent history. In long sessions, parallel forks can be expensive even with cache discounts. Worth it for wall-clock speedup, but budget accordingly.
- **Filesystem isolation for edit fan-outs:** when fanning out forks that will edit files, dispatch each with `isolation: "worktree"`. Without it, parallel forks share the same working directory and risk overwriting each other's edits or producing silent merge conflicts. Read-only fan-outs (search, analysis, reporting) do not need worktree isolation. Project `.gitignore` should exclude `.claude/worktrees/` — see `fork-fan-out` skill.

## Post-dispatch verification

After a fan-out returns, run this ritual before considering the work done. Non-optional for fan-outs that include edits — skipping it produces silent regressions where individual forks succeeded but the combined state is broken.

1. **Read each fork's summary.** Understand what each one actually did, not just whether it reported success. Forks can hallucinate completion.

2. **Diff for file overlap.** If two forks edited the same file (or two worktrees touched the same path), integration is needed before merging. With `isolation: "worktree"` this surfaces as parallel branches that need a manual reconcile step.

3. **Run the full build/test suite.** Each fork verified its own slice. Only the integrated whole reveals whether the slices compose correctly.

4. **Spot-check for systematic errors.** Forks share the parent's biases and assumptions. If one fork made a wrong inference (e.g., misread an API contract), the others likely did too. Sample one or two outputs deeply rather than trusting all uniformly.

For single-fork dispatches, steps 1 and 3 still apply. Step 2 is moot, step 4 less critical. For multi-fork fan-outs, the `fork-fan-out` skill expands this ritual with registry tracking and merge-stage discipline.

## Worked example

User asks: "Spawn an agent that researches the Superpowers project on GitHub."

Wrong move (improvising a named subagent):
```
Agent(description="research superpowers",
      subagent_type="researcher",
      prompt="Research Superpowers... [needs full briefing because zero context]")
```

Correct move (fork — the parent already knows what Superpowers is from this conversation):
```
Agent(description="GitHub research on Superpowers",
      subagent_type="fork",
      prompt="Research the obra/superpowers repo on GitHub. Return: feature list, recent release notes, comparison to the alternatives we already discussed.")
```

The fork-prompt is shorter precisely because the fork already inherits "the alternatives we already discussed". With a named subagent, that reference would have to be expanded into the prompt, doubling its length and risking summarization loss.

## When this skill is most actionable

Right before you emit an Agent/Task tool call, ask the three questions in order:

1. **Is this a parallelizable batch?** Apply the "When to parallelize at all" criteria. If no, single dispatch. If yes, plan the fan-out before issuing calls — consult `fork-fan-out` for orchestration.

2. **Per worker, does the task benefit from current conversation context?**
   - Yes → fork (set `subagent_type: "fork"` explicitly)
   - No, and it's a cheap read-only search → `subagent_type: "Explore"`
   - No, and it's a deliberately fresh second opinion → named subagent with full briefing per cases 1/4
   - Otherwise → fork

3. **If fanning out with edits:** add `isolation: "worktree"` to each fork.

After dispatch returns, run the post-dispatch verification ritual.

Apply silently. Do not narrate the decision tree unless asked.
