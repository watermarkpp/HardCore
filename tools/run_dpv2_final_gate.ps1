param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$Runner = Join-Path $ProjectRoot 'tools\run_godot_tests.ps1'
$PythonCommand = Get-Command py -ErrorAction SilentlyContinue
$PythonArguments = @('-3.12')
if ($null -eq $PythonCommand) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    $PythonArguments = @()
}
$ExportScene = 'res://tools/monster_drop_p1a_runtime_export.tscn'
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
$ExportLog = Join-Path $LogRoot 'dpv2_final_gate_export.log'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\runtime_appdata_dpv2_final_gate'
$script:blocker_count = 0

New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
New-Item -ItemType Directory -Path $RuntimeAppData -Force | Out-Null

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
        if ($LASTEXITCODE -ne 0) {
            throw "exit_code_$LASTEXITCODE"
        }
        Write-Output "DPV2_FINAL_GATE_STEP_PASS=$Name"
    }
    catch {
        $script:blocker_count += 1
        Write-Error "DPV2_FINAL_GATE_STEP_FAIL=$Name $($_.Exception.Message)"
        throw
    }
}

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

try {
    if ($null -eq $PythonCommand) {
        throw 'Python launcher missing: expected py or python on PATH'
    }

    # Keep direct exporter user:// output inside this worktree. The formal
    # runner applies the same policy for each Godot test invocation.
    $env:APPDATA = $RuntimeAppData

    # 1. Export the real Godot snapshot before any validator or test consumes it.
    Invoke-GateStep -Name 'export' -Action {
        if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
            throw "missing Godot console binary: $Godot"
        }
        Invoke-Native $Godot @('--headless', '--path', $ProjectRoot, '--log-file', $ExportLog, $ExportScene)
    }

    # 2. Validate the exported snapshot and every reproducible authority output.
    Invoke-GateStep -Name 'validate_snapshot' -Action {
        Invoke-Native $PythonCommand.Source (@($PythonArguments) + (Join-Path $ProjectRoot 'tools\test_analyze_monster_drop_p1a.py'))
        Invoke-Native $PythonCommand.Source (@($PythonArguments) + (Join-Path $ProjectRoot 'tools\analyze_monster_drop_p1a.py'))
        Invoke-Native $PythonCommand.Source (@($PythonArguments) + (Join-Path $ProjectRoot 'tools\activate_dpv2_drop_runtime.py') + '--check')
        Invoke-Native $PythonCommand.Source (@($PythonArguments) + (Join-Path $ProjectRoot 'tools\build_canonical_monster_catalog.py') + '--check')
        Invoke-Native $PythonCommand.Source (@($PythonArguments) + (Join-Path $ProjectRoot 'tools\validate_dpv2_a07_human_authority_freeze.py'))
    }

    # 3. Run the focused DPV2 runtime policy contract through the formal runner.
    Invoke-GateStep -Name 'dpv2_runtime_policy' -Action {
        & $Runner -TestPaths @('tests/dpv2_drop_runtime_policy_test.tscn')
        if ($LASTEXITCODE -ne 0) {
            throw "formal_runner_exit_code_$LASTEXITCODE"
        }
    }

    # 4. Verify the P1A runtime contract and unified monster gold path.
    Invoke-GateStep -Name 'p1a_runtime_contract' -Action {
        & $Runner -TestPaths @('tests/monster_drop_p1a_runtime_contract_test.tscn')
        if ($LASTEXITCODE -ne 0) {
            throw "formal_runner_exit_code_$LASTEXITCODE"
        }
    }
    Invoke-GateStep -Name 'monster_gold_runtime' -Action {
        & $Runner -TestPaths @('tests/monster_gold_drop_runtime_test.tscn')
        if ($LASTEXITCODE -ne 0) {
            throw "formal_runner_exit_code_$LASTEXITCODE"
        }
    }

    # 5. Verify the real world death/drop integration after the focused gates.
    Invoke-GateStep -Name 'world_integration' -Action {
        & $Runner -TimeoutSeconds 60 -TestPaths @('tests/monster_world_integration_test.tscn')
        if ($LASTEXITCODE -ne 0) {
            throw "formal_runner_exit_code_$LASTEXITCODE"
        }
    }
}
catch {
    if ($script:blocker_count -eq 0) {
        $script:blocker_count = 1
    }
}

if ($script:blocker_count -ne 0) {
    Write-Output "DPV2_FINAL_GATE_FAIL blocker_count=$script:blocker_count"
    exit 1
}
Write-Output 'DPV2_FINAL_GATE_PASS blocker_count=0'
exit 0
