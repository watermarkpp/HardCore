param(
    [string]$Commit = "HEAD",
    [string]$OutputApk = "",
    [string]$GodotConsole = "",
    [string]$AndroidRoot = "",
    [string]$BaselineApkPath = "",
    [int]$ExpectedVersionCode = 0,
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

function Assert-AndroidSplashTheme {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApkPath,
        [Parameter(Mandatory = $true)]
        [string]$AndroidRoot
    )

    $BuildToolsPath = Join-Path $AndroidRoot "sdk\build-tools"
    $Aapt2 = Get-ChildItem -LiteralPath $BuildToolsPath -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "aapt2.exe" } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$Aapt2)) {
        throw "Android splash verification requires aapt2.exe under: $BuildToolsPath"
    }

    $ResourceDump = ((& $Aapt2 dump resources $ApkPath 2>&1) -join "`n")
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ResourceDump)) {
        throw "Unable to dump Android resources for splash verification: $ApkPath"
    }
    $SplashMatches = [regex]::Matches(
        $ResourceDump,
        '(?ms)^\s*resource\s+0x[0-9a-f]+\s+style/GodotAppSplashTheme.*?(?=^\s*resource\s+0x[0-9a-f]+\s+style/|\z)'
    )
    if ($SplashMatches.Count -lt 1) {
        throw "APK has no GodotAppSplashTheme resource: $ApkPath"
    }
    $SplashBlock = ($SplashMatches | ForEach-Object { $_.Value }) -join "`n"
    if ($SplashBlock -match 'splash_icon|icon_background') {
        throw "APK GodotAppSplashTheme still references the launcher/splash icon: $ApkPath"
    }
    if ($SplashBlock -notmatch '(?i)windowSplashScreenAnimatedIcon[\s\S]{0,120}@null') {
        throw "APK GodotAppSplashTheme does not disable the Android 12 splash icon: $ApkPath"
    }
    if ($SplashBlock -notmatch '(?i)(#ff000000|#000000|0xff000000)') {
        throw "APK GodotAppSplashTheme does not contain the black BrandIntro startup background: $ApkPath"
    }
    Write-Output "ANDROID_SPLASH_THEME_VERIFY_PASS"
}

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
if ($ExportPresetText -notmatch '(?m)^gradle_build/custom_theme_attributes=\{') {
    throw "Build commit Android preset must use a Dictionary for gradle_build/custom_theme_attributes."
}
foreach ($RequiredSplashAttribute in @(
    '"[splash]android:windowSplashScreenBackground": "#000000"',
    '"[splash]windowSplashScreenBackground": "#000000"',
    '"[splash]android:windowSplashScreenBrandingImage": "@null"',
    '"[splash]windowSplashScreenAnimatedIcon": "@null"',
    '"[splash]android:windowSplashScreenIconBackgroundColor": "#000000"',
    '"[splash]windowSplashScreenIconBackgroundColor": "#000000"'
)) {
    if (-not $ExportPresetText.Contains($RequiredSplashAttribute)) {
        throw "Build commit Android preset is missing required splash theme attribute: $RequiredSplashAttribute"
    }
}
$VersionCodeMatch = [regex]::Match($ExportPresetText, '(?m)^version/code=(\d+)\r?$')
if (-not $VersionCodeMatch.Success) {
    throw "Build commit export preset has no readable version/code."
}
$PresetVersionCode = [int]$VersionCodeMatch.Groups[1].Value
if ($ExpectedVersionCode -le 0) {
    $ExpectedVersionCode = $PresetVersionCode
}
elseif ($PresetVersionCode -ne $ExpectedVersionCode) {
    throw "Build commit export preset contains version/code=$PresetVersionCode, expected $ExpectedVersionCode."
}
$VersionNameMatch = [regex]::Match($ExportPresetText, '(?m)^version/name="([^"]+)"\r?$')
if (-not $VersionNameMatch.Success) {
    throw "Build commit export preset has no readable version/name."
}
$PresetVersionName = $VersionNameMatch.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($ExpectedVersionName)) {
    $ExpectedVersionName = $PresetVersionName
}
elseif ($PresetVersionName -ne $ExpectedVersionName) {
    throw "Build commit export preset contains version/name=`"$PresetVersionName`", expected `"$ExpectedVersionName`"."
}
$ProjectConfigText = (@(& git -C $ProjectRoot show "${ResolvedCommit}:project.godot")) -join "`n"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ProjectConfigText)) {
    throw "Build commit has no readable project.godot: $ResolvedCommit"
}
if ($ProjectConfigText -notmatch ("(?m)^config/version=`"{0}`"`r?$" -f [regex]::Escape($ExpectedVersionName))) {
    throw "Build commit project.godot does not contain config/version=`"$ExpectedVersionName`"."
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

    # Bootstrap the host-managed Gradle template into the disposable stage
    # without network access or mutation of the integration worktree.
    if ($ExportPresetText -match '(?m)^gradle_build/use_gradle_build=true\r?$') {
        $AndroidSourceZip = Join-Path $ProjectRoot "tools\godot-4.7\editor_data\export_templates\4.7.stable\android_source.zip"
        if (-not (Test-Path -LiteralPath $AndroidSourceZip -PathType Leaf)) {
            throw "Gradle Android export is enabled but offline template is missing: $AndroidSourceZip"
        }
        # Godot detects a custom Android build template only at android/build.
        # The official android_source.zip contains the build root itself.
        $StageAndroidPath = [System.IO.Path]::GetFullPath((Join-Path $StageProjectPath "android\build"))
        $SafeStagePrefix = $StageProjectPath + [System.IO.Path]::DirectorySeparatorChar
        if (-not $StageAndroidPath.StartsWith($SafeStagePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe Android template extraction path: $StageAndroidPath"
        }
        New-Item -ItemType Directory -Path $StageAndroidPath -Force | Out-Null
        & tar -xf $AndroidSourceZip -C $StageAndroidPath
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $StageAndroidPath "res\values\themes.xml") -PathType Leaf)) {
            throw "Offline Android template extraction failed: $StageAndroidPath"
        }
        $StageThemesPath = Join-Path $StageAndroidPath "res\values\themes.xml"
        $StageThemesText = Get-Content -LiteralPath $StageThemesPath -Raw
        $Tab = [char]9
        $SplashThemeReplacement = @(
            '<style name="GodotAppSplashTheme" parent="Theme.SplashScreen">',
            ($Tab + $Tab + '<item name="android:windowSplashScreenBackground">#000000</item>'),
            ($Tab + $Tab + '<item name="android:windowSplashScreenBrandingImage">@null</item>'),
            ($Tab + $Tab + '<item name="windowSplashScreenAnimatedIcon">@null</item>'),
            ($Tab + $Tab + '<item name="android:windowSplashScreenIconBackgroundColor">#000000</item>'),
            ($Tab + $Tab + '<item name="postSplashScreenTheme">@style/GodotAppMainTheme</item>'),
            ($Tab + $Tab + '<item name="android:windowIsTranslucent">false</item>'),
            ($Tab + '</style>')
        ) -join [Environment]::NewLine
        $StageThemesText = $StageThemesText -replace '(?s)<style name="GodotAppSplashTheme".*?</style>', $SplashThemeReplacement
        $Utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($StageThemesPath, $StageThemesText, $Utf8WithoutBom)
        [System.IO.File]::WriteAllText((Join-Path $StageProjectPath "android\.build_version"), "4.7.stable`n", $Utf8WithoutBom)
        [System.IO.File]::WriteAllText((Join-Path $StageAndroidPath ".gdignore"), "`n", $Utf8WithoutBom)
        if ($StageThemesText -notmatch 'windowSplashScreenAnimatedIcon.*@null' -or $StageThemesText -notmatch 'windowSplashScreenBrandingImage.*@null') {
            throw "Offline Android template splash patch did not apply: $StageThemesPath"
        }
        Write-Output "ANDROID_GRADLE_TEMPLATE_BOOTSTRAP_PASS"
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
    $PortableEditorSettings = Join-Path (Split-Path $GodotConsole -Parent) "editor_data\editor_settings-4.7.tres"
    $PortableEditorSettingsBackup = $null
    try {
        $JavaHome = Get-ChildItem (Join-Path $AndroidRoot "jdk") -Directory | Select-Object -First 1 -ExpandProperty FullName
        $env:APPDATA = $RuntimeAppData
        $env:JAVA_HOME = $JavaHome
        $env:ANDROID_HOME = Join-Path $AndroidRoot "sdk"
        $env:ANDROID_SDK_ROOT = Join-Path $AndroidRoot "sdk"
        if (Test-Path -LiteralPath $PortableEditorSettings -PathType Leaf) {
            $PortableEditorSettingsBackup = [System.IO.File]::ReadAllBytes($PortableEditorSettings)
            $PortableSettingsText = [System.IO.File]::ReadAllText($PortableEditorSettings)
            $PortableSettingsText = [regex]::Replace($PortableSettingsText, '(?m)^export/android/java_sdk_path = ".*"$', 'export/android/java_sdk_path = "' + ($JavaHome -replace '\\', '/') + '"')
            $PortableSettingsText = [regex]::Replace($PortableSettingsText, '(?m)^export/android/android_sdk_path = ".*"$', 'export/android/android_sdk_path = "' + ($env:ANDROID_HOME -replace '\\', '/') + '"')
            [System.IO.File]::WriteAllText($PortableEditorSettings, $PortableSettingsText, (New-Object System.Text.UTF8Encoding($false)))
        }

        # P1-014: generate build_info.json before Godot import so it is included in the APK
        $BuildInfoScript = Join-Path $StageProjectPath "tools/generate_build_info.ps1"
        if (-not (Test-Path -LiteralPath $BuildInfoScript -PathType Leaf)) {
            throw "Staged project has no build-info generator: $BuildInfoScript"
        }
        & powershell -ExecutionPolicy Bypass -File $BuildInfoScript -StageRoot $StageProjectPath -IgnoreAndroidBuildTemplate
        $BuildInfoExitCode = $LASTEXITCODE
        if ($BuildInfoExitCode -ne 0) {
            throw "Build-info generation failed with exit code $BuildInfoExitCode."
        }
        Write-Output "build_info.json generated in staged project"

        & $GodotConsole --headless --path $StageProjectPath --log-file $ImportLog --import
        $ImportExitCode = $LASTEXITCODE
        if ($ImportExitCode -ne 0) {
            throw "Godot isolated import failed. Log: $ImportLog"
        }
        $ExportStdout = Join-Path $StageProjectPath "outputs\android_isolated_export_stdout.log"
        $ExportStderr = Join-Path $StageProjectPath "outputs\android_isolated_export_stderr.log"
        $ExportProcess = Start-Process $GodotConsole -ArgumentList @(
            "--headless", "--path", $StageProjectPath, "--log-file", $ExportLog,
            "--export-debug", "Android", $StageApk
        ) -RedirectStandardOutput $ExportStdout -RedirectStandardError $ExportStderr -WindowStyle Hidden -PassThru
        $ExportDeadline = (Get-Date).AddMinutes(10)
        while (-not $ExportProcess.HasExited -and (Get-Date) -lt $ExportDeadline) {
            Start-Sleep -Seconds 2
            $ExportProcess.Refresh()
            if (Test-Path -LiteralPath $StageApk -PathType Leaf) {
                $FirstLength = (Get-Item -LiteralPath $StageApk).Length
                Start-Sleep -Seconds 2
                $ExportProcess.Refresh()
                if (-not $ExportProcess.HasExited -and (Get-Item -LiteralPath $StageApk).Length -eq $FirstLength -and $FirstLength -gt 0) {
                    $ExportLogText = if (Test-Path $ExportLog) { Get-Content -LiteralPath $ExportLog -Raw } else { "" }
                    if ($ExportLogText -match '\[ DONE \].*export') {
                        Stop-Process -Id $ExportProcess.Id -Force
                        $ExportProcess.WaitForExit()
                        break
                    }
                }
            }
        }
        if (-not $ExportProcess.HasExited) {
            Stop-Process -Id $ExportProcess.Id -Force
            throw "Godot isolated Android export timed out. Log: $ExportLog"
        }
        if (-not (Test-Path -LiteralPath $StageApk -PathType Leaf)) {
            throw "Godot isolated Android export failed. Log: $ExportLog"
        }
    }
    finally {
        if ($null -ne $PortableEditorSettingsBackup) {
            [System.IO.File]::WriteAllBytes($PortableEditorSettings, $PortableEditorSettingsBackup)
        }
        $env:APPDATA = $PreviousAppData
        $env:JAVA_HOME = $PreviousJavaHome
        $env:ANDROID_HOME = $PreviousAndroidHome
        $env:ANDROID_SDK_ROOT = $PreviousAndroidSdkRoot
    }

    if (-not (Test-Path -LiteralPath $StageApk -PathType Leaf)) {
        throw "Godot reported success but did not create the isolated APK: $StageApk"
    }
    Copy-Item -LiteralPath $StageApk -Destination $ResolvedOutputApk -Force

    Assert-AndroidSplashTheme -ApkPath $ResolvedOutputApk -AndroidRoot $AndroidRoot

    & (Join-Path $PSScriptRoot "verify_android_build.ps1") `
        -ApkPath $ResolvedOutputApk `
        -AndroidRoot $AndroidRoot `
        -BaselineApkPath $BaselineApkPath `
        -ExpectedVersionCode $ExpectedVersionCode `
        -ExpectedVersionName $ExpectedVersionName `
        -ExpectedCommit $ResolvedCommit
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
