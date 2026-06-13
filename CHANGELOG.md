# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — 2026-06-13

### Fixed
- **Critical: Fork-Guard false-positive in Claude Code v2.1.177.** The runtime's recursion guard (`$m_()` in the bundled binary) does a naive substring scan for `<fork-boilerplate` across all user-messages. The previous skill texts described the boilerplate tag literally, so every Skill-invoke poisoned the session and caused every subsequent fork dispatch to fail with `Fork is not available inside a forked worker.` — even in clean top-level sessions. All literal occurrences are now replaced with Unicode angle brackets (`‹fork-boilerplate›`, U+2039 / U+203A), which preserves the semantic meaning for human readers while breaking the substring match. See [`UPDATE.md`](UPDATE.md) for the full root-cause analysis, recovery steps for already-poisoned sessions, and upstream-fix recommendations.

### Added
- **`UPDATE.md`** — full incident report for the v2.1.177 Fork-Guard bug: binary-string evidence, reproduction, source-patch + session-JSONL-recovery procedure, trigger source warn-list, upstream-fix proposal.
- **Skill updates** with empirical findings from Claude Code v2.1.177:
  - Both skills gain a **"Self-check: are you the fork?"** section so fork-workers don't re-trigger the no-recursion rule by reading the default-to-fork mandate.
  - `prefer-fork-agents` documents that `subagent_type: "fork"` must be set **explicitly** (verified empirically in v2.1.177 — omission silently falls back to `general-purpose`, losing the cache-share advantage).
  - Updated fork-detection signatures: first JSONL line `type == "fork-context-ref"` is the load-bearing single check; `attributionAgent: fork` on assistant turns is the secondary signature.
- CI smoke test workflow (`install-test.yml`) covering `install.sh` on `ubuntu-latest` + `macos-latest` and `install.ps1` on `windows-latest`, with stubbed `claude` binary returning a known version.
- `CONTRIBUTING.md`, `SECURITY.md`, GitHub issue forms (`bug_report.yml`, `feature_request.yml`), and a pull request template under `.github/`.
- `install.sh` and `install.ps1` now accept `--dry-run` / `-n`, `--check`, `--uninstall` (with `--yes` / `-Yes` to skip confirmation), and `--help`. Re-running without flags preserves the original idempotent behavior.

### Changed
- **Breaking (documentation, not runtime):** the previous skill text claimed fork mode triggers by **omitting** `subagent_type`. Verified against the v2.1.177 binary: that is wrong — omission falls back to `general-purpose`. The new guidance is to **always pass `subagent_type: "fork"` explicitly**. Existing skill prompts in user code that relied on the omission pattern silently produce a non-fork agent and must be updated.

## [1.0.0] — TBD

Initial tagged release. See `docs/RELEASE-v1.0.0.md` (produced by the Phase 1 fork) for the full launch notes once reconciliation completes.

[2.0.0]: https://github.com/Kirchlive/Claude-Full-Context-Agent/releases/tag/v2.0.0
[1.0.0]: https://github.com/Kirchlive/Claude-Full-Context-Agent/releases/tag/v1.0.0
