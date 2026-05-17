#!/usr/bin/env bash
# Enable-Claude-Fork-Agent installer
# Sets CLAUDE_CODE_FORK_SUBAGENT=1 in ~/.claude/settings.json and installs the prefer-fork-agents skill.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
SKILLS_DIR="$CLAUDE_DIR/skills"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$SETTINGS.pre-fork-backup-$TIMESTAMP"

echo "Enable-Claude-Fork-Agent installer"
echo "=================================="
echo

# ---- Step 1: Verify Claude Code is installed and version ≥ 2.1.117 ----

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: 'claude' CLI not found in PATH."
  echo "Install Claude Code first: https://code.claude.com/docs/en/install"
  exit 1
fi

CLAUDE_VERSION="$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
REQUIRED="2.1.117"

if [ -z "${CLAUDE_VERSION:-}" ]; then
  echo "WARNING: could not detect Claude Code version. Proceeding anyway."
else
  if [ "$(printf '%s\n' "$REQUIRED" "$CLAUDE_VERSION" | sort -V | head -1)" != "$REQUIRED" ]; then
    echo "ERROR: Claude Code $CLAUDE_VERSION detected, but $REQUIRED+ is required for fork mode."
    echo "Update via: claude --update  (or your install method)"
    exit 1
  fi
  echo "Claude Code version: $CLAUDE_VERSION (OK)"
fi

# ---- Step 2: Verify python3 is available (for safe JSON merge) ----

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found. Install Python 3 or perform manual installation."
  echo "See README.md for the 3-step manual procedure."
  exit 1
fi

# ---- Step 3: Backup existing settings.json ----

mkdir -p "$CLAUDE_DIR"
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$BACKUP"
  echo "Backed up existing settings to: $BACKUP"
else
  echo "No existing settings.json — will create a new one."
fi

# ---- Step 4: Merge env.CLAUDE_CODE_FORK_SUBAGENT=1 (preserves everything else) ----

python3 - "$SETTINGS" <<'PYEOF'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
data = {}

if settings_path.exists() and settings_path.stat().st_size > 0:
    try:
        # object_pairs_hook detects accidental duplicate top-level keys
        def detect_dupes(pairs):
            keys = [p[0] for p in pairs]
            if len(keys) != len(set(keys)):
                dupes = [k for k in keys if keys.count(k) > 1]
                raise ValueError(f"settings.json contains duplicate top-level keys: {sorted(set(dupes))}")
            return dict(pairs)
        data = json.loads(settings_path.read_text(), object_pairs_hook=detect_dupes)
    except json.JSONDecodeError as e:
        print(f"ERROR: existing settings.json is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        print("Fix the duplicate keys manually before re-running this installer.", file=sys.stderr)
        sys.exit(1)

if "env" not in data or not isinstance(data["env"], dict):
    data["env"] = {}
data["env"]["CLAUDE_CODE_FORK_SUBAGENT"] = "1"

settings_path.write_text(json.dumps(data, indent=2) + "\n")
print(f"Merged CLAUDE_CODE_FORK_SUBAGENT=1 into {settings_path}")
PYEOF

# ---- Step 5: Install the skill ----

SKILL_SOURCE="$SCRIPT_DIR/skills/prefer-fork-agents"
SKILL_DEST="$SKILLS_DIR/prefer-fork-agents"

if [ ! -f "$SKILL_SOURCE/SKILL.md" ]; then
  echo "ERROR: skill source not found at $SKILL_SOURCE/SKILL.md"
  echo "       (Are you running install.sh from the repo root?)"
  exit 1
fi

mkdir -p "$SKILL_DEST"
cp "$SKILL_SOURCE/SKILL.md" "$SKILL_DEST/SKILL.md"
echo "Installed skill to: $SKILL_DEST/SKILL.md"

# ---- Done ----

echo
echo "Installation complete."
echo
echo "Next steps:"
echo "  1. Restart Claude Code (close and reopen — settings load at process startup)"
echo "  2. In a fresh session, run /skills — 'prefer-fork-agents' should be listed"
echo "  3. Try /fork — the slash command should now be available"
echo "  4. Test: 'Spawn an agent that searches my repo for X'"
echo "     The agent indicator should show 'fork' instead of 'general-purpose'"
echo
echo "To uninstall:"
echo "  cp $BACKUP $SETTINGS"
echo "  rm -rf $SKILL_DEST"
