param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$Runner = Join-Path $ProjectRoot 'tools\run_godot_tests.ps1'
$PythonCommand = Get-Command py -ErrorAction SilentlyContinue
$PythonArguments = @('-3.12')
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\runtime_appdata_dpv2_final_gate'
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
        Write-Output 'DPV2_PRODUCTION_LEGACY_DEPENDENCY_SEARCH_PASS: targets=2 matches=0 classifications=Tier,DropRole,role_factor,tier_factor,old_runtime_authority'
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
