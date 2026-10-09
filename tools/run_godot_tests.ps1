param(
    [ValidateSet('critical', 'audit_upgrade_critical', 'warrior', 'bich', 'equipment', 'monster', 'pricing_authority', 'taoist_critical', 'snapshot_coordinate_critical', 'snapshot_production_critical', 'projectile_spatial_critical', 'safe_logout_critical', 'persistent_ground_effect_critical', 'fire_wall_controller_critical', 'monster_streaming_critical', 'skill_execution_plan_critical', 'skill_production_migration_critical', 'skill_runtime_cleanup_critical', 'wizard_line_geometry_critical', 'combat_absolute_ground_critical', 'combat_projection_fail_closed_critical', 'formal_map_projection_critical', 'map_runtime_release_critical', 'map_runtime_release_transaction_critical', 'player_visual_contract_critical', 'skill_panel_layout_critical', 'device_lab_critical', 'source176_r3', 'user_feedback_20260930')]
    [string]$Suite = 'critical',
    [ValidateRange(1, 90)]
    [int]$TimeoutSeconds = 30,
    [switch]$Verbose,
    [string[]]$TestPaths = @()
)

$ErrorActionPreference = 'Stop'
$RunnerIsLinux = [Environment]::OSVersion.Platform -eq [PlatformID]::Unix
$LinuxNativeProcess = $null
$LinuxStdoutStream = $null
$LinuxStderrStream = $null
$LinuxStdoutTask = $null
$LinuxStderrTask = $null
$RunnerInvocationId = [Guid]::NewGuid().ToString()
function Assert-PhysicalRuntimeDirectory([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('/') + '/'
    if (-not $fullPath.StartsWith($prefix, [StringComparison]::Ordinal)) { throw 'Runtime directory escapes checkout.' }
    $current = $ProjectRoot
    foreach ($part in [IO.Path]::GetRelativePath($ProjectRoot, $fullPath).Split('/')) {
        $current = Join-Path $current $part
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Linux runtime directory must not traverse a symlink.'
            }
        }
    }
}
function Get-LinuxOwnedGroupProcesses {
    $groupId = if ($null -ne $LinuxNativeProcess) { $LinuxNativeProcess.Id } else { -1 }
    $members = @()
    foreach ($directory in [IO.Directory]::EnumerateDirectories('/proc')) {
        if ([IO.Path]::GetFileName($directory) -notmatch '^[0-9]+$') { continue }
        try { $stat = [IO.File]::ReadAllText((Join-Path $directory 'stat')) } catch { continue }
        $fields = $stat.Substring($stat.LastIndexOf(')') + 2).Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        # Require both the owned process group and its private session. Never
        # infer ownership from a shared engine path or a reusable process name.
        $memberId = [int][IO.Path]::GetFileName($directory)
        $privateGroup = $fields[2] -eq [string]$groupId -and $fields[3] -eq [string]$groupId
        # Godot OS.create_process intentionally detaches its child session.
        # A subreaper adopts it after engine exit, retaining exact ownership.
        $adopted = $fields[1] -eq [string]$PID -and $memberId -ne $groupId -and $memberId -notin $LinuxBaselineChildIds
        if ($fields[0] -ne 'Z' -and ($privateGroup -or $adopted)) {
            $members += [pscustomobject]@{ Id = $memberId; PrivateGroup = $privateGroup }
        }
    }
    return $members
}
function Complete-LinuxOutput([bool]$FailOnIncomplete = $true) {
    if ($null -eq $LinuxStdoutTask -or $null -eq $LinuxStderrTask) { return }
    try {
        $drain = [Threading.Tasks.Task]::WhenAll([Threading.Tasks.Task[]]@($LinuxStdoutTask, $LinuxStderrTask))
        if (-not $drain.Wait(2000)) { throw 'Linux native output pipes did not close after owned process cleanup.' }
        $drain.GetAwaiter().GetResult() | Out-Null
    } catch {
        $script:LinuxOutputIncomplete = $true
        if ($null -ne $LinuxNativeProcess) {
            $LinuxNativeProcess.StandardOutput.Dispose()
            $LinuxNativeProcess.StandardError.Dispose()
        }
        if ($FailOnIncomplete) { throw }
    } finally {
        $script:LinuxStdoutTask = $null
        $script:LinuxStderrTask = $null
    }
}
# A single worktree owns one import cache, userdata directory and log namespace.
# Reject overlapping runners before either can overwrite evidence or terminate
# a peer's child process during cleanup. The OS also releases abandoned locks.
$RunnerHashAlgorithm = [Security.Cryptography.SHA256]::Create()
$RunnerMutexKey = [BitConverter]::ToString($RunnerHashAlgorithm.ComputeHash(
    [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($PSScriptRoot).ToUpperInvariant())
)).Replace('-', '')
$RunnerHashAlgorithm.Dispose()
$RunnerMutex = New-Object Threading.Mutex($false, "Local\HardCoreGodotRunner_$RunnerMutexKey")
$RunnerLockHeld = $false
$FrameworkEnvironmentCaptured = $false
try {
    try { $RunnerLockHeld = $RunnerMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $RunnerLockHeld = $true }
    if (-not $RunnerLockHeld) {
        throw 'Another Godot test runner owns this worktree. Wait for its explicit handoff before retrying.'
    }
# Some Codex desktop shells inherit both `Path` and `PATH`. PowerShell's
# Start-Process treats environment keys case-insensitively and aborts when both
# spellings are present, so normalize the process copy before launching Godot.
if (-not $RunnerIsLinux) {
    $ProcessPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    [Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
    [Environment]::SetEnvironmentVariable('Path', $ProcessPath, 'Process')
}
$ProjectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'test_framework_receipt.ps1')
$PreviousFrameworkRunId = [Environment]::GetEnvironmentVariable('HARDCORE_FRAMEWORK_RUN_ID', 'Process')
$PreviousFrameworkInvocationId = [Environment]::GetEnvironmentVariable('HARDCORE_FRAMEWORK_INVOCATION_ID', 'Process')
$FrameworkEnvironmentCaptured = $true
$Godot = if ($RunnerIsLinux) { $env:HARDCORE_GODOT } else { Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe' }
if ($RunnerIsLinux -and ([string]::IsNullOrEmpty($Godot) -or -not (Test-Path -LiteralPath $Godot -PathType Leaf))) {
    throw 'Linux requires an explicit existing HARDCORE_GODOT executable.'
}
$GodotDirectory = Split-Path -Parent $Godot
$LogRoot = if ($env:HARDCORE_AUDIT_LOG_ROOT) { $env:HARDCORE_AUDIT_LOG_ROOT } else { Join-Path $ProjectRoot 'outputs\test_logs' }
$RuntimeAppData = if ($env:HARDCORE_AUDIT_RUNTIME_APPDATA) { $env:HARDCORE_AUDIT_RUNTIME_APPDATA } else { Join-Path $ProjectRoot '.godot\runtime_appdata' }
if ($RunnerIsLinux) {
    $LinuxLauncher = @(Get-Command setsid -CommandType Application -ErrorAction Stop)[0].Source
    Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class HardCoreNativeSignals { [DllImport("libc", SetLastError=true)] public static extern int kill(int pid, int signal); [DllImport("libc", SetLastError=true)] public static extern int prctl(int option, ulong arg2, ulong arg3, ulong arg4, ulong arg5); [DllImport("libc", SetLastError=true)] public static extern int waitpid(int pid, out int status, int options); }'
    $LinuxBaselineChildIds = @((Get-LinuxOwnedGroupProcesses).Id)
    if ([HardCoreNativeSignals]::prctl(36, 1, 0, 0, 0) -ne 0) { throw 'Linux native runner could not enable child subreaper ownership.' }
    $ownedRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot '.godot/runtime_appdata')).TrimEnd('/') + '/'
    $RuntimeAppData = [IO.Path]::GetFullPath((Join-Path $RuntimeAppData "cloud_$RunnerInvocationId"))
    if (-not $RuntimeAppData.StartsWith($ownedRoot, [StringComparison]::Ordinal)) {
        throw 'Linux test userdata must remain inside this checkout .godot/runtime_appdata/.'
    }
    Assert-PhysicalRuntimeDirectory $RuntimeAppData
    if ($env:HARDCORE_R3_CONTENT_SHA256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Linux formal runs require a source fingerprint from source176_r3_validation.py.'
    }
    $engineVersion = (& $Godot --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $engineVersion -cne '4.7.stable.official.5b4e0cb0f') {
        throw "Linux engine version mismatch: $engineVersion"
    }
}

$EffectiveSuite = $Suite
if ($TestPaths.Count -gt 0) {
    if ($PSBoundParameters.ContainsKey('Suite')) {
        throw 'TestPaths is adhoc-only and cannot be combined with an explicit formal Suite.'
    }
    $EffectiveSuite = 'adhoc'
    $testsRoot = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'tests'))
    $testsRootPrefix = $testsRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $validatedTestPaths = @()
    foreach ($candidatePath in $TestPaths) {
        if ([string]::IsNullOrWhiteSpace($candidatePath)) {
            throw 'TestPaths entries cannot be empty.'
        }
        $normalizedPath = $candidatePath.Replace('\', '/')
        if ([IO.Path]::IsPathRooted($candidatePath) -or ($normalizedPath -split '/') -contains '..') {
            throw "TestPaths entry must remain inside tests/: $candidatePath"
        }
        if ($normalizedPath -notmatch '^tests/(?:[^/]+/)*[^/]+\.tscn$') {
            throw "TestPaths entry must match tests/**/*.tscn: $candidatePath"
        }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot ($normalizedPath.Replace('/', [IO.Path]::DirectorySeparatorChar))))
        if (-not $fullPath.StartsWith($testsRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "TestPaths entry resolves outside tests/: $candidatePath"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "TestPaths entry does not exist: $candidatePath"
        }
        $trackedPaths = @(& git -C $ProjectRoot ls-files -- $normalizedPath 2>$null)
        if ($trackedPaths -cnotcontains $normalizedPath) {
            throw "TestPaths entry must be Git tracked with exact path casing: $candidatePath"
        }
        $validatedTestPaths += $normalizedPath
    }
    $TestPaths = $validatedTestPaths
}

