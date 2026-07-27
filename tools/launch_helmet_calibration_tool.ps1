param(
    [string]$TargetManifest = 'res://assets/data/helmet_calibration_active_target.json'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64.exe'
$Scene = 'res://tools/helmet_calibration_tool.tscn'
$InteractiveArgument = '--helmet-calibration-interactive'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\helmet_calibration_appdata'
$OutputDirectory = Join-Path $ProjectRoot 'outputs'
$EngineLog = Join-Path $OutputDirectory 'helmet_calibration_interactive.log'
$TargetManifestPath = if ($TargetManifest.StartsWith('res://')) {
    Join-Path $ProjectRoot ($TargetManifest.Substring(6).Replace('/', '\'))
} else {
    $TargetManifest
}

if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot executable not found: $Godot"
}
if (-not (Test-Path -LiteralPath $TargetManifestPath)) {
    throw "Helmet calibration target manifest not found: $TargetManifestPath"
}

New-Item -ItemType Directory -Path $RuntimeAppData -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

# Keep this editor's Godot user data and logs inside the worktree. In
# particular, a denied normal %APPDATA% log directory must never terminate the
# calibration window before it can show an initialization error.
$env:APPDATA = $RuntimeAppData

Start-Process -FilePath $Godot `
    -ArgumentList @(
        '--path', $ProjectRoot,
        '--log-file', $EngineLog,
        $Scene,
        '--', $InteractiveArgument,
        "--helmet-calibration-target=$TargetManifest"
    ) `
    -WorkingDirectory $ProjectRoot `
    -WindowStyle Normal
