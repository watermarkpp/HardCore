param(
    [switch] $Compact
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Get-Location).Path
$reportPath = Join-Path $RepoRoot "outputs/agent_bootstrap/latest.json"
$errors = New-Object System.Collections.Generic.List[string]

function Fail([string]$message) {
    $null = $errors.Add($message)
}

function PathExists([string]$path) {
    return Test-Path $path
}

try {
    if (-not $Compact) {
        Fail "Compact flag required: run tools/agent_bootstrap.ps1 -Compact"
        throw "invalid-call"
    }

    $branch = (& git branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) { Fail "Cannot read current git branch" }

    $head = (& git rev-parse HEAD).Trim()
    if ([string]::IsNullOrWhiteSpace($head)) { Fail "Cannot read HEAD" }

$baselineFile = Join-Path $RepoRoot "assets/data/agent/integration_baseline.json"
$snapshotFile = Join-Path $RepoRoot "docs/CODEX_CONTEXT_SNAPSHOT.compact.json"
$ownershipFile = Join-Path $RepoRoot "assets/data/agent/worktree_ownership.json"
$matrixFile = Join-Path $RepoRoot "outputs/agent_rules_migration/rule_migration_matrix.json"

    if (-not (PathExists $baselineFile)) { Fail "Missing assets/data/agent/integration_baseline.json" }
    if (-not (PathExists $snapshotFile)) { Fail "Missing docs/CODEX_CONTEXT_SNAPSHOT.compact.json" }
    if (-not (PathExists $ownershipFile)) { Fail "Missing assets/data/agent/worktree_ownership.json" }
    if (-not (PathExists $matrixFile)) { Fail "Missing outputs/agent_rules_migration/rule_migration_matrix.json" }

    $ruleMap = @{
        "codex/integration" = "docs/agent_rules/integration.md"
        "codex/ui-art" = "docs/agent_rules/ui-art.md"
        "codex/maps" = "docs/agent_rules/maps.md"
        "codex/monsters" = "docs/agent_rules/monsters.md"
        "codex/equipment" = "docs/agent_rules/equipment.md"
        "codex/professions-skills" = "docs/agent_rules/professions-skills.md"
    }

    if (-not $ruleMap.ContainsKey($branch)) {
        Fail "Unknown branch for bootstrap routing: $branch"
    }

    $ruleFile = $ruleMap[$branch]
    if (-not (PathExists $ruleFile)) {
        Fail "Missing rule file for branch ${branch}: $ruleFile"
    }

    $protectedFiles = @(
        Join-Path $RepoRoot "AGENTS.md"
        Join-Path $RepoRoot "docs/CODEX_CONTEXT_SNAPSHOT.md"
        Join-Path $RepoRoot "outputs/agent_rules_migration/AGENTS.before.md"
        Join-Path $RepoRoot "outputs/agent_rules_migration/CODEX_CONTEXT_SNAPSHOT.before.md"
        $snapshotFile
    )
    $protectedChanged = $false
    foreach ($f in $protectedFiles) {
        if (Test-Path $f) {
            $status = git status --porcelain -- $f
            if (-not [string]::IsNullOrWhiteSpace($status)) {
                $protectedChanged = $true
            }
        }
    }

    $baseline = (Get-Content -Path $baselineFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue)
    $snapshot = (Get-Content -Path $snapshotFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue)
    $ruleEntry = (Get-Content -Path $matrixFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue)
    if (-not $baseline) { Fail "Invalid integration_baseline.json" }
    if (-not $snapshot) { Fail "Invalid CODEX_CONTEXT_SNAPSHOT.compact.json" }
    if (-not $ruleEntry) { Fail "Invalid rule_migration_matrix.json" }

    if ($errors.Count -eq 0) {
        # Use branch head as baseline if explicit baseline file is missing entry
        $baselineHead = $null
        if ($baseline.PSObject.Properties.Name -contains "integration_head") {
            $baselineHead = $baseline.integration_head
        } else {
            $baselineHead = $head
        }
        if ($branch -eq "codex/integration" -and $baseline.PSObject.Properties.Name -contains "worktrees" -and $baseline.worktrees -and $baseline.worktrees.$branch) {
            $baselineHead = $baseline.worktrees.$branch.baseline_head
        }

        $entryHint = @()
        if ($snapshot -and $snapshot.worktrees -and $snapshot.worktrees.$branch) {
            $entryHint = @($snapshot.worktrees.$branch)
        }

        $result = [ordered]@{
            status = "PASS"
            branch = $branch
            head = $head
            baseline = $baselineHead
            rule_file = $ruleFile
            snapshot = "docs/CODEX_CONTEXT_SNAPSHOT.compact.json"
            entry_hint = $entryHint
            protected_changed = $protectedChanged
            report = "outputs/agent_bootstrap/latest.json"
        }
        $json = $result | ConvertTo-Json -Compress
        New-Item -ItemType Directory -Path (Split-Path $reportPath) -Force | Out-Null
        $json | Set-Content $reportPath
        Write-Output $json
    } else {
        $result = [ordered]@{
            status = "FAIL"
            branch = $branch
            head = $head
            failed_checks = $errors.Count
            issues = $errors | Select-Object -First 5
            report = "outputs/agent_bootstrap/latest.json"
        }
        $json = $result | ConvertTo-Json -Compress
        New-Item -ItemType Directory -Path (Split-Path $reportPath) -Force | Out-Null
        $json | Set-Content $reportPath
        Write-Output "FAIL"
        Write-Output "issues= $($errors.Count)"
        Write-Output ($errors | Select-Object -First 5)
        Write-Output "report=outputs/agent_bootstrap/latest.json"
    }
} catch {
    if ($errors.Count -eq 0) {
        $null = $errors.Add($_.Exception.Message)
    }
    $result = [ordered]@{
        status = "FAIL"
        branch = $branch
        head = $head
        failed_checks = $errors.Count
        issues = $errors
        report = "outputs/agent_bootstrap/latest.json"
    }
    $json = $result | ConvertTo-Json -Compress
    New-Item -ItemType Directory -Path (Split-Path $reportPath) -Force | Out-Null
    $json | Set-Content $reportPath
    Write-Output "FAIL"
    Write-Output "issues= $($errors.Count)"
    Write-Output ($errors | Select-Object -First 5)
    Write-Output "report=outputs/agent_bootstrap/latest.json"
    exit 1
}
