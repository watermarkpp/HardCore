param(
    [switch]$MonsterGroundReview,
    [switch]$FixedAreaGroundSpikeReview,
    [switch]$WarriorSkillReview,
    [ValidateRange(1, 2147483647)]
    [int]$MonsterId
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

$GodotArgs = @(
    '--path', $ProjectRoot,
    '--log-file', (Join-Path $LogRoot 'visual_acceptance_lab.log'),
    $Scene
)
$UserArgs = @()
if ($FixedAreaGroundSpikeReview) {
    $UserArgs += '--fixed-area-ground-spike-review'
}
elseif ($MonsterGroundReview) {
    $UserArgs += '--monster-ground-review'
}
elseif ($WarriorSkillReview) {
    $UserArgs += '--warrior-skill-review'
}
if ($PSBoundParameters.ContainsKey('MonsterId')) {
    $UserArgs += "--monster-id=$MonsterId"
}
if ($UserArgs.Count -gt 0) {
    $GodotArgs += '--'
    $GodotArgs += $UserArgs
}
& $Godot @GodotArgs
exit $LASTEXITCODE
