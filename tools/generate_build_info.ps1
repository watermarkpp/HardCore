<#
.SYNOPSIS
    Generate res://assets/generated/build_info.json from Git state.
    HC-P1-014: binds exported builds to source revision.
#>
param(
    [switch]$AllowDirty,
    [string]$StageRoot,
    [switch]$SkipDirtyCheck,
    [switch]$IgnoreAndroidBuildTemplate,
    [int]$VersionCodeOverride = 0
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
if ($IgnoreAndroidBuildTemplate) {
    $UntrackedPaths = @($UntrackedPaths | Where-Object { $_ -notmatch '^android/' })
}
$dirty = ($TrackedDirtyExitCode -eq 1 -or $UntrackedPaths.Count -gt 0)

if ($dirty -and -not $AllowDirty -and -not $SkipDirtyCheck) {
    Write-Error "Working tree is dirty. Use -AllowDirty for dev builds."
    Pop-Location; exit 1
}

function Read-BuildGitUtf8([string]$RelativePath) {
    # Git blobs are UTF-8; never decode them using the host console codepage.
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = 'git.exe'
    $info.WorkingDirectory = [IO.Path]::GetFullPath($ROOT)
    $info.Arguments = 'show "HEAD:' + $RelativePath + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Unable to read build metadata from Git.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('Build metadata Git read failed exit={0}: {1}' -f $process.ExitCode, $errorText) }
        return $text
    } finally { $process.Dispose() }
}

$ProjectText = Read-BuildGitUtf8 'project.godot'
$PresetText = Read-BuildGitUtf8 'export_presets.cfg'
$NameMatches = [regex]::Matches($ProjectText, '(?m)^config/version="([^"\r\n]+)"\r?$')
$CodeMatches = [regex]::Matches($PresetText, '(?m)^version/code=(\d+)\r?$')
if ($NameMatches.Count -ne 1 -or $CodeMatches.Count -ne 1) { throw 'Missing or ambiguous version metadata in the fixed Git source.' }
$versionName = $NameMatches[0].Groups[1].Value
$versionCode = $CodeMatches[0].Groups[1].Value
# QA override (remote review 2026-09-16): the isolated build injects a
# monotonic per-QA versionCode into the staged preset; build_info.json must
# record the SAME code or the runtime-resource verify step rejects the APK.
if ($VersionCodeOverride -gt 0) {
    $versionCode = [string]$VersionCodeOverride
}
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
