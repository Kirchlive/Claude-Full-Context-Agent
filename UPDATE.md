# UPDATE — Fork-Guard False-Positive (Claude Code v2.1.177)

> **Status:** Workaround angewandt in dieser Plugin-Version (Skill-Source-Patch).
> **Upstream-Fix:** ausstehend — Bug liegt im Claude-Code-Runtime, nicht im Plugin.

## TL;DR

In Claude Code **v2.1.177** schlägt jeder Fork-Dispatch in einer Top-Level-Session fehl mit:

```
Fork is not available inside a forked worker. Complete your task directly using your tools.
```

— obwohl die Session nachweislich kein Fork ist (`CLAUDE_CODE_FORK_SUBAGENT=1` gesetzt, JSONL-Header `last-prompt` statt `fork-context-ref`).

Ursache: Der Runtime-Guard, der Fork-Recursion verhindert, macht einen naiven Substring-Scan auf den Tag `<fork-boilerplate` in der gesamten User-Message-History. Die Skill-Doku-Texte dieses Plugins (`prefer-fork-agents/SKILL.md`, `fan-out-fork-agents/SKILL.md`) enthielten diesen Tag wörtlich in ihrer Self-Check-Erklärung — beim Skill-Invoke landeten die Texte als `tool_result` in user-Messages und triggern den Guard fälschlich.

## Der Guard (aus dem Claude-Code-Binary, v2.1.177)

```js
// Konstante
z7H = "fork-boilerplate"

// Guard
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

// Dispatch-Check (Agent-Tool)
if (z.options.querySource === `agent:builtin:${Zx.agentType}` || $m_(z.messages)) {
  throw new gTH(
    "Fork is not available inside a forked worker. Complete your task directly using your tools."
  );
}
```

**Bug:** `text.includes("<fork-boilerplate")` ist ein blinder Substring-Match. Jeder Text in jeder user-Message, der die Zeichenfolge enthält — Skill-Dokumentation, Memory-Dumps, CLAUDE.md-Inhalte, Bug-Reports — löst den Guard aus. Korrekt wäre: Match nur auf die strukturelle Position (erste Sidechain-User-Turn der Fork-Session) oder auf ein eindeutiges Wrapper-Format.

## Reproduktion

Frische Top-Level-Session:

```bash
echo $CLAUDE_CODE_FORK_SUBAGENT   # → 1
# /skill prefer-fork-agents (Skill-Output enthält "<fork-boilerplate>" 4×)
# Anschließend Agent-Tool-Call mit subagent_type:"fork"
# → Error: "Fork is not available inside a forked worker."
```

Verifikation, dass es kein echter Fork ist:

```bash
head -1 ~/.claude/projects/<project>/<session-id>.jsonl
# → {"type":"last-prompt", ...}   (NICHT "fork-context-ref")
```

## Fix in diesem Plugin (v1.0.2-patch)

In beiden Skill-Files den Tag `<fork-boilerplate>` durch Unicode-Angles `‹fork-boilerplate›` (U+2039 / U+203A) ersetzt:

```diff
- A `<fork-boilerplate>` block appears in your prompt
+ A `‹fork-boilerplate›` block appears in your prompt
```

Betroffene Dateien:
- `skills/prefer-fork-agents/SKILL.md` (4 Vorkommen)
- `skills/fan-out-fork-agents/SKILL.md` (1 Vorkommen)

Semantik bleibt erhalten (Self-Check-Lesbarkeit für Forks unverändert), Guard-Match bricht (Substring `<fork-boilerplate` nicht mehr enthalten).

## Recovery für bestehende Sessions

Wenn der Bug eine **bereits laufende Session** verseucht hat (Skill-Output bereits in der Message-History), reicht der Source-Patch nicht — die Skill-Outputs liegen als `tool_result` in der Session-JSONL und werden beim nächsten Resume wieder geladen.

### Schritt 1 — Session-JSONL patchen

```bash
SESSION=~/.claude/projects/<project>/<session-id>.jsonl
cp "$SESSION" "$SESSION.bak"
python3 -c "
import sys
path = '$SESSION'
with open(path) as f:
    data = f.read()
data = data.replace('<fork-boilerplate', '‹fork-boilerplate›'.split('›')[0])
data = data.replace('fork-boilerplate>', 'fork-boilerplate›')
with open(path, 'w') as f:
    f.write(data)
"
grep -c '<fork-boilerplate' "$SESSION"   # → 0
```

### Schritt 2 — Claude Code mit Resume neu starten

```bash
claude --resume <session-id>
```

Beim Resume liest Claude die gepatchten Messages aus der JSONL. Der In-Memory-State des **laufenden** Prozesses lässt sich nicht patchen — Restart ist Pflicht.

### Schritt 3 — Verifizieren

```
Agent(subagent_type:"fork", description:"test", prompt:"Echo: alive")
# → Async agent launched successfully.
```

## Was den Guard alles triggert (Warn-Liste)

Jede der folgenden Quellen löst false-positives aus, sobald ihr Inhalt als user-Message in der History landet:

- Skill-Dokumentation, die den Tag literal beschreibt
- Memory-Dumps / Auto-Memory-Indizes, die vergangene Fork-Investigationen zitieren
- Bug-Reports oder CLAUDE.md-Einträge, die `<fork-boilerplate>` als Beispiel zeigen
- Kopierte Transkripte aus echten Fork-Sessions, die der User in ein Prompt einfügt

**Faustregel beim Schreiben von Doku/Skills:** Den literalen Tag `<fork-boilerplate>` nie unmaskiert in Plaintext, der als Tool-Result oder User-Input landen könnte. Stattdessen: Unicode-Angles `‹fork-boilerplate›`, HTML-Entities `&lt;fork-boilerplate&gt;`, Backticks-Inline mit Leerzeichen `< fork-boilerplate >`, oder Umschreibung.

## Upstream-Empfehlung an Anthropic

Der Guard sollte strukturell prüfen, nicht textuell:

1. **Position-basiert:** Nur die erste Sidechain-User-Turn auf den Boilerplate-Marker prüfen — das ist die einzige Position, an der das Runtime den Tag tatsächlich injiziert.
2. **Marker-Eindeutigkeit:** Den injizierten Tag um ein nicht-rateBares Suffix erweitern (z.B. `<fork-boilerplate session-uuid="...">`) und Match auf das vollständige Pattern.
3. **Session-Metadata first:** `querySource === "agent:builtin:fork"` ist bereits ein eindeutiges Signal — der Substring-Check als Fallback ist redundant und fehleranfällig.

Issue-Tracker: <https://github.com/anthropics/claude-code/issues>

## Versionierung

- **Betroffen:** Claude Code v2.1.177 (möglicherweise frühere v2.1.x — nicht verifiziert)
- **Plugin-Patch:** `Claude-Full-Context-Agent` 1.0.2, angewandt 2026-06-13
- **Aufzuheben sobald:** Anthropic den Guard auf strukturellen Match umstellt; bis dahin den Patch in allen Skill-Sources behalten.
