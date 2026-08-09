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
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
    throw "Unable to resolve Git HEAD for build-info."
}
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw "Unable to resolve Git branch for build-info."
}
& git diff-index --quiet HEAD --
$TrackedDirtyExitCode = $LASTEXITCODE
if ($TrackedDirtyExitCode -notin @(0, 1)) {
    throw "Unable to inspect tracked Git state for build-info (exit $TrackedDirtyExitCode)."
}
$UntrackedPaths = @(& git ls-files --others --exclude-standard)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect untracked Git state for build-info."
}
$dirty = ($TrackedDirtyExitCode -eq 1 -or $UntrackedPaths.Count -gt 0)

if ($dirty -and -not $AllowDirty -and -not $SkipDirtyCheck) {
    Write-Error "Working tree is dirty. Use -AllowDirty for dev builds."
    Pop-Location; exit 1
}

$versionName = (git show HEAD:project.godot | Select-String 'config/version' | ForEach { $_ -replace '.*=\s*"([^"]+)".*','$1' }).Trim()
$versionCode = (git show HEAD:export_presets.cfg | Select-String 'version/code=' | ForEach { $_ -replace '.*version/code=(\d+).*','$1' }).Trim()
$buildType = if ($dirty) { "dirty_dev" } elseif ($branch -match "validation/") { "validation" } else { "development" }

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
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $dest "build_info.json"), $info + [Environment]::NewLine, $utf8NoBom)
Write-Host "BUILD_INFO: $head ($buildType)"
Write-Host "Dirty: $dirty"
Pop-Location
