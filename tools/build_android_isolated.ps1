param(
    [string]$Commit = "HEAD",
    [string]$OutputApk = "",
    [string]$GodotConsole = "",
    [string]$AndroidRoot = "",
    [string]$BaselineApkPath = "",
    [int]$ExpectedVersionCode = 0,
    [string]$ExpectedVersionName = "",
    [int]$VersionCode = 0,
    [string]$PreparedStagePath = "",
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
    $TransparentIconMatch = [regex]::Match(
        $SplashBlock,
        '(?i)windowSplashScreenAnimatedIcon[^\r\n]*=@(?<resource>android:color/transparent|0x[0-9a-f]+)'
    )
    if (-not $TransparentIconMatch.Success) {
        throw "APK GodotAppSplashTheme does not use a transparent Android 12 splash icon: $ApkPath"
    }
    $TransparentIconResource = $TransparentIconMatch.Groups['resource'].Value
    if ($TransparentIconResource.StartsWith('0x', [System.StringComparison]::OrdinalIgnoreCase)) {
        # aapt2 resolves @android:color/transparent to its public framework
        # resource id in the compiled APK. Verify that id against the same SDK
        # platform instead of accepting an arbitrary reference.
        $PlatformJar = Get-ChildItem -LiteralPath (Join-Path $AndroidRoot 'sdk\platforms') -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'android.jar' } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace([string]$PlatformJar)) {
            throw "Android splash verification requires android.jar under the configured SDK."
        }
        $FrameworkDump = ((& $Aapt2 dump resources $PlatformJar 2>&1) -join "`n")
        $TransparentPattern = '(?ims)^\s*resource\s+' + [regex]::Escape($TransparentIconResource) + '\s+color/transparent\s+PUBLIC\s*$[\s\S]{0,120}?#[0]{8}'
        if ($LASTEXITCODE -ne 0 -or $FrameworkDump -notmatch $TransparentPattern) {
            throw "APK splash icon resource is not the SDK public transparent color: @$TransparentIconResource"
        }
    }
    if ($SplashBlock -notmatch '(?i)(#ff000000|#000000|0xff000000)') {
        throw "APK GodotAppSplashTheme does not contain the black BrandIntro startup background: $ApkPath"
    }
    Write-Output "ANDROID_SPLASH_THEME_VERIFY_PASS"
}

function Read-GitUtf8Blob {
    param([string]$Revision, [string]$RelativePath)
    # Git emits blob bytes as UTF-8, independently of the Windows console locale.
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = 'git.exe'
    $info.Arguments = '-C "' + $ProjectRoot + '" show "' + $Revision + ':' + $RelativePath + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Unable to start Git blob read.' }
        $output = $process.StandardOutput.ReadToEnd()
        $failure = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw ("Git blob read failed: {0} {1}" -f $RelativePath, $failure) }
        return $output
    } finally { $process.Dispose() }
}

