#!/usr/bin/env pwsh
# Full-Context-Fork-Agent installer (PowerShell)
# Sets CLAUDE_CODE_FORK_SUBAGENT=1 in ~/.claude/settings.json and installs all bundled skills.
#
# Requires PowerShell 7+. On Windows, install via:  winget install --id Microsoft.Powershell
#
# Usage:
#   ./install.ps1               # install (default; idempotent)
#   ./install.ps1 -DryRun       # preview every action without writing
#   ./install.ps1 -Check        # report current state and exit
#   ./install.ps1 -Uninstall    # restore most-recent backup, remove skills
#   ./install.ps1 -Help         # show usage

[CmdletBinding()]
param(
    [Alias('n')][switch]$DryRun,
    [switch]$EnvOnly,
    [switch]$Check,
    [switch]$Uninstall,
    [Alias('y')][switch]$Yes,
    [Alias('h')][switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
    @"
Full-Context-Fork-Agent installer (PowerShell)

Usage:
  ./install.ps1 [OPTIONS]

Options:
  (no flags)        Install: backup settings, merge CLAUDE_CODE_FORK_SUBAGENT=1, install skills
  -EnvOnly          Only merge CLAUDE_CODE_FORK_SUBAGENT=1; skip skill install
                    (use when skills are already provided by the marketplace plugin)
  -DryRun, -n       Print every action without making changes
  -Check            Report current state (env var, skills, last backup); always exits 0
  -Uninstall        Restore most-recent backup and remove installed skills
  -Yes, -y          Skip confirmation prompts (used with -Uninstall)
  -Help, -h         Show this message and exit

Examples:
  ./install.ps1                     # install
  ./install.ps1 -DryRun             # preview only
  ./install.ps1 -Check              # status report
  ./install.ps1 -Uninstall          # interactive uninstall
  ./install.ps1 -Uninstall -Yes     # non-interactive uninstall
"@ | Write-Host
    exit 0
}

# ---- Verify PowerShell version ----

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error @"
PowerShell 7+ required (detected: $($PSVersionTable.PSVersion)).
Install via:
  Windows: winget install --id Microsoft.Powershell
  macOS:   brew install --cask powershell
  Linux:   see https://learn.microsoft.com/powershell/scripting/install/installing-powershell
"@
    exit 1
}

# ---- Common paths ----

$Required  = [version]'2.1.117'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeDir = Join-Path $HOME '.claude'
$Settings  = Join-Path $ClaudeDir 'settings.json'
$SkillsDir = Join-Path $ClaudeDir 'skills'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup    = "$Settings.pre-fork-backup-$Timestamp"
$SkillsBase = Join-Path $ScriptDir 'skills'

# ---- Dry-run wrappers ----

function Invoke-OrSay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][scriptblock]$Action
    )
    if ($DryRun) {
        Write-Host "[dry-run] $Description"
    } else {
        & $Action
    }
}

# ---- Sub-commands ----

function Invoke-Check {
    Write-Host 'Full-Context-Fork-Agent — status check'
    Write-Host '======================================='
    Write-Host ''
    Write-Host "settings.json:   $Settings"
    if (Test-Path $Settings) {
        $raw = Get-Content -Raw -Path $Settings
        if ($raw -match '"CLAUDE_CODE_FORK_SUBAGENT"\s*:\s*"1"') {
            Write-Host '  CLAUDE_CODE_FORK_SUBAGENT: set'
        } else {
            Write-Host '  CLAUDE_CODE_FORK_SUBAGENT: not set'
        }
    } else {
        Write-Host '  (file does not exist)'
        Write-Host '  CLAUDE_CODE_FORK_SUBAGENT: not set'
    }
    Write-Host ''

    Write-Host "Skills (bundled vs installed at ${SkillsDir}):"
    if (Test-Path $SkillsBase) {
        foreach ($skillDirInfo in Get-ChildItem -Path $SkillsBase -Directory) {
            $skillName = $skillDirInfo.Name
            $installed = Join-Path $SkillsDir $skillName 'SKILL.md'
            if (Test-Path $installed) {
                Write-Host "  [installed] $skillName"
            } else {
                Write-Host "  [missing]   $skillName"
            }
        }
    } else {
        Write-Host "  (bundled skills directory not found at $SkillsBase)"
    }
    Write-Host ''

    $backups = Get-ChildItem -Path $ClaudeDir -Filter 'settings.json.pre-fork-backup-*' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending
    if ($backups) {
        Write-Host "Last backup:     $($backups[0].FullName)"
    } else {
        Write-Host 'Last backup:     (none)'
    }
}

