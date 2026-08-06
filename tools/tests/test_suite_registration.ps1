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
    'tests/canonical_snapshot_identity_production_test.tscn',
    'tests/taoist_profession_package_test.tscn'
)

$ProjectileSuite = 'projectile_spatial_critical'
$ProjectileExpected = @(
    'tests/projectile_broadphase_hit_parity_test.tscn',
    'tests/projectile_broadphase_no_false_negative_test.tscn',
    'tests/projectile_broadphase_candidate_reduction_test.tscn',
    'tests/projectile_broadphase_stable_order_test.tscn',
    'tests/projectile_broadphase_terrain_cutoff_test.tscn',
    'tests/projectile_broadphase_runtime_map_isolation_test.tscn',
    'tests/projectile_spatial_index_lifecycle_test.tscn',
    'tests/projectile_snapshot_single_build_per_step_test.tscn',
    'tests/projectile_spatial_index_same_frame_teleport_test.tscn',
    'tests/projectile_spatial_index_same_frame_knockback_test.tscn',
    'tests/projectile_spatial_index_query_before_enemy_tick_test.tscn',
    'tests/projectile_spatial_index_ready_contract_test.tscn'
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

$PersistentSuite = 'persistent_ground_effect_critical'
$PersistentExpected = @(
    'tests/persistent_ground_effect_hit_parity_test.tscn',
    'tests/persistent_ground_effect_no_false_negative_test.tscn',
    'tests/persistent_ground_effect_tick_cadence_test.tscn',
    'tests/persistent_ground_effect_stacking_claim_test.tscn',
    'tests/persistent_ground_effect_stable_order_test.tscn',
    'tests/persistent_ground_effect_runtime_map_isolation_test.tscn',
    'tests/persistent_ground_effect_lifecycle_test.tscn',
    'tests/persistent_ground_effect_candidate_reduction_test.tscn',
    'tests/persistent_ground_effect_no_group_scan_test.tscn',
    'tests/persistent_ground_effect_spatial_service_reuse_test.tscn'
)

$FireWallSuite = 'fire_wall_controller_critical'
$FireWallExpected = @(
    'tests/fire_wall_single_query_per_tick_test.tscn',
    'tests/fire_wall_single_exact_test_per_candidate_test.tscn',
    'tests/fire_wall_visual_cells_pure_test.tscn',
    'tests/fire_wall_hit_parity_test.tscn',
    'tests/fire_wall_tick_claim_parity_test.tscn',
    'tests/fire_wall_boundary_target_test.tscn',
    'tests/fire_wall_stacking_parity_test.tscn',
    'tests/fire_wall_runtime_map_isolation_test.tscn',
    'tests/fire_wall_visual_cell_lifecycle_test.tscn',
    'tests/fire_wall_candidate_reduction_test.tscn',
    'tests/fire_wall_no_group_scan_test.tscn',
    'tests/fire_wall_canonical_snapshot_identity_test.tscn'
)

$MonsterStreamingSuite = 'monster_streaming_critical'
$MonsterStreamingExpected = @(
    'tests/monster_streaming_single_poll_per_frame_test.tscn',
    'tests/monster_streaming_request_dedup_test.tscn',
    'tests/monster_streaming_visual_parity_test.tscn',
    'tests/monster_streaming_animation_continuity_test.tscn',
    'tests/monster_streaming_registration_lifecycle_test.tscn',
    'tests/monster_streaming_generation_guard_test.tscn',
    'tests/monster_streaming_failure_contract_test.tscn',
    'tests/monster_streaming_no_visual_queue_test.tscn',
    'tests/monster_streaming_no_sync_load_test.tscn',
    'tests/monster_streaming_spatial_index_non_regression_test.tscn',
    'tests/monster_streaming_scaling_test.tscn'
)

$SkillPlanSuite = 'skill_execution_plan_critical'
$SkillPlanExpected = @(
    'tests/skill_plan_contract_test.tscn',
    'tests/skill_plan_shadow_parity_test.tscn',
    'tests/skill_plan_no_side_effect_shadow_test.tscn',
    'tests/skill_plan_single_resource_commit_test.tscn',
    'tests/skill_plan_single_cooldown_commit_test.tscn',
    'tests/skill_plan_single_snapshot_build_test.tscn',
    'tests/skill_plan_immutable_consumer_test.tscn',
    'tests/skill_plan_rejection_reason_parity_test.tscn',
    'tests/caster_runtime_canonical_plan_adapter_test.tscn',
    'tests/skill_plan_profession_matrix_test.tscn'
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

# projectile_spatial_critical verification
$projMissing = @()
$projDuplicates = @()
$projGitTracked = @()
foreach ($path in $ProjectileExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $projMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $projGitTracked += $path
    }
}
$projDuplicates = @($ProjectileExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$projBlock = $false
$projFound = $false
$projEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.projectile_spatial_critical\s*=') {
        $projBlock = $true
        $projFound = $true
        continue
    }
    if ($projBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $projEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $projBlock = $false
            break
        }
    }
}
$projIncluded = ($RunnerSource -match '\$Suites\.projectile_spatial_critical\s*\+')
$projValidateSet = ($RunnerSource -match "projectile_spatial_critical")

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

