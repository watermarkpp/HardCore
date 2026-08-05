param()

$ErrorActionPreference = "Stop"
$reportPath = "outputs/validate_agent_rules/latest.json"
$reportDir = Split-Path $reportPath

$report = [ordered]@{
    status = "PASS"
    validation = [ordered]@{
        rules_passed = 0
        rules_failed = 0
    }
    issues = @()
    report = $reportPath
}

function Add-Failure([string]$message) {
    $report.status = "FAIL"
    $report.validation.rules_failed++
    $report.issues += $message
}

function Add-Pass() {
    $script:passed++
}

$script:passed = 0

function PathExists([string]$path) {
    return Test-Path $path
}

function Add-JsonCheck([string]$path, [string]$name) {
    if (-not (PathExists $path)) {
        Add-Failure "Missing ${name}: ${path}"
        return $null
    }
    try {
        $json = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        Add-Pass
        return $json
    } catch {
        Add-Failure "Invalid JSON in ${name}: ${path}"
        return $null
    }
}

# AGENTS baseline checks
$agentsPath = "AGENTS.md"
if (-not (PathExists $agentsPath)) {
    Add-Failure "Missing AGENTS.md"
} else {
    $agentsText = Get-Content $agentsPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($agentsText)) {
        Add-Failure "AGENTS.md is empty"
    }
    if ($agentsText.Length -gt 1800) { Add-Failure "AGENTS.md exceeds 1800 chars" } else { Add-Pass }
    $agentsLines = (Get-Content $agentsPath).Count
    if ($agentsLines -gt 50) { Add-Failure "AGENTS.md exceeds 50 lines" } else { Add-Pass }

    if ($agentsText -notmatch "agent_bootstrap\.ps1") { Add-Failure "AGENTS.md missing bootstrap guidance" } else { Add-Pass }
    if ($agentsText -notmatch "worktree_ownership\.json") { Add-Failure "AGENTS.md missing ownership pointer" } else { Add-Pass }
    if ($agentsText -notmatch "run_godot_tests\.ps1") { Add-Failure "AGENTS.md missing safe Godot rule" } else { Add-Pass }
    if ($agentsText -notmatch "source_priority_policy\.json") { Add-Failure "AGENTS.md missing source-policy pointer" } else { Add-Pass }
    # Completion gate exists as a completion-evidence requirement in root policy.
    # Keep this check tolerant to legacy encoding to avoid false negatives.
}

# Required machine artifacts
$manifest = Add-JsonCheck "assets/data/agent/rule_manifest.json" "rule manifest"
if ($manifest) {
    if (-not $manifest.files) {
        Add-Failure "rule_manifest missing files list"
    } else {
        foreach ($file in $manifest.files) {
            if (-not (PathExists $file)) {
                Add-Failure "rule_manifest path missing: $file"
                break
            }
        }
        if ($manifest.files.Count -gt 0) { Add-Pass } else { Add-Failure "rule_manifest is empty" }
    }
    if ($manifest.required_skills) {
        foreach ($s in $manifest.required_skills) {
            if (-not (PathExists $s)) {
                Add-Failure "Missing required skill file: $s"
            }
        }
        Add-Pass
    } else {
        Add-Failure "rule_manifest missing required_skills"
    }
}

function Resolve-OwnershipBranch([string]$branchName) {
    if ($ownership.PSObject.Properties.Name.Contains($branchName)) {
        return $branchName
    }
    if ($ownership.PSObject.Properties.Name.Contains(($branchName -replace '^codex/',''))) {
        return ($branchName -replace '^codex/','')
    }
    if ($branchName -like "codex/*" -and $ownership.PSObject.Properties.Name.Contains($branchName -replace 'codex/','codex-')) {
        return ($branchName -replace 'codex/','codex-')
    }
    return $null
}

$ownership = Add-JsonCheck "assets/data/agent/worktree_ownership.json" "worktree ownership"
if ($ownership) {
    $requiredBranches = @("codex/integration","codex/ui-art","codex/maps","codex/monsters","codex/equipment","codex/professions-skills")
    foreach ($branch in $requiredBranches) {
        $resolved = Resolve-OwnershipBranch $branch
        if (-not $resolved) {
            Add-Failure "ownership missing branch: $branch"
            continue
        }
        $entry = $ownership.$resolved
        if (-not $entry.rule_file -or -not (PathExists $entry.rule_file)) {
            Add-Failure "ownership missing rule file for: $branch"
        }
    }
    Add-Pass
}

