# Contributing

Thanks for your interest. This project is small on purpose — please read these ground rules before opening a PR.

## Scope

This repo does exactly two things: flip `CLAUDE_CODE_FORK_SUBAGENT=1` in `~/.claude/settings.json` and install the bundled skills. Anything outside that scope (new commands, hooks beyond the documented `PreToolUse` example, integrations with external services) is unlikely to be merged unless discussed in an issue first.

## Ground rules

### Installer scripts must stay dependency-light

- **`install.sh`** may use only POSIX shell + `python3` standard library. No `jq`, no Node, no extra package installs. The Python heredoc must remain inline (no auxiliary `.py` files).
- **`install.ps1`** must run on stock PowerShell 7+ with no module imports beyond what ships with `pwsh`. No `Install-Module` calls, no third-party assemblies.
- Both scripts must remain idempotent: re-running without flags must converge to the same end state, taking a backup each time.

Any change that introduces a new runtime dependency will be rejected without discussion.

### Skills must be TDD-baselined

If you add a new skill (or materially edit an existing one), follow the methodology described by the `superpowers:writing-skills` skill:

1. **RED:** run the pressure scenario(s) against a subagent **without** the skill and document the baseline failures verbatim in your PR description.
2. **GREEN:** write the minimal skill that addresses those specific failures. Re-run and verify the subagent now complies.
3. **REFACTOR:** close any remaining loopholes; re-test.

A PR that ships a new or edited skill without the RED-phase transcript will be marked as a draft until provided. "I tested it manually" does not count.

### Commit style

- One concern per commit, present-tense imperative subject line (`Add --dry-run flag to install.sh`, not `Added --dry-run flag`).
- Reference issues in the body, not the subject (`Closes #12`, `Refs #34`).
- Sign your commits if you can (`git commit -S`).
- Web-UI commits are accepted but discouraged for code changes — the lack of local pre-commit hooks tends to let typos through.

### PR review

- One reviewer minimum (the owner, until the project has more contributors).
- CI (`install-test.yml`) must be green before merge.
- For changes that touch documentation referencing Anthropic features, link the relevant `code.claude.com/docs/...` page or `anthropics/claude-code` issue. Tribal knowledge is fine in commit bodies, not in the docs themselves.

## Development setup

```bash
git clone https://github.com/Kirchlive/Full-Context-Fork-Agent.git
cd Full-Context-Fork-Agent
# Hack on install.sh, skills/, etc.
bash install.sh --dry-run  # confirm intended actions without touching ~/.claude/
```

For Windows:

```powershell
./install.ps1 -DryRun
```

## Reporting bugs

Use the GitHub issue forms under `.github/ISSUE_TEMPLATE/`. The bug-report form asks for the Claude Code version, OS, and reproduction steps — please fill them in. Bugs with `cannot reproduce` will be closed if the reporter doesn't respond within a reasonable window.

## Security

See `SECURITY.md`.
