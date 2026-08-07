param(
    [ValidateSet('critical', 'warrior', 'bich', 'equipment', 'monster', 'snapshot_coordinate_critical', 'snapshot_production_critical', 'projectile_spatial_critical', 'safe_logout_critical', 'persistent_ground_effect_critical', 'fire_wall_controller_critical', 'monster_streaming_critical', 'skill_execution_plan_critical', 'skill_production_migration_critical', 'skill_runtime_cleanup_critical', 'wizard_line_geometry_critical', 'combat_absolute_ground_critical')]
    [string]$Suite = 'critical',
    [int]$TimeoutSeconds = 8,
    [string[]]$TestPaths = @()
)

$ErrorActionPreference = 'Stop'
# Some Codex desktop shells inherit both `Path` and `PATH`. PowerShell's
# Start-Process treats environment keys case-insensitively and aborts when both
# spellings are present, so normalize the process copy before launching Godot.
$ProcessPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
[Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
[Environment]::SetEnvironmentVariable('Path', $ProcessPath, 'Process')
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$GodotDirectory = Split-Path -Parent $Godot
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\runtime_appdata'

# Codex desktop may sandbox the normal roaming AppData directory. Godot 4.7
# crashes in its Windows file logger after a denied user://logs write, even
# when the test itself has already passed. Keep all test-only user data inside
# the current worktree so every professional tree remains isolated and the
# engine can shut down cleanly without an application-error dialog.
New-Item -ItemType Directory -Path $RuntimeAppData -Force | Out-Null
[Environment]::SetEnvironmentVariable('APPDATA', $RuntimeAppData, 'Process')

$Suites = @{
    monster = @(
		'tests/monster_id_contract_test.tscn',
		'tests/all_monster_loading_test.tscn',
		'tests/monster_world_integration_test.tscn',
		'tests/complete_monster_client_art_test.tscn',
		'tests/fixed_area_monster_test.tscn',
		'tests/classic_boss_order_test.tscn',
		'tests/monster_threat_animation_test.tscn',
		'tests/bich_monster_visual_test.tscn',
		'tests/bich_common_client_art_test.tscn',
		'tests/bich_route_monster_test.tscn',
		'tests/bich_undead_client_art_test.tscn',
		'tests/skeleton_spirit_boss_test.tscn',
		'tests/corpse_king_boss_test.tscn',
		'tests/crowd_grounding_test.tscn',
		'tests/monster_unit_adapter_test.tscn',
		'tests/monster_ground_unit_runtime_test.tscn',
		'tests/monster_melee_contact_geometry_test.tscn',
		'tests/placeholder_attack_animation_test.tscn'
	)
    warrior = @(
		'tests/complete_client_resource_catalog_test.tscn',
		'tests/player_movement_respawn_test.tscn',
		'tests/warrior_wear_mapping_test.tscn',
        'tests/warrior_service_formula_test.tscn',
        'tests/warrior_skill_state_machine_test.tscn',
        'tests/caster_spell_action_timing_test.tscn',
		'tests/wizard_geometry_visual_alignment_test.tscn',
		'tests/game_root_wizard_geometry_integration_test.tscn',
		'tests/game_root_spell_lock_input_integration_test.tscn',
		'tests/fire_wall_runtime_overlap_test.tscn',
        'tests/skill_runtime_integration_test.tscn',
        'tests/canonical_skill_production_entry_test.tscn',
        'tests/skill_progression_save_integration_test.tscn',
        'tests/warrior_client_art_test.tscn',
        'tests/skill_combat_profile_test.tscn',
        'tests/warrior_attack_timing_test.tscn',
		'tests/combat_release_geometry_test.tscn',
		'tests/live_attack_resolution_test.tscn',
		'tests/melee_lock_fallback_test.tscn',
        'tests/warrior_visual_test.tscn',
        'tests/class_combat_test.tscn',
        'tests/mobile_targeting_test.tscn',
        'tests/item_catalog_test.tscn',
        'tests/skeleton_spirit_boss_test.tscn',
        'tests/smoke_test.tscn'
    )
    bich = @(
		'tests/brand_intro_test.tscn',
		'tests/npc_facing_interaction_test.tscn',
		'tests/world_spatial_contract_test.tscn',
		'tests/zone_portal_visual_test.tscn',
		'tests/bich_hard_boundary_test.tscn',
		'tests/bich_content_1_test.tscn',
		'tests/bich_map_3_runtime_bridge_test.tscn',
		'tests/wooma_game_runtime_integration_test.tscn',
		'tests/phase1_game_runtime_integration_test.tscn',
		'tests/game_root_monster_prefetch_test.tscn',
		'tests/orc_tomb_runtime_visual_geometry_test.tscn',
		'tests/orc_tomb_game_visual_geometry_test.tscn',
		'tests/architecture_final_test.tscn',
		'tests/five_layer_architecture_test.tscn',
		'tests/bich_community_baseline_test.tscn',
		'tests/map_coordinate_mapping_test.tscn',
		'tests/map_combat_unit_contract_test.tscn',
		'tests/game_root_map_unit_integration_test.tscn',
		'tests/source_collision_chunk_test.tscn',
		'tests/bich_content_closure_test.tscn',
		'tests/corpse_king_boss_test.tscn',
		'tests/orc_tomb_source_integration_test.tscn',
		'tests/natural_cave_source_integration_test.tscn',
		'tests/bich_common_client_art_test.tscn',
		'tests/bich_undead_client_art_test.tscn',
		'tests/bich_quest_chain_test.tscn',
        'tests/bich_source_map_integration_test.tscn',
        'tests/service_runtime_integration_test.tscn',
        'tests/bich_environment_test.tscn',
        'tests/bich_area_test.tscn',
        'tests/progression_test.tscn',
        'tests/vertical_slice_loop_test.tscn'
    )
    equipment = @(
		'tests/complete_item_system_test.tscn',
		'tests/inventory_equipment_ui_test.tscn',
		'tests/multi_character_save_test.tscn',
		'tests/system_menu_test.tscn',
		'tests/equipment_client_art_test.tscn',
        'tests/equipment_future_modifiers_test.tscn',
        'tests/equipment_customization_test.tscn',
        'tests/equipment_special_phase2_test.tscn',
        'tests/equipment_special_effects_test.tscn',
        'tests/equipment_luck_test.tscn',
        'tests/equipment_durability_policy_test.tscn',
        'tests/equipment_service_rules_test.tscn',
        'tests/equipment_attribute_master_test.tscn',
        'tests/equipment_slot_migration_test.tscn',
        'tests/item_catalog_test.tscn',
        'tests/vertical_slice_loop_test.tscn',
        'tests/android_layout_test.tscn'
    )
}

$Suites.caster_visual_critical = @(
    'tests/caster_skill_visual_factory_entry_test.tscn',
    'tests/laser_direction_visual_extent_test.tscn',
    'tests/caster_skill_animation_routing_test.tscn',
    'tests/wizard_geometry_visual_alignment_test.tscn',
    'tests/sky_strike_visual_contract_test.tscn',
    'tests/lightning_runtime_map_visual_test.tscn',
    'tests/hell_lightning_self_area_visual_test.tscn',
    'tests/beam_visual_contract_test.tscn',
    'tests/beam_runtime_empty_space_test.tscn',
    'tests/beam_runtime_terrain_cutoff_test.tscn',
    'tests/beam_single_active_test.tscn',
    'tests/visual_profile_merge_contract_test.tscn',
    'tests/fire_wall_runtime_absolute_ground_test.tscn',
    'tests/fire_wall_single_controller_test.tscn',
    'tests/player_initial_resource_sync_test.tscn',
    "tests/gameplay_input_gate_test.tscn",
    "tests/input_release_cleanup_test.tscn",
    "tests/initial_world_input_lock_test.tscn",
    "tests/map_transition_input_lock_test.tscn"
)

$Suites.snapshot_coordinate_critical = @(
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

$Suites.snapshot_production_critical = @(
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

$Suites.projectile_spatial_critical = @(
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

$Suites.safe_logout_critical = @(
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

$Suites.persistent_ground_effect_critical = @(
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

$Suites.fire_wall_controller_critical = @(
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

$Suites.monster_streaming_critical = @(
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

$Suites.skill_execution_plan_critical = @(
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

$Suites.skill_production_migration_critical = @(
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

$Suites.skill_runtime_cleanup_critical = @(
    'tests/skill_runtime_no_legacy_api_test.tscn',
    'tests/skill_runtime_single_public_entry_test.tscn',
    'tests/skill_plan_golden_contract_test.tscn',
    'tests/skill_runtime_no_visual_plan_test.tscn',
    'tests/skill_runtime_single_result_contract_test.tscn',
    'tests/skill_runtime_mapped_world_strict_snapshot_test.tscn'
)

$Suites.wizard_line_geometry_critical = @(
    'tests/wizard_line_footprint_core_test.tscn',
    'tests/wizard_line_visual_stability_test.tscn'
)

$Suites.combat_absolute_ground_critical = @(
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

$Suites.critical = @(
    'tests/combat_unit_runtime_static_audit_test.tscn'
) + @(
    $Suites.caster_visual_critical +
    $Suites.snapshot_coordinate_critical +
    $Suites.snapshot_production_critical +
    $Suites.projectile_spatial_critical +
    $Suites.safe_logout_critical +
    $Suites.persistent_ground_effect_critical +
    $Suites.fire_wall_controller_critical +
    $Suites.monster_streaming_critical +
    $Suites.skill_execution_plan_critical +
    $Suites.skill_production_migration_critical +
    $Suites.skill_runtime_cleanup_critical +
    $Suites.wizard_line_geometry_critical +
    $Suites.combat_absolute_ground_critical +
    $Suites.warrior + $Suites.bich + $Suites.equipment + $Suites.monster |
        Select-Object -Unique
)

# ── Q0-A: final judgement contract ──
# PASS is granted only when every gate below is satisfied. A PASS marker never
# exempts timeout, non-zero exit, or engine-log failures.
$FailurePattern = 'SCRIPT ERROR:|Parse Error:|Assertion failed:|FATAL:|Unhandled exception|Crash|Segmentation fault'
$PassMarkerPattern = '[A-Z0-9_]+_PASS'

# Minimal, cause-specific allowlist for known non-fatal `ERROR:` lines produced
# by the current suite. Any other `ERROR:` line fails the test.
$EngineErrorAllowlist = @(
    @{
        pattern = '^ERROR: String formatting error: not all arguments converted during string formatting\.'
        reason = 'benign Godot String.format warning emitted by monster_melee_contact_geometry_test debug output; test still completes and passes'
    },
    @{
        pattern = '^ERROR: \d+ resources still in use at exit'
        reason = 'Godot headless emits this at normal engine exit when queue_freed nodes finish releasing after quit; observed across ~42/105 suite tests with varying counts, exit code and PASS marker unaffected'
    },
    @{
        pattern = '^ERROR: \d+ RID allocations? of type ''PN\d+RendererDummy\d+TextureStorage\d+DummyTextureE'' were leaked at exit\.'
        reason = 'Godot dummy renderer reports leaked RID textures at engine exit in headless visual tests; non-fatal, exit code and PASS marker unaffected'
    },
    @{
        pattern = '^ERROR: Parameter "t" is null\.'
        reason = 'Godot dummy renderer logs a null texture parameter when a threaded texture lands after scene teardown in headless runs; non-fatal, exit code and PASS marker unaffected (observed in player_movement_respawn / phase1 / android_layout)'
    }
)

function Get-FailureLineCount([string]$Text, [string]$Pattern) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 0
    }
    return @($Text -split "`r?`n" | Where-Object { $_ -match $Pattern }).Count
}

function Get-UnallowlistedErrorLineCount([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return 0
    }
    $count = 0
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -notmatch '^ERROR:') {
            continue
        }
        $allowed = $false
        foreach ($entry in $EngineErrorAllowlist) {
            if ($line -match $entry.pattern) {
                $allowed = $true
                break
            }
        }
        if (-not $allowed) {
            $count += 1
        }
    }
    return $count
}

function Stop-TestProcessTree([int]$ProcessId) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-TestProcessTree -ProcessId ([int]$child.ProcessId)
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot不存在：$Godot"
}
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

function Get-WorktreeGodotProcesses {
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        if ($_.ProcessName -notlike 'Godot*') {
            return $false
        }
        # A process can exit between enumeration and Path access. Snapshot the
        # value once so Split-Path never receives a raced null value.
        $candidatePath = $null
        try {
            $candidatePath = $_.Path
        } catch {
            return $false
        }
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            return $false
        }
        return [System.IO.Path]::GetDirectoryName($candidatePath) -eq $GodotDirectory
    })
}

$BaselineGodotIds = @(Get-WorktreeGodotProcesses | Select-Object -ExpandProperty Id)

function Stop-NewGodotProcesses([int]$GraceMilliseconds = 0) {
    if ($GraceMilliseconds -gt 0) {
        $graceDeadline = [DateTime]::UtcNow.AddMilliseconds($GraceMilliseconds)
        $quietSince = $null
        while ([DateTime]::UtcNow -lt $graceDeadline) {
            if (@(Get-NewGodotProcesses).Count -eq 0) {
                if ($null -eq $quietSince) {
                    $quietSince = [DateTime]::UtcNow
                } elseif (([DateTime]::UtcNow - $quietSince).TotalMilliseconds -ge 300) {
                    return
                }
            } else {
                $quietSince = $null
            }
            Start-Sleep -Milliseconds 100
        }
    }
    $newProcesses = @(Get-NewGodotProcesses)
    foreach ($newProcess in $newProcesses) {
        Stop-TestProcessTree -ProcessId $newProcess.Id
    }
}

function Get-NewGodotProcesses {
    return @(Get-WorktreeGodotProcesses | Where-Object { $_.Id -notin $BaselineGodotIds })
}

$SelectedTests = if ($TestPaths.Count -gt 0) { $TestPaths } else { $Suites[$Suite] }
$StructuredResults = @()
foreach ($testPath in $SelectedTests) {
    $testName = [IO.Path]::GetFileNameWithoutExtension($testPath)
    $stdout = Join-Path $LogRoot "$testName.stdout.log"
    $stderr = Join-Path $LogRoot "$testName.stderr.log"
    $engineLog = Join-Path $LogRoot "$testName.godot.log"
    $engineLogArgument = "outputs/test_logs/$testName.godot.log"
    Remove-Item -LiteralPath $stdout, $stderr, $engineLog -Force -ErrorAction SilentlyContinue
    # Q0-A 3.2: run through cmd.exe so the final process object exposes the
    # effective exit code (the Godot console wrapper forwards the engine code,
    # but Start-Process with -Redirect* loses ExitCode on this host). Output is
    # redirected inside the command string; polling reads the same files.
    $launchCommand = '""' + $Godot + '" --headless --log-file "' + $engineLogArgument + '" --path . "' + $testPath + '" > "' + $stdout + '" 2> "' + $stderr + '"'
    $process = Start-Process -FilePath 'cmd.exe' `
        -ArgumentList @('/c', $launchCommand) `
        -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $wrapperExitWithoutChildSince = $null
    $earlyFailure = $false
    $hasPassMarker = $false
    $naturalExit = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $currentOutput = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue } else { '' }
        $currentError = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($currentError -match $FailurePattern) {
            $earlyFailure = $true
            Stop-TestProcessTree -ProcessId $process.Id
            break
        }
        if ($currentOutput -match $PassMarkerPattern) {
            $hasPassMarker = $true
            # Do NOT break - wait for natural exit to capture post-PASS failures (HC-P0-006)
        }
        # On Windows the console executable can exit after spawning the real
        # Godot process. Keep waiting while that child is still running instead
        # of treating the wrapper exit as the end of the test.
        if ($process.HasExited -and @(Get-NewGodotProcesses).Count -eq 0) {
            if ($null -eq $wrapperExitWithoutChildSince) {
                $wrapperExitWithoutChildSince = [DateTime]::UtcNow
            } elseif (
                ([DateTime]::UtcNow - $wrapperExitWithoutChildSince).TotalMilliseconds -ge 1000
            ) {
                $naturalExit = $true
                break
            }
        } else {
            $wrapperExitWithoutChildSince = $null
        }
    }
    # Q0-A 3.1: reaching the deadline is a timeout regardless of the PASS marker.
    $timedOut = -not $earlyFailure -and -not $naturalExit -and [DateTime]::UtcNow -ge $deadline
    if ($timedOut) {
        Stop-TestProcessTree -ProcessId $process.Id
    }
    # A passing scene asks Godot to quit, but on Windows the console wrapper
    # can print the PASS marker before the child process has fully released its
    # handles. Give that child a short natural-exit window before force cleanup;
    # otherwise the next headless launch can be killed during process handoff.
    $graceMilliseconds = if ($hasPassMarker -and -not $earlyFailure -and -not $timedOut) { 2000 } else { 0 }
    Stop-NewGodotProcesses -GraceMilliseconds $graceMilliseconds
    $outText = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue } else { '' }
    $errText = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue } else { '' }
    $engineText = if (Test-Path -LiteralPath $engineLog) { Get-Content -LiteralPath $engineLog -Raw -ErrorAction SilentlyContinue } else { '' }
    $hasPassMarker = $outText -match $PassMarkerPattern

    # Q0-A 3.2: effective exit code. The console wrapper forwards the engine's
    # exit code; without a natural wrapper/child exit the code is unavailable
    # and the result must not be a strict PASS.
    $wrapperExitCode = $null
    if ($process.HasExited) {
        $process.Refresh()
        if ($process.HasExited) {
            $wrapperExitCode = $process.ExitCode
        }
    }
    $childProcessesAlive = @(Get-NewGodotProcesses).Count
    $childProcessExitState = 'not_observed'
    if ($earlyFailure -or $timedOut) {
        $childProcessExitState = 'forced_termination'
    } elseif ($naturalExit) {
        $childProcessExitState = 'exited'
    } elseif ($childProcessesAlive -gt 0) {
        $childProcessExitState = 'alive'
    }
    $finalEffectiveExitCode = $wrapperExitCode
    if ($null -eq $finalEffectiveExitCode) {
        $finalEffectiveExitCode = -1
    }
    $processExited = $naturalExit

    # Q0-A 3.3: scan stdout, stderr and the engine log.
    $stdoutFailureCount = (Get-FailureLineCount $outText $FailurePattern) + (Get-UnallowlistedErrorLineCount $outText)
    $stderrFailureCount = (Get-FailureLineCount $errText $FailurePattern) + (Get-UnallowlistedErrorLineCount $errText)
    $engineLogFailureCount = (Get-FailureLineCount $engineText $FailurePattern) + (Get-UnallowlistedErrorLineCount $engineText)

    $reasons = @()
    if (-not $hasPassMarker) { $reasons += 'missing_pass_marker' }
    if (-not $processExited) { $reasons += 'process_did_not_exit' }
    if ($timedOut) { $reasons += "timeout_${TimeoutSeconds}s" }
    if ($earlyFailure) { $reasons += 'early_script_error' }
    if ($finalEffectiveExitCode -ne 0) {
        if ($null -eq $wrapperExitCode) { $reasons += 'missing_effective_exit_code' } else { $reasons += "non_zero_exit_code_$finalEffectiveExitCode" }
    }
    if ($stdoutFailureCount -gt 0) { $reasons += "stdout_failures_$stdoutFailureCount" }
    if ($stderrFailureCount -gt 0) { $reasons += "stderr_failures_$stderrFailureCount" }
    if ($engineLogFailureCount -gt 0) { $reasons += "engine_log_failures_$engineLogFailureCount" }

    $result = 'PASS'
    if ($reasons.Count -gt 0) {
        $result = 'FAIL'
    }
    $StructuredResults += [ordered]@{
        test_name = $testName
        test_path = $testPath
        pass_marker_found = $hasPassMarker
        process_exited = $processExited
        wrapper_exit_code = $wrapperExitCode
        child_process_exit_state = $childProcessExitState
        effective_exit_code = $finalEffectiveExitCode
        timeout = $timedOut
        stdout_failure_count = $stdoutFailureCount
        stderr_failure_count = $stderrFailureCount
        engine_log_failure_count = $engineLogFailureCount
        result = $result
        reason = ($reasons -join ';')
    }
    if ($result -eq 'FAIL') {
        $reason = if ($reasons.Count -gt 0) { $reasons -join ';' } else { 'unknown' }
        Write-Host "[FAIL] $testName - $reason" -ForegroundColor Red
        if ($outText) { Write-Host $outText.Trim() }
        if ($errText) { Write-Host $errText.Trim() }
    } else {
        Write-Host "[PASS] $testName" -ForegroundColor Green
    }
}