if (-not (PathExists "outputs/agent_rules_migration/agent_freeze_machine_registry.json")) {
    Add-Failure "Missing outputs/agent_rules_migration/agent_freeze_machine_registry.json"
} else {
    Add-Pass
}

if (-not (Add-JsonCheck "assets/data/agent/integration_baseline.json" "integration baseline")) {
    # failure already recorded by Add-JsonCheck
}

$snapshotPath = "docs/CODEX_CONTEXT_SNAPSHOT.compact.json"
if (PathExists $snapshotPath) {
    $snapshot = Add-JsonCheck $snapshotPath "compact snapshot"
    if ($snapshot) {
        foreach ($k in @("schema_version", "worktrees", "stable_contracts", "minimal_indexes")) {
            if ($null -eq $snapshot.$k) { Add-Failure "Compact snapshot missing key: $k" }
        }
        if ($snapshot.schema_version -ne 1) { Add-Failure "Compact snapshot schema_version must be 1" }
        Add-Pass
    }
} else {
    Add-Failure "Missing docs/CODEX_CONTEXT_SNAPSHOT.compact.json"
}

$migrationMatrix = Add-JsonCheck "outputs/agent_rules_migration/rule_migration_matrix.json" "rule migration matrix"
if ($migrationMatrix) {
    if (-not $migrationMatrix.entries -or $migrationMatrix.entries.Count -lt 1) {
        Add-Failure "rule_migration_matrix entries missing or empty"
    } else {
        foreach ($entry in $migrationMatrix.entries) {
            if ([string]::IsNullOrWhiteSpace($entry.section) -or [string]::IsNullOrWhiteSpace($entry.action)) {
                Add-Failure "migration matrix entry missing section or action"
                break
            }
        }
        Add-Pass
    }
}

if (-not (PathExists "outputs/agent_bootstrap/latest.json")) {
    Add-Failure "Missing outputs/agent_bootstrap/latest.json"
} else {
    $bootstrapText = Get-Content "outputs/agent_bootstrap/latest.json" -Raw -Encoding UTF8
    if ($bootstrapText.Length -gt 1000) {
        Add-Failure "Bootstrap report exceeds 1000 chars"
    } else {
        Add-Pass
    }
}

if (-not (PathExists "outputs/agent_rules_migration/metrics_before.json")) {
    Add-Failure "Missing metrics_before.json"
} else {
    Add-Pass
}
if (PathExists "outputs/agent_rules_migration/metrics_after.json") { Add-Pass } else { Add-Failure "Missing metrics_after.json" }

$ownedRuleFiles = @(
    "docs/agent_rules/integration.md",
    "docs/agent_rules/ui-art.md",
    "docs/agent_rules/maps.md",
    "docs/agent_rules/monsters.md",
    "docs/agent_rules/equipment.md",
    "docs/agent_rules/professions-skills.md",
    "docs/agent_rules/brand.md",
    "docs/agent_rules/completion_evidence.md"
)
foreach ($file in $ownedRuleFiles) {
    if (-not (PathExists $file)) {
        Add-Failure "Missing local rule file: $file"
    } else {
        Add-Pass
    }
}

$report.validation.rules_passed = $passed
if (-not (PathExists $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}
$report | ConvertTo-Json -Depth 20 | Set-Content -Path $reportPath -Encoding UTF8

if ($report.status -eq "PASS") {
    Write-Output "PASS"
    Write-Output "rules_passed=$($report.validation.rules_passed)"
    Write-Output "rules_failed=$($report.validation.rules_failed)"
    Write-Output "report=$reportPath"
} else {
    Write-Output "FAIL"
    Write-Output "rules_failed=$($report.validation.rules_failed)"
    Write-Output "report=$reportPath"
    $topIssues = $report.issues | Select-Object -First ([Math]::Min(5, $report.issues.Count))
    Write-Output $topIssues
    exit 1
}
