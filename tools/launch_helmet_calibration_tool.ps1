param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64.exe'
$Scene = 'res://tools/helmet_calibration_tool.tscn'

if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot executable not found: $Godot"
}

Start-Process -FilePath $Godot `
    -ArgumentList @('--path', $ProjectRoot, $Scene) `
    -WorkingDirectory $ProjectRoot `
    -WindowStyle Normal