# Codex desktop may sandbox the normal roaming AppData directory. Godot 4.7
# crashes in its Windows file logger after a denied user://logs write, even
# when the test itself has already passed. Keep all test-only user data inside
# the current worktree so every professional tree remains isolated and the
# engine can shut down cleanly without an application-error dialog.
New-Item -ItemType Directory -Path $RuntimeAppData -Force | Out-Null
if ($RunnerIsLinux) { Assert-PhysicalRuntimeDirectory $RuntimeAppData }
$RuntimeAppData = (Get-Item -LiteralPath $RuntimeAppData).FullName
[Environment]::SetEnvironmentVariable('APPDATA', $RuntimeAppData, 'Process')
if ($RunnerIsLinux) { [Environment]::SetEnvironmentVariable('XDG_DATA_HOME', $RuntimeAppData, 'Process') }
$RuntimeEnvironmentRecord = [ordered]@{
    project_root = $ProjectRoot
    runtime_appdata = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
    runner_process_id = $PID
}

$Suites = @{
    monster = @(
        # HC-POLY-R2: registered production regression scenes
        'tests/hc_polygon_navigation_test.tscn',
		'tests/canonical_monster_catalog_test.tscn',
		'tests/monster_drop_authoring_overlay_contract_test.tscn',
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
		'tests/monster_accuracy_runtime_test.tscn',
		'tests/monster_anti_stealth_runtime_test.tscn',
		'tests/monster_mfc1_attribute_timing_audit_test.tscn',
		'tests/monster_movement_cadence_test.tscn',
		'tests/monster_struck_policy_test.tscn',
		'tests/monster_struck_visual_queue_test.tscn',
		'tests/monster_struck_runtime_test.tscn',
		'tests/source176_delivery_gate_test.tscn',
		'tests/source176_decision_gate_test.tscn',
		'tests/monster_dormant_damage_wake_test.tscn',
		'tests/monster_neighbor_step_policy_test.tscn',
		'tests/monster_cadence_runtime_integration_test.tscn',
		'tests/monster_cadence_blocked_step_test.tscn',
		'tests/monster_forced_relocation_during_step_test.tscn',
		'tests/monster_density_diagnostics_window_test.tscn',
		'tests/safe_zone_spatial_runtime_test.tscn',
		'tests/monster_parent_redraw_gate_test.tscn',
		'tests/monster_physical_projectile_visual_source_test.tscn',
		'tests/monster_target_magic_primary_visual_test.tscn',
		'tests/monster_special_delivery_contract_test.tscn',
		'tests/monster_special_delivery_runtime_test.tscn',
		'tests/direct_spell_compiled_stats_parity_test.tscn',
		'tests/multi_target_damage_transaction_test.tscn',
		'tests/game_root_combat_resolution_integration_test.tscn',
		'tests/game_root_r3x6_targeting_broadphase_test.tscn',
		'tests/enemy_mass_death_batch_pipeline_test.tscn',
		'tests/death_drop_budget_queue_test.tscn',
		'tests/death_queue_lifecycle_rework_test.tscn',
		'tests/placeholder_attack_animation_test.tscn',
		'tests/source176_r2/natural_approach_runtime_test.tscn'
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
		'tests/skills/warrior_target_aligned_release_geometry_test.tscn',
		'tests/skills/warrior_target_aligned_visual_effect_test.tscn',
		'tests/game_root_warrior_target_aligned_integration_test.tscn',
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
		'tests/pricing_authority_test.tscn',
		'tests/inventory_weight_authority_test.tscn',
		'tests/loot_pickup_ground_unit_test.tscn',
		'tests/loot_pickup_runtime_manager_test.tscn',
		'tests/loot_expiry_pending_guard_test.tscn',
		'tests/hud_authority_integration_test.tscn',
		'tests/hud_background_prewarm_test.tscn',
		'tests/complete_item_system_test.tscn',
		'tests/inventory_equipment_ui_test.tscn',
		'tests/multi_character_save_test.tscn',
		'tests/new_character_starter_loadout_test.tscn',
		'tests/system_menu_test.tscn',
		'tests/equipment_client_art_test.tscn',
        'tests/equipment_future_modifiers_test.tscn',
        'tests/equipment_customization_test.tscn',
        'tests/equipment_special_phase2_test.tscn',
        'tests/equipment_special_effects_test.tscn',
        'tests/equipment_luck_test.tscn',
        'tests/equipment_durability_policy_test.tscn',
        'tests/equipment_precise_durability_test.tscn',
        'tests/equipment_service_rules_test.tscn',
        'tests/equipment_attribute_master_test.tscn',
        'tests/equipment_slot_migration_test.tscn',
        'tests/item_catalog_test.tscn',
        'tests/vertical_slice_loop_test.tscn',
        'tests/android_layout_test.tscn'
    )
}

# R31 formalizes every natural-frame approach fixture in the checked-in
# manifest. Fail closed on count, identity, duplication, or missing scenes
# so an accidentally generated subset cannot masquerade as full coverage.
$Source176R3ManifestPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tests/source176_r3/native_scene_manifest.json'
$Source176R3Manifest = Get-Content -LiteralPath $Source176R3ManifestPath -Raw | ConvertFrom-Json
$Source176R3Scenes = @($Source176R3Manifest.scenes)
if ($Source176R3Scenes.Count -ne 48) {
    throw "source176_r3 manifest must contain exactly 48 scenes, found $($Source176R3Scenes.Count)"
}
if (($Source176R3Scenes | Sort-Object -Unique).Count -ne 48) {
    throw 'source176_r3 manifest contains duplicate scene paths'
}
$Source176R3PathPattern = '^(?:tests/source176_r3/natural_(?:64|89)_p[0-2]_d[0-7]\.tscn)$'
foreach ($scenePath in $Source176R3Scenes) {
    if ($scenePath -notmatch $Source176R3PathPattern) {
        throw "source176_r3 manifest contains an unexpected scene path: $scenePath"
    }
    if (-not (Test-Path -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) $scenePath))) {
        throw "source176_r3 manifest scene is missing on disk: $scenePath"
    }
}
$Suites.monster = @($Suites.monster + $Source176R3Scenes | Select-Object -Unique)

$Suites.caster_visual_critical = @(
    'tests/caster_skill_visual_factory_entry_test.tscn',
    'tests/laser_direction_visual_extent_test.tscn',
    'tests/laser_chest_translation_test.tscn',
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
    "tests/map_transition_input_lock_test.tscn",
    'tests/caster_skill_workset_lease_test.tscn',
    'tests/r14_caster_sequence_lease_test.tscn',
    'tests/r14_caster_production_caller_lease_test.tscn'
)

