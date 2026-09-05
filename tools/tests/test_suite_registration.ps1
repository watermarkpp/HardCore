$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$RunnerPath = Join-Path $ProjectRoot 'tools\run_godot_tests.ps1'
$RunnerSource = Get-Content -LiteralPath $RunnerPath -Raw -Encoding UTF8

function Test-StringSetEqual([string[]]$ExpectedValues, [string[]]$ActualValues) {
    $expectedSet = @($ExpectedValues | Sort-Object -Unique)
    $actualSet = @($ActualValues | Sort-Object -Unique)
    return @(
        Compare-Object -ReferenceObject $expectedSet -DifferenceObject $actualSet
    ).Count -eq 0
}

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
    'tests/safe_logout_atomic_recovery_test.tscn',
    'tests/safe_logout_home_resolution_failure_test.tscn',
    'tests/safe_logout_character_select_guard_test.tscn',
    'tests/safe_logout_exit_guard_test.tscn',
    'tests/safe_logout_save_failure_test.tscn',
    'tests/safe_logout_existing_state_preservation_test.tscn',
    'tests/home_resolution_side_effect_guard_test.tscn',
    'tests/service_home_no_current_position_fallback_test.tscn',
    'tests/death_revival_home_failure_test.tscn',
    'tests/death_revival_touch_input_test.tscn',
    'tests/character_select_launch_loading_test.tscn',
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
    'tests/skill_plan_golden_parity_test.tscn',
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
# Monster Streaming is intentionally excluded from default critical while
# PROJECT_CURRENT_STATUS marks it HOLD. The direct suite remains registered.
$msIncluded = ($RunnerSource -match '\$Suites\.monster_streaming_critical\s*\+')
$msExcludedFromDefaultCritical = -not $msIncluded
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

# skill_production_migration_critical verification (Q3-B)
$ProductionMigrationSuite = 'skill_production_migration_critical'
$ProductionMigrationExpected = @(
    'tests/skill_production_canonical_entry_test.tscn',
    'tests/skill_production_no_visual_plan_test.tscn',
    'tests/skill_production_no_legacy_planner_test.tscn',
    'tests/skill_production_single_release_id_test.tscn',
    'tests/skill_production_single_snapshot_test.tscn',
    'tests/skill_production_single_commit_test.tscn',
    'tests/skill_execution_result_contract_test.tscn',
    'tests/skill_production_plan_immutable_test.tscn',
    'tests/skill_production_profession_matrix_test.tscn',
    'tests/skill_production_rejection_flow_test.tscn',
    'tests/skill_production_descriptor_failure_parity_test.tscn'
)

$pmMissing = @()
$pmDuplicates = @()
$pmGitTracked = @()
foreach ($path in $ProductionMigrationExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $pmMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $pmGitTracked += $path
    }
}
$pmDuplicates = @($ProductionMigrationExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$pmBlock = $false
$pmFound = $false
$pmEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.skill_production_migration_critical\s*=') {
        $pmBlock = $true
        $pmFound = $true
        continue
    }
    if ($pmBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $pmEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $pmBlock = $false
            break
        }
    }
}
$pmIncluded = ($RunnerSource -match '\$Suites\.skill_production_migration_critical\s*\+')
$pmValidateSet = ($RunnerSource -match "skill_production_migration_critical")

# skill_runtime_cleanup_critical verification (Q3-C)
$CleanupSuite = 'skill_runtime_cleanup_critical'
$CleanupExpected = @(
    'tests/skill_runtime_no_legacy_api_test.tscn',
    'tests/skill_runtime_single_public_entry_test.tscn',
    'tests/skill_plan_golden_contract_test.tscn',
    'tests/skill_runtime_no_visual_plan_test.tscn',
    'tests/skill_runtime_single_result_contract_test.tscn',
    'tests/skill_runtime_mapped_world_strict_snapshot_test.tscn'
)

