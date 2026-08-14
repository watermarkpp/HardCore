$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'

if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot console executable not found: $Godot"
}

# Keep the editor's user data and logs inside this worktree. This prevents a
# launch from reading or writing the normal Godot APPDATA profile and makes
# the startup markers available for black-screen diagnosis.
$RuntimeRoot = Join-Path $ProjectRoot '.godot\runtime_appdata\mse_launcher'
$AppDataRoot = Join-Path $RuntimeRoot 'Roaming'
$LocalAppDataRoot = Join-Path $RuntimeRoot 'Local'
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
New-Item -ItemType Directory -Path $AppDataRoot, $LocalAppDataRoot, $LogRoot -Force | Out-Null
$Stdout = Join-Path $LogRoot 'mse_launcher.stdout.log'
$Stderr = Join-Path $LogRoot 'mse_launcher.stderr.log'
Remove-Item -LiteralPath $Stdout, $Stderr -Force -ErrorAction SilentlyContinue

$OldAppData = $env:APPDATA
$OldLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = $AppDataRoot
    $env:LOCALAPPDATA = $LocalAppDataRoot
    $process = Start-Process -FilePath $Godot -ArgumentList @('--path', $ProjectRoot, 'res://scenes/tools/mafa_scene_editor.tscn') -WorkingDirectory $ProjectRoot -WindowStyle Normal -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr -PassThru
}
finally {
    $env:APPDATA = $OldAppData
    $env:LOCALAPPDATA = $OldLocalAppData
}

Write-Output ("MSE launcher started PID={0}" -f $process.Id)
Write-Output ("MSE launcher stdout: {0}" -f $Stdout)
Write-Output ("MSE launcher stderr: {0}" -f $Stderr)