function Get-LatestBackup {
    Get-ChildItem -Path $ClaudeDir -Filter 'settings.json.pre-fork-backup-*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Invoke-Uninstall {
    Write-Host 'Full-Context-Fork-Agent — uninstall'
    Write-Host '===================================='
    Write-Host ''

    $lastBackup = Get-LatestBackup

    Write-Host 'Planned actions:'
    if ($lastBackup) {
        Write-Host "  - Restore: $($lastBackup.FullName) -> $Settings"
    } else {
        Write-Host '  - (no backup found; settings.json will be left in place)'
    }
    if (Test-Path $SkillsBase) {
        foreach ($skillDirInfo in Get-ChildItem -Path $SkillsBase -Directory) {
            $skillName = $skillDirInfo.Name
            $installed = Join-Path $SkillsDir $skillName
            if (Test-Path $installed) {
                Write-Host "  - Remove:  $installed"
            }
        }
    }
    Write-Host ''

    if (-not $Yes) {
        $ans = Read-Host 'Proceed? [y/N]'
        if ($ans -notmatch '^(y|Y|yes|YES)$') {
            Write-Host 'Aborted.'
            exit 1
        }
    }

    if ($lastBackup) {
        Invoke-OrSay -Description "cp '$($lastBackup.FullName)' '$Settings'" -Action {
            Copy-Item -Path $lastBackup.FullName -Destination $Settings -Force
        }
        Write-Host 'Restored settings.json from backup.'
    }

    if (Test-Path $SkillsBase) {
        foreach ($skillDirInfo in Get-ChildItem -Path $SkillsBase -Directory) {
            $skillName = $skillDirInfo.Name
            $installed = Join-Path $SkillsDir $skillName
            if (Test-Path $installed) {
                Invoke-OrSay -Description "rm -rf '$installed'" -Action {
                    Remove-Item -Recurse -Force -Path $installed
                }
                Write-Host "Removed $installed"
            }
        }
    }

    Write-Host ''
    Write-Host 'Uninstall complete. Restart Claude Code for changes to take effect.'
}

