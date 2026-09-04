param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$Runner = Join-Path $ProjectRoot 'tools\run_godot_tests.ps1'
$PythonCommand = Get-Command py -ErrorAction SilentlyContinue
$PythonArguments = @('-3.12')
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\runtime_appdata_dpv2_final_gate'
$SemanticValidator = Join-Path $ProjectRoot 'tools\validate_dpv2_21cq_x1_r1_semantic_closure.py'
$DirectBaseline = Join-Path $ProjectRoot 'assets\data\drop\dpv2_direct_baseline_v2.json'
$CanonicalCatalog = Join-Path $ProjectRoot 'assets\data\runtime\canonical_monster_catalog.json'
$CurrentDropSemanticTargets = @(
    'tools/build_dpv2_21cq_direct_baseline.py',
    'tools/build_canonical_monster_catalog.py',
    'tools/monster_drop_p1a_runtime_export.gd',
    'tools/analyze_monster_drop_p1a.py',
    'tools/run_monster_drop_p1a.ps1',
    'tools/run_monster_drop_p1a_audit.ps1',
    'assets/data/runtime/canonical_monster_catalog.json',
    'assets/data/drop/dpv2_monster_drop_semantic_authority_v1.json',
    'assets/data/drop/dpv2_21cq_monster_mapping_v1.json',
    'assets/data/drop/dpv2_21cq_item_mapping_v1.json',
    'assets/data/drop/dpv2_21cq_overflow_authority_v1.json',
    'assets/data/drop/dpv2_21cq_source_provenance_v1.json',
    'assets/data/drop/dpv2_direct_baseline_v2.json',
    'assets/data/drop/dpv2_direct_baseline_manifest_v2.json'
)
$script:blocker_count = 0

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
New-Item -ItemType Directory -Path $RuntimeAppData -Force | Out-Null

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [Parameter(Mandatory = $false)]
        [object[]]$Arguments = @()
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable exit_code_$LASTEXITCODE"
    }
}

function Invoke-Python {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Invoke-Native $PythonCommand.Source (@($PythonArguments) + $Arguments)
}

function Invoke-GodotTests {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TestPaths
    )

    & $Runner -TimeoutSeconds 60 -TestPaths $TestPaths
    if ($LASTEXITCODE -ne 0) {
        throw "formal_runner_exit_code_$LASTEXITCODE"
    }
}

function Invoke-GateStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Output "DPV2_FINAL_GATE_STEP=$Name"
    try {
        & $Action
        Write-Output "DPV2_FINAL_GATE_STEP_PASS=$Name"
    }
    catch {
        $script:blocker_count += 1
        Write-Output "DPV2_FINAL_GATE_STEP_FAIL=$Name $($_.Exception.Message)"
    }
}

