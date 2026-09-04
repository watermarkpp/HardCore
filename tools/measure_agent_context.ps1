param()

$ErrorActionPreference = "Stop"

$agentsPath = "AGENTS.md"
$snapshotPath = "docs/CODEX_CONTEXT_SNAPSHOT.compact.json"
$bootstrapPath = Join-Path $PSScriptRoot "agent_bootstrap.ps1"
$manifestPath = "assets/data/agent/rule_manifest.json"
$metricsBeforePath = "outputs/agent_rules_migration/metrics_before.json"
$metricsAfterPath = "outputs/agent_rules_migration/metrics_after.json"
$bootstrapReportPath = "outputs/agent_bootstrap/latest.json"
$rulesBranchMap = @{
    "codex/integration" = "docs/agent_rules/integration.md"
    "codex/ui-art" = "docs/agent_rules/ui-art.md"
    "codex/maps" = "docs/agent_rules/maps.md"
    "codex/monsters" = "docs/agent_rules/monsters.md"
    "codex/equipment" = "docs/agent_rules/equipment.md"
    "codex/professions-skills" = "docs/agent_rules/professions-skills.md"
}

function Get-Text([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    return Get-Content $path -Raw
}

function Get-Lines([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    return (Get-Content $path).Count
}

function Safe-Json([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    $text = Get-Text $path
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return ($text | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

try {
    $branch = (& git branch --show-current).Trim()
    $ruleFile = if ($rulesBranchMap.ContainsKey($branch)) { $rulesBranchMap[$branch] } else { $null }
    $ruleChars = if ($ruleFile -and (Test-Path $ruleFile)) { (Get-Text $ruleFile).Length } else { 0 }

    $snapshot = Safe-Json $snapshotPath
    $snapshotText = Get-Text $snapshotPath
    $snapshotChars = if ($snapshotText) { $snapshotText.Length } else { 0 }
    $branchSnapshotChars = 0
    if ($snapshot -and $snapshot.worktrees -and $snapshot.worktrees.$branch) {
        $branchEntry = $snapshot.worktrees.$branch
        $branchSnapshotChars = ($branchEntry | ConvertTo-Json -Compress).Length
    } elseif ($snapshotText) {
        $branchSnapshotChars = [math]::Min(120, $snapshotChars)
    }

    if (-not (Test-Path $bootstrapPath)) { throw "Missing tools/agent_bootstrap.ps1" }
    $bootstrapOutput = & powershell -NoProfile -NonInteractive -File (Resolve-Path $bootstrapPath).Path -Compact 2>&1 | Out-String
    $bootstrapOutput = $bootstrapOutput.Trim()
    if ([string]::IsNullOrWhiteSpace($bootstrapOutput)) {
        throw "Bootstrap produced empty output"
    }
    $bootstrapChars = $bootstrapOutput.Length

    $manifest = Safe-Json $manifestPath
    $rootChars = (Get-Text $agentsPath).Length
    $rootLines = Get-Lines $agentsPath
    $before = Safe-Json $metricsBeforePath

    $beforeDefaultStartup = 0
    if ($before -and $before.default_startup_chars) {
        $beforeDefaultStartup = [int]$before.default_startup_chars
    } else {
        $beforeRoot = if ($before -and $before.root_chars) { [int]$before.root_chars } else { 0 }
        $beforeSnapshot = if ($before -and $before.snapshot_chars) { [int]$before.snapshot_chars } else { 0 }
        $beforeDefaultStartup = $beforeRoot + $beforeSnapshot
        if ($beforeDefaultStartup -eq 0) {
            $beforeDefaultStartup = ($rootChars + [math]::Max($snapshotChars, 0))
        }
    }

    $afterDefaultStartup = $rootChars + $bootstrapChars + $ruleChars + $branchSnapshotChars
    $reduction = 0
    if ($beforeDefaultStartup -gt 0) {
        $reduction = [Math]::Round((1 - ($afterDefaultStartup / [double]$beforeDefaultStartup)) * 100, 2)
    }

    $result = [ordered]@{
        before = [ordered]@{
            root_chars = $rootChars
            root_lines = $rootLines
            default_startup_chars = $beforeDefaultStartup
        }
        after = [ordered]@{
            root_chars = $rootChars
            root_lines = $rootLines
            bootstrap_pass_chars = $bootstrapChars
            branch_rule_chars = $ruleChars
            default_startup_chars = $afterDefaultStartup
        }
        reduction_percent_by_chars = $reduction
        branch = $branch
        rule_file = $ruleFile
        snapshot_entry_chars = $branchSnapshotChars
        manifest_present = [bool]($manifest -and $manifest.files -and (Test-Path $bootstrapPath))
    }

    $resultJson = $result | ConvertTo-Json -Depth 8
    New-Item -ItemType Directory -Path (Split-Path $metricsAfterPath) -Force | Out-Null
    $resultJson | Set-Content $metricsAfterPath
    Write-Output $resultJson
} catch {
    Write-Error $_
    exit 1
}