$passedCount = @($StructuredResults | Where-Object { $_.result -eq 'PASS' }).Count
$failedCount = @($StructuredResults | Where-Object { $_.result -eq 'FAIL' }).Count
$engineLogErrorTotal = 0
foreach ($resultEntry in $StructuredResults) {
    $engineLogErrorTotal += [int]$resultEntry.engine_log_failure_count
}
$resultsFilePath = Join-Path $LogRoot ("runner_results_{0}_{1}.json" -f $Suite, (Get-Date -Format 'yyyyMMdd_HHmmss'))
@{
    suite = $Suite
    generated_at = (Get-Date -Format o)
    git_head = (git rev-parse HEAD 2>$null | Out-String).Trim()
    total = $StructuredResults.Count
    passed = $passedCount
    failed = $failedCount
    engine_log_errors = $engineLogErrorTotal
    results = $StructuredResults
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultsFilePath -Encoding UTF8
Write-Host "RUNNER_RESULTS_JSON=$resultsFilePath"
Write-Host "TEST_SUMMARY suite=$Suite passed=$passedCount failed=$failedCount engine_log_errors=$engineLogErrorTotal"
Stop-NewGodotProcesses
if ($failedCount -gt 0) {
    $failedNames = @($StructuredResults | Where-Object { $_.result -eq 'FAIL' } | ForEach-Object { "$($_.test_name) ($($_.reason))" }) -join '; '
    Write-Host ("FAILED_TESTS=" + $failedNames) -ForegroundColor Red
    exit 1
}
exit 0