$clMissing = @()
$clDuplicates = @()
$clGitTracked = @()
foreach ($path in $CleanupExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $clMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $clGitTracked += $path
    }
}
$clDuplicates = @($CleanupExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$clBlock = $false
$clFound = $false
$clEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.skill_runtime_cleanup_critical\s*=') {
        $clBlock = $true
        $clFound = $true
        continue
    }
    if ($clBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $clEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $clBlock = $false
            break
        }
    }
}
$clIncluded = ($RunnerSource -match '\$Suites\.skill_runtime_cleanup_critical\s*\+')
$clValidateSet = ($RunnerSource -match "skill_runtime_cleanup_critical")

# wizard_line_geometry_critical verification (FREEZE-G0)
$WizardLineSuite = 'wizard_line_geometry_critical'
$WizardLineExpected = @(
    'tests/wizard_line_footprint_core_test.tscn',
    'tests/wizard_line_visual_stability_test.tscn',
    'tests/wizard_line_presentation_alignment_test.tscn'
)

$wlMissing = @()
$wlDuplicates = @()
$wlGitTracked = @()
foreach ($path in $WizardLineExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $wlMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $wlGitTracked += $path
    }
}
$wlDuplicates = @($WizardLineExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$wlBlock = $false
$wlFound = $false
$wlEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.wizard_line_geometry_critical\s*=') {
        $wlBlock = $true
        $wlFound = $true
        continue
    }
    if ($wlBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $wlEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $wlBlock = $false
            break
        }
    }
}
$wlIncluded = ($RunnerSource -match '\$Suites\.wizard_line_geometry_critical\s*\+')
$wlValidateSet = ($RunnerSource -match "wizard_line_geometry_critical")

# combat_absolute_ground_critical verification (FREEZE-P0)
$CombatSuite = 'combat_absolute_ground_critical'
$CombatExpected = @(
    'tests/combat_absolute_ground_roundtrip_test.tscn',
    'tests/enemy_spatial_index_absolute_coordinate_test.tscn',
    'tests/projectile_absolute_release_snapshot_test.tscn',
    'tests/summon_absolute_snapshot_test.tscn',
    'tests/persistent_ground_effect_absolute_broadphase_test.tscn',
    'tests/fire_wall_absolute_broadphase_test.tscn',
    'tests/shared_spatial_index_absolute_contract_test.tscn',
    'tests/combat_absolute_ground_integration_test.tscn',
    'tests/combat_absolute_ground_parity_test.tscn'
)

$cbMissing = @()
$cbDuplicates = @()
$cbGitTracked = @()
foreach ($path in $CombatExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $cbMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $cbGitTracked += $path
    }
}
$cbDuplicates = @($CombatExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$cbBlock = $false
$cbFound = $false
$cbEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.combat_absolute_ground_critical\s*=') {
        $cbBlock = $true
        $cbFound = $true
        continue
    }
    if ($cbBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $cbEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $cbBlock = $false
            break
        }
    }
}
$cbIncluded = ($RunnerSource -match '\$Suites\.combat_absolute_ground_critical\s*\+')
$cbValidateSet = ($RunnerSource -match "combat_absolute_ground_critical")

# combat_projection_fail_closed_critical verification (FREEZE-P0.1)
$FailClosedSuite = 'combat_projection_fail_closed_critical'
$FailClosedExpected = @(
    'tests/mapped_enemy_missing_projection_rejected_test.tscn',
    'tests/mapped_projectile_missing_projection_rejected_test.tscn',
    'tests/mapped_summon_missing_projection_rejected_test.tscn',
    'tests/mapped_fire_wall_missing_projection_rejected_test.tscn',
    'tests/mapped_skill_plan_missing_projection_rejected_test.tscn',
    'tests/mapped_game_root_projection_failure_test.tscn'
)