$Suites.taoist_critical = @(
	'tests/canonical_summon_integration_test.tscn',
    'tests/skills/taoist_summon_projectile_async_visual_test.tscn',
	'tests/skills/taoist_soul_fire_launch_timing_test.tscn',
    'tests/skills/taoist_summon_projectile_origin_anchor_test.tscn',
    'tests/skills/taoist_summon_projectile_stealth_buff_visual_test.tscn',
    'tests/skills/taoist_support_policy_test.tscn',
    'tests/skills/taoist_support_runtime_test.tscn',
    'tests/skills/taoist_canonical_runtime_test.tscn',
    'tests/skills/taoist_entrapment_boundary_production_test.tscn',
    'tests/skills/taoist_dual_defense_contract_test.tscn',
    'tests/skills/spell_target_lock_and_footprint_test.tscn',
    'tests/skills/skill_semantic_contracts_test.tscn',
    'tests/taoist_support_production_integration_test.tscn',
    'tests/canonical_skill_production_entry_test.tscn',
    'tests/skill_button_assignments_v2_test.tscn',
    'tests/class_combat_test.tscn',
    'tests/game_root_spell_lock_input_integration_test.tscn'
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
    'tests/monster_streaming_scaling_test.tscn',
    'tests/monster_streaming_lifecycle_test.tscn',
    'tests/monster_streaming_active_lease_test.tscn'
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
    'tests/wizard_line_visual_stability_test.tscn',
    'tests/wizard_line_presentation_alignment_test.tscn'
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

$Suites.combat_projection_fail_closed_critical = @(
    'tests/mapped_enemy_missing_projection_rejected_test.tscn',
    'tests/mapped_projectile_missing_projection_rejected_test.tscn',
    'tests/mapped_summon_missing_projection_rejected_test.tscn',
    'tests/mapped_fire_wall_missing_projection_rejected_test.tscn',
    'tests/mapped_skill_plan_missing_projection_rejected_test.tscn',
    'tests/mapped_game_root_projection_failure_test.tscn'
)

$Suites.formal_map_projection_critical = @(
    'tests/implemented_map_runtime_projection_test.tscn',
    'tests/phase1_network_runtime_coverage_test.tscn',
    'tests/unbuilt_planned_map_not_playable_test.tscn',
    'tests/reference_map_not_playable_test.tscn',
    'tests/legacy_reference_projection_isolation_test.tscn',
    'tests/formal_map_projection_coverage_test.tscn',
    'tests/world_ready_gating_test.tscn',
    'tests/safe_logout_world_location_inf_guard_test.tscn'
)

$Suites.map_runtime_release_critical = @(

    # HC-POLY-R2: registered production regression scenes

    'tests/hc_polygon_geometry_test.tscn',

    'tests/hc_polygon_navigation_test.tscn',

    'tests/hc_polygon_physics_test.tscn',

    'tests/hc_polygon_precision_test.tscn',

    'tests/hc_polygon_editor_input_test.tscn',

    'tests/hc_polygon_release_alignment_test.tscn',

    'tests/hc_polygon_numerics_test.tscn',

    'tests/hc_polygon_reset_test.tscn',

    'tests/hc_polygon_reset_release_test.tscn',
    'tests/map_runtime_release_registry_contract_test.tscn',
    'tests/map_ui_presentation_projection_test.tscn',
    'tests/map_persistent_boss_spawn_identity_test.tscn',
    'tests/release_registry_current_maps_test.tscn',
    'tests/map_runtime_release_gate_test.tscn',
    'tests/map_editor_save_path_isolation_test.tscn',
    'tests/map_release_identity_matrix_test.tscn',
    'tests/hc_polygon_counterexample_matrix_test.tscn',
    'tests/aoe_shape_edge_counterexample_test.tscn'
)

$Suites.map_runtime_release_transaction_critical = @(
    'tests/build_candidate_does_not_mutate_release_test.tscn',
    'tests/publish_promotes_candidate_test.tscn',
    'tests/publish_failure_rollback_test.tscn',
    'tests/map_publish_restart_recovery_test.tscn',
    'tests/release_registry_consumer_validation_test.tscn',
    'tests/future_map_build_publish_no_code_edit_test.tscn',
    'tests/mse_publish_entry_wired_test.tscn',
    # RV14-R2 review: multi-map backup comparison and recovery counterexamples.
    'tests/rv14_registry_review_counterexamples.tscn',
    'tests/rv14_restore_rollback_injection_test.tscn',
    'tests/rv14_multi_map_publish_sibling_invariance_test.tscn',
    # RV14-R2 review item 7: deterministic promote/rollback failure injection.
    'tests/rv14_restore_injected_failures_test.tscn',
    # RV15 joint review: sheet validation counterexamples and SPB decoupling.
    'tests/rv15_provider_validation_counterexamples_test.tscn',
    'tests/rv15_spb_ledger_decoupling_test.tscn'
)

$Suites.player_visual_contract_critical = @(
    'tests/passive_proc_actor_plane_contract_test.tscn'
)

$Suites.skill_panel_layout_critical = @(
    'tests/skill_panel_assignment_hint_layout_contract_test.tscn'
)

$Suites.device_lab_critical = @(
    'tests/device_lab_local_capture_test.tscn',
    'tests/device_lab_runtime_test.tscn',
    'tests/device_lab_patch_bootstrap_test.tscn',
    'tests/perf_frame_diagnostics_test.tscn',
    'tests/r14_diagnostic_mode_test.tscn'
)

$Suites.audit_upgrade_critical = @(
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
    'tests/runtime_loot_spatial_index_order_test.tscn',
    'tests/audit_39fe_regressions.tscn',
    'tests/player_cast_release_overwrite_test.tscn',
    'tests/player_status_effect_lifecycle_test.tscn',
    # RV14-R2 review: synchronous reentry epoch boundary for both spells and
    # plain attacks, with death/transition/exit-tree lifecycle coverage.
    'tests/rv14_release_reentry_test.tscn',
    # RV15 joint review: sheet validation counterexamples and SPB decoupling.
    'tests/rv15_provider_validation_counterexamples_test.tscn',
    'tests/rv15_spb_ledger_decoupling_test.tscn'
)

$Suites.critical = @(
    'tests/combat_unit_runtime_static_audit_test.tscn',
    'tests/android_attack_action_lifecycle_test.tscn',
    'tests/virtual_joystick_lifecycle_test.tscn',
    'tests/circular_touch_button_lifecycle_test.tscn'
) + @(
    $Suites.caster_visual_critical +
    $Suites.taoist_critical +
    $Suites.snapshot_coordinate_critical +
    $Suites.snapshot_production_critical +
    $Suites.projectile_spatial_critical +
    $Suites.safe_logout_critical +
    $Suites.persistent_ground_effect_critical +
    $Suites.fire_wall_controller_critical +
    # 2026-09-21 RV14-04 (O07): Monster Streaming returns to the default
    # critical suite (HOLD lifted for the streaming runtime). These scenes
    # need the elevated per-test budget; the runner refuses to start any run
    # that includes them below 30 seconds.
    $Suites.monster_streaming_critical +
    $Suites.skill_execution_plan_critical +
    $Suites.skill_production_migration_critical +
    $Suites.skill_runtime_cleanup_critical +
    $Suites.wizard_line_geometry_critical +
    $Suites.combat_absolute_ground_critical +
    $Suites.combat_projection_fail_closed_critical +
    $Suites.formal_map_projection_critical +
    $Suites.map_runtime_release_critical +
    $Suites.map_runtime_release_transaction_critical +
    $Suites.player_visual_contract_critical +
    $Suites.skill_panel_layout_critical +
    $Suites.device_lab_critical +
    $Suites.audit_upgrade_critical +
    $Suites.warrior + $Suites.bich + $Suites.equipment + $Suites.monster |
        Select-Object -Unique
)

# 2026-09-06 gameplay/audio integration regressions. Keep these production
# boundaries in the formal suite instead of relying on one-off adhoc evidence.
$Suites.critical = @($Suites.critical + @(
	'tests/random_teleport_map_extent_test.tscn',
    'tests/loot_stable_identity_save_test.tscn',
    'tests/loot_inventory_transaction_batch_test.tscn',
    'tests/loot_runtime_item_policy_test.tscn',
    'tests/combat_unit_source_priority_test.tscn',
    'tests/skill_book_rank_upgrade_integration_test.tscn',
    'tests/skill_progression_save_integration_test.tscn',
    'tests/player_level_up_effect_runtime_test.tscn',
    'tests/town_music_controller_test.tscn',
    'tests/audio_runtime_service_test.tscn',
    'tests/player_core_audio_hook_test.tscn',
    'tests/skills/warrior_thrust_defense_runtime_test.tscn',
    'tests/skills/warrior_melee_entry_runtime_test.tscn',
    'tests/skills/summon_owner_teleport_runtime_test.tscn',
    'tests/skills/summon_incoming_damage_runtime_test.tscn',
    'tests/skills/summon_audio_hook_test.tscn',
    'tests/monster_audio_hook_test.tscn',
    'tests/projectile_audio_lifecycle_test.tscn',
    'tests/player_item_audio_event_test.tscn',
    'tests/skills/skill_contract_manifest_test.tscn',
    'tests/skills/skill_source_of_truth_test.tscn',
    'tests/skills/skill_semantic_contracts_test.tscn'
) | Select-Object -Unique)

# 2026-09-27 R3/R4 monster-combat closure: the correctness scenes from the
# monster-combat R3 audit and the R4 fixed-point closure join the formal
# critical suite. paired_load_realism stays OUT until its INVALID_MEASUREMENT
# unit/sampling rebuild lands (R4 T6). The explicit-identity correctness
# fixtures below include the real natural cadence and fault gates.
$Suites.critical = @($Suites.critical + @(
    'tests/hc_monster_combat_r3/attack_facing_freeze_test.tscn',
    'tests/hc_monster_combat_r3/attack_game_clock_test.tscn',
    'tests/hc_monster_combat_r3/attack_parent_release_identity_test.tscn',
    'tests/hc_monster_combat_r3/audio_stale_frame_test.tscn',
    'tests/hc_monster_combat_r3/body_rejection_world_isolation_test.tscn',
    'tests/hc_monster_combat_r3/body_rule_tier_cross_test.tscn',
    'tests/hc_monster_combat_r3/real_admission_census_test.tscn',
    'tests/hc_monster_combat_r3/stale_death_notification_test.tscn',
    'tests/hc_monster_combat_r4/attack_expiry_without_render_test.tscn',
    'tests/hc_monster_combat_r4/attack_owner_idempotence_test.tscn',
    'tests/hc_monster_combat_r4/body_rejected_factory_isolation_test.tscn',
    'tests/hc_monster_combat_r4/body_rejected_query_contract_test.tscn',
    'tests/hc_monster_combat_r4/overhead_property_scan_test.tscn',
    'tests/monster_overhead_return_regression_test.tscn',
    'tests/monster_overhead_cold_activation_test.tscn',
    'tests/hc_monster_combat_r4/double_generation_death_test.tscn',
    'tests/hc_monster_combat_r4/perf_unit_determinism_test.tscn',
    'tests/hc_monster_combat_r4/native_physics_sampling_test.tscn',
    'tests/hc_monster_combat_r4/synchronous_revive_death_token_test.tscn',
    'tests/hc_monster_combat_r4/observer_integrity_test.tscn',
    'tests/hc_monster_combat_r4/mp_payment_observation_test.tscn',
    'tests/hc_monster_combat_r4/d3_boundary_runtime_test.tscn',
    'tests/hc_monster_combat_r4/d3_motion_pressure_runtime_test.tscn',
    'tests/hc_monster_combat_r4/body_multitarget_lifecycle_test.tscn',
    'tests/hc_monster_combat_r4/async_line_lifecycle_test.tscn',
    'tests/hc_monster_combat_r4/cancelled_release_observation_test.tscn',
    'tests/hc_monster_combat_r4/source_destroyed_pending_test.tscn',
    'tests/hc_monster_combat_r4/explicit_zero_attack_timing_test.tscn',
    'tests/hc_monster_combat_r4/runtime_capability_inventory_test.tscn',
    'tests/hc_monster_combat_r4/summon_planner_radius_test.tscn',
    'tests/hc_monster_combat_r4/damage_attribution_counterexamples_test.tscn',
    'tests/hc_monster_combat_r4/all_damage_lost_test.tscn',
    'tests/hc_monster_combat_r4/natural_cadence_24_test.tscn',
    'tests/hc_monster_combat_r4/natural_cadence_76_test.tscn',
    'tests/hc_monster_combat_r4/natural_cadence_238_test.tscn',
    'tests/hc_monster_combat_r4/natural_cadence_239_test.tscn',
    'tests/hc_monster_combat_r4/natural_cadence_24_chase_test.tscn',
    'tests/audio_w4_actor_service_test.tscn'
) | Select-Object -Unique)

# September 9 closure: persist the new integration boundaries in critical.
# Performance probes stay explicit because their sampling needs a controlled
# machine window; they are not correctness gates for every ordinary test run.
$Suites.critical = @($Suites.critical + @(
    'tests/game_root_loading_transition_test.tscn',
    'tests/r3_gold_cap_entrypoints_test.tscn',
    'tests/w1_exact_ranged_delivery_test.tscn',
    'tests/monster_mixed_damage_atomic_test.tscn',
    'tests/monster_source_status_test.tscn',
    'tests/headless_prefetch_compatibility_test.tscn',
    'tests/hc_monster_ai/geometry_test.tscn',
    'tests/hc_monster_ai/crowd_surround_runtime_test.tscn',
    'tests/hc_monster_ai/w1_delivery_geometry_test.tscn',
    'tests/hc_monster_ai/w1_special_delivery_runtime_test.tscn',
    'tests/hc_monster_ai/inventory_test.tscn',
    'tests/hc_monster_ai/lightning_test.tscn',
    'tests/hc_monster_ai/path_test.tscn',
    'tests/hc_monster_ai/scheduler_storm_test.tscn',
    'tests/hc_monster_ai/runtime_test.tscn',
    'tests/hc_monster_ai/world_obstacle_runtime_test.tscn',
    'tests/hc_monster_ai/combat_epoch_delivery_test.tscn',
    'tests/w6_visual_contract_test.tscn',
    'tests/equipment_inventory_slot_swap_test.tscn',
    'tests/combat_environment_request_integration_test.tscn',
    'tests/loot_world_placement_integration_test.tscn',
    'tests/item_drop_instance_rules_test.tscn',
    'tests/item_drop_instance_persistence_test.tscn',
    'tests/warrior_slaying_release_integration_test.tscn',
    'tests/audio_w4_actor_service_test.tscn',
    'tests/audio_w4_contract_test.tscn',
    'tests/inventory_equipment_ui_test.tscn',
    'tests/warehouse_gothic_ui_test.tscn',
    'tests/shop_gothic_ui_test.tscn',
    'tests/shared_warehouse_transaction_test.tscn',
    'tests/shared_warehouse_migration_test.tscn'
) | Select-Object -Unique)

# September 18 R1.1 closure: the error-feedback boundary and the player
# overhead status-marker presentation are permanent regression gates. The R1
# versions of these tests existed but were never registered here; they are
# registered now together with the corrected marker-row tests.
$Suites.critical = @($Suites.critical + @(
    'tests/ui_error_feedback_scope_guard_test.tscn',
    'tests/ui_error_machine_reason_leak_test.tscn',
    'tests/ui_error_feedback_overlay_test.tscn',
    'tests/repair_20260913/inventory_error_feedback_real_input_test.tscn',
    'tests/player_poison_presentation_test.tscn',
    'tests/player_health_bar_status_marker_test.tscn'
) | Select-Object -Unique)

# September 18 UNIFIED-PLAYER-NOTICE R2: the unified central notice layer is a
# permanent regression gate. The overlay/contract tests run in critical; the
# real-input notice tests also join the equipment lane (§38).
$Suites.critical = @($Suites.critical + @(
    'tests/player_notice_overlay_test.tscn',
    'tests/player_notice_item_style_test.tscn',
    'tests/player_notice_dedupe_priority_test.tscn',
    'tests/player_notice_action_result_contract_test.tscn',
    'tests/equipment_success_notice_real_input_test.tscn',
    'tests/skill_learning_notice_real_input_test.tscn'
) | Select-Object -Unique)

# September 22 user loot sheet authority: the compiled spreadsheet is the sole
# production drop probability source. The sheet contract and the retired-chain
# production gate are permanent regression gates.
$Suites.critical = @($Suites.critical + @(
    'tests/user_loot_sheet_authority_test.tscn',
    'tests/dpv2_drop_runtime_policy_test.tscn'
) | Select-Object -Unique)

$Suites.equipment = @($Suites.equipment + @(
    'tests/player_notice_item_style_test.tscn',
    'tests/equipment_success_notice_real_input_test.tscn'
) | Select-Object -Unique)

# ── Q0-A: final judgement contract ──
$Suites.critical = @($Suites.critical + @(
    'tests/formal_map_destination_regression_test.tscn',
    'tests/game_root_fail_map_transition_test.tscn',
    'tests/formal_map_spawn_policy_test.tscn',
    'tests/wall_render_binding_test.tscn',
    'tests/monster_continuous_step_facing_test.tscn',
    'tests/monster_empty_safe_zone_fast_path_test.tscn',
    'tests/monster_idle_acquisition_budget_test.tscn',
    'tests/monster_idle_scan_cadence_test.tscn',
    'tests/boss_respawn_map_reentry_test.tscn',
    'tests/skill_visual_cold_lifecycle_test.tscn',
    'tests/magic_shield_map_lifecycle_test.tscn',
    'tests/wall_render_publisher_snapshot_test.tscn',
    'tests/hud_script_prefetch_exit_test.tscn',
    'tests/random_teleport_destination_contract_test.tscn',
    'tests/player_struck_release_order_test.tscn',
    'tests/player_skill_struck_chain_test.tscn',
    'tests/player_hit_reaction_policy_test.tscn',
    'tests/player_enemy_struck_chain_e2e_test.tscn',
    'tests/player_struck_scene_sweep_test.tscn',
    'tests/player_struck_lock_test.tscn',
    'tests/camera_black_budget_region_test.tscn',
    'tests/map_diamond_camera_constraint_test.tscn',
    'tests/map_diamond_camera_strict_edge_test.tscn',
    'tests/game_root_diamond_camera_constraint_test.tscn',
    'tests/live_map_loot_authority_export_test.tscn',
    'tests/armor_single_slot_authority_test.tscn',
    'tests/repair_20260913/loot_async_durability_test.tscn'
) | Select-Object -Unique)

# v92 production regressions and previously unregistered live consumers.
$Suites.critical = @($Suites.critical + @(
    'tests/device_lab_local_capture_test.tscn',
    'tests/player_growth_live_runtime_test.tscn',
    'tests/skill_runtime_classification_test.tscn',
    'tests/skill_target_context_partition_test.tscn',
    'tests/fire_wall_animation_batch_test.tscn',
    'tests/fire_wall_release_owner_result_test.tscn',
    'tests/hellfire_catchup_batch_test.tscn',
    'tests/player_physical_defense_production_test.tscn',
    'tests/taoist_passive_accuracy_production_test.tscn',
    'tests/summon_outgoing_defense_production_test.tscn',
    'tests/summon_growth_rank_upgrade_test.tscn',
    'tests/taoist_summon_growth_contract_test.tscn',
    'tests/ui_result_feedback_timing_test.tscn',
    'tests/hidden_inventory_stats_refresh_test.tscn',
    'tests/progression_loot_20260913/drop_balance_test.tscn',
    'tests/loot_ui_20260914/runtime_followup_test.tscn',
    'tests/repair_20260913/warehouse_prepared_transaction_test.tscn',
    'tests/repair_20260913/bank_prepared_transaction_test.tscn',
    'tests/character_delete_transaction_test.tscn',
    'tests/player_world_position_unit_migration_test.tscn',
    'tests/loot_ui_20260914/settings_function_test.tscn',
    'tests/ui_r5_audio_config_strict_test.tscn',
    'tests/ui_r5_audio_test.tscn',
    'tests/touch_scroll_support_test.tscn',
    'tests/character_select_touch_scroll_test.tscn',
    'tests/r6_1_review/shop_selection_identity_test.tscn',
    'tests/quest_gothic_ui_test.tscn',
    'tests/death_revival_gothic_ui_test.tscn',
    'tests/system_menu_gothic_ui_test.tscn',
    'tests/town_music_runtime_test.tscn',
    'tests/equipment_skill_level_affix_test.tscn',
    'tests/world_background_staged_map_build_test.tscn',
    'tests/mse_collision_grid_alignment_test.tscn'
) | Select-Object -Unique)

# September 25-26 HC-MONSTER-COMBAT-R1 + HC-BODY-2TIER-1P5-V1: the monster
# attack timing boundaries, dual-direction struck presentation, non-positive
# damage boundary, atomic death commit and the two-tier footsole body system
# are permanent regression gates.
$Suites.critical = @($Suites.critical + @(
    'tests/hc_monster_combat_r1/boss_interval_test.tscn',
    'tests/hc_monster_combat_r1/player_visual_duration_test.tscn',
    'tests/hc_monster_combat_r1/player_poison_reapply_test.tscn',
    'tests/hc_monster_combat_r1/attack_presentation_backlog_test.tscn',
    'tests/hc_monster_combat_r1/continuous_magic_walk_delay_test.tscn',
    'tests/hc_monster_combat_r1/damage_boundary_test.tscn',
    'tests/hc_monster_combat_r1/death_reentry_test.tscn',
    'tests/hc_monster_combat_r1/actor_body_policy_contract_test.tscn',
    'tests/hc_monster_combat_r1/actor_body_projection_test.tscn',
    'tests/hc_monster_combat_r1/monster_melee_body_pair_test.tscn',
    'tests/hc_monster_combat_r1/summon_body_spawn_consistency_test.tscn',
    'tests/hc_monster_combat_r1/monster_crowd_scale_performance_probe_test.tscn'
) | Select-Object -Unique)

# September 26 HC-MONSTER-COMBAT-R2: identity-bound body resolution,
# fail-closed rejection, attack presentation identity/logic clocks and the
# R2 regression gates are permanent.
$Suites.critical = @($Suites.critical + @(
    'tests/hc_monster_combat_r2/monster_body_rejection_test.tscn',
    'tests/hc_monster_combat_r2/revival_durability_test.tscn',
    'tests/hc_monster_combat_r2/attack_presentation_identity_test.tscn',
    'tests/hc_monster_combat_r2/attack_clock_red_test.tscn',
    'tests/hc_monster_combat_r2/direct_magic_step_chain_test.tscn',
    'tests/hc_monster_combat_r2/player_struck_poison_chain_test.tscn',
    'tests/hc_monster_combat_r2/monster_runtime_census_test.tscn',
    'tests/hc_monster_combat_r2/large_body_swing_cadence_test.tscn'
) | Select-Object -Unique)

# v93 CPU query correctness gates; the timed crowd matrix remains opt-in.
$Suites.critical = @($Suites.critical + @(
    'tests/melee_blocked_query_order_test.tscn',
    'tests/polygon_query_streaming_test.tscn'
) | Select-Object -Unique)

# F03 world-clock delta and real persistence/old-character recovery gates.
$Suites.critical = @($Suites.critical + @(
    'tests/world_monster_clock_ledger_test.tscn',
    'tests/world_monster_clock_persistence_test.tscn',
    'tests/world_monster_clock_legacy_migration_test.tscn',
    'tests/f03_hot_persistence_test.tscn',
    'tests/f03_world_delta_compatibility_test.tscn',
    'tests/f03_background_writer_test.tscn',
    'tests/f03_pickup_receipt_lifecycle_test.tscn',
    'tests/f03_warehouse_receipt_boundary_test.tscn',
    'tests/f03_native_pickup_lifecycle_test.tscn',
    'tests/f03_ordered_cleanup_test.tscn',
    'tests/f03_periodic_background_save_test.tscn',
    'tests/f05_settlement_display_separation_test.tscn',
    'tests/f03_async_death_receipt_test.tscn',
    'tests/f03_native_death_lifecycle_test.tscn',
    'tests/portal_actual_arrival_guard_test.tscn',
    'tests/portal_all_map_authoring_footprint_test.tscn'
) | Select-Object -Unique)

# Independent R4 body-index boundaries and real Boss hit/miss outcomes.
$Suites.critical = @($Suites.critical + @(
    'tests/hc_monster_combat_r4/body_radius_bucket_boundary_test.tscn',
    'tests/hc_monster_combat_r4/body_radius_index_consistency_test.tscn',
    'tests/classic_boss_area_magic_outcomes_test.tscn'
) | Select-Object -Unique)

# Integrated forge, relic and expanded Taoist summon production contracts.
$Suites.critical = @($Suites.critical + @(
    'tests/ancient_relic_fragment_test.tscn',
    'tests/equipment_enhancement_black_iron_test.tscn',
    'tests/equipment_enhancement_display_test.tscn',
    'tests/equipment_enhancement_grade_test.tscn',
    'tests/equipment_enhancement_material_notice_test.tscn',
    'tests/equipment_enhancement_panel_flow_test.tscn',
    'tests/equipment_enhancement_rules_test.tscn',
    'tests/equipment_enhancement_transaction_test.tscn',
    'tests/forge_persistence_roundtrip_test.tscn',
    'tests/new_item_icon_surfaces_test.tscn',
    'tests/equipment_skill_level_affix_rollout_test.tscn',
    'tests/forge_calibrator_save_test.tscn',
    'tests/forge_hud_target_occlusion_test.tscn',
    'tests/forge_panel_layout_test.tscn',
    'tests/relic_synthesis_runtime_test.tscn',
    'tests/skeleton_multi_performance_test.tscn',
    'tests/skeleton_multi_summon_contract_test.tscn',
    'tests/skills/skill_rank_zero_three_matrix_test.tscn',
    'tests/synthesis_panel_preview_test.tscn',
    'tests/f03_workbench_receipt_boundary_test.tscn',
    'tests/immediate_item_save_test.tscn',
    'tests/player_bich_roadblock_escape_test.tscn',
    'tests/skills/player_character_ground_movement_test.tscn',
    'tests/workbench_any_slot_test.tscn',
    'tests/relic_equipped_actor_test.tscn',
    'tests/relic_combat_entry_test.tscn',
    'tests/skill_mechanics_description_test.tscn',
    'tests/skill_panel_combat_unit_test.tscn'
) | Select-Object -Unique)

# R3 takeover: keep the three R2 runtime fixtures and every stable R3 gate.
# Mutation scenes intentionally fail and belong only to the negative battery.
$Source176R3StableGates = @(
    'tests/source176_r2/shared_permission_runtime_test.tscn',
    'tests/source176_r2/exact_leg_runtime_test.tscn',
    'tests/source176_r2/natural_approach_runtime_test.tscn',
    'tests/source176_r3/exact_leg_and_corridor_test.tscn',
    'tests/source176_r3/eight_direction_admission_test.tscn',
    'tests/source176_r3/box_snapshot_consumer_test.tscn',
    'tests/source176_r3/source_permission_lifecycle_test.tscn',
    'tests/source176_r3/source_game_clock_trace_test.tscn',
    'tests/source176_r3/source_idle_wake_phase_test.tscn',
    'tests/source176_r3/source_idle_3_test.tscn',
    'tests/source176_r3/source_idle_10_test.tscn',
    'tests/source176_r3/source_direct_phase_trace_test.tscn',
    'tests/source176_r3/cold_hot_action_phase_test.tscn',
    'tests/source176_r3/body_action_owner_matrix_test.tscn',
    'tests/source176_r3/area_parent_admission_test.tscn',
    'tests/source176_r3/movement_frame_budget_test.tscn',
    'tests/source176_r3/published_map_approach_test.tscn',
    'tests/source176_r3/all_skill_reaction_paths_test.tscn',
    'tests/source176_r3/identity_export_test.tscn'
    'tests/source176_r3/target_magic_admission_test.tscn',
    'tests/source176_r3/direct_reception_edges_test.tscn',
    'tests/source176_r3/release_lifecycle_test.tscn',
    'tests/source176_r3/render_sequence_test.tscn',
    'tests/source176_r3/ordinary_body_clearance_test.tscn',
    'tests/source176_r3/point_motor_path_test.tscn',
    'tests/source176_r3/cadence_fast_path_test.tscn',
    'tests/source176_r3/c05_native_detour_test.tscn'
)
$Suites.monster = @($Suites.monster + $Source176R3StableGates | Select-Object -Unique)
$Suites.critical = @($Suites.critical + $Source176R3StableGates | Select-Object -Unique)
$Source176R3GateMembership = @($Suites.critical | Where-Object { $_ -in $Source176R3StableGates })
if ($Source176R3GateMembership.Count -ne $Source176R3StableGates.Count -or
    @($Source176R3GateMembership | Group-Object | Where-Object { $_.Count -ne 1 }).Count -ne 0) {
    throw 'R3 stable critical membership is incomplete or duplicated'
}

# User additions are stable gates, with exact membership; no mutation cases.
$UserFeedbackGates = @(
    'tests/user_feedback_20260930/consumable_icon_surfaces_test.tscn',
    'tests/user_feedback_20260930/corner_wait_requirement_test.tscn',
    'tests/user_feedback_20260930/crowd_fractional_escape_test.tscn',
    'tests/user_feedback_20260930/crowd_position_candidates_test.tscn',
    'tests/user_feedback_20260930/crowd_recovery_30_test.tscn',
    'tests/user_feedback_20260930/crowd_recovery_4_test.tscn',
    'tests/user_feedback_20260930/crowd_recovery_8_test.tscn',
    'tests/user_feedback_20260930/crowd_recovery_test.tscn',
    'tests/user_feedback_20260930/flank_committed_segment_test.tscn',
    'tests/user_feedback_20260930/flank_projection_residual_test.tscn',
    'tests/user_feedback_20260930/full_surround_24_fractional_test.tscn',
    'tests/user_feedback_20260930/full_surround_64_test.tscn',
    'tests/user_feedback_20260930/full_surround_89_fractional_test.tscn',
    'tests/user_feedback_20260930/full_surround_89_prefilled_test.tscn',
    'tests/user_feedback_20260930/full_surround_89_test.tscn',
    'tests/user_feedback_20260930/full_surround_mixed_test.tscn',
    'tests/user_feedback_20260930/full_surround_moving_test.tscn',
    'tests/user_feedback_20260930/full_surround_native_test.tscn',
    'tests/user_feedback_20260930/full_surround_prefilled_test.tscn',
    'tests/user_feedback_20260930/full_surround_west_wall_test.tscn',
    'tests/user_feedback_20260930/immediate_warrior_toggle_save_test.tscn',
    'tests/user_feedback_20260930/large_surround_packing_test.tscn',
    'tests/user_feedback_20260930/monster_blocked_locomotion_test.tscn',
    'tests/user_feedback_20260930/motion_candidate_reuse_test.tscn',
    'tests/user_feedback_20260930/player_blocked_locomotion_test.tscn',
    'tests/user_feedback_20260930/surround_vacancy_refill_89_test.tscn',
    'tests/user_feedback_20260930/surround_target_body_route_test.tscn',
    'tests/user_feedback_20260930/surround_vacancy_refill_test.tscn',
    'tests/user_feedback_20260930/warrior_toggle_camera_native_test.tscn'
)
if ($UserFeedbackGates.Count -ne 29 -or ($UserFeedbackGates | Sort-Object -Unique).Count -ne 29) {
    throw 'User feedback gate membership must contain exactly 29 unique scenes'
}
$Suites.user_feedback_20260930 = $UserFeedbackGates
$Suites.source176_r3 = @($Source176R3StableGates + $Source176R3Scenes | Select-Object -Unique)
$Suites.monster = @($Suites.monster + $UserFeedbackGates | Select-Object -Unique)
$Suites.critical = @($Suites.critical + $UserFeedbackGates | Select-Object -Unique)

# 2026-10-06 third-tree architecture closeout (baseline 272430b36): register
# the new structural proofs — the S2 capacity trifold and birth-closure
# combination, the S3 resource scene-change immediate failure, the S4
# residency latency distribution, and the DOT replace contract.
$ThirdTree20261006 = @(
    'tests/framework/feature_capacity_trifold_test.tscn',
    'tests/feature_birth_capacity_combination_test.tscn',
    'tests/framework/feature_resource_scene_change_failure_test.tscn',
    'tests/framework/feature_residency_latency_distribution_test.tscn',
    'tests/framework/dot_replace_contract_test.tscn'
)
if ($ThirdTree20261006.Count -ne 5 -or ($ThirdTree20261006 | Sort-Object -Unique).Count -ne 5) {
    throw 'thirdtree_20261006 membership must contain exactly 5 unique scenes'
}
foreach ($scene in $ThirdTree20261006) {
    if (-not (Test-Path (Join-Path $ProjectRoot $scene))) {
        throw "thirdtree_20261006 registered scene is missing on disk: $scene"
    }
}
$Suites.thirdtree_20261006 = $ThirdTree20261006
$Suites.critical = @($Suites.critical + $ThirdTree20261006 | Select-Object -Unique)

# Re-audit the fully assembled critical suite for the R31 contract after all
# later domain extensions have run. This catches accidental removal, shadowing
# by another block, or duplicate registration.
$Source176R3CriticalMembers = @($Suites.critical | Where-Object { $_ -match $Source176R3PathPattern })
if ($Source176R3CriticalMembers.Count -ne 48) {
	throw "source176_r3 critical registration must contain exactly 48 members, found $($Source176R3CriticalMembers.Count)"
}
$Source176R3MemberCounts = $Source176R3CriticalMembers | Group-Object
$Source176R3Duplicates = @($Source176R3MemberCounts | Where-Object { $_.Count -ne 1 })
if ($Source176R3Duplicates.Count -ne 0) {
	throw "source176_r3 critical registration contains duplicates: $(($Source176R3Duplicates | ForEach-Object { $_.Name }) -join ', ')"
}
$Source176R3MissingFromCritical = @($Source176R3Scenes | Where-Object { $_ -notin $Source176R3CriticalMembers })
if ($Source176R3MissingFromCritical.Count -ne 0) {
	throw "source176_r3 critical registration is missing scenes: $(($Source176R3MissingFromCritical) -join ', ')"
}
$Source176R3CriticalEvidence = [ordered]@{
	contract = 'source176.r3.critical_membership.v1'
	count = $Source176R3CriticalMembers.Count
	unique_count = ($Source176R3CriticalMembers | Sort-Object -Unique).Count
	manifest_count = $Source176R3Scenes.Count
	missing = @($Source176R3MissingFromCritical)
	duplicates = @($Source176R3Duplicates | ForEach-Object { $_.Name })
	members = @($Source176R3CriticalMembers | Sort-Object)
	stable_gates = @($Source176R3GateMembership | Sort-Object)
	user_feedback_gates = @($UserFeedbackGates | Sort-Object)
	full_critical_members = @($Suites.critical | Sort-Object)
}
$Source176R3EvidenceDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'outputs/test_logs/source176_r3'
New-Item -ItemType Directory -Force -Path $Source176R3EvidenceDir | Out-Null
$Source176R3CriticalEvidence | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Source176R3EvidenceDir 'critical_members.json') -Encoding UTF8

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
$Suites.pricing_authority = @(
	'tests/pricing_authority_test.tscn',
	'tests/hud_authority_integration_test.tscn',
	'tests/shop_gothic_ui_test.tscn'
)

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
    if ($RunnerIsLinux) {
        if ($null -ne $LinuxNativeProcess) {
            $owned = @(Get-LinuxOwnedGroupProcesses)
            if ($ProcessId -eq $LinuxNativeProcess.Id -or $ProcessId -in $owned.Id) {
                $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(2)
                $reapIds = [Collections.Generic.HashSet[int]]::new()
                do {
                    $owned = @(Get-LinuxOwnedGroupProcesses)
                    if (@($owned | Where-Object { $_.PrivateGroup }).Count -gt 0) {
                        [HardCoreNativeSignals]::kill(-$LinuxNativeProcess.Id, 9) | Out-Null
                    }
                    foreach ($child in @($owned | Where-Object { -not $_.PrivateGroup })) {
                        if ([HardCoreNativeSignals]::kill($child.Id, 9) -eq 0) { $reapIds.Add($child.Id) | Out-Null }
                    }
                    if (-not $LinuxNativeProcess.HasExited) {
                        try { $LinuxNativeProcess.Kill($true) }
                        catch { if (-not $LinuxNativeProcess.HasExited) { $script:LinuxCleanupIncomplete = $true } }
                    }
                    foreach ($childId in @($reapIds)) {
                        $childStatus = 0
                        if ([HardCoreNativeSignals]::waitpid($childId, [ref]$childStatus, 1) -ne 0) { $reapIds.Remove($childId) | Out-Null }
                    }
                    $remaining = @(Get-LinuxOwnedGroupProcesses)
                    if ($remaining.Count -gt 0 -or $reapIds.Count -gt 0) { Start-Sleep -Milliseconds 10 }
                } while (($remaining.Count -gt 0 -or $reapIds.Count -gt 0) -and [DateTime]::UtcNow -lt $cleanupDeadline)
                # Killing a detached parent can adopt another generation. The
                # fixed deadline covers every rescan, not a new budget per child.
                if ($remaining.Count -gt 0 -or -not $LinuxNativeProcess.HasExited) { $script:LinuxCleanupIncomplete = $true }
            }
        }
        return
    }
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        Stop-TestProcessTree -ProcessId ([int]$child.ProcessId)
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot不存在：$Godot"
}
# Test scenes write structured reports to the project-local report directory.
# Keep it available even when console/engine evidence is routed externally.
$ProjectReportRoot = Join-Path $ProjectRoot 'outputs\test_logs'
New-Item -ItemType Directory -Path $ProjectReportRoot -Force | Out-Null
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null

