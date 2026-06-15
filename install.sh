#!/usr/bin/env bash
# Full-Context-Fork-Agent installer
# Sets CLAUDE_CODE_FORK_SUBAGENT=1 in ~/.claude/settings.json and installs all bundled skills.
#
# Usage:
#   bash install.sh              # install (default; idempotent)
#   bash install.sh --dry-run    # preview every action without writing
#   bash install.sh --check      # report current state and exit
#   bash install.sh --uninstall  # restore most-recent backup, remove skills
#   bash install.sh --help       # show usage

set -euo pipefail

# ---- Argument parsing ----

DRY_RUN=0
CHECK=0
UNINSTALL=0
ASSUME_YES=0
ENV_ONLY=0

print_help() {
  cat <<'EOF'
Full-Context-Fork-Agent installer

Usage:
  bash install.sh [OPTIONS]

Options:
  (no flags)        Install: backup settings, merge CLAUDE_CODE_FORK_SUBAGENT=1, install skills
      --env-only    Only merge CLAUDE_CODE_FORK_SUBAGENT=1; skip skill install
                    (use when skills are already provided by the marketplace plugin)
  -n, --dry-run     Print every action without making changes
      --check       Report current state (env var, skills, last backup); always exits 0
      --uninstall   Restore most-recent backup and remove installed skills
  -y, --yes         Skip confirmation prompts (used with --uninstall)
  -h, --help        Show this message and exit

Examples:
  bash install.sh                       # install
  bash install.sh --dry-run             # preview only
  bash install.sh --check               # status report
  bash install.sh --uninstall           # interactive uninstall
  bash install.sh --uninstall --yes     # non-interactive uninstall
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    --env-only) ENV_ONLY=1 ;;
    --check) CHECK=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) print_help; exit 0 ;;
    --) shift; break ;;
    *) echo "Unknown option: $1" >&2; echo "Try: bash install.sh --help" >&2; exit 2 ;;
  esac
  shift
done

# ---- Common paths ----

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
SKILLS_DIR="$CLAUDE_DIR/skills"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$SETTINGS.pre-fork-backup-$TIMESTAMP"
SKILLS_BASE="$SCRIPT_DIR/skills"

# ---- Dry-run helpers ----

# run_or_say <command...> : execute the command, or print "[dry-run] cmd args" if --dry-run.
run_or_say() {
  if [ "$DRY_RUN" = "1" ]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# write_or_say <path> <heredoc-content-via-stdin> : write file via stdin, or describe.
write_or_say() {
  local path="$1"
  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] write $path  (content from stdin, $(wc -c) bytes)"
    cat >/dev/null
  else
    cat > "$path"
  fi
}

# ---- Sub-commands ----

cmd_check() {
  echo "Full-Context-Fork-Agent — status check"
  echo "======================================="
  echo
  echo "settings.json:   $SETTINGS"
  if [ -f "$SETTINGS" ]; then
    if grep -Eq '"CLAUDE_CODE_FORK_SUBAGENT"[[:space:]]*:[[:space:]]*"1"' "$SETTINGS"; then
      echo "  CLAUDE_CODE_FORK_SUBAGENT: set"
    else
      echo "  CLAUDE_CODE_FORK_SUBAGENT: not set"
    fi
  else
    echo "  (file does not exist)"
    echo "  CLAUDE_CODE_FORK_SUBAGENT: not set"
  fi
  echo

  echo "Skills (bundled vs installed at $SKILLS_DIR):"
  if [ -d "$SKILLS_BASE" ]; then
    for skill_dir in "$SKILLS_BASE"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name="$(basename "$skill_dir")"
      if [ -f "$SKILLS_DIR/$skill_name/SKILL.md" ]; then
        echo "  [installed] $skill_name"
      else
        echo "  [missing]   $skill_name"
      fi
    done
  else
    echo "  (bundled skills directory not found at $SKILLS_BASE)"
  fi
  echo

  last_backup="$(ls -t "$SETTINGS".pre-fork-backup-* 2>/dev/null | head -1 || true)"
  if [ -n "$last_backup" ]; then
    echo "Last backup:     $last_backup"
  else
    echo "Last backup:     (none)"
  fi
}