function Invoke-Install {
    Write-Host 'Full-Context-Fork-Agent installer'
    Write-Host '=================================='
    if ($DryRun) { Write-Host '(dry-run: no files will be modified)' }
    Write-Host ''

    # ---- Step 1: Verify Claude Code is installed and version >= 2.1.117 ----

    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claudeCmd) {
        Write-Error "'claude' CLI not found in PATH.`nInstall Claude Code first: https://code.claude.com/docs/en/install"
        exit 1
    }

    try {
        $versionLine = (& claude --version 2>$null) | Select-Object -First 1
        if ($versionLine -match '(\d+)\.(\d+)\.(\d+)') {
            $detected = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
            if ($detected -lt $Required) {
                Write-Error "Claude Code $detected detected, but $Required+ is required for fork mode.`nUpdate via: claude --update  (or your install method)"
                exit 1
            }
            Write-Host "Claude Code version: $detected (OK)"
        } else {
            Write-Warning 'Could not detect Claude Code version. Proceeding anyway.'
        }
    } catch {
        Write-Warning "Could not run 'claude --version'. Proceeding anyway."
    }

    # ---- Step 2: Backup existing settings.json ----

    Invoke-OrSay -Description "mkdir -p '$ClaudeDir'" -Action {
        New-Item -ItemType Directory -Path $ClaudeDir -Force | Out-Null
    }

    if (Test-Path $Settings) {
        Invoke-OrSay -Description "cp '$Settings' '$Backup'" -Action {
            Copy-Item -Path $Settings -Destination $Backup
        }
        Write-Host "Backed up existing settings to: $Backup"
    } else {
        Write-Host 'No existing settings.json — will create a new one.'
    }

    # ---- Step 3: Merge env.CLAUDE_CODE_FORK_SUBAGENT=1 (preserves everything else) ----

    if ($DryRun) {
        Write-Host "[dry-run] would merge CLAUDE_CODE_FORK_SUBAGENT=1 into $Settings (preserving other keys)"
    } else {
        $data = @{}

        if ((Test-Path $Settings) -and ((Get-Item $Settings).Length -gt 0)) {
            $raw = Get-Content -Path $Settings -Raw

            # Best-effort duplicate top-level key detection via brace-depth tracking.
            $pattern = '(?m)^[ \t]+"([^"\\]+)"\s*:'
            $topLevelKeys = @()
            foreach ($match in [regex]::Matches($raw, $pattern)) {
                $depth = 0
                $inString = $false
                $escaped = $false
                for ($i = 0; $i -lt $match.Index; $i++) {
                    $c = $raw[$i]
                    if ($escaped) { $escaped = $false; continue }
                    if ($c -eq '\') { $escaped = $true; continue }
                    if ($c -eq '"') { $inString = -not $inString; continue }
                    if (-not $inString) {
                        if ($c -eq '{') { $depth++ }
                        elseif ($c -eq '}') { $depth-- }
                    }
                }
                if ($depth -eq 1) {
                    $topLevelKeys += $match.Groups[1].Value
                }
            }

            $dupes = $topLevelKeys | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
            if ($dupes) {
                Write-Error "settings.json contains duplicate top-level keys: $($dupes -join ', ')`nFix the duplicate keys manually before re-running this installer."
                exit 1
            }

            try {
                $data = $raw | ConvertFrom-Json -AsHashtable
                if ($null -eq $data) { $data = @{} }
            } catch {
                Write-Error "existing settings.json is not valid JSON: $_"
                exit 1
            }
        }

        if (-not $data.ContainsKey('env') -or ($data['env'] -isnot [hashtable])) {
            $data['env'] = @{}
        }
        $data['env']['CLAUDE_CODE_FORK_SUBAGENT'] = '1'

        $json = $data | ConvertTo-Json -Depth 32
        Set-Content -Path $Settings -Value $json -Encoding UTF8 -NoNewline
        Add-Content -Path $Settings -Value "`n" -NoNewline

        Write-Host "Merged CLAUDE_CODE_FORK_SUBAGENT=1 into $Settings"
    }

    # ---- Step 4: Install all bundled skills (auto-discovered) ----

    $InstalledCount = 0
    if ($EnvOnly) {
        Write-Host 'Skipping skill install (-EnvOnly). Skills are provided by the marketplace plugin.'
    } else {
        if (-not (Test-Path $SkillsBase)) {
            Write-Error "skills directory not found at $SkillsBase`n(Are you running install.ps1 from the repo root?)"
            exit 1
        }

        foreach ($skillDirInfo in Get-ChildItem -Path $SkillsBase -Directory) {
            $skillName = $skillDirInfo.Name
            $skillFile = Join-Path $skillDirInfo.FullName 'SKILL.md'
            if (-not (Test-Path $skillFile)) {
                Write-Host "  skip $skillName (no SKILL.md)"
                continue
            }
            $skillDest = Join-Path $SkillsDir $skillName
            Invoke-OrSay -Description "mkdir -p '$skillDest' && cp SKILL.md" -Action {
                New-Item -ItemType Directory -Path $skillDest -Force | Out-Null
                Copy-Item -Path $skillFile -Destination (Join-Path $skillDest 'SKILL.md') -Force
            }
            Write-Host "Installed skill: $(Join-Path $skillDest 'SKILL.md')"
            $InstalledCount++
        }

        if ($InstalledCount -eq 0) {
            Write-Error "no skills found to install in $SkillsBase"
            exit 1
        }
    }

    # ---- Done ----

    Write-Host ''
    if ($EnvOnly) {
        Write-Host 'Installation complete (env-only).'
    } else {
        Write-Host "Installation complete. $InstalledCount skill(s) installed."
    }
    if ($DryRun) { Write-Host '(dry-run: nothing was actually written.)' }
    Write-Host ''
    Write-Host 'Next steps:'
    Write-Host '  1. Restart Claude Code (close and reopen — settings load at process startup)'
    Write-Host '  2. In a fresh session, run /skills — the fork skills should be listed'
    Write-Host "  3. Test: 'Spawn an agent that searches my repo for X'"
    Write-Host "     The agent indicator should show 'fork' instead of 'general-purpose'"
    Write-Host ''
    Write-Host 'Recommended next step for projects using parallel fork fan-outs:'
    Write-Host "  Add '.claude/worktrees/' to your project's .gitignore."
    Write-Host '  (Worktree forks create nested .git directories that should be excluded.)'
    Write-Host ''
    Write-Host 'To roll back this install:'
    Write-Host '  ./install.ps1 -Uninstall'
}

# ---- Dispatch ----

if ($Check)     { Invoke-Check;     exit 0 }
if ($Uninstall) { Invoke-Uninstall; exit 0 }
Invoke-Install