function Get-WorktreeGodotProcesses {
    if ($RunnerIsLinux) { return @() }
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
    if ($RunnerIsLinux) {
        return @(Get-LinuxOwnedGroupProcesses)
    }
    return @(Get-WorktreeGodotProcesses | Where-Object { $_.Id -notin $BaselineGodotIds })
}

$SelectedTests = if ($TestPaths.Count -gt 0) { $TestPaths } else { $Suites[$Suite] }
# Explicit user-approved diagnostic exception; never extends an ordinary
# scene or a whole suite. It changes only the external process window.
$Authorized90SecondScenes = @(
    'tests/hc_monster_combat_r4/all_damage_lost_test.tscn',
    'tests/hc_monster_combat_r4/natural_cadence_24_test.tscn',
    'tests/hc_monster_combat_r4/natural_cadence_76_test.tscn',
    'tests/framework/natural_sustained_chain_test.tscn',
    'tests/framework/natural_sustained_resource_test.tscn'
)
$AuthorizedSustainedColdScenes = @(
    'tests/framework/natural_sustained_chain_cold_test.tscn',
    'tests/framework/natural_sustained_resource_cold_test.tscn'
)
if ($TimeoutSeconds -gt 60) {
    if ($TimeoutSeconds -ne 90 -or $EffectiveSuite -cne 'adhoc' -or @($SelectedTests | Where-Object {
        $Authorized90SecondScenes -cnotcontains $_ -and $AuthorizedSustainedColdScenes -cnotcontains $_
    }).Count -gt 0) {
        throw 'Only the explicit user-approved diagnostic live scenes may use a 90s window, using TestPaths.'
    }
    foreach ($coldPath in $AuthorizedSustainedColdScenes) {
        if ($SelectedTests -ccontains $coldPath) {
            $livePath = $coldPath.Replace('_cold_test.tscn', '_test.tscn')
            if ([Array]::IndexOf($SelectedTests, $livePath) -lt 0 -or
                [Array]::IndexOf($SelectedTests, $livePath) -gt [Array]::IndexOf($SelectedTests, $coldPath)) {
                throw 'A sustained cold scene needs its matching live producer earlier in this invocation.'
            }
        }
    }
}

