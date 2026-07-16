param(
    [ValidateSet('critical', 'warrior', 'bich', 'equipment', 'monster')]
    [string]$Suite = 'critical',
    [int]$TimeoutSeconds = 8,
    [string[]]$TestPaths = @()
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'

$Suites = @{
    monster = @(
		'tests/monster_id_contract_test.tscn',
		'tests/classic_boss_order_test.tscn',
		'tests/monster_threat_animation_test.tscn',
		'tests/bich_monster_visual_test.tscn',
		'tests/bich_common_client_art_test.tscn',
		'tests/bich_route_monster_test.tscn',
		'tests/bich_undead_client_art_test.tscn',
		'tests/skeleton_spirit_boss_test.tscn',
		'tests/corpse_king_boss_test.tscn',
		'tests/crowd_grounding_test.tscn',
		'tests/placeholder_attack_animation_test.tscn'
	)
    warrior = @(
		'tests/complete_client_resource_catalog_test.tscn',
		'tests/player_movement_respawn_test.tscn',
		'tests/warrior_wear_mapping_test.tscn',
        'tests/warrior_service_formula_test.tscn',
        'tests/warrior_skill_state_machine_test.tscn',
        'tests/warrior_client_art_test.tscn',
        'tests/skill_combat_profile_test.tscn',
        'tests/warrior_attack_timing_test.tscn',
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
		'tests/bich_hard_boundary_test.tscn',
		'tests/bich_content_1_test.tscn',
		'tests/bich_map_3_runtime_bridge_test.tscn',
		'tests/architecture_final_test.tscn',
		'tests/five_layer_architecture_test.tscn',
		'tests/bich_community_baseline_test.tscn',
		'tests/map_coordinate_mapping_test.tscn',
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
        'tests/equipment_slot_migration_test.tscn',
        'tests/item_catalog_test.tscn',
        'tests/vertical_slice_loop_test.tscn',
        'tests/android_layout_test.tscn'
    )
}
$Suites.critical = @($Suites.warrior + $Suites.bich + $Suites.equipment + $Suites.monster | Select-Object -Unique)

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
$BaselineGodotIds = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' } | Select-Object -ExpandProperty Id)

function Stop-NewGodotProcesses {
    $newProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like 'Godot*' -and $_.Id -notin $BaselineGodotIds
    })
    foreach ($newProcess in $newProcesses) {
        Stop-TestProcessTree -ProcessId $newProcess.Id
    }
}

$SelectedTests = if ($TestPaths.Count -gt 0) { $TestPaths } else { $Suites[$Suite] }
$failed = @()
$passed = @()
foreach ($testPath in $SelectedTests) {
    $testName = [IO.Path]::GetFileNameWithoutExtension($testPath)
    $stdout = Join-Path $LogRoot "$testName.stdout.log"
    $stderr = Join-Path $LogRoot "$testName.stderr.log"
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    $process = Start-Process -FilePath $Godot `
        -ArgumentList @('--headless', '--path', '.', $testPath) `
        -WorkingDirectory $ProjectRoot -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $earlyFailure = $false
    while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $currentError = if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($currentError -match 'SCRIPT ERROR:|Parse Error:|Assertion failed:') {
            $earlyFailure = $true
            Stop-TestProcessTree -ProcessId $process.Id
            break
        }
    }
    $timedOut = -not $process.HasExited -and -not $earlyFailure
    if ($timedOut) {
        Stop-TestProcessTree -ProcessId $process.Id
    }
    Stop-NewGodotProcesses
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
