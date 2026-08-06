$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$RunnerPath = Join-Path $ProjectRoot 'tools\run_godot_tests.ps1'
$RunnerSource = Get-Content -LiteralPath $RunnerPath -Raw -Encoding UTF8

$Suite = 'snapshot_coordinate_critical'
$Expected = @(
    'tests/skill_footprint_snapshot_coordinate_contract_test.tscn',
    'tests/skill_footprint_snapshot_map_identity_test.tscn',
    'tests/skill_footprint_snapshot_projection_origin_test.tscn',
    'tests/skill_footprint_snapshot_legacy_upgrade_test.tscn',
    'tests/canonical_snapshot_propagation_test.tscn'
)

$missing = @()
$duplicates = @()
$gitTracked = @()
foreach ($path in $Expected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $missing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $gitTracked += $path
    }
}
$duplicates = @($Expected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })

$suiteBlock = $false
$suiteFound = $false
$suiteEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.snapshot_coordinate_critical\s*=') {
        $suiteBlock = $true
        $suiteFound = $true
        continue
    }
    if ($suiteBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $suiteEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $suiteBlock = $false
            break
        }
    }
}
$includedInDefaultCritical = ($RunnerSource -match '\$Suites\.snapshot_coordinate_critical\s*\+\s*\$Suites\.warrior')
if (-not $includedInDefaultCritical) {
    $includedInDefaultCritical = ($RunnerSource -match 'snapshot_coordinate_critical\s*\+' -and $RunnerSource -match '\$Suites\.critical')
}
$validateSetHasSuite = ($RunnerSource -match "snapshot_coordinate_critical")

$ok = $suiteFound -and ($suiteEntries.Count -eq $Expected.Count) -and ($missing.Count -eq 0) -and ($duplicates.Count -eq 0) -and ($gitTracked.Count -eq 0) -and $includedInDefaultCritical -and $validateSetHasSuite
$result = 'PASS'
if (-not $ok) {
    $result = 'FAIL'
}

$report = [ordered]@{
    suite = $Suite
    expected_count = $Expected.Count
    actual_count = $suiteEntries.Count
    missing = $missing
    duplicates = $duplicates
    not_git_tracked = $gitTracked
    included_in_default_critical = $includedInDefaultCritical
    validate_set_has_suite = $validateSetHasSuite
    result = $result
}
$report | ConvertTo-Json -Depth 4
if ($result -eq 'FAIL') {
    Write-Host "SUITE_REGISTRATION_CHECK_FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "SUITE_REGISTRATION_CHECK_PASS" -ForegroundColor Green
exit 0
