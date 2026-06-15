#!/usr/bin/env bash
# Full-Context-Fork-Agent — post-install verification.
# Exits 0 if all checks pass, non-zero otherwise.

set -uo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
SKILLS_DIR="$CLAUDE_DIR/skills"
REQUIRED="2.1.117"

pass=0
fail=0

check() {
  local label="$1" ok="$2"
  if [ "$ok" = "1" ]; then
    printf '  \033[32m[OK]\033[0m   %s\n' "$label"
    pass=$((pass + 1))
  else
    printf '  \033[31m[FAIL]\033[0m %s\n' "$label"
    fail=$((fail + 1))
  fi
}

echo "Full-Context-Fork-Agent verification"
echo "====================================="

# 1. settings.json exists and parses as JSON
parses=0
if [ -f "$SETTINGS" ] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS" >/dev/null 2>&1; then
  check "settings.json exists and parses as JSON" 1
  parses=1
else
  check "settings.json exists and parses as JSON" 0
fi

# 2. env flag set to "1"
if [ "$parses" = "1" ]; then
  val="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('env', {}).get('CLAUDE_CODE_FORK_SUBAGENT', ''))" "$SETTINGS" 2>/dev/null)"
  if [ "$val" = "1" ]; then
    check 'env.CLAUDE_CODE_FORK_SUBAGENT == "1"' 1
  else
    check "env.CLAUDE_CODE_FORK_SUBAGENT == \"1\" (got \"$val\")" 0
  fi
else
  check 'env.CLAUDE_CODE_FORK_SUBAGENT == "1"' 0
fi

# 3-4. skills present
for skill in prefer-fork-agents fan-out-fork-agents; do
  if [ -f "$SKILLS_DIR/$skill/SKILL.md" ] || { [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/$skill/SKILL.md" ]; }; then
    check "skill available: $skill" 1
  else
    check "skill available: $skill" 0
  fi
done

# 5. claude CLI version
if command -v claude >/dev/null 2>&1; then
  ver="$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [ -n "$ver" ] && [ "$(printf '%s\n' "$REQUIRED" "$ver" | sort -V | head -1)" = "$REQUIRED" ]; then
    check "claude CLI $ver >= $REQUIRED" 1
  else
    check "claude CLI >= $REQUIRED (got ${ver:-unknown})" 0
  fi
else
  check "claude CLI in PATH" 0
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
