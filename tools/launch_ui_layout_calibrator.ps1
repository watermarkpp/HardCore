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

# The calibrator instantiates the production game scene. A fresh integration
# worktree may have tracked `.import` descriptors but no local `.godot/imported`
# payloads for the service-home ground yet, which leaves the production
# bootstrap correctly covered by its Loading overlay. Import only when one of
# those required local payloads is absent; normal launches stay fast.
$HomeVisualPath = Join-Path $ProjectRoot 'assets\data\runtime\map_editor\world_bich_province.visual.json'
$HomeVisual = Get-Content -Raw -LiteralPath $HomeVisualPath | ConvertFrom-Json
$NeedsImport = $false
foreach ($Chunk in $HomeVisual.chunks) {
	$SourcePath = Join-Path $ProjectRoot ($Chunk.image -replace '/', '\')
	$ImportDescriptor = "$SourcePath.import"
	if (-not (Test-Path -LiteralPath $ImportDescriptor)) {
		$NeedsImport = $true
		break
	}
	$CompressedPathLine = Select-String -LiteralPath $ImportDescriptor -Pattern '^path\.s3tc="res://(.+)"$'
	if ($null -eq $CompressedPathLine) {
		$NeedsImport = $true
		break
	}
	$CompressedRelativePath = $CompressedPathLine.Matches[0].Groups[1].Value -replace '/', '\'
	if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $CompressedRelativePath))) {
		$NeedsImport = $true
		break
	}
}
if ($NeedsImport) {
	& $Godot '--path' $ProjectRoot '--headless' '--import'
	if ($LASTEXITCODE -ne 0) {
		throw "Godot resource import failed with exit code $LASTEXITCODE"
	}
}

Start-Process -FilePath $Godot -ArgumentList $Arguments
