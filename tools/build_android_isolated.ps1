param(
    [string]$Commit = "HEAD",
    [string]$OutputApk = "",
    [string]$GodotConsole = "",
    [string]$AndroidRoot = "",
    [string]$BaselineApkPath = "",
    [int]$ExpectedVersionCode = 38,
    [string]$ExpectedVersionName = "",
    [switch]$PreflightOnly,
    [switch]$KeepStage
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

if ([string]::IsNullOrWhiteSpace($OutputApk)) {
    $OutputApk = Join-Path $ProjectRoot "outputs\hardcore\HardCore-candidate-debug.apk"
}
if ([string]::IsNullOrWhiteSpace($GodotConsole)) {
    $GodotConsole = Join-Path $ProjectRoot "tools\godot-4.7\Godot_v4.7-stable_win64_console.exe"
}
if ([string]::IsNullOrWhiteSpace($AndroidRoot)) {
    $AndroidRoot = $env:ANDROID_BUILD_ROOT
}
if ([string]::IsNullOrWhiteSpace($AndroidRoot)) {
    $AndroidRoot = Join-Path $ProjectRoot "tools\android-build"
}
if ([string]::IsNullOrWhiteSpace($BaselineApkPath)) {
    $BaselineApkPath = Join-Path $ProjectRoot "outputs\hardcore\HardCore-slim-v38-debug.apk"
}

foreach ($RequiredFile in @($GodotConsole, $BaselineApkPath)) {
    if (-not (Test-Path -LiteralPath $RequiredFile -PathType Leaf)) {
        throw "Required file does not exist: $RequiredFile"
    }
}
if (-not (Test-Path -LiteralPath $AndroidRoot -PathType Container)) {
    throw "Android build root does not exist: $AndroidRoot"
}
$GodotConsole = (Resolve-Path -LiteralPath $GodotConsole).Path
$BaselineApkPath = (Resolve-Path -LiteralPath $BaselineApkPath).Path
$AndroidRoot = (Resolve-Path -LiteralPath $AndroidRoot).Path

$ResolvedCommitOutput = @(& git -C $ProjectRoot rev-parse --verify "$Commit^{commit}")
if ($LASTEXITCODE -ne 0 -or $ResolvedCommitOutput.Count -ne 1) {
    throw "Unable to resolve build commit: $Commit"
}
$ResolvedCommit = ([string]$ResolvedCommitOutput[0]).Trim()
if ([string]::IsNullOrWhiteSpace($ResolvedCommit)) {
    throw "Unable to resolve build commit: $Commit"
}
$ExportPresetText = (@(& git -C $ProjectRoot show "${ResolvedCommit}:export_presets.cfg")) -join "`n"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ExportPresetText)) {
    throw "Build commit has no readable export_presets.cfg: $ResolvedCommit"
}
if ($ExportPresetText -notmatch "(?m)^version/code=$ExpectedVersionCode`r?$") {
    throw "Build commit export preset does not contain version/code=$ExpectedVersionCode."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersionName) -and
    $ExportPresetText -notmatch ("(?m)^version/name=`"{0}`"`r?$" -f [regex]::Escape($ExpectedVersionName))) {
    throw "Build commit export preset does not contain version/name=`"$ExpectedVersionName`"."
}
$ShortCommit = $ResolvedCommit.Substring(0, 12)
$StageParent = Join-Path (Split-Path $ProjectRoot -Parent) "HardCore-android-staging"
$StageName = "{0}-{1}-{2}" -f $ShortCommit, (Get-Date -Format "yyyyMMdd-HHmmss"), ([guid]::NewGuid().ToString("N").Substring(0, 8))
$StagePath = Join-Path $StageParent $StageName
$ResolvedOutputDirectory = [System.IO.Path]::GetFullPath((Split-Path $OutputApk -Parent))
$ResolvedOutputApk = Join-Path $ResolvedOutputDirectory (Split-Path $OutputApk -Leaf)

Write-Output "ANDROID_ISOLATED_BUILD_PREFLIGHT_PASS"
Write-Output "CONTRACT=release.android.isolated_build.v1"
Write-Output "COMMIT=$ResolvedCommit"
Write-Output "STAGE=$StagePath"
Write-Output "OUTPUT_APK=$ResolvedOutputApk"
Write-Output "BASELINE_APK=$BaselineApkPath"
Write-Output "EXPECTED_VERSION_CODE=$ExpectedVersionCode"
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersionName)) {
    Write-Output "EXPECTED_VERSION_NAME=$ExpectedVersionName"
}

if ($PreflightOnly) {
    return
}

New-Item -ItemType Directory -Path $StageParent -Force | Out-Null
New-Item -ItemType Directory -Path $ResolvedOutputDirectory -Force | Out-Null

$StageCreated = $false
$BuildSucceeded = $false
try {
    & git -C $ProjectRoot worktree add --detach $StagePath $ResolvedCommit
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create isolated build worktree."
    }
    $StageCreated = $true

    $StageProjectPath = [System.IO.Path]::GetFullPath($StagePath)
    $SafeStageParent = [System.IO.Path]::GetFullPath($StageParent) + [System.IO.Path]::DirectorySeparatorChar
    if ($StageProjectPath -eq $ProjectRoot -or
        -not $StageProjectPath.StartsWith($SafeStageParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing unsafe isolated stage path: $StageProjectPath"
    }
    if (Test-Path -LiteralPath (Join-Path $StageProjectPath ".godot")) {
        throw "Fresh isolated stage unexpectedly contains an existing Godot cache."
    }

    $StageOutputDirectory = Join-Path $StageProjectPath "outputs\hardcore"
    New-Item -ItemType Directory -Path $StageOutputDirectory -Force | Out-Null
    $StageApk = Join-Path $StageOutputDirectory "HardCore-isolated-debug.apk"
    $ImportLog = Join-Path $StageProjectPath "outputs\android_isolated_import.log"
    $ExportLog = Join-Path $StageProjectPath "outputs\android_isolated_export.log"
    $RuntimeAppData = Join-Path $StageProjectPath ".godot\runtime_appdata"
    New-Item -ItemType Directory -Path $RuntimeAppData -Force | Out-Null

    $PreviousAppData = $env:APPDATA
    $PreviousJavaHome = $env:JAVA_HOME
    $PreviousAndroidHome = $env:ANDROID_HOME
    $PreviousAndroidSdkRoot = $env:ANDROID_SDK_ROOT
    try {
        $JavaHome = Get-ChildItem (Join-Path $AndroidRoot "jdk") -Directory | Select-Object -First 1 -ExpandProperty FullName
        $env:APPDATA = $RuntimeAppData
        $env:JAVA_HOME = $JavaHome
        $env:ANDROID_HOME = Join-Path $AndroidRoot "sdk"
        $env:ANDROID_SDK_ROOT = Join-Path $AndroidRoot "sdk"

        & $GodotConsole --headless --path $StageProjectPath --log-file $ImportLog --import
        if ($LASTEXITCODE -ne 0) {
            throw "Godot isolated import failed. Log: $ImportLog"
        }
        & $GodotConsole --headless --path $StageProjectPath --log-file $ExportLog --export-debug "Android" $StageApk
        if ($LASTEXITCODE -ne 0) {
            throw "Godot isolated Android export failed. Log: $ExportLog"
        }
    }
    finally {
        $env:APPDATA = $PreviousAppData
        $env:JAVA_HOME = $PreviousJavaHome
        $env:ANDROID_HOME = $PreviousAndroidHome
        $env:ANDROID_SDK_ROOT = $PreviousAndroidSdkRoot
    }

    if (-not (Test-Path -LiteralPath $StageApk -PathType Leaf)) {
        throw "Godot reported success but did not create the isolated APK: $StageApk"
    }
    Copy-Item -LiteralPath $StageApk -Destination $ResolvedOutputApk -Force

    & (Join-Path $PSScriptRoot "verify_android_build.ps1") `
        -ApkPath $ResolvedOutputApk `
        -AndroidRoot $AndroidRoot `
        -BaselineApkPath $BaselineApkPath `
        -ExpectedVersionCode $ExpectedVersionCode `
        -ExpectedVersionName $ExpectedVersionName
    if ($LASTEXITCODE -ne 0) {
        throw "Isolated Android APK verification failed."
    }

    $BuildSucceeded = $true
    Write-Output "ANDROID_ISOLATED_BUILD_PASS"
    Write-Output "APK=$ResolvedOutputApk"
    Write-Output "SHA256=$((Get-FileHash -LiteralPath $ResolvedOutputApk -Algorithm SHA256).Hash)"
}
finally {
    if ($StageCreated -and $BuildSucceeded -and -not $KeepStage) {
        $SafeStagePath = [System.IO.Path]::GetFullPath($StagePath)
        $SafeStageParent = [System.IO.Path]::GetFullPath($StageParent) + [System.IO.Path]::DirectorySeparatorChar
        if ($SafeStagePath -eq $ProjectRoot -or -not $SafeStagePath.StartsWith($SafeStageParent, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe isolated stage cleanup: $SafeStagePath"
        }
        & git -C $ProjectRoot worktree remove --force $SafeStagePath
        if ($LASTEXITCODE -ne 0) {
            throw "Isolated build succeeded, but its disposable worktree could not be removed: $SafeStagePath"
        }
        & git -C $ProjectRoot worktree prune
    }
    elseif ($StageCreated) {
        Write-Warning "Isolated build stage preserved for diagnostics: $StagePath"
    }
}