cmd_uninstall() {
  echo "Full-Context-Fork-Agent — uninstall"
  echo "===================================="
  echo

  last_backup="$(ls -t "$SETTINGS".pre-fork-backup-* 2>/dev/null | head -1 || true)"

  echo "Planned actions:"
  if [ -n "$last_backup" ]; then
    echo "  - Restore: $last_backup -> $SETTINGS"
  else
    echo "  - (no backup found; settings.json will be left in place)"
  fi
  if [ -d "$SKILLS_BASE" ]; then
    for skill_dir in "$SKILLS_BASE"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name="$(basename "$skill_dir")"
      if [ -d "$SKILLS_DIR/$skill_name" ]; then
        echo "  - Remove:  $SKILLS_DIR/$skill_name"
      fi
    done
  fi
  echo

  if [ "$ASSUME_YES" != "1" ]; then
    printf 'Proceed? [y/N] '
    read -r ans
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "Aborted."; exit 1 ;;
    esac
  fi

  if [ -n "$last_backup" ]; then
    run_or_say cp "$last_backup" "$SETTINGS"
    echo "Restored settings.json from backup."
  fi

  if [ -d "$SKILLS_BASE" ]; then
    for skill_dir in "$SKILLS_BASE"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name="$(basename "$skill_dir")"
      if [ -d "$SKILLS_DIR/$skill_name" ]; then
        run_or_say rm -rf "$SKILLS_DIR/$skill_name"
        echo "Removed $SKILLS_DIR/$skill_name"
      fi
    done
  fi

  echo
  echo "Uninstall complete. Restart Claude Code for changes to take effect."
}

cmd_install() {
  echo "Full-Context-Fork-Agent installer"
  echo "=================================="
  if [ "$DRY_RUN" = "1" ]; then
    echo "(dry-run: no files will be modified)"
  fi
  echo

  # ---- Step 1: Verify Claude Code is installed and version >= 2.1.117 ----

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
    echo "See README.md for the manual procedure."
    exit 1
  fi

  # ---- Step 3: Backup existing settings.json ----

  run_or_say mkdir -p "$CLAUDE_DIR"
  if [ -f "$SETTINGS" ]; then
    run_or_say cp "$SETTINGS" "$BACKUP"
    echo "Backed up existing settings to: $BACKUP"
  else
    echo "No existing settings.json — will create a new one."
  fi

  # ---- Step 4: Merge env.CLAUDE_CODE_FORK_SUBAGENT=1 (preserves everything else) ----

  if [ "$DRY_RUN" = "1" ]; then
    echo "[dry-run] would merge CLAUDE_CODE_FORK_SUBAGENT=1 into $SETTINGS (preserving other keys)"
  else
    python3 - "$SETTINGS" <<'PYEOF'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
data = {}

if settings_path.exists() and settings_path.stat().st_size > 0:
    try:
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
  fi

  # ---- Step 5: Install all bundled skills (auto-discovered) ----

  if [ "$ENV_ONLY" = "1" ]; then
    echo "Skipping skill install (--env-only). Skills are provided by the marketplace plugin."
  else
    if [ ! -d "$SKILLS_BASE" ]; then
      echo "ERROR: skills directory not found at $SKILLS_BASE"
      echo "       (Are you running install.sh from the repo root?)"
      exit 1
    fi

    INSTALLED_COUNT=0
    for skill_dir in "$SKILLS_BASE"/*/; do
      [ -d "$skill_dir" ] || continue
      skill_name="$(basename "$skill_dir")"
      skill_md="$skill_dir/SKILL.md"
      if [ ! -f "$skill_md" ]; then
        echo "  skip $skill_name (no SKILL.md)"
        continue
      fi
      dest="$SKILLS_DIR/$skill_name"
      run_or_say mkdir -p "$dest"
      run_or_say cp "$skill_md" "$dest/SKILL.md"
      echo "Installed skill: $dest/SKILL.md"
      INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    done

    if [ "$INSTALLED_COUNT" -eq 0 ]; then
      echo "ERROR: no skills found to install in $SKILLS_BASE"
      exit 1
    fi
  fi

  # ---- Done ----

  echo
  echo "Installation complete."
  if [ "$DRY_RUN" = "1" ]; then
    echo "(dry-run: nothing was actually written.)"
  fi
  echo
  echo "Next steps:"
  echo "  1. Restart Claude Code (close and reopen — settings load at process startup)"
  echo "  2. In a fresh session, run /skills — the fork skills should be listed"
  echo "  3. Test: 'Spawn an agent that searches my repo for X'"
  echo "     The agent indicator should show 'fork' instead of 'general-purpose'"
  echo
  echo "Recommended next step for projects using parallel fork fan-outs:"
  echo "  Add '.claude/worktrees/' to your project's .gitignore."
  echo "  (Worktree forks create nested .git directories that should be excluded.)"
  echo
  echo "To roll back this install:"
  echo "  bash install.sh --uninstall"
}

# ---- Dispatch ----

if [ "$CHECK" = "1" ]; then
  cmd_check
  exit 0
fi

if [ "$UNINSTALL" = "1" ]; then
  cmd_uninstall
  exit 0
fi

cmd_install