$fcMissing = @()
$fcDuplicates = @()
$fcGitTracked = @()
foreach ($path in $FailClosedExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $fcMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $fcGitTracked += $path
    }
}
$fcDuplicates = @($FailClosedExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$fcBlock = $false
$fcFound = $false
$fcEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.combat_projection_fail_closed_critical\s*=') {
        $fcBlock = $true
        $fcFound = $true
        continue
    }
    if ($fcBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $fcEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $fcBlock = $false
            break
        }
    }
}
$fcIncluded = ($RunnerSource -match '\$Suites\.combat_projection_fail_closed_critical\s*\+')
$fcValidateSet = ($RunnerSource -match "combat_projection_fail_closed_critical")

# formal_map_projection_critical verification (FREEZE-P0.2)
$ProfileSuite = 'formal_map_projection_critical'
$ProfileExpected = @(
    'tests/implemented_map_runtime_projection_test.tscn',
    'tests/phase1_network_runtime_coverage_test.tscn',
    'tests/unbuilt_planned_map_not_playable_test.tscn',
    'tests/reference_map_not_playable_test.tscn',
    'tests/legacy_reference_projection_isolation_test.tscn',
    'tests/formal_map_projection_coverage_test.tscn',
    'tests/world_ready_gating_test.tscn',
    'tests/safe_logout_world_location_inf_guard_test.tscn'
)

$pfMissing = @()
$pfDuplicates = @()
$pfGitTracked = @()
foreach ($path in $ProfileExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $pfMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $pfGitTracked += $path
    }
}
$pfDuplicates = @($ProfileExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$pfBlock = $false
$pfFound = $false
$pfEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.formal_map_projection_critical\s*=') {
        $pfBlock = $true
        $pfFound = $true
        continue
    }
    if ($pfBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $pfEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $pfBlock = $false
            break
        }
    }
}
$pfIncluded = ($RunnerSource -match '\$Suites\.formal_map_projection_critical\s*\+')
$pfValidateSet = ($RunnerSource -match "formal_map_projection_critical")

# map_runtime_release_critical verification (FREEZE-P0.3)
$ReleaseSuite = 'map_runtime_release_critical'
$ReleaseExpected = @(
    'tests/map_runtime_release_registry_contract_test.tscn',
    'tests/map_ui_presentation_projection_test.tscn',
    'tests/map_persistent_boss_spawn_identity_test.tscn',
    'tests/release_registry_current_maps_test.tscn',
    'tests/map_runtime_release_gate_test.tscn'
)

$rlMissing = @()
$rlDuplicates = @()
$rlGitTracked = @()
foreach ($path in $ReleaseExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $rlMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $rlGitTracked += $path
    }
}
$rlDuplicates = @($ReleaseExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$rlBlock = $false
$rlFound = $false
$rlEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.map_runtime_release_critical\s*=') {
        $rlBlock = $true
        $rlFound = $true
        continue
    }
    if ($rlBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $rlEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $rlBlock = $false
            break
        }
    }
}
$rlIncluded = ($RunnerSource -match '\$Suites\.map_runtime_release_critical\s*\+')
$rlValidateSet = ($RunnerSource -match "map_runtime_release_critical")

# map_runtime_release_transaction_critical verification (FREEZE-P0.3R)
$TransactionSuite = 'map_runtime_release_transaction_critical'
$TransactionExpected = @(
    'tests/build_candidate_does_not_mutate_release_test.tscn',
    'tests/publish_promotes_candidate_test.tscn',
    'tests/publish_failure_rollback_test.tscn',
    'tests/release_registry_consumer_validation_test.tscn',
    'tests/future_map_build_publish_no_code_edit_test.tscn',
    'tests/mse_publish_entry_wired_test.tscn'
)

$rtMissing = @()
$rtDuplicates = @()
$rtGitTracked = @()
foreach ($path in $TransactionExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $rtMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $rtGitTracked += $path
    }
}
$rtDuplicates = @($TransactionExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$rtBlock = $false
$rtFound = $false
$rtEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.map_runtime_release_transaction_critical\s*=') {
        $rtBlock = $true
        $rtFound = $true
        continue
    }
    if ($rtBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $rtEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $rtBlock = $false
            break
        }
    }
}
$rtIncluded = ($RunnerSource -match '\$Suites\.map_runtime_release_transaction_critical\s*\+')
$rtValidateSet = ($RunnerSource -match "map_runtime_release_transaction_critical")