$ResolvedCommitOutput = @(& git -C $ProjectRoot rev-parse --verify "$Commit^{commit}")
if ($LASTEXITCODE -ne 0 -or $ResolvedCommitOutput.Count -ne 1) {
    throw "Unable to resolve build commit: $Commit"
}
$ResolvedCommit = ([string]$ResolvedCommitOutput[0]).Trim()
if ([string]::IsNullOrWhiteSpace($ResolvedCommit)) {
    throw "Unable to resolve build commit: $Commit"
}
$ExportPresetText = Read-GitUtf8Blob $ResolvedCommit 'export_presets.cfg'
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
    '"[splash]windowSplashScreenAnimatedIcon": "@android:color/transparent"',
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
# QA override (remote review 2026-09-16): each device QA APK carries a
# monotonic versionCode (83, 84, ...), injected into the disposable stage
# only - the tracked export preset stays untouched.
if ($VersionCode -gt 0) {
    $ExpectedVersionCode = $VersionCode
}
if ($ExpectedVersionCode -le 0) {
    $ExpectedVersionCode = $PresetVersionCode
}
elseif ($VersionCode -le 0 -and $PresetVersionCode -ne $ExpectedVersionCode) {
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
$ProjectConfigText = Read-GitUtf8Blob $ResolvedCommit 'project.godot'
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
if (-not [string]::IsNullOrWhiteSpace($PreparedStagePath)) {
    # A Codex-managed, clean checkout may be supplied instead of creating a
    # second worktree. Its lifecycle stays with the caller; never remove it.
    $StagePath = (Resolve-Path -LiteralPath $PreparedStagePath).Path
    $StageTop = ((& git -C $StagePath rev-parse --show-toplevel) -join '').Trim()
    $StageHead = ((& git -C $StagePath rev-parse HEAD) -join '').Trim()
    $StageCommon = ((& git -C $StagePath rev-parse --path-format=absolute --git-common-dir) -join '').Trim()
    $SourceCommon = ((& git -C $ProjectRoot rev-parse --path-format=absolute --git-common-dir) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or $StageHead -ne $ResolvedCommit -or $StageCommon -ne $SourceCommon -or
        [IO.Path]::GetFullPath($StageTop) -ne [IO.Path]::GetFullPath($StagePath) -or $StagePath -eq $ProjectRoot) {
        throw "Prepared stage must be a separate worktree of this repository at the exact build commit."
    }
    $StageStatus = @(& git -C $StagePath status --porcelain --untracked-files=normal)
    if ($LASTEXITCODE -ne 0 -or $StageStatus.Count -gt 0 -or (Test-Path -LiteralPath (Join-Path $StagePath '.godot'))) {
        throw "Prepared stage must be clean and have no Godot import cache."
    }
    $StageParent = Split-Path $StagePath -Parent
}
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
    if ([string]::IsNullOrWhiteSpace($PreparedStagePath)) {
        # v98 regression fix (GPT Pro review 2026-10-06): the host default
        # core.autocrlf=true re-writes LF-blob identity JSONs to CRLF in a
        # fresh stage, so GameData's raw-byte identity checks fail on the
        # device even though the dev tree (historical LF checkout) passes.
        # Check the stage out as pure blob bytes: LF sources land as LF,
        # i/crlf sources land as CRLF - every registered hash then matches.
        # Git's normal progress is stderr, not a PowerShell terminating error.
        # Retain both streams and use the actual native exit status.
        $GitCreate = Start-Process -FilePath 'git.exe' -ArgumentList @('-c','core.autocrlf=false','-C',([char]34+$ProjectRoot+[char]34),'worktree','add','--detach',([char]34+$StagePath+[char]34),$ResolvedCommit) -RedirectStandardOutput ($StagePath + '.create.stdout.log') -RedirectStandardError ($StagePath + '.create.stderr.log') -PassThru -Wait -WindowStyle Hidden
        if ($GitCreate.ExitCode -ne 0) {
            throw ("Unable to create isolated build worktree, exit={0}; see {1}.create.stderr.log" -f $GitCreate.ExitCode, $StagePath)
        }
        $StageCreated = $true
    }

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
            ($Tab + $Tab + '<item name="windowSplashScreenAnimatedIcon">@android:color/transparent</item>'),
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
        if ($StageThemesText -notmatch 'windowSplashScreenAnimatedIcon.*@android:color/transparent' -or $StageThemesText -notmatch 'windowSplashScreenBrandingImage.*@null') {
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
        & powershell -ExecutionPolicy Bypass -File $BuildInfoScript -StageRoot $StageProjectPath -IgnoreAndroidBuildTemplate -VersionCodeOverride $VersionCode
        $BuildInfoExitCode = $LASTEXITCODE
        if ($BuildInfoExitCode -ne 0) {
            throw "Build-info generation failed with exit code $BuildInfoExitCode."
        }
        Write-Output "build_info.json generated in staged project"

        # QA versionCode override (remote review 2026-09-16): inject the QA
        # code into the staged export preset AFTER build-info generation
        # (the generator records the same code via -VersionCodeOverride and
        # still runs on the pure commit content, keeping git_dirty=false for
        # the verify contract). The tracked preset is untouched.
        if ($VersionCode -gt 0) {
            $StagePresetPath = Join-Path $StageProjectPath "export_presets.cfg"
            $StagePresetText = [System.IO.File]::ReadAllText($StagePresetPath)
            if (-not $StagePresetText -match '(?m)^version/code=\d+\r?$') {
                throw "Staged export preset has no readable version/code to override."
            }
            $Utf8NoBomPreset = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText(
                $StagePresetPath,
                [regex]::Replace($StagePresetText, '(?m)^version/code=\d+', "version/code=$VersionCode"),
                $Utf8NoBomPreset
            )
            Write-Output "VERSION_CODE_OVERRIDE=$VersionCode"
        }

        # v98 regression gate (GPT Pro review 2026-10-06): the identity
        # registry pins raw-byte SHA256 hashes for its source JSONs and
        # GameData refuses to load on any mismatch. Verify the stage bytes
        # against those registered hashes BEFORE import/export so a bad
        # checkout fails here instead of on the device.
        $StageIdentityRegistry = Join-Path $StageProjectPath "assets\data\runtime\entity_registry_v1.json"
        if (-not (Test-Path -LiteralPath $StageIdentityRegistry -PathType Leaf)) {
            throw "Stage identity registry missing: $StageIdentityRegistry"
        }
        $RegistryText = [System.IO.File]::ReadAllText($StageIdentityRegistry)
        $IdentityEntries = [regex]::Matches($RegistryText, '"res://(assets/data/[^"]+\.json)":\s*"([0-9a-f]{64})"')
        if ($IdentityEntries.Count -eq 0) {
            throw "No registered identity source hashes found in $StageIdentityRegistry"
        }
        $IdentitySha = [System.Security.Cryptography.SHA256]::Create()
        $IdentityFailed = 0
        foreach ($Entry in $IdentityEntries) {
            $RelPath = $Entry.Groups[1].Value -replace '/', [System.IO.Path]::DirectorySeparatorChar
            $StageSource = Join-Path $StageProjectPath $RelPath
            if (-not (Test-Path -LiteralPath $StageSource -PathType Leaf)) {
                Write-Output "IDENTITY_BYTE_GATE MISSING: $($Entry.Groups[1].Value)"
                $IdentityFailed++
                continue
            }
            $Actual = [BitConverter]::ToString($IdentitySha.ComputeHash([System.IO.File]::ReadAllBytes($StageSource))).Replace('-', '').ToLower()
            if ($Actual -ne $Entry.Groups[2].Value) {
                Write-Output "IDENTITY_BYTE_GATE MISMATCH: $($Entry.Groups[1].Value) actual=$($Actual.Substring(0,12)) expected=$($Entry.Groups[2].Value.Substring(0,12))"
                $IdentityFailed++
            }
        }
        if ($IdentityFailed -gt 0) {
            throw "Stage identity byte gate failed for $IdentityFailed of $($IdentityEntries.Count) registered sources."
        }
        Write-Output "IDENTITY_BYTE_GATE PASS files=$($IdentityEntries.Count)"

        & (Join-Path $StageProjectPath 'tools/verify_wall_render_bindings.ps1') -ProjectRoot $StageProjectPath
        & $GodotConsole --headless --path $StageProjectPath --log-file $ImportLog --import
        $ImportExitCode = $LASTEXITCODE
        if ($ImportExitCode -ne 0) {
            # On a fresh checkout, Godot can finish the full import and then
            # return a nonzero exit status while closing its first editor run.
            # Retry only when the recorded import completed without errors;
            # the second run must exit successfully before export can proceed.
            $ImportText = Get-Content -LiteralPath $ImportLog -Raw
            if ($ImportText -notmatch '\[ DONE \] reimport' -or $ImportText -match '(?m)^ERROR:') {
                throw "Godot isolated import failed. Log: $ImportLog"
            }
            $ImportRetryLog = Join-Path $StageProjectPath "outputs\android_isolated_import_retry.log"
            Write-Warning "Fresh isolated import completed but exited $ImportExitCode; retrying once with the same imported cache."
            & $GodotConsole --headless --path $StageProjectPath --log-file $ImportRetryLog --import
            $ImportExitCode = $LASTEXITCODE
            if ($ImportExitCode -ne 0) {
                throw "Godot isolated import retry failed. Logs: $ImportLog, $ImportRetryLog"
            }
        }
        # Two-pass Android seal export (GPT Pro directive 2026-10-06, promoted
        # from the reviewed runtime_bridge_candidate). Pass 1 exports with the
        # tracked placeholder metadata; build_android_seal.py binds the actual
        # APK/template/source bytes; pass 2 exports with the generated
        # AVAILABLE=true metadata. Between passes only that one generated file
        # may change and every frozen input is re-verified by the hook.
        . (Join-Path $ProjectRoot 'tools\android_seal\bridge\android_two_pass_export_hook.ps1')
        $RealEngineExe = Join-Path $ProjectRoot "tools\godot-4.7\Godot_v4.7-stable_win64.exe"
        $TemplateApk = Join-Path $ProjectRoot "tools\godot-4.7\editor_data\export_templates\4.7.stable\android_debug.apk"
        $TemplateSha = (Get-FileHash -LiteralPath $TemplateApk -Algorithm SHA256).Hash.ToLowerInvariant()
        $ApkSigner = Join-Path $AndroidRoot "sdk\build-tools\35.0.1\apksigner.bat"
        $PythonExe = (Get-Command python).Source
        $SealEvidenceRoot = Join-Path $StageParent ("seal-evidence-" + (Split-Path $StagePath -Leaf))
        # The stage worktree has no engine assets; the runner inside the stage
        # resolves the engine through a junction to the host tree's engine so
        # the capture scenes execute the exact bytes recorded in the namespace.
        $StageEngineLink = Join-Path $StageProjectPath "tools\godot-4.7"
        if (-not (Test-Path -LiteralPath $StageEngineLink)) {
            $GodotDirectory = Split-Path -Parent $GodotConsole
            cmd /c mklink /J "$StageEngineLink" "$GodotDirectory" | Out-Null
        }
        $RegenerateStageCatalogue = {
            param($StageRoot, $EvidenceRoot)
            $Sha256 = [System.Security.Cryptography.SHA256]::Create()
            $contentStream = New-Object System.IO.MemoryStream
            Get-ChildItem (Join-Path $StageRoot 'scripts') -Recurse -Filter '*.gd' | Sort-Object FullName | ForEach-Object {
                $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                $contentStream.Write($bytes, 0, $bytes.Length)
            }
            $previousContentSha = $env:HARDCORE_R3_CONTENT_SHA256
            $previousAuditAppData = $env:HARDCORE_AUDIT_RUNTIME_APPDATA
            $env:HARDCORE_R3_CONTENT_SHA256 = [BitConverter]::ToString($Sha256.ComputeHash($contentStream.ToArray())).Replace('-', '').ToLower()
            $frameworkDir = Join-Path $StageRoot 'outputs\test_logs\framework'
            $artifacts = [ordered]@{
                namespace = 'code_preparation_engine_namespace_capture_test.namespace.json'
                symbols = 'code_preparation_native_symbol_probe_test.symbols.json'
                fold = 'code_preparation_scalar_math_probe_test.symbols.json'
            }
            $sceneByArtifact = [ordered]@{
                namespace = 'tests/framework/code_preparation_engine_namespace_capture_test.tscn'
                symbols = 'tests/framework/code_preparation_native_symbol_probe_test.tscn'
                fold = 'tests/framework/code_preparation_scalar_math_probe_test.tscn'
            }
            try {
                foreach ($key in $artifacts.Keys) {
                    $runAppData = Join-Path $StageRoot ".godot\runtime_appdata\seal_$key\"
                    $env:HARDCORE_AUDIT_RUNTIME_APPDATA = $runAppData
                    & pwsh -NoProfile -File (Join-Path $StageRoot 'tools\run_godot_tests.ps1') -TestPaths $sceneByArtifact[$key] -TimeoutSeconds 30 | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "Stage capture scene failed: $($sceneByArtifact[$key])" }
                    $artifactPath = Join-Path $frameworkDir $artifacts[$key]
                    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { throw "Missing stage capture artifact: $($artifacts[$key])" }
                }
            } finally {
                $env:HARDCORE_R3_CONTENT_SHA256 = $previousContentSha
                $env:HARDCORE_AUDIT_RUNTIME_APPDATA = $previousAuditAppData
            }
            $namespacePath = Join-Path $frameworkDir $artifacts['namespace']
            $symbolsPath = Join-Path $frameworkDir $artifacts['symbols']
            $foldPath = Join-Path $frameworkDir $artifacts['fold']
            $planPath = Join-Path $EvidenceRoot 'caster_inputs.json'
            $null = & $PythonExe -B (Join-Path $StageRoot 'tools\compile_code_preparation_inputs.py') `
                --root $StageRoot --class-cache (Join-Path $StageRoot '.godot\global_script_class_cache.cfg') `
                --max-source-nodes 64 --entry res://scripts/caster_skill_animation_player.gd `
                --native-namespace $namespacePath --expected-engine-binary-sha256 (Get-FileHash -LiteralPath $RealEngineExe -Algorithm SHA256).Hash.ToLower() `
                --global-symbols $symbolsPath --expected-global-symbols-sha256 (Get-FileHash -LiteralPath $symbolsPath -Algorithm SHA256).Hash.ToLower() `
                --fold-symbols $foldPath --expected-fold-symbols-sha256 (Get-FileHash -LiteralPath $foldPath -Algorithm SHA256).Hash.ToLower() `
                --out $planPath
            if ($LASTEXITCODE -ne 0) { throw 'Stage source plan generation failed.' }
            $cataloguePath = Join-Path $EvidenceRoot 'generated\internal_code_preparation_catalog_data.gd'
            $null = & $PythonExe -B (Join-Path $StageRoot 'tools\build_internal_code_catalogue.py') `
                --root $StageRoot --class-cache (Join-Path $StageRoot '.godot\global_script_class_cache.cfg') `
                --max-source-nodes 64 --entry-id framework.code.caster_animation.v1 `
                --expected-producer-sha256 (Get-FileHash -LiteralPath (Join-Path $StageRoot 'tools\compile_code_preparation_inputs.py') -Algorithm SHA256).Hash.ToLower() `
                --plan $planPath --namespace $namespacePath --symbols $symbolsPath --fold $foldPath `
                --expected-namespace-sha256 (Get-FileHash -LiteralPath $namespacePath -Algorithm SHA256).Hash.ToLower() `
                --expected-symbols-sha256 (Get-FileHash -LiteralPath $symbolsPath -Algorithm SHA256).Hash.ToLower() `
                --expected-fold-sha256 (Get-FileHash -LiteralPath $foldPath -Algorithm SHA256).Hash.ToLower() `
                --out $cataloguePath
            if ($LASTEXITCODE -ne 0) { throw 'Stage catalogue generation failed.' }
            # The sealed source bundle must be the one the APK actually loads,
            # not merely the external evidence copy used by the collector.
            $InstalledCatalogue = Join-Path $StageRoot 'scripts\features\generated\internal_code_preparation_catalog_data.gd'
            Copy-Item -LiteralPath $cataloguePath -Destination $InstalledCatalogue -Force
            if ((Get-FileHash -LiteralPath $InstalledCatalogue -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $cataloguePath -Algorithm SHA256).Hash) { throw 'Installed stage catalogue byte mismatch.' }
            return @{
                SourceCatalogue = $InstalledCatalogue
                SourcePlan = $planPath
                Producer = (Join-Path $StageRoot 'tools\compile_code_preparation_inputs.py')
                Namespace = $namespacePath
                EntryId = 'framework.code.caster_animation.v1'
            }
        }
        $VerifyProductionBuild = {
            param($ApkPath, $Commit)
            & (Join-Path $ProjectRoot 'tools\verify_android_build.ps1') -ApkPath $ApkPath -AndroidRoot $AndroidRoot `
                -BaselineApkPath $BaselineApkPath -ExpectedVersionCode $ExpectedVersionCode `
                -ExpectedVersionName $ExpectedVersionName -ExpectedCommit $Commit
            if ($LASTEXITCODE -ne 0) { throw "Isolated Android APK verification failed." }
        }
        $FinalExport = Invoke-TwoPassAndroidCodeExport -StageRoot $StageProjectPath -GodotConsole $RealEngineExe `
            -Python $PythonExe -OutputApk $StageApk -EvidenceRoot $SealEvidenceRoot -SourceCommit $ResolvedCommit `
            -TemplateApk $TemplateApk -ExpectedTemplateSha256 $TemplateSha -BaselineApk $BaselineApkPath `
            -ApkSigner $ApkSigner -RegenerateStageCatalogue $RegenerateStageCatalogue -VerifyProductionBuild $VerifyProductionBuild
        Write-Output ("TWO_PASS_SEAL_EXPORT_PASS final=" + $FinalExport.apk_sha256)
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