# persistent_ground_effect_critical verification
$pgMissing = @()
$pgDuplicates = @()
$pgGitTracked = @()
foreach ($path in $PersistentExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $pgMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $pgGitTracked += $path
    }
}
$pgDuplicates = @($PersistentExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$pgBlock = $false
$pgFound = $false
$pgEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.persistent_ground_effect_critical\s*=') {
        $pgBlock = $true
        $pgFound = $true
        continue
    }
    if ($pgBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $pgEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $pgBlock = $false
            break
        }
    }
}
$pgIncluded = ($RunnerSource -match '\$Suites\.persistent_ground_effect_critical\s*\+')
$pgValidateSet = ($RunnerSource -match "persistent_ground_effect_critical")

# fire_wall_controller_critical verification
$fwMissing = @()
$fwDuplicates = @()
$fwGitTracked = @()
foreach ($path in $FireWallExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $fwMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $fwGitTracked += $path
    }
}
$fwDuplicates = @($FireWallExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$fwBlock = $false
$fwFound = $false
$fwEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.fire_wall_controller_critical\s*=') {
        $fwBlock = $true
        $fwFound = $true
        continue
    }
    if ($fwBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $fwEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $fwBlock = $false
            break
        }
    }
}
$fwIncluded = ($RunnerSource -match '\$Suites\.fire_wall_controller_critical\s*\+')
$fwValidateSet = ($RunnerSource -match "fire_wall_controller_critical")

# monster_streaming_critical verification
$msMissing = @()
$msDuplicates = @()
$msGitTracked = @()
foreach ($path in $MonsterStreamingExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $msMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $msGitTracked += $path
    }
}
$msDuplicates = @($MonsterStreamingExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$msBlock = $false
$msFound = $false
$msEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.monster_streaming_critical\s*=') {
        $msBlock = $true
        $msFound = $true
        continue
    }
    if ($msBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $msEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $msBlock = $false
            break
        }
    }
}
$msIncluded = ($RunnerSource -match '\$Suites\.monster_streaming_critical\s*\+')
$msValidateSet = ($RunnerSource -match "monster_streaming_critical")

# skill_execution_plan_critical verification
$spMissing = @()
$spDuplicates = @()
$spGitTracked = @()
foreach ($path in $SkillPlanExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $spMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $spGitTracked += $path
    }
}
$spDuplicates = @($SkillPlanExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$spBlock = $false
$spFound = $false
$spEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.skill_execution_plan_critical\s*=') {
        $spBlock = $true
        $spFound = $true
        continue
    }
    if ($spBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $spEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $spBlock = $false
            break
        }
    }
}
$spIncluded = ($RunnerSource -match '\$Suites\.skill_execution_plan_critical\s*\+')
$spValidateSet = ($RunnerSource -match "skill_execution_plan_critical")

