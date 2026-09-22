$ErrorActionPreference = 'Stop'
$root = 'C:\Users\Administrator\Documents\HardCore'
$stage = 'C:\Users\Administrator\Documents\HardCore-android-staging\abbb5efbaba3-20260922-222708-8c8f94e6'
$source = 'abbb5efbaba3b4d3f539f674b52b27ca2dc9f16e'
$apk = 'C:\Users\Administrator\Desktop\HardCore-v92-20260922-abbb5ef-debug.apk'
$baseline = 'D:\HardCoreAudit\HardCore-20260922-rv15-loot-overlay-85d37077-v91-debug.apk'
$stageApk = Join-Path $stage 'outputs/hardcore/HardCore-isolated-debug.apk'
$godot = Join-Path $root 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
$settings = Join-Path $root 'tools/godot-4.7/editor_data/editor_settings-4.7.tres'
$savedSettings = [IO.File]::ReadAllBytes($settings)
$settingsHash = (Get-FileHash -LiteralPath $settings).Hash
if ((& git -C $stage rev-parse HEAD) -ne $source) { throw 'Wrong staging source' }
$build = Get-Content (Join-Path $stage 'assets/generated/build_info.json') -Raw | ConvertFrom-Json
if ($build.git_head -ne $source -or $build.git_dirty -ne $false -or $build.version_code -ne 92) { throw 'Wrong staged build identity' }
if (Test-Path -LiteralPath $apk) { throw 'Refuse to overwrite a desktop APK' }
# Process-local repair for the reproduced PipeImpl/UnixDomainSockets failure.
$env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:/Windows/Temp'
$env:JAVA_HOME = Join-Path $root 'tools/android-build/jdk/jdk-17.0.20+8'
$env:ANDROID_HOME = Join-Path $root 'tools/android-build/sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:APPDATA = Join-Path $stage '.godot/runtime_appdata'
try {
    $text = [IO.File]::ReadAllText($settings)
    $text = [regex]::Replace($text, '(?m)^export/android/java_sdk_path = ".*"$', 'export/android/java_sdk_path = "' + $env:JAVA_HOME.Replace('\','/') + '"')
    $text = [regex]::Replace($text, '(?m)^export/android/android_sdk_path = ".*"$', 'export/android/android_sdk_path = "' + $env:ANDROID_HOME.Replace('\','/') + '"')
    [IO.File]::WriteAllText($settings, $text, [Text.UTF8Encoding]::new($false))
    & (Join-Path $root 'tools/verify_wall_render_bindings.ps1') -ProjectRoot $stage
    $log = Join-Path $stage 'outputs/android_isolated_export_retry.log'
    $stdout = Join-Path $stage 'outputs/android_isolated_export_retry_stdout.log'
    $stderr = Join-Path $stage 'outputs/android_isolated_export_retry_stderr.log'
    $process = Start-Process $godot -ArgumentList @('--headless','--path',$stage,'--log-file',$log,'--export-debug','Android',$stageApk) -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $deadline = (Get-Date).AddMinutes(10)
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $process.Refresh()
        if (Test-Path -LiteralPath $stageApk) {
            $length = (Get-Item -LiteralPath $stageApk).Length
            Start-Sleep -Seconds 2
            $process.Refresh()
            if (-not $process.HasExited -and $length -gt 0 -and (Get-Item -LiteralPath $stageApk).Length -eq $length -and (Get-Content -LiteralPath $log -Raw) -match '\[ DONE \].*export') {
                Stop-Process -Id $process.Id -Force
                $process.WaitForExit()
                break
            }
        }
    }
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force; throw 'Export timed out' }
    if (-not (Test-Path -LiteralPath $stageApk)) { throw 'No APK produced' }
    $errors = @(Select-String -Path $log,$stderr -Pattern '^ERROR:|^SCRIPT ERROR:')
    if ($errors.Count -gt 0) { throw 'Retry export contains errors; inspect preserved logs' }
    Copy-Item -LiteralPath $stageApk -Destination $apk
}
finally {
    [IO.File]::WriteAllBytes($settings, $savedSettings)
}
if ((Get-FileHash -LiteralPath $settings).Hash -ne $settingsHash) { throw 'Portable settings restore mismatch' }
# Reuse the source build script's exact splash verifier without running its build body.
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tools/build_android_isolated.ps1'), [ref]$tokens, [ref]$parseErrors)
$function = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-AndroidSplashTheme'}, $true)
if (-not $function -or $parseErrors.Count -gt 0) { throw 'Cannot load tracked splash verifier' }
. ([ScriptBlock]::Create($function.Extent.Text))
Assert-AndroidSplashTheme -ApkPath $apk -AndroidRoot (Join-Path $root 'tools/android-build')
& (Join-Path $root 'tools/verify_android_build.ps1') -ApkPath $apk -BaselineApkPath $baseline -ExpectedVersionCode 92 -ExpectedVersionName 'hardcore 1.0 正式版' -ExpectedCommit $source
if ($LASTEXITCODE -ne 0) { throw 'APK identity verification failed' }
Write-Output 'ANDROID_ISOLATED_RESUME_BUILD_PASS'