Push-Location $ProjectRoot
try {
    if ($null -eq $PythonCommand) {
        throw 'Python launcher missing: expected py -3.12 on PATH'
    }
    if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
        throw "missing Godot console binary: $Godot"
    }
    if (-not (Test-Path -LiteralPath $Runner -PathType Leaf)) {
        throw "missing formal Godot test runner: $Runner"
    }

    # Keep direct Godot output inside this worktree and normalize the inherited
    # environment before the runner starts a console process.
    $ProcessPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    [Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
    [Environment]::SetEnvironmentVariable('Path', $ProcessPath, 'Process')
    [Environment]::SetEnvironmentVariable('APPDATA', $RuntimeAppData, 'Process')

    Invoke-GateStep -Name 'semantic_authority_cross_authority' -Action {
        if (-not (Test-Path -LiteralPath $SemanticValidator -PathType Leaf)) {
            throw "missing semantic authority validator: $SemanticValidator"
        }
        Invoke-Python @('tools\validate_dpv2_21cq_x1_r1_semantic_closure.py', '--check')
    }
    Invoke-GateStep -Name 'existing_base_sha_slot_immutability' -Action {
        $baseSha = 'c1cfe8cf809d5047344060e9fe3ea06a9b9799f8'
        $baseSlotCount = 5995
        $baseSlotHash = '2D70FB2A279BA4E9EA471BDAFA2A777AA4B899BFA70A76A3FE8055BFA4941A14'
        $frozenText = & git show "$baseSha`:assets/data/drop/dpv2_direct_baseline_v2.json"
        if ($LASTEXITCODE -ne 0) {
            throw "cannot load BASE_SHA baseline: $baseSha"
        }
        $frozen = ($frozenText -join "`n") | ConvertFrom-Json
        $current = Get-Content -LiteralPath $DirectBaseline -Raw -Encoding UTF8 | ConvertFrom-Json
        $frozenSlots = [System.Collections.Generic.List[object]]::new()
        $currentSlots = [System.Collections.Generic.List[object]]::new()
        foreach ($profile in @($frozen.profiles)) {
            foreach ($slot in @($profile.slots)) { [void]$frozenSlots.Add($slot) }
        }
        foreach ($profile in @($current.profiles)) {
            foreach ($slot in @($profile.slots)) { [void]$currentSlots.Add($slot) }
        }
        if ($frozenSlots.Count -ne $baseSlotCount) {
            throw "BASE_SHA slot count=$($frozenSlots.Count) expected=$baseSlotCount"
        }
        if ([string]$current.baseline_freeze.base_sha -ne $baseSha -or
            [int]$current.baseline_freeze.base_slot_count -ne $baseSlotCount -or
            [string]$current.baseline_freeze.base_slot_sha256 -ne $baseSlotHash) {
            throw 'current baseline freeze metadata drift'
        }
        $currentByUid = @{}
        $frozenByUid = @{}
        foreach ($slot in $currentSlots) {
            $uid = [string]$slot.slot_uid
            $currentByUid[$uid] = ($slot | ConvertTo-Json -Depth 20 -Compress)
        }
        foreach ($slot in $frozenSlots) {
            $uid = [string]$slot.slot_uid
            $frozenByUid[$uid] = ($slot | ConvertTo-Json -Depth 20 -Compress)
        }
        $missing = @($frozenByUid.Keys | Where-Object { -not $currentByUid.ContainsKey($_) })
        if ($missing.Count -ne 0) {
            throw "BASE_SHA slots missing=$($missing.Count)"
        }
        $drift = @($frozenByUid.Keys | Where-Object { $currentByUid[$_] -cne $frozenByUid[$_] }).Count
        if ($drift -ne 0) {
            throw "BASE_SHA slot drift=$drift"
        }
        Write-Output "DPV2_BASE_SHA_SLOT_IMMUTABILITY_PASS: base_sha=$baseSha base_slots=$baseSlotCount preserved_slots=$($frozenByUid.Count) drift=$drift"
    }
    Invoke-GateStep -Name 'restored_814_x1_parity' -Action {
        $baseline = Get-Content -LiteralPath $DirectBaseline -Raw -Encoding UTF8 | ConvertFrom-Json
        $summary = $baseline.summary
        $expected = @{
            compiled_slots = 6809
            restored_existing_slots = 814
            x1_probability_mismatch = 0
            restored_x1_probability_mismatch = 0
            duplicate_slot_collapse = 0
        }
        foreach ($key in $expected.Keys) {
            if ([int]$summary.$key -ne [int]$expected[$key]) {
                throw "baseline summary $key=$($summary.$key) expected=$($expected[$key])"
            }
        }
        $zombieIds = @(79, 81, 83, 85, 87)
        $chestIds = @(226, 227, 228, 229, 230, 231, 232, 233, 234)
        $zombie = 0
        $chest = 0
        foreach ($profile in @($baseline.profiles)) {
            foreach ($slot in @($profile.slots)) {
                $parts = ([string]$slot.slot_uid).Split('.')
                if ($parts.Count -ne 4) { throw "invalid direct slot UID: $($slot.slot_uid)" }
                $monsterId = [int]([string]$parts[2]).TrimStart('m')
                if ($zombieIds -contains $monsterId) { $zombie += 1 }
                if ($chestIds -contains $monsterId) { $chest += 1 }
            }
        }
        if ($zombie -ne 296 -or $chest -ne 518 -or ($zombie + $chest) -ne 814) {
            throw "restored subset counts zombie=$zombie chest=$chest total=$($zombie + $chest)"
        }
        Write-Output "DPV2_RESTORED_X1_PARITY_PASS: restored=814 zombie=$zombie chest=$chest compiled_subset_mismatch=0 restored_x1_mismatch=0 preserved_x1_mismatch=0 duplicate_slot_collapse=0"
    }
    Invoke-GateStep -Name 'runtime_allowed_profile_gate' -Action {
        $catalog = Get-Content -LiteralPath $CanonicalCatalog -Raw -Encoding UTF8 | ConvertFrom-Json
        $baseline = Get-Content -LiteralPath $DirectBaseline -Raw -Encoding UTF8 | ConvertFrom-Json
        $entries = @($catalog.entries)
        $profiles = @($baseline.profiles)
        if ($entries.Count -ne 156 -or $profiles.Count -ne 156) {
            throw "profile count entries=$($entries.Count) baseline=$($profiles.Count) expected=156"
        }
        $catalogById = @{}
        foreach ($entry in $entries) { $catalogById[[int]$entry.monster_id] = $entry }
        $profileById = @{}
        foreach ($profile in $profiles) { $profileById[[int]$profile.canonical_monster_id] = $profile }
        if ($catalogById.Count -ne 156 -or $profileById.Count -ne 156) {
            throw 'duplicate or missing canonical profile IDs'
        }
        $runtimeAllowed = @($entries | Where-Object { $_.runtime_allowed -eq $true }).Count
        $enabled = @($profiles | Where-Object { $_.drop_enabled -eq $true }).Count
        $explicit = @($profiles | Where-Object { $_.semantic_status -eq 'EXPLICIT_NON_LOOT' }).Count
        $disabled = @($profiles | Where-Object { $_.semantic_status -eq 'RUNTIME_DISABLED' }).Count
        if ($runtimeAllowed -ne 153 -or $enabled -ne 144 -or $explicit -ne 9 -or $disabled -ne 3) {
            throw "profile partition runtime_allowed=$runtimeAllowed enabled=$enabled explicit=$explicit disabled=$disabled"
        }
        $runtimeDisabledIds = @($entries | Where-Object { $_.runtime_allowed -eq $false } | ForEach-Object { [int]$_.monster_id })
        if (@(Compare-Object (@(33,183,241) | Sort-Object) ($runtimeDisabledIds | Sort-Object)).Count -ne 0) {
            throw "runtime-disabled IDs drift: $($runtimeDisabledIds -join ',')"
        }
        foreach ($id in $catalogById.Keys) {
            $entry = $catalogById[$id]
            $profile = $profileById[$id]
            if ([bool]$profile.runtime_allowed -ne [bool]$entry.runtime_allowed) {
                throw "runtime_allowed mismatch for monster=$id"
            }
            if ($profile.semantic_status -in @('EXPLICIT_NON_LOOT', 'RUNTIME_DISABLED') -and @($profile.slots).Count -ne 0) {
                throw "excluded profile contains slots for monster=$id"
            }
        }
        Write-Output "DPV2_RUNTIME_ALLOWED_PROFILE_GATE_PASS: profiles=156 runtime_allowed=$runtimeAllowed enabled=$enabled explicit_non_loot=$explicit runtime_disabled=$disabled"
    }

    # Direct baseline and canonical catalog checks are the production data
    # contracts. Retired pre-cutover validators are intentionally not part of
    # this gate.
    Invoke-GateStep -Name 'direct_baseline_generator_check' -Action {
        Invoke-Python @('tools\build_dpv2_21cq_direct_baseline.py', '--check')
    }
    Invoke-GateStep -Name 'canonical_monster_catalog_check' -Action {
        Invoke-Python @('tools\build_canonical_monster_catalog.py', '--check')
    }
    Invoke-GateStep -Name 'source_priority_verifier' -Action {
        Invoke-Python @('tools\verify_source_priority_policy.py')
    }
    Invoke-GateStep -Name 'dpv2_direct_python_tests' -Action {
        Invoke-Python @(
            '-m',
            'unittest',
            'tests/test_dpv2_21cq_source_audit.py',
            'tests/test_dpv2_21cq_mapping_authority.py',
            'tests/test_dpv2_21cq_direct_baseline.py',
            'tests/test_dpv2_21cq_x1_r1_semantic_closure.py',
            '-v'
        )
    }
    Invoke-GateStep -Name 'production_legacy_dependency_search' -Action {
        $targets = @(
            'scripts/game_data.gd',
            'scripts/layers/runtime/loot_runtime_service.gd'
        )
        $pattern = 'DPV2_ITEM_TIER|DPV2_MONSTER_ROLE|role_factor|tier_factor|tier_denominator|dpv2_role_ratio|dpv2_monster_drop_state|dpv2_resolve_reward_policy|_load_dpv2_drop_authorities|activate_dpv2_drop_runtime|dpv2_drop_runtime_authority_v1'
        $matches = @(rg -n -i -- $pattern @targets 2>$null)
        $rgExitCode = $LASTEXITCODE
        if ($rgExitCode -eq 0) {
            throw "forbidden production dependency matches:`n$($matches -join "`n")"
        }
        if ($rgExitCode -ne 1) {
            throw "legacy dependency search exit_code_$rgExitCode"
        }
        Write-Output 'DPV2_PRODUCTION_LEGACY_DEPENDENCY_SEARCH_PASS: targets=2 current_runtime_matches=0 classifications=Tier,DropRole,role_factor,tier_factor,old_runtime_authority'
    }
    Invoke-GateStep -Name 'current_drop_semantic_a07_dependency_search' -Action {
        $pattern = '(?<![A-Za-z0-9])A0[._-]?7(?![A-Za-z0-9])|legacy_role|drop_role|dpv2_role_ratio|dpv2_monster_drop_state|role_factor(?!_participates)|tier_factor|tier_denominator(?!_participates)|dpv2_resolve_reward_policy|_load_dpv2_drop_authorities|activate_dpv2_drop_runtime'
        $searchTargets = $CurrentDropSemanticTargets
        # The builder and generated artifacts may retain historical migration
        # provenance. Search only current semantic inclusion terms; the
        # production runtime search above covers old authorities in consumers.
        $matches = @(rg -n -i -P -- $pattern @searchTargets 2>$null)
        $rgExitCode = $LASTEXITCODE
        if ($rgExitCode -eq 0) {
            throw "forbidden current drop-semantic A0.7 dependency matches:`n$($matches -join "`n")"
        }
        elseif ($rgExitCode -ne 1) {
            throw "current drop-semantic A0.7 dependency search exit_code_$rgExitCode"
        }
        Write-Output "DPV2_CURRENT_DROP_SEMANTIC_A07_DEPENDENCY_SEARCH_PASS: targets=$($searchTargets.Count) current_semantic_inclusion_matches=0 historical_a07_retained=explicitly_historical_only"
    }

    # These tests cover the direct loader/API, canonical-ID joins, rational
    # scaling, independent slot RNG, post-RNG protected/priority retention,
    # the policy contract, P1A runtime export, and separate gold behavior.
    Invoke-GateStep -Name 'dpv2_direct_runtime_contracts' -Action {
        Invoke-GodotTests @(
            'tests/dpv2_21cq_direct_loader_test.tscn',
            'tests/dpv2_21cq_direct_runtime_test.tscn',
            'tests/dpv2_drop_runtime_policy_test.tscn',
            'tests/monster_drop_p1a_runtime_contract_test.tscn',
            'tests/monster_gold_drop_runtime_test.tscn'
        )
    }
    Invoke-GateStep -Name 'fresh_p1a' -Action {
        & (Join-Path $ProjectRoot 'tools\run_monster_drop_p1a.ps1')
        if ($LASTEXITCODE -ne 0) {
            throw "fresh_p1a_exit_code_$LASTEXITCODE"
        }
    }
    Invoke-GateStep -Name 'fresh_p1a_audit' -Action {
        & (Join-Path $ProjectRoot 'tools\run_monster_drop_p1a_audit.ps1')
        if ($LASTEXITCODE -ne 0) {
            throw "fresh_p1a_audit_exit_code_$LASTEXITCODE"
        }
    }
    Invoke-GateStep -Name 'world_integration' -Action {
        Invoke-GodotTests @('tests/monster_world_integration_test.tscn')
    }
    Invoke-GateStep -Name 'git_diff_check' -Action {
        & git -C $ProjectRoot diff --check
        if ($LASTEXITCODE -ne 0) {
            throw "git_diff_check_exit_code_$LASTEXITCODE"
        }
    }
}
catch {
    $script:blocker_count += 1
    Write-Output "DPV2_FINAL_GATE_FATAL=$($_.Exception.Message)"
}
finally {
    Pop-Location
}

if ($script:blocker_count -ne 0) {
    Write-Output "DPV2_FINAL_GATE_FAIL blocker_count=$script:blocker_count"
    exit 1
}
Write-Output 'DPV2_FINAL_GATE_PASS blocker_count=0'
exit 0
