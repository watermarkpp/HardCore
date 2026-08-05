<#
.SYNOPSIS
    Generate res://generated/build_info.json from Git state.
    HC-P1-014: binds exported builds to source revision.
#>
param(
    [switch]$AllowDirty,
    [string]$StageRoot,
    [switch]$SkipDirtyCheck
)

$ErrorActionPreference = "Stop"
if ($StageRoot) {
    $ROOT = $StageRoot
} else {
    $ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ROOT = Split-Path -Parent $ROOT
}
Push-Location $ROOT -ErrorAction Stop

$head = (git rev-parse HEAD).Trim()
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$dirty = $false
try { 
    $null = git diff-index --quiet HEAD --
} catch { 
    $dirty = $true 
}

if ($dirty -and -not $AllowDirty -and -not $SkipDirtyCheck) {
    Write-Error "Working tree is dirty. Use -AllowDirty for dev builds."
    Pop-Location; exit 1
}

$versionName = (git show HEAD:project.godot | Select-String 'config/version' | ForEach { $_ -replace '.*=\s*"([^"]+)".*','$1' }).Trim()
$versionCode = (git show HEAD:export_presets.cfg | Select-String 'version/code=' | ForEach { $_ -replace '.*version/code=(\d+).*','$1' }).Trim()
$buildType = if ($AllowDirty) { "dirty_dev" } elseif ($branch -match "validation/") { "validation" } else { "development" }

$info = @{
    git_head = $head
    git_short_head = $head.Substring(0,8)
    git_branch = $branch
    git_dirty = $dirty
    build_timestamp_utc = [DateTime]::UtcNow.ToString("o")
    version_name = $versionName
    version_code = [int]$versionCode
    build_type = $buildType
} | ConvertTo-Json

$dest = Join-Path $ROOT "assets/generated"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$info | Out-File (Join-Path $dest "build_info.json") -Encoding UTF8NoBOM
Write-Host "BUILD_INFO: $head ($buildType)"
Write-Host "Dirty: $dirty"
Pop-Location
