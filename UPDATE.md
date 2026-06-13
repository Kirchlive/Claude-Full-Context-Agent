# UPDATE — Fork-Guard False-Positive (Claude Code v2.1.177)

> **Status:** workaround applied in this plugin version (skill-source patch).
> **Upstream fix:** pending — the bug is in the Claude Code runtime, not in the plugin. Tracked at [anthropics/claude-code#68233](https://github.com/anthropics/claude-code/issues/68233).

## TL;DR

On Claude Code **v2.1.177**, every fork dispatch from a top-level session fails with:

```
Fork is not available inside a forked worker. Complete your task directly using your tools.
```

— even though the session is provably *not* a fork (`CLAUDE_CODE_FORK_SUBAGENT=1` is set, and the session JSONL starts with `last-prompt` rather than `fork-context-ref`).

Root cause: the runtime's fork-recursion guard does a naive substring scan for the tag `‹fork-boilerplate` across the entire user-message history. The previous skill texts in this plugin (`prefer-fork-agents/SKILL.md`, `fan-out-fork-agents/SKILL.md`) described that tag literally in their Self-Check sections. On every skill invocation, those texts landed in user-messages as `tool_result` blocks and falsely triggered the guard.

## The guard (from the Claude Code v2.1.177 binary)

```js
// constant
z7H = "fork-boilerplate"

// guard
function $m_(messages) {
  return messages.some(m => {
    if (m.type !== "user") return false;
    const content = m.message.content;
    if (!Array.isArray(content)) return false;
    return content.some(c =>
      c.type === "text" && c.text.includes(`<${z7H}`)
    );
  });
}

// Agent-tool dispatch check
if (z.options.querySource === `agent:builtin:${Zx.agentType}` || $m_(z.messages)) {
  throw new gTH(
    "Fork is not available inside a forked worker. Complete your task directly using your tools."
  );
}
```

**Bug:** `text.includes("‹fork-boilerplate")` (shown here with Unicode angles so this file itself doesn't poison your session — the real check uses ASCII `<`) is a blind substring match. Any text in any user-message containing that sequence — skill documentation, memory dumps, CLAUDE.md content, bug reports — triggers the guard. The correct behavior would be a structural match: either on the precise position (first sidechain user turn of the fork session) or on a unique wrapper format.

## Reproduction

In a fresh top-level session:

```bash
echo $CLAUDE_CODE_FORK_SUBAGENT     # → 1
# /skill prefer-fork-agents  (the v1.0.2 skill output contains the literal tag 4×)
# then any Agent-tool call with subagent_type: "fork"
# → Error: "Fork is not available inside a forked worker."
```

To verify the session is **not** actually a fork:

```bash
head -1 ~/.claude/projects/<project>/<session-id>.jsonl
# → {"type":"last-prompt", ...}   (NOT "fork-context-ref")
```

## The fix in this plugin (v2.0.0)

In both skill files, the literal ASCII-angle tag is replaced with the Unicode-angle-bracket form `‹fork-boilerplate›` (U+2039 / U+203A):

```diff
- A `‹fork-boilerplate›` block appears in your prompt
+ A `‹fork-boilerplate›` block appears in your prompt
```

(The diff renders identically here because both sides use Unicode angles in this document — the actual replacement in the skill sources was ASCII `<…>` → Unicode `‹…›`.)

Affected files:
- `skills/prefer-fork-agents/SKILL.md` (4 occurrences)
- `skills/fan-out-fork-agents/SKILL.md` (1 occurrence)

Semantics are preserved (the Self-Check section remains readable for fork-workers), but the guard substring no longer matches.

## Recovery for already-poisoned sessions

If the bug has already polluted a **running session** (skill output already in the message history), patching the sources is not enough — the skill outputs sit as `tool_result` blocks in the session JSONL and are reloaded on the next resume.

### Step 1 — patch the session JSONL

```bash
SESSION=~/.claude/projects/<project>/<session-id>.jsonl
cp "$SESSION" "$SESSION.bak"
python3 -c "
path = '$SESSION'
with open(path) as f:
    data = f.read()
# Replace both opening and closing literal angles with Unicode angles
data = data.replace('<fork-boilerplate', '‹fork-boilerplate')
data = data.replace('fork-boilerplate>', 'fork-boilerplate›')
with open(path, 'w') as f:
    f.write(data)
"
grep -c '<fork-boilerplate' "$SESSION"   # → 0
```

### Step 2 — restart Claude Code with resume

```bash
claude --resume <session-id>
```

On resume, Claude reads the patched messages from the JSONL. The in-memory state of the **running** process cannot be patched — a restart is mandatory.

### Step 3 — verify

```
Agent(subagent_type:"fork", description:"test", prompt:"Echo: alive")
# → Async agent launched successfully.
```

## What else triggers the guard (warn-list)

Any of the following sources will produce false-positives as soon as their content lands in a user-message:

- Skill documentation that describes the tag literally
- Memory dumps / auto-memory indexes that cite past fork investigations
- Bug reports or CLAUDE.md entries that show the tag as an example
- Pasted transcripts from real fork sessions that the user inserts into a prompt

**Rule of thumb for skill/doc authors:** never write the literal tag unescaped into any plaintext that could land as a tool result or user input. Use Unicode angles `‹fork-boilerplate›`, HTML entities `&lt;fork-boilerplate&gt;`, an inline backtick form with a space `< fork-boilerplate >`, or a paraphrase.

## Recommended upstream fix (to Anthropic)

The guard should be structural rather than textual:

1. **Position-based:** only check the first sidechain user turn for the boilerplate marker — that is the single position where the runtime actually injects the tag.
2. **Marker uniqueness:** extend the injected tag with a non-guessable suffix (e.g., a session-uuid attribute) and match the full pattern.
3. **Trust the metadata:** `querySource === "agent:builtin:fork"` is already a definitive signal — promote it to authoritative and drop the substring fallback (or keep it as a debug-only assertion).

Issue tracker: <https://github.com/anthropics/claude-code/issues/68233>

## Versioning

- **Affected:** Claude Code v2.1.177 (possibly earlier v2.1.x — not verified)
- **Plugin patch:** `Claude-Full-Context-Agent` v2.0.0, released 2026-06-13
- **Lift this workaround once:** Anthropic switches the guard to a structural match; until then, keep the escape in every skill source.
