param(
    [switch]$MonsterGroundReview
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$Scene = 'res://tools/visual_acceptance_lab/visual_acceptance_lab.tscn'
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
$AppDataRoot = Join-Path $ProjectRoot '.godot\visual_acceptance_appdata'

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
New-Item -ItemType Directory -Force -Path $AppDataRoot | Out-Null

$env:APPDATA = $AppDataRoot
$env:LOCALAPPDATA = $AppDataRoot

if ($MonsterGroundReview) {
    & $Godot --path $ProjectRoot --log-file (Join-Path $LogRoot 'visual_acceptance_lab.log') $Scene -- --monster-ground-review
}
else {
    & $Godot --path $ProjectRoot --log-file (Join-Path $LogRoot 'visual_acceptance_lab.log') $Scene
}
exit $LASTEXITCODE
