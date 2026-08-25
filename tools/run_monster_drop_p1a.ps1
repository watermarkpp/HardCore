param()

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\runtime_appdata_p1a'

if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot console binary not found: $Godot"
}

# Match the repository's established Windows/Godot test environment handling.
$ProcessPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
[Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
[Environment]::SetEnvironmentVariable('Path', $ProcessPath, 'Process')
New-Item -ItemType Directory -Path $RuntimeAppData -Force | Out-Null
[Environment]::SetEnvironmentVariable('APPDATA', $RuntimeAppData, 'Process')

function Invoke-Python {
    param([string[]]$Arguments)

    $Py = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $Py) {
        & $Py.Source -3 @Arguments
    }
    else {
        $Python = Get-Command python -ErrorAction Stop
        & $Python.Source @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Python failed with exit code $LASTEXITCODE: $($Arguments -join ' ')"
    }
}

function Invoke-GodotScene {
    param([string]$Scene)

    & $Godot --headless --path $ProjectRoot $Scene
    if ($LASTEXITCODE -ne 0) {
        throw "Godot scene failed with exit code $LASTEXITCODE: $Scene"
    }
}

Push-Location $ProjectRoot
try {
    Write-Host '[P1A 1/4] Python analyzer unit tests'
    Invoke-Python @('tools/test_analyze_monster_drop_p1a.py')

    Write-Host '[P1A 2/4] Real LootRuntime/GameData contract'
    Invoke-GodotScene 'res://tests/monster_drop_p1a_runtime_contract_test.tscn'

    Write-Host '[P1A 3/4] Export runtime-grounded snapshot'
    Invoke-GodotScene 'res://tools/monster_drop_p1a_runtime_export.tscn'

    $Snapshot = Join-Path $ProjectRoot 'outputs\monster_drop_p1a\runtime_snapshot.json'
    if (-not (Test-Path -LiteralPath $Snapshot -PathType Leaf)) {
        throw "P1A exporter did not produce snapshot: $Snapshot"
    }

    Write-Host '[P1A 4/4] Validate/analyze exported snapshot'
    Invoke-Python @(
        'tools/analyze_monster_drop_p1a.py',
        '--snapshot', 'outputs/monster_drop_p1a/runtime_snapshot.json',
        '--output-dir', 'outputs/monster_drop_p1a'
    )

    Write-Host 'MONSTER_DROP_P1A_ALL_PASS'
}
finally {
    Pop-Location
}