# player_visual_contract_critical verification (FREEZE-G0.2-A.1)
$PlayerVisualSuite = 'player_visual_contract_critical'
$PlayerVisualExpected = @(
    'tests/passive_proc_actor_plane_contract_test.tscn'
)

$pvMissing = @()
$pvDuplicates = @()
$pvGitTracked = @()
foreach ($path in $PlayerVisualExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $pvMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $pvGitTracked += $path
    }
}
$pvDuplicates = @($PlayerVisualExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$pvBlock = $false
$pvFound = $false
$pvEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.player_visual_contract_critical\s*=') {
        $pvBlock = $true
        $pvFound = $true
        continue
    }
    if ($pvBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $pvEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $pvBlock = $false
            break
        }
    }
}
$pvIncluded = ($RunnerSource -match '\$Suites\.player_visual_contract_critical\s*\+')
$pvValidateSet = ($RunnerSource -match "player_visual_contract_critical")

# skill_panel_layout_critical verification (FREEZE-G0.2-B)
$SkillPanelSuite = 'skill_panel_layout_critical'
$SkillPanelExpected = @(
    'tests/skill_panel_assignment_hint_layout_contract_test.tscn'
)

$slpMissing = @()
$slpDuplicates = @()
$slpGitTracked = @()
foreach ($path in $SkillPanelExpected) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($path -replace '/', '\')))) {
        $slpMissing += $path
    }
    $tracked = (& git ls-files -- $path 2>$null | Out-String).Trim()
    if ($tracked -ne $path) {
        $slpGitTracked += $path
    }
}
$slpDuplicates = @($SkillPanelExpected | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
$slpBlock = $false
$slpFound = $false
$slpEntries = @()
foreach ($line in ($RunnerSource -split "`r?`n")) {
    if ($line -match '^\$Suites\.skill_panel_layout_critical\s*=') {
        $slpBlock = $true
        $slpFound = $true
        continue
    }
    if ($slpBlock) {
        if ($line -match "^\s*'([^']+\.tscn)'") {
            $slpEntries += $Matches[1]
        } elseif ($line -match '^\s*\)') {
            $slpBlock = $false
            break
        }
    }
}
$slpIncluded = ($RunnerSource -match '\$Suites\.skill_panel_layout_critical\s*\+')
$slpValidateSet = ($RunnerSource -match "skill_panel_layout_critical")

$ok = $suiteFound -and (Test-StringSetEqual $Expected $suiteEntries) -and ($missing.Count -eq 0) -and ($duplicates.Count -eq 0) -and ($gitTracked.Count -eq 0) -and $includedInDefaultCritical -and $validateSetHasSuite
$ok = $ok -and $prodFound -and (Test-StringSetEqual $ProductionExpected $prodEntries) -and ($prodMissing.Count -eq 0) -and ($prodDuplicates.Count -eq 0) -and ($prodGitTracked.Count -eq 0) -and $prodIncluded -and $prodValidateSet
$ok = $ok -and $projFound -and (Test-StringSetEqual $ProjectileExpected $projEntries) -and ($projMissing.Count -eq 0) -and ($projDuplicates.Count -eq 0) -and ($projGitTracked.Count -eq 0) -and $projIncluded -and $projValidateSet
$ok = $ok -and $slFound -and (Test-StringSetEqual $SafeLogoutExpected $slEntries) -and ($slMissing.Count -eq 0) -and ($slDuplicates.Count -eq 0) -and ($slGitTracked.Count -eq 0) -and $slIncluded -and $slValidateSet
$ok = $ok -and $pgFound -and (Test-StringSetEqual $PersistentExpected $pgEntries) -and ($pgMissing.Count -eq 0) -and ($pgDuplicates.Count -eq 0) -and ($pgGitTracked.Count -eq 0) -and $pgIncluded -and $pgValidateSet
$ok = $ok -and $fwFound -and (Test-StringSetEqual $FireWallExpected $fwEntries) -and ($fwMissing.Count -eq 0) -and ($fwDuplicates.Count -eq 0) -and ($fwGitTracked.Count -eq 0) -and $fwIncluded -and $fwValidateSet
$ok = $ok -and $msFound -and (Test-StringSetEqual $MonsterStreamingExpected $msEntries) -and ($msMissing.Count -eq 0) -and ($msDuplicates.Count -eq 0) -and ($msGitTracked.Count -eq 0) -and $msExcludedFromDefaultCritical -and $msValidateSet
$ok = $ok -and $spFound -and (Test-StringSetEqual $SkillPlanExpected $spEntries) -and ($spMissing.Count -eq 0) -and ($spDuplicates.Count -eq 0) -and ($spGitTracked.Count -eq 0) -and $spIncluded -and $spValidateSet
$ok = $ok -and $pmFound -and (Test-StringSetEqual $ProductionMigrationExpected $pmEntries) -and ($pmMissing.Count -eq 0) -and ($pmDuplicates.Count -eq 0) -and ($pmGitTracked.Count -eq 0) -and $pmIncluded -and $pmValidateSet
$ok = $ok -and $clFound -and (Test-StringSetEqual $CleanupExpected $clEntries) -and ($clMissing.Count -eq 0) -and ($clDuplicates.Count -eq 0) -and ($clGitTracked.Count -eq 0) -and $clIncluded -and $clValidateSet
$ok = $ok -and $wlFound -and (Test-StringSetEqual $WizardLineExpected $wlEntries) -and ($wlMissing.Count -eq 0) -and ($wlDuplicates.Count -eq 0) -and ($wlGitTracked.Count -eq 0) -and $wlIncluded -and $wlValidateSet
$ok = $ok -and $cbFound -and (Test-StringSetEqual $CombatExpected $cbEntries) -and ($cbMissing.Count -eq 0) -and ($cbDuplicates.Count -eq 0) -and ($cbGitTracked.Count -eq 0) -and $cbIncluded -and $cbValidateSet
$ok = $ok -and $fcFound -and (Test-StringSetEqual $FailClosedExpected $fcEntries) -and ($fcMissing.Count -eq 0) -and ($fcDuplicates.Count -eq 0) -and ($fcGitTracked.Count -eq 0) -and $fcIncluded -and $fcValidateSet
$ok = $ok -and $pfFound -and (Test-StringSetEqual $ProfileExpected $pfEntries) -and ($pfMissing.Count -eq 0) -and ($pfDuplicates.Count -eq 0) -and ($pfGitTracked.Count -eq 0) -and $pfIncluded -and $pfValidateSet
$ok = $ok -and $rlFound -and (Test-StringSetEqual $ReleaseExpected $rlEntries) -and ($rlMissing.Count -eq 0) -and ($rlDuplicates.Count -eq 0) -and ($rlGitTracked.Count -eq 0) -and $rlIncluded -and $rlValidateSet
$ok = $ok -and $rtFound -and (Test-StringSetEqual $TransactionExpected $rtEntries) -and ($rtMissing.Count -eq 0) -and ($rtDuplicates.Count -eq 0) -and ($rtGitTracked.Count -eq 0) -and $rtIncluded -and $rtValidateSet
$ok = $ok -and $pvFound -and (Test-StringSetEqual $PlayerVisualExpected $pvEntries) -and ($pvMissing.Count -eq 0) -and ($pvDuplicates.Count -eq 0) -and ($pvGitTracked.Count -eq 0) -and $pvIncluded -and $pvValidateSet
$ok = $ok -and $slpFound -and (Test-StringSetEqual $SkillPanelExpected $slpEntries) -and ($slpMissing.Count -eq 0) -and ($slpDuplicates.Count -eq 0) -and ($slpGitTracked.Count -eq 0) -and $slpIncluded -and $slpValidateSet
$auditExpected = @(
    'tests/profile_business_validation_recovery_test.tscn',
    'tests/persistence_business_transactions_test.tscn',
    'tests/shared_warehouse_transaction_test.tscn',
    'tests/shared_warehouse_migration_test.tscn',
    'tests/map_editor_workspace_delete_safety_test.tscn',
    'tests/startup_loading_failure_recovery_test.tscn',
    'tests/brand_intro_test.tscn',
    'tests/device_lab_patch_bootstrap_test.tscn',
    'tests/lootclock/loot_retry_clock_test.tscn',
    'tests/lootclock/loot_visual_clock_test.tscn',
    'tests/runtime_loot_spatial_index_order_test.tscn'
)
$auditBlock = [regex]::Match($RunnerSource, '(?ms)^\$Suites\.audit_upgrade_critical\s*=\s*@\((.*?)^\)')
$auditEntries = @([regex]::Matches($auditBlock.Groups[1].Value, "'([^']+\.tscn)'") | ForEach-Object { $_.Groups[1].Value })
$auditMissing = @($auditExpected | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $ProjectRoot $_)) -or
    ((& git -C $ProjectRoot ls-files -- $_ | Out-String).Trim() -ne $_)
})
$auditOk = $auditBlock.Success -and
    (Test-StringSetEqual $auditExpected $auditEntries) -and
    $auditEntries.Count -eq $auditExpected.Count -and
    $auditMissing.Count -eq 0 -and
    $RunnerSource.Contains("'audit_upgrade_critical'") -and
    ($RunnerSource -match '\$Suites\.audit_upgrade_critical\s*\+')