$ok = $suiteFound -and ($suiteEntries.Count -eq $Expected.Count) -and ($missing.Count -eq 0) -and ($duplicates.Count -eq 0) -and ($gitTracked.Count -eq 0) -and $includedInDefaultCritical -and $validateSetHasSuite
$ok = $ok -and $prodFound -and ($prodEntries.Count -eq $ProductionExpected.Count) -and ($prodMissing.Count -eq 0) -and ($prodDuplicates.Count -eq 0) -and ($prodGitTracked.Count -eq 0) -and $prodIncluded -and $prodValidateSet
$ok = $ok -and $projFound -and ($projEntries.Count -eq $ProjectileExpected.Count) -and ($projMissing.Count -eq 0) -and ($projDuplicates.Count -eq 0) -and ($projGitTracked.Count -eq 0) -and $projIncluded -and $projValidateSet
$ok = $ok -and $slFound -and ($slEntries.Count -eq $SafeLogoutExpected.Count) -and ($slMissing.Count -eq 0) -and ($slDuplicates.Count -eq 0) -and ($slGitTracked.Count -eq 0) -and $slIncluded -and $slValidateSet
$ok = $ok -and $pgFound -and ($pgEntries.Count -eq $PersistentExpected.Count) -and ($pgMissing.Count -eq 0) -and ($pgDuplicates.Count -eq 0) -and ($pgGitTracked.Count -eq 0) -and $pgIncluded -and $pgValidateSet
$ok = $ok -and $fwFound -and ($fwEntries.Count -eq $FireWallExpected.Count) -and ($fwMissing.Count -eq 0) -and ($fwDuplicates.Count -eq 0) -and ($fwGitTracked.Count -eq 0) -and $fwIncluded -and $fwValidateSet
$ok = $ok -and $msFound -and ($msEntries.Count -eq $MonsterStreamingExpected.Count) -and ($msMissing.Count -eq 0) -and ($msDuplicates.Count -eq 0) -and ($msGitTracked.Count -eq 0) -and $msIncluded -and $msValidateSet
$ok = $ok -and $spFound -and ($spEntries.Count -eq $SkillPlanExpected.Count) -and ($spMissing.Count -eq 0) -and ($spDuplicates.Count -eq 0) -and ($spGitTracked.Count -eq 0) -and $spIncluded -and $spValidateSet
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
    projectile_spatial_suite = $ProjectileSuite
    projectile_spatial_expected_count = $ProjectileExpected.Count
    projectile_spatial_actual_count = $projEntries.Count
    projectile_spatial_missing = $projMissing
    projectile_spatial_duplicates = $projDuplicates
    projectile_spatial_not_git_tracked = $projGitTracked
    projectile_spatial_included_in_default_critical = $projIncluded
    projectile_spatial_validate_set = $projValidateSet
    persistent_ground_effect_suite = $PersistentSuite
    persistent_ground_effect_expected_count = $PersistentExpected.Count
    persistent_ground_effect_actual_count = $pgEntries.Count
    persistent_ground_effect_missing = $pgMissing
    persistent_ground_effect_duplicates = $pgDuplicates
    persistent_ground_effect_not_git_tracked = $pgGitTracked
    persistent_ground_effect_included_in_default_critical = $pgIncluded
    persistent_ground_effect_validate_set = $pgValidateSet
    fire_wall_controller_suite = $FireWallSuite
    fire_wall_controller_expected_count = $FireWallExpected.Count
    fire_wall_controller_actual_count = $fwEntries.Count
    fire_wall_controller_missing = $fwMissing
    fire_wall_controller_duplicates = $fwDuplicates
    fire_wall_controller_not_git_tracked = $fwGitTracked
    fire_wall_controller_included_in_default_critical = $fwIncluded
    fire_wall_controller_validate_set = $fwValidateSet
    monster_streaming_suite = $MonsterStreamingSuite
    monster_streaming_expected_count = $MonsterStreamingExpected.Count
    monster_streaming_actual_count = $msEntries.Count
    monster_streaming_missing = $msMissing
    monster_streaming_duplicates = $msDuplicates
    monster_streaming_not_git_tracked = $msGitTracked
    monster_streaming_included_in_default_critical = $msIncluded
    monster_streaming_validate_set = $msValidateSet
    skill_execution_plan_suite = $SkillPlanSuite
    skill_execution_plan_expected_count = $SkillPlanExpected.Count
    skill_execution_plan_actual_count = $spEntries.Count
    skill_execution_plan_missing = $spMissing
    skill_execution_plan_duplicates = $spDuplicates
    skill_execution_plan_not_git_tracked = $spGitTracked
    skill_execution_plan_included_in_default_critical = $spIncluded
    skill_execution_plan_validate_set = $spValidateSet
    result = $result
}
$report | ConvertTo-Json -Depth 4
if ($result -eq 'FAIL') {
    Write-Host "SUITE_REGISTRATION_CHECK_FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "SUITE_REGISTRATION_CHECK_PASS" -ForegroundColor Green
exit 0
