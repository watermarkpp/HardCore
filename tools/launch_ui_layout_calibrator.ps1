param()

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\runtime_appdata'
New-Item -ItemType Directory -Force -Path $RuntimeAppData | Out-Null
$env:APPDATA = $RuntimeAppData
$env:LOCALAPPDATA = $RuntimeAppData

$Arguments = @(
	'--path', $ProjectRoot,
	'--display-driver', 'windows',
	'--rendering-method', 'gl_compatibility',
	'--audio-driver', 'Dummy',
	'--resolution', '2664x1200',
	'tests/ui_layout_calibration_workbench.tscn'
)

Start-Process -FilePath $Godot -ArgumentList $Arguments
