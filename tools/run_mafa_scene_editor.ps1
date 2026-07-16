$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64.exe'

if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot not found: $Godot"
}

Start-Process -FilePath $Godot -ArgumentList @('--path', $ProjectRoot, 'res://scenes/tools/mafa_scene_editor.tscn') -WorkingDirectory $ProjectRoot