$ok = $ok -and $auditOk

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
    monster_streaming_excluded_from_default_critical_while_hold = $msExcludedFromDefaultCritical
    monster_streaming_validate_set = $msValidateSet
    skill_execution_plan_suite = $SkillPlanSuite
    skill_execution_plan_expected_count = $SkillPlanExpected.Count
    skill_execution_plan_actual_count = $spEntries.Count
    skill_execution_plan_missing = $spMissing
    skill_execution_plan_duplicates = $spDuplicates
    skill_execution_plan_not_git_tracked = $spGitTracked
    skill_execution_plan_included_in_default_critical = $spIncluded
    skill_execution_plan_validate_set = $spValidateSet
    skill_production_migration_suite = $ProductionMigrationSuite
    skill_production_migration_expected_count = $ProductionMigrationExpected.Count
    skill_production_migration_actual_count = $pmEntries.Count
    skill_production_migration_missing = $pmMissing
    skill_production_migration_duplicates = $pmDuplicates
    skill_production_migration_not_git_tracked = $pmGitTracked
    skill_production_migration_included_in_default_critical = $pmIncluded
    skill_production_migration_validate_set = $pmValidateSet
    skill_runtime_cleanup_suite = $CleanupSuite
    skill_runtime_cleanup_expected_count = $CleanupExpected.Count
    skill_runtime_cleanup_actual_count = $clEntries.Count
    skill_runtime_cleanup_missing = $clMissing
    skill_runtime_cleanup_duplicates = $clDuplicates
    skill_runtime_cleanup_not_git_tracked = $clGitTracked
    skill_runtime_cleanup_included_in_default_critical = $clIncluded
    skill_runtime_cleanup_validate_set = $clValidateSet
    wizard_line_geometry_suite = $WizardLineSuite
    wizard_line_geometry_expected_count = $WizardLineExpected.Count
    wizard_line_geometry_actual_count = $wlEntries.Count
    wizard_line_geometry_missing = $wlMissing
    wizard_line_geometry_duplicates = $wlDuplicates
    wizard_line_geometry_not_git_tracked = $wlGitTracked
    wizard_line_geometry_included_in_default_critical = $wlIncluded
    wizard_line_geometry_validate_set = $wlValidateSet
    combat_absolute_ground_suite = $CombatSuite
    combat_absolute_ground_expected_count = $CombatExpected.Count
    combat_absolute_ground_actual_count = $cbEntries.Count
    combat_absolute_ground_missing = $cbMissing
    combat_absolute_ground_duplicates = $cbDuplicates
    combat_absolute_ground_not_git_tracked = $cbGitTracked
    combat_absolute_ground_included_in_default_critical = $cbIncluded
    combat_absolute_ground_validate_set = $cbValidateSet
    combat_projection_fail_closed_suite = $FailClosedSuite
    combat_projection_fail_closed_expected_count = $FailClosedExpected.Count
    combat_projection_fail_closed_actual_count = $fcEntries.Count
    combat_projection_fail_closed_missing = $fcMissing
    combat_projection_fail_closed_duplicates = $fcDuplicates
    combat_projection_fail_closed_not_git_tracked = $fcGitTracked
    combat_projection_fail_closed_included_in_default_critical = $fcIncluded
    combat_projection_fail_closed_validate_set = $fcValidateSet
    formal_map_projection_suite = $ProfileSuite
    formal_map_projection_expected_count = $ProfileExpected.Count
    formal_map_projection_actual_count = $pfEntries.Count
    formal_map_projection_missing = $pfMissing
    formal_map_projection_duplicates = $pfDuplicates
    formal_map_projection_not_git_tracked = $pfGitTracked
    formal_map_projection_included_in_default_critical = $pfIncluded
    formal_map_projection_validate_set = $pfValidateSet
    map_runtime_release_suite = $ReleaseSuite
    map_runtime_release_expected_count = $ReleaseExpected.Count
    map_runtime_release_actual_count = $rlEntries.Count
    map_runtime_release_missing = $rlMissing
    map_runtime_release_duplicates = $rlDuplicates
    map_runtime_release_not_git_tracked = $rlGitTracked
    map_runtime_release_included_in_default_critical = $rlIncluded
    map_runtime_release_validate_set = $rlValidateSet
    map_runtime_release_transaction_suite = $TransactionSuite
    map_runtime_release_transaction_expected_count = $TransactionExpected.Count
    map_runtime_release_transaction_actual_count = $rtEntries.Count
    map_runtime_release_transaction_missing = $rtMissing
    map_runtime_release_transaction_duplicates = $rtDuplicates
    map_runtime_release_transaction_not_git_tracked = $rtGitTracked
    map_runtime_release_transaction_included_in_default_critical = $rtIncluded
    map_runtime_release_transaction_validate_set = $rtValidateSet
    player_visual_contract_suite = $PlayerVisualSuite
    player_visual_contract_expected_count = $PlayerVisualExpected.Count
    player_visual_contract_actual_count = $pvEntries.Count
    player_visual_contract_missing = $pvMissing
    player_visual_contract_duplicates = $pvDuplicates
    player_visual_contract_not_git_tracked = $pvGitTracked
    player_visual_contract_included_in_default_critical = $pvIncluded
    player_visual_contract_validate_set = $pvValidateSet
    skill_panel_layout_suite = $SkillPanelSuite
    skill_panel_layout_expected_count = $SkillPanelExpected.Count
    skill_panel_layout_actual_count = $slpEntries.Count
    skill_panel_layout_missing = $slpMissing
    skill_panel_layout_duplicates = $slpDuplicates
    skill_panel_layout_not_git_tracked = $slpGitTracked
    skill_panel_layout_included_in_default_critical = $slpIncluded
    skill_panel_layout_validate_set = $slpValidateSet
    audit_upgrade_expected_count = $auditExpected.Count
    audit_upgrade_actual_count = $auditEntries.Count
    audit_upgrade_missing_or_untracked = $auditMissing
    audit_upgrade_registration_pass = $auditOk
    result = $result
}
$report | ConvertTo-Json -Depth 4
if ($result -eq 'FAIL') {
    Write-Host "SUITE_REGISTRATION_CHECK_FAIL" -ForegroundColor Red
    exit 1
}
Write-Host "SUITE_REGISTRATION_CHECK_PASS" -ForegroundColor Green
exit 0