# 2026-09-21 RV14-04 (O07): Monster Streaming scenes stream chunks with real
# generation windows and exceed the 8-second default budget. Refuse before
# launching anything when the selected set includes them below 30 seconds so
# a run cannot masquerade as a timeout regression.
$MonsterStreamingBudgetFloor = 30
$MonsterStreamingMembers = $Suites.monster_streaming_critical
$SelectedIncludesStreaming = @($SelectedTests | Where-Object { $MonsterStreamingMembers -contains $_ }).Count -gt 0
if ($SelectedIncludesStreaming -and $TimeoutSeconds -lt $MonsterStreamingBudgetFloor) {
    throw (
        'Monster Streaming tests require -TimeoutSeconds {0} or higher ' +
        '(got {1}). Re-run with -TimeoutSeconds 30.' -f $MonsterStreamingBudgetFloor, $TimeoutSeconds
    )
}
$StructuredResults = @()
# One native invocation owns its live/cold evidence pair. A source hash alone
# cannot distinguish a successful prior invocation from the current failed one.
[Environment]::SetEnvironmentVariable('HARDCORE_FRAMEWORK_INVOCATION_ID', $RunnerInvocationId, 'Process')
$NativeHandoffPath = Join-Path $ProjectReportRoot 'framework\native_handoffs.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $NativeHandoffPath) -Force | Out-Null
$NativeHandoffs = [ordered]@{
    schema_version = 1
    runtime_environment = $RuntimeEnvironmentRecord
    invocation_id = $env:HARDCORE_FRAMEWORK_INVOCATION_ID
    source_content_sha256 = $env:HARDCORE_R3_CONTENT_SHA256
    producers = [ordered]@{}
}
# Reset before any child can fail early and leave a prior receipt untouched.
[IO.File]::WriteAllText($NativeHandoffPath, ($NativeHandoffs | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
foreach ($testPath in $SelectedTests) {
    $LinuxCleanupIncomplete = $false
    $LinuxOutputIncomplete = $false
    $testName = [IO.Path]::GetFileNameWithoutExtension($testPath)
    $isFramework = $testPath.Replace('\', '/') -match '^tests/framework/(?:[^/]+/)*[^/]+\.tscn$'
    if ($isFramework) {
        # An explicit test list may repeat a scene. Its second failed producer
        # must not inherit the first successful producer in this invocation.
        $NativeHandoffs.producers.Remove($testName)
        [IO.File]::WriteAllText($NativeHandoffPath, ($NativeHandoffs | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    }
    $frameworkRunId = if ($isFramework) { [Guid]::NewGuid().ToString() } else { '' }
    [Environment]::SetEnvironmentVariable('HARDCORE_FRAMEWORK_RUN_ID', $frameworkRunId, 'Process')
    $stdout = Join-Path $LogRoot "$testName.stdout.log"
    $stderr = Join-Path $LogRoot "$testName.stderr.log"
    $engineLog = Join-Path $LogRoot "$testName.godot.log"
    $engineLogArgument = $engineLog
    Remove-Item -LiteralPath $stdout, $stderr, $engineLog -Force -ErrorAction SilentlyContinue
    # Q0-A 3.2: run through cmd.exe so the final process object exposes the
    # effective exit code (the Godot console wrapper forwards the engine code,
    # but Start-Process with -Redirect* loses ExitCode on this host). Output is
    # redirected inside the command string; polling reads the same files.
    # Only the two static receiver queue-boundary fixtures couple a process
    # release timer with an exact physics expiration tick. Deterministic
    # engine stepping constructs that boundary without replacing either owner.
    # Natural combat, performance and all other scenes stay in real time.
    $BoundaryFixedFps = if ($testPath -cin @(
        'tests/framework/death_burst_lifecycle_test.tscn',
        'tests/framework/death_expiry_overlap_test.tscn'
    )) { 60 } else { 0 }
    $BoundaryClockArguments = if ($BoundaryFixedFps -eq 60) { ' --fixed-fps 60 --max-fps 60' } else { '' }
    $VerboseArgument = if ($Verbose) { ' --verbose' } else { '' }
    $launchCommand = '""' + $Godot + '" --headless' + $VerboseArgument + $BoundaryClockArguments + ' --log-file "' + $engineLogArgument + '" --path . "' + $testPath + '" > "' + $stdout + '" 2> "' + $stderr + '"'
    if ($RunnerIsLinux) {
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        # setsid exec preserves the native PID while confining its descendants
        # to an invocation-owned session/group for cleanup after parent exit.
        $startInfo.FileName = $LinuxLauncher
        $startInfo.ArgumentList.Add('--')
        $startInfo.ArgumentList.Add($Godot)
        $startInfo.WorkingDirectory = $ProjectRoot
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @('--headless')) { $startInfo.ArgumentList.Add($argument) }
        if ($Verbose) { $startInfo.ArgumentList.Add('--verbose') }
        if ($BoundaryFixedFps -eq 60) {
            foreach ($argument in @('--fixed-fps', '60', '--max-fps', '60')) { $startInfo.ArgumentList.Add($argument) }
        }
        foreach ($argument in @('--log-file', $engineLogArgument, '--path', $ProjectRoot, $testPath)) { $startInfo.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $LinuxStdoutStream = [IO.FileStream]::new($stdout, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 1)
        $LinuxStderrStream = [IO.FileStream]::new($stderr, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 1)
        try {
            if (-not $process.Start()) { throw 'Linux native engine did not start.' }
            $LinuxNativeProcess = $process
        } catch { $process.Dispose(); throw }
        $LinuxStdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($LinuxStdoutStream)
        $LinuxStderrTask = $process.StandardError.BaseStream.CopyToAsync($LinuxStderrStream)
    } else {
        $process = Start-Process -FilePath 'cmd.exe' `
            -ArgumentList @('/c', $launchCommand) `
            -WorkingDirectory $ProjectRoot -WindowStyle Hidden -PassThru
    }
    $wrapperStartedUtc = $process.StartTime.ToUniversalTime().ToString('o')
    # Natural cadence scenes observe six real 4-second attack windows plus
    # pursuit/detour physics. The 1/100/300-monster streaming scale scene
    # also runs 1800 real frames and exits normally in roughly 38 seconds.
    # Keep ordinary scenes at 30 seconds.
    $HeavyR4Scenes = @(
		'tests/monster_streaming_scaling_test.tscn',
        'tests/hc_monster_ai/runtime_test.tscn',
        'tests/hc_monster_combat_r4/d3_motion_pressure_runtime_test.tscn',
        'tests/hc_monster_combat_r4/natural_cadence_24_test.tscn',
        'tests/hc_monster_combat_r4/natural_cadence_76_test.tscn',
        'tests/hc_monster_combat_r4/natural_cadence_238_test.tscn',
        'tests/hc_monster_combat_r4/natural_cadence_239_test.tscn',
        'tests/hc_monster_combat_r4/all_damage_lost_test.tscn',
        'tests/hc_monster_combat_r4/damage_attribution_counterexamples_test.tscn',
        # Prior fixed-source 60s evidence covers these full workloads.
        'tests/source176_r3/eight_direction_admission_test.tscn',
        'tests/source176_r3/source_idle_wake_phase_test.tscn',
        'tests/source176_r3/published_map_approach_test.tscn',
        'tests/user_feedback_20260930/full_surround_24_fractional_test.tscn',
        'tests/user_feedback_20260930/full_surround_64_test.tscn',
        'tests/user_feedback_20260930/full_surround_89_fractional_test.tscn',
        'tests/user_feedback_20260930/full_surround_89_fractional_identity0_test.tscn',
        'tests/user_feedback_20260930/full_surround_89_fractional_identity1_test.tscn',
        'tests/user_feedback_20260930/full_surround_89_prefilled_test.tscn',
        'tests/user_feedback_20260930/full_surround_89_test.tscn',
        'tests/user_feedback_20260930/full_surround_mixed_test.tscn',
        'tests/user_feedback_20260930/full_surround_moving_test.tscn',
        'tests/user_feedback_20260930/full_surround_native_test.tscn',
        'tests/user_feedback_20260930/full_surround_prefilled_test.tscn',
        'tests/user_feedback_20260930/full_surround_west_wall_test.tscn',
        'tests/user_feedback_20260930/surround_vacancy_refill_89_test.tscn',
        'tests/user_feedback_20260930/surround_vacancy_refill_test.tscn'
    )
    $TestTimeoutSeconds = if ($TimeoutSeconds -eq 90 -and $testPath -in $AuthorizedSustainedColdScenes) {
        30
    } elseif ($testPath -in $HeavyR4Scenes) { [Math]::Max(60, $TimeoutSeconds) } else { $TimeoutSeconds }
    $deadline = [DateTime]::UtcNow.AddSeconds($TestTimeoutSeconds)
    $wrapperExitWithoutChildSince = $null
    $earlyFailure = $false
    $hasPassMarker = $false
    $naturalExit = $false
    $LinuxOrphanedChildren = $false
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
        if ($RunnerIsLinux -and $process.HasExited -and @(Get-NewGodotProcesses).Count -gt 0) {
            $LinuxOrphanedChildren = $true
            break
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
    # The native process must finish within its budget. A last-moment exit
    # may still be inside the wrapper handoff confirmation window above.
    # Finish only that confirmation after the deadline; never allow a live
    # engine additional execution time, and never infer exit from PASS text.
    if (-not $earlyFailure -and -not $naturalExit -and $null -ne $wrapperExitWithoutChildSince) {
        $confirmationDeadline = $wrapperExitWithoutChildSince.AddMilliseconds(1000)
        while ([DateTime]::UtcNow -lt $confirmationDeadline) {
            if (-not $process.HasExited -or @(Get-NewGodotProcesses).Count -gt 0) {
                $wrapperExitWithoutChildSince = $null
                break
            }
            Start-Sleep -Milliseconds 100
        }
        if (
            $null -ne $wrapperExitWithoutChildSince -and
            $wrapperExitWithoutChildSince -lt $deadline -and
            $process.HasExited -and @(Get-NewGodotProcesses).Count -eq 0
        ) {
            $naturalExit = $true
        }
    }
    # Q0-A 3.1: a live process at the deadline times out regardless of PASS.
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
    if ($RunnerIsLinux) {
        if (-not $process.WaitForExit(2000)) { $LinuxCleanupIncomplete = $true }
        Complete-LinuxOutput -FailOnIncomplete $false
        $LinuxStdoutStream.Dispose()
        $LinuxStderrStream.Dispose()
        $LinuxStdoutStream = $null
        $LinuxStderrStream = $null
    }
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
    if ($timedOut) { $reasons += "timeout_${TestTimeoutSeconds}s" }
    if ($earlyFailure) { $reasons += 'early_script_error' }
    if ($LinuxOrphanedChildren) { $reasons += 'lingering_native_children' }
    if ($LinuxCleanupIncomplete) { $reasons += 'native_cleanup_incomplete' }
    if ($LinuxOutputIncomplete) { $reasons += 'native_output_pipes_incomplete' }
    if ($finalEffectiveExitCode -ne 0) {
        if ($null -eq $wrapperExitCode) { $reasons += 'missing_effective_exit_code' } else { $reasons += "non_zero_exit_code_$finalEffectiveExitCode" }
    }
    if ($stdoutFailureCount -gt 0) { $reasons += "stdout_failures_$stdoutFailureCount" }
    if ($stderrFailureCount -gt 0) { $reasons += "stderr_failures_$stderrFailureCount" }
    if ($engineLogFailureCount -gt 0) { $reasons += "engine_log_failures_$engineLogFailureCount" }

    $frameworkReceipt = $null
    if ($isFramework) {
        $frameworkReceiptPath = Join-Path $ProjectReportRoot ('framework\' + $testName + '.result.json')
        $frameworkReceipt = Test-FrameworkReceipt -Path $frameworkReceiptPath -ExpectedRunId $frameworkRunId `
            -ExpectedSceneId $testName -ExpectedContentSha256 $env:HARDCORE_R3_CONTENT_SHA256
        if (-not $frameworkReceipt.valid) { $reasons += $frameworkReceipt.reasons }
        elseif ((Get-Content -LiteralPath $frameworkReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json).invocation_id -ne $env:HARDCORE_FRAMEWORK_INVOCATION_ID) {
            $reasons += 'framework_invocation_mismatch'
        }
        if ($RunnerIsLinux -and $frameworkReceipt.valid) {
            $nativeReceipt = Get-Content -LiteralPath $frameworkReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $receiptRuntime = $nativeReceipt.runtime_environment
            try { Assert-PhysicalRuntimeDirectory ([string]$receiptRuntime.user_data_directory) }
            catch { $reasons += 'framework_runtime_directory_unconfined' }
            if ($receiptRuntime.project_root -isnot [string] -or $receiptRuntime.user_data_directory -isnot [string] -or
                $receiptRuntime.native_process_id -ne $process.Id -or $nativeReceipt.engine_version -cne '4.7-stable (official)' -or
                $receiptRuntime.project_root.TrimEnd('/') -cne $ProjectRoot.TrimEnd('/') -or
                $receiptRuntime.runtime_appdata -cne $RuntimeAppData -or
                [string]::IsNullOrEmpty($receiptRuntime.user_data_directory) -or
                -not $receiptRuntime.user_data_directory.StartsWith(($RuntimeAppData.TrimEnd('/') + '/'), [StringComparison]::Ordinal)) {
                $reasons += 'framework_runtime_environment_mismatch'
            }
        }
    }
    $result = 'PASS'
    if ($reasons.Count -gt 0) {
        $result = 'FAIL'
    }
    $StructuredResults += [ordered]@{
        test_name = $testName
        test_path = $testPath
        wrapper_process_id = $process.Id
        wrapper_started_utc = $wrapperStartedUtc
        runtime_appdata = $RuntimeAppData
        fixed_fps = $BoundaryFixedFps
        pass_marker_found = $hasPassMarker
        process_exited = $processExited
        wrapper_exit_code = $wrapperExitCode
        child_process_exit_state = $childProcessExitState
        execution_deadline_utc = $deadline.ToString('o')
        native_exit_observed_utc = if ($null -ne $wrapperExitWithoutChildSince) { $wrapperExitWithoutChildSince.ToString('o') } else { $null }
        effective_exit_code = $finalEffectiveExitCode
        timeout = $timedOut
        stdout_failure_count = $stdoutFailureCount
        stderr_failure_count = $stderrFailureCount
        engine_log_failure_count = $engineLogFailureCount
        framework_run_id = $frameworkRunId
        framework_receipt_valid = if ($isFramework) { $frameworkReceipt.valid } else { $null }
        result = $result
        reason = ($reasons -join ';')
    }
    if ($isFramework -and $result -eq 'PASS') {
        # The child cannot attest to its own native exit. Only this validated
        # runner result makes its exact receipt eligible for a later cold test.
        $ReceiptHasher = [Security.Cryptography.SHA256]::Create()
        try { $ReceiptHash = [BitConverter]::ToString($ReceiptHasher.ComputeHash([IO.File]::ReadAllBytes($frameworkReceiptPath))).Replace('-', '').ToLowerInvariant() }
        finally { $ReceiptHasher.Dispose() }
        $NativeHandoffs.producers[$testName] = [ordered]@{
            scene_id = $testName
            run_id = $frameworkRunId
            source_content_sha256 = $env:HARDCORE_R3_CONTENT_SHA256
            process_exited = $processExited
            effective_exit_code = $finalEffectiveExitCode
            result = $result
            receipt_sha256 = $ReceiptHash
        }
        [IO.File]::WriteAllText($NativeHandoffPath, ($NativeHandoffs | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    }
    if ($result -eq 'FAIL') {
        $reason = if ($reasons.Count -gt 0) { $reasons -join ';' } else { 'unknown' }
        Write-Host "[FAIL] $testName - $reason" -ForegroundColor Red
        if ($outText) { Write-Host $outText.Trim() }
        if ($errText) { Write-Host $errText.Trim() }
    } else {
        Write-Host "[PASS] $testName" -ForegroundColor Green
    }
    if ($env:HARDCORE_AUDIT_EVIDENCE_ROOT) {
        # Archive before the next scene can overwrite a repeated producer's
        # receipt or logs. Every attempt retains its own native association.
        $attemptId = if ($frameworkRunId) { $frameworkRunId } else { [Guid]::NewGuid().ToString() }
        $attemptRoot = Join-Path $env:HARDCORE_AUDIT_EVIDENCE_ROOT $attemptId
        New-Item -ItemType Directory -Path $attemptRoot -Force | Out-Null
        foreach ($artifact in @($stdout, $stderr, $engineLog, $NativeHandoffPath)) {
            if (Test-Path -LiteralPath $artifact -PathType Leaf) { Copy-Item -LiteralPath $artifact -Destination $attemptRoot }
        }
        $StructuredResults[-1] | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $attemptRoot 'native_result.json') -Encoding UTF8
        if ($isFramework) {
            # Preserve the exact receipt consulted by the gate even when it
            # is malformed or stale; native_result records its rejection.
            if (Test-Path -LiteralPath $frameworkReceiptPath -PathType Leaf) {
                Copy-Item -LiteralPath $frameworkReceiptPath -Destination $attemptRoot
            }
            foreach ($artifact in @(
                (Join-Path (Split-Path -Parent $frameworkReceiptPath) (($testName -replace '_test$', '') + '_trace.json')),
                (Join-Path (Split-Path -Parent $frameworkReceiptPath) (($testName -replace '_test$', '') + '_expected.json')))) {
                if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { continue }
                try { $ownedArtifact = Get-Content -LiteralPath $artifact -Raw -Encoding UTF8 | ConvertFrom-Json }
                catch { continue }
                if ($ownedArtifact.run_id -ceq $frameworkRunId -or $ownedArtifact.producer_run_id -ceq $frameworkRunId) {
                    Copy-Item -LiteralPath $artifact -Destination $attemptRoot
                }
            }
        }
    }
    if ($RunnerIsLinux) { $process.Dispose(); $LinuxNativeProcess = $null }
}

$passedCount = @($StructuredResults | Where-Object { $_.result -eq 'PASS' }).Count
$failedCount = @($StructuredResults | Where-Object { $_.result -eq 'FAIL' }).Count
$engineLogErrorTotal = 0
foreach ($resultEntry in $StructuredResults) {
    $engineLogErrorTotal += [int]$resultEntry.engine_log_failure_count
}
$resultsFilePath = Join-Path $LogRoot ("runner_results_{0}_{1}_{2}.json" -f $EffectiveSuite, (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $PID)
@{
    suite = $EffectiveSuite
    invocation_id = $env:HARDCORE_FRAMEWORK_INVOCATION_ID
    runtime_environment = $RuntimeEnvironmentRecord
    generated_at = (Get-Date -Format o)
    git_head = (& git -C $ProjectRoot rev-parse HEAD 2>$null | Out-String).Trim()
    total = $StructuredResults.Count
    passed = $passedCount
    failed = $failedCount
    engine_log_errors = $engineLogErrorTotal
    results = $StructuredResults
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultsFilePath -Encoding UTF8
Write-Host "RUNNER_RESULTS_JSON=$resultsFilePath"
Write-Host "TEST_SUMMARY suite=$EffectiveSuite passed=$passedCount failed=$failedCount engine_log_errors=$engineLogErrorTotal"
Stop-NewGodotProcesses
if ($failedCount -gt 0) {
    $failedNames = @($StructuredResults | Where-Object { $_.result -eq 'FAIL' } | ForEach-Object { "$($_.test_name) ($($_.reason))" }) -join '; '
    Write-Host ("FAILED_TESTS=" + $failedNames) -ForegroundColor Red
    exit 1
}
exit 0
} finally {
    if ($null -ne $LinuxNativeProcess) {
        Stop-TestProcessTree -ProcessId $LinuxNativeProcess.Id
        Complete-LinuxOutput -FailOnIncomplete $false
        $LinuxNativeProcess.Dispose()
    }
    if ($null -ne $LinuxStdoutStream) { $LinuxStdoutStream.Dispose() }
    if ($null -ne $LinuxStderrStream) { $LinuxStderrStream.Dispose() }
    if ($FrameworkEnvironmentCaptured) {
        [Environment]::SetEnvironmentVariable('HARDCORE_FRAMEWORK_RUN_ID', $PreviousFrameworkRunId, 'Process')
        [Environment]::SetEnvironmentVariable('HARDCORE_FRAMEWORK_INVOCATION_ID', $PreviousFrameworkInvocationId, 'Process')
    }
    if ($RunnerLockHeld) { $RunnerMutex.ReleaseMutex() }
    $RunnerMutex.Dispose()
}
