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
    'tests/canonical_snapshot_propagation_test.tscn',
    'tests/snapshot_strict_consumer_rejection_test.tscn',
    'tests/snapshot_v2_no_legacy_fallback_test.tscn',
    'tests/snapshot_absolute_converter_failure_test.tscn',
    'tests/snapshot_non_finite_coordinate_test.tscn',
    'tests/snapshot_legacy_explicit_policy_test.tscn',
    'tests/snapshot_consumer_runtime_map_guard_test.tscn',
    'tests/warrior_snapshot_v2_production_test.tscn',
    'tests/enemy_snapshot_v2_production_test.tscn',
    'tests/summon_snapshot_v2_production_test.tscn',
    'tests/projectile_snapshot_v2_production_test.tscn',
    'tests/ground_effect_snapshot_v2_production_test.tscn',
    'tests/fire_wall_snapshot_v2_production_test.tscn',
    'tests/production_snapshot_no_legacy_test.tscn',
    'tests/canonical_snapshot_identity_production_test.tscn'
)

$ProductionSuite = 'snapshot_production_critical'
$ProductionExpected = @(
    'tests/warrior_snapshot_v2_production_test.tscn',
    'tests/enemy_snapshot_v2_production_test.tscn',
    'tests/summon_snapshot_v2_production_test.tscn',
    'tests/projectile_snapshot_v2_production_test.tscn',
    'tests/ground_effect_snapshot_v2_production_test.tscn',
    'tests/fire_wall_snapshot_v2_production_test.tscn',
    'tests/production_snapshot_no_legacy_test.tscn',
    'tests/canonical_snapshot_identity_production_test.tscn'
)

$SafeLogoutSuite = 'safe_logout_critical'
$SafeLogoutExpected = @(
    'tests/safe_logout_home_resolution_failure_test.tscn',
    'tests/safe_logout_character_select_guard_test.tscn',
    'tests/safe_logout_exit_guard_test.tscn',
    'tests/safe_logout_save_failure_test.tscn',
    'tests/safe_logout_existing_state_preservation_test.tscn',
    'tests/home_resolution_side_effect_guard_test.tscn',
    'tests/service_home_no_current_position_fallback_test.tscn',
    'tests/death_revival_home_failure_test.tscn',
    'tests/map_transition_missing_arrival_test.tscn',
    'tests/portal_home_lookup_failure_test.tscn'
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

# snapshot_production_critical verification
$prodMissing = @()
$prodDuplicates = @()
$prodGitTracked = @()
foreach ($path in $ProductionExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $prodMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $prodGitTracked += $path
    }
}
$prodDuplicates = @($ProductionExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$prodBlock = $false
$prodFound = $false
$prodEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.snapshot_production_critical\s*=') {
        $prodBlock = $true
        $prodFound = $true
        continue
    }
    if ($prodBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $prodEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $prodBlock = $false
            break
        }
    }
}
$prodIncluded = ($RunnerSource -match '\$Suites\.snapshot_production_critical\s*\+')
$prodValidateSet = ($RunnerSource -match "snapshot_production_critical")

# safe_logout_critical verification
$slMissing = @()
$slDuplicates = @()
$slGitTracked = @()
foreach ($path in $SafeLogoutExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $slMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $slGitTracked += $path
    }
}
$slDuplicates = @($SafeLogoutExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$slBlock = $false
$slFound = $false
$slEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.safe_logout_critical\s*=') {
        $slBlock = $true
        $slFound = $true
        continue
    }
    if ($slBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $slEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $slBlock = $false
            break
        }
    }
}
$slIncluded = ($RunnerSource -match '\$Suites\.safe_logout_critical\s*\+')
$slValidateSet = ($RunnerSource -match "safe_logout_critical")

$ok = $suiteFound -and ($suiteEntries.Count -eq $Expected.Count) -and ($missing.Count -eq 0) -and ($duplicates.Count -eq 0) -and ($gitTracked.Count -eq 0) -and $includedInDefaultCritical -and $validateSetHasSuite
$ok = $ok -and $prodFound -and ($prodEntries.Count -eq $ProductionExpected.Count) -and ($prodMissing.Count -eq 0) -and ($prodDuplicates.Count -eq 0) -and ($prodGitTracked.Count -eq 0) -and $prodIncluded -and $prodValidateSet
$ok = $ok -and $slFound -and ($slEntries.Count -eq $SafeLogoutExpected.Count) -and ($slMissing.Count -eq 0) -and ($slDuplicates.Count -eq 0) -and ($slGitTracked.Count -eq 0) -and $slIncluded -and $slValidateSet
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
    safe_logout_suite = $SafeLogoutSuite
    safe_logout_expected_count = $SafeLogoutExpected.Count
    safe_logout_actual_count = $slEntries.Count
    safe_logout_missing = $slMissing
    safe_logout_duplicates = $slDuplicates
    safe_logout_not_git_tracked = $slGitTracked
    safe_logout_included_in_default_critical = $slIncluded
    safe_logout_validate_set = $slValidateSet
    snapshot_production_suite = $ProductionSuite
    snapshot_production_expected_count = $ProductionExpected.Count
    snapshot_production_actual_count = $prodEntries.Count
    snapshot_production_missing = $prodMissing
    snapshot_production_duplicates = $prodDuplicates
    snapshot_production_not_git_tracked = $prodGitTracked
    snapshot_production_included_in_default_critical = $prodIncluded
    snapshot_production_validate_set = $prodValidateSet
    result = $result
}
$report | ConvertTo-Json -Depth 4
if ($result -eq 'FAIL') {
    Write-Host "SUITE_REGISTRATION_CHECK_FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "SUITE_REGISTRATION_CHECK_PASS" -ForegroundColor Green
exit 0
