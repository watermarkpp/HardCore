param(
    [switch]$LevelUpPreview,
    [string]$CaptureLevelUpPreview = '',
    [switch]$InventoryAttributePreview,
    [string]$CaptureInventoryAttributePreview = '',
    [switch]$CharacterStatsPreview,
    [string]$CaptureCharacterStatsPreview = '',
    [switch]$ChassisDesignCompare,
    [string]$CaptureChassisDesignCompare = '',
    [switch]$ForgePreview,
    [string]$CaptureForgePreview = '',
    [switch]$SynthesisPreview,
    [string]$CaptureSynthesisPreview = '',
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\runtime_appdata'
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
$LogPath = Join-Path $LogRoot 'ui_layout_calibrator.log'
$ImportLogPath = Join-Path $LogRoot 'ui_layout_calibrator_import.log'
New-Item -ItemType Directory -Force -Path $RuntimeAppData | Out-Null
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$env:APPDATA = $RuntimeAppData
$env:LOCALAPPDATA = $RuntimeAppData

function Resolve-ProjectLocalPngArgument {
    param([string]$CandidatePath)

    $rawPath = $CandidatePath.Trim()
    if ([string]::IsNullOrWhiteSpace($rawPath)) {
        throw 'CaptureLevelUpPreview must be a non-empty project-local PNG path.'
    }
    $projectRootFull = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    if ($rawPath.StartsWith('res://', [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $rawPath.Substring(6).Replace('/', '\')
        $fullPath = [IO.Path]::GetFullPath((Join-Path $projectRootFull $relativePath))
    } elseif ([IO.Path]::IsPathRooted($rawPath)) {
        $fullPath = [IO.Path]::GetFullPath($rawPath)
    } else {
        $fullPath = [IO.Path]::GetFullPath((Join-Path $projectRootFull ($rawPath.Replace('/', '\'))))
    }
    $projectPrefix = $projectRootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "CaptureLevelUpPreview must remain inside the project: $CandidatePath"
    }
    if ([IO.Path]::GetExtension($fullPath) -ine '.png') {
        throw "CaptureLevelUpPreview must end in .png: $CandidatePath"
    }
    $relativeForGodot = $fullPath.Substring($projectPrefix.Length).Replace('\', '/')
    return "res://$relativeForGodot"
}

function Resolve-ProjectLocalDirArgument {
    param([string]$CandidatePath)

    $rawPath = $CandidatePath.Trim()
    if ([string]::IsNullOrWhiteSpace($rawPath)) {
        throw 'CaptureChassisDesignCompare must be a non-empty project-local directory.'
    }
    $projectRootFull = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    if ($rawPath.StartsWith('res://', [StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $rawPath.Substring(6).Replace('/', '\')
        $fullPath = [IO.Path]::GetFullPath((Join-Path $projectRootFull $relativePath))
    } elseif ([IO.Path]::IsPathRooted($rawPath)) {
        $fullPath = [IO.Path]::GetFullPath($rawPath)
    } else {
        $fullPath = [IO.Path]::GetFullPath((Join-Path $projectRootFull ($rawPath.Replace('/', '\'))))
    }
    $projectPrefix = $projectRootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "CaptureChassisDesignCompare must remain inside the project: $CandidatePath"
    }
    $relativeForGodot = $fullPath.Substring($projectPrefix.Length).Replace('\', '/')
    return "res://$relativeForGodot"
}

$PreviewUserArguments = @()
if ($LevelUpPreview.IsPresent -or -not [string]::IsNullOrWhiteSpace($CaptureLevelUpPreview)) {
    $PreviewUserArguments += '--level-up-preview'
}
if (-not [string]::IsNullOrWhiteSpace($CaptureLevelUpPreview)) {
    $CaptureArgument = Resolve-ProjectLocalPngArgument $CaptureLevelUpPreview
    $PreviewUserArguments += "--capture-level-up-preview=$CaptureArgument"
}
if ($InventoryAttributePreview.IsPresent -or -not [string]::IsNullOrWhiteSpace($CaptureInventoryAttributePreview)) {
    $PreviewUserArguments += '--inventory-attribute-preview'
}
if (-not [string]::IsNullOrWhiteSpace($CaptureInventoryAttributePreview)) {
    $InventoryCaptureArgument = Resolve-ProjectLocalPngArgument $CaptureInventoryAttributePreview
    $PreviewUserArguments += "--capture-inventory-attribute-preview=$InventoryCaptureArgument"
}
if ($CharacterStatsPreview.IsPresent -or -not [string]::IsNullOrWhiteSpace($CaptureCharacterStatsPreview)) {
    $PreviewUserArguments += '--character-stats-preview'
}
if (-not [string]::IsNullOrWhiteSpace($CaptureCharacterStatsPreview)) {
    $CharacterCaptureArgument = Resolve-ProjectLocalPngArgument $CaptureCharacterStatsPreview
    $PreviewUserArguments += "--capture-character-stats-preview=$CharacterCaptureArgument"
}

if ($ChassisDesignCompare.IsPresent -or -not [string]::IsNullOrWhiteSpace($CaptureChassisDesignCompare)) {
    $PreviewUserArguments += '--chassis-design-compare'
}
if ($ForgePreview.IsPresent -or -not [string]::IsNullOrWhiteSpace($CaptureForgePreview)) {
    $PreviewUserArguments += '--forge-preview'
}
if (-not [string]::IsNullOrWhiteSpace($CaptureForgePreview)) {
    $ForgeCaptureArgument = Resolve-ProjectLocalPngArgument $CaptureForgePreview
    $PreviewUserArguments += "--capture-forge-preview=$ForgeCaptureArgument"
}
if ($SynthesisPreview.IsPresent -or -not [string]::IsNullOrWhiteSpace($CaptureSynthesisPreview)) {
    $PreviewUserArguments += '--synthesis-preview'
}
if (-not [string]::IsNullOrWhiteSpace($CaptureSynthesisPreview)) {
    $SynthesisCaptureArgument = Resolve-ProjectLocalPngArgument $CaptureSynthesisPreview
    $PreviewUserArguments += "--capture-synthesis-preview=$SynthesisCaptureArgument"
}
if (-not [string]::IsNullOrWhiteSpace($CaptureChassisDesignCompare)) {
    $CaptureDirArgument = Resolve-ProjectLocalDirArgument $CaptureChassisDesignCompare
    $PreviewUserArguments += "--capture-chassis-design-compare=$CaptureDirArgument"
}

$Arguments = @(
	'--path', $ProjectRoot,
	'--display-driver', 'windows',
	'--rendering-method', 'gl_compatibility',
	'--log-file', $LogPath,
	'--resolution', '2664x1200',
	'tests/ui_layout_calibration_workbench.tscn'
)
if (-not ($Visible.IsPresent -and ($ForgePreview.IsPresent -or $SynthesisPreview.IsPresent))) {
	$Arguments = @('--audio-driver', 'Dummy') + $Arguments
}

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
	$ImportArguments = @(
		'--path', $ProjectRoot,
		'--headless',
		'--log-file', $ImportLogPath,
		'--import'
	)
    $ImportProcess = Start-Process -FilePath $Godot -ArgumentList $ImportArguments -WorkingDirectory $ProjectRoot -WindowStyle Hidden -Wait -PassThru
	if ($ImportProcess.ExitCode -ne 0) {
		throw "Godot resource import failed with exit code $($ImportProcess.ExitCode)"
	}
}

if ($PreviewUserArguments.Count -gt 0) {
    $Arguments += '--'
    $Arguments += $PreviewUserArguments
}
$WindowStyle = 'Hidden'
if ($Visible.IsPresent) {
    $WindowStyle = 'Normal'
}
Start-Process -FilePath $Godot -ArgumentList $Arguments -WorkingDirectory $ProjectRoot -WindowStyle $WindowStyle
