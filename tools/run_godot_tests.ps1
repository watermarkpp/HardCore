param(
    [ValidateSet('critical', 'warrior', 'bich', 'equipment', 'monster')]
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

$Suites.critical = @(
    'tests/combat_unit_runtime_static_audit_test.tscn'
) + @(
    $Suites.caster_visual_critical +
    $Suites.warrior + $Suites.bich + $Suites.equipment + $Suites.monster |
        Select-Object -Unique
)

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
$failed = @()
$passed = @()
foreach ($testPath in $SelectedTests) {
    $testName = [IO.Path]::GetFileNameWithoutExtension($testPath)
    $stdout = Join-Path $LogRoot "$testName.stdout.log"
    $stderr = Join-Path $LogRoot "$testName.stderr.log"
    $engineLog = Join-Path $LogRoot "$testName.godot.log"
    $engineLogArgument = "outputs/test_logs/$testName.godot.log"
    Remove-Item -LiteralPath $stdout, $stderr, $engineLog -Force -ErrorAction SilentlyContinue
    $process = Start-Process -FilePath $Godot `
        -ArgumentList @('--headless', '--log-file', $engineLogArgument, '--path', '.', $testPath) `
        -WorkingDirectory $ProjectRoot -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $wrapperExitWithoutChildSince = $null
    $earlyFailure = $false
    $hasPassMarker = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $currentOutput = if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue } else { '' }
        $currentError = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($currentError -match 'SCRIPT ERROR:|Parse Error:|Assertion failed:') {
            $earlyFailure = $true
            Stop-TestProcessTree -ProcessId $process.Id
            break
        }
        if ($currentOutput -match '[A-Z0-9_]+_PASS') {
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
                break
            }
        } else {
            $wrapperExitWithoutChildSince = $null
        }
    }
    $timedOut = -not $earlyFailure -and -not $hasPassMarker -and [DateTime]::UtcNow -ge $deadline
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
    $hasPassMarker = $outText -match '[A-Z0-9_]+_PASS'
    $hasFailure = $earlyFailure -or $timedOut -or $errText -match 'SCRIPT ERROR:|Parse Error:|Assertion failed:' -or -not $hasPassMarker
    if ($hasFailure) {
        $reason = if ($timedOut) { "超时${TimeoutSeconds}s" } elseif ($earlyFailure) { '断言/脚本错误' } elseif (-not $hasPassMarker) { '缺少PASS标记' } else { '脚本错误' }
        $failed += "$testName ($reason)"
        Write-Host "[FAIL] $testName - $reason" -ForegroundColor Red
        if ($outText) { Write-Host $outText.Trim() }
        if ($errText) { Write-Host $errText.Trim() }
    } else {
        $passed += $testName
        Write-Host "[PASS] $testName" -ForegroundColor Green
    }
}

Write-Host "TEST_SUMMARY suite=$Suite passed=$($passed.Count) failed=$($failed.Count)"
Stop-NewGodotProcesses
if ($failed.Count -gt 0) {
    Write-Host ("FAILED_TESTS=" + ($failed -join '; ')) -ForegroundColor Red
    exit 1
}
exit 0
