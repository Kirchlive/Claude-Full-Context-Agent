#!/usr/bin/env pwsh
# Full-Context-Fork-Agent — post-install verification.
# Exits 0 if all checks pass, non-zero otherwise.

$ErrorActionPreference = 'Continue'

$ClaudeDir = Join-Path $HOME '.claude'
$Settings  = Join-Path $ClaudeDir 'settings.json'
$SkillsDir = Join-Path $ClaudeDir 'skills'
$Required  = [version]'2.1.117'

$script:pass = 0
$script:fail = 0

function Check([string]$label, [bool]$ok) {
    if ($ok) {
        Write-Host '  [OK]   ' -ForegroundColor Green -NoNewline
        Write-Host $label
        $script:pass++
    } else {
        Write-Host '  [FAIL] ' -ForegroundColor Red -NoNewline
        Write-Host $label
        $script:fail++
    }
}

Write-Host 'Full-Context-Fork-Agent verification'
Write-Host '====================================='

# 1. settings.json exists and parses as JSON
$parses = $false
$data = $null
if (Test-Path $Settings) {
    try {
        $data = Get-Content $Settings -Raw | ConvertFrom-Json -AsHashtable
        $parses = $true
    } catch { $parses = $false }
}
Check 'settings.json exists and parses as JSON' $parses

# 2. env flag set
$envOk = $false
if ($parses -and $data.ContainsKey('env') -and $data['env'] -is [hashtable]) {
    $envOk = ($data['env']['CLAUDE_CODE_FORK_SUBAGENT'] -eq '1')
}
Check 'env.CLAUDE_CODE_FORK_SUBAGENT == "1"' $envOk

# 3-4. skills present
foreach ($skill in @('prefer-fork-agents', 'fan-out-fork-agents')) {
    $userPath = Join-Path $SkillsDir "$skill/SKILL.md"
    $pluginPath = if ($env:CLAUDE_PLUGIN_ROOT) { Join-Path $env:CLAUDE_PLUGIN_ROOT "skills/$skill/SKILL.md" } else { $null }
    $present = (Test-Path $userPath) -or ($pluginPath -and (Test-Path $pluginPath))
    Check "skill available: $skill" $present
}

# 5. claude CLI version
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    try {
        $line = (& claude --version 2>$null) | Select-Object -First 1
        if ($line -match '(\d+)\.(\d+)\.(\d+)') {
            $detected = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
            Check ("claude CLI $detected >= $Required") ($detected -ge $Required)
        } else {
            Check 'claude CLI version detectable' $false
        }
    } catch {
        Check 'claude CLI version detectable' $false
    }
} else {
    Check 'claude CLI in PATH' $false
}

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
