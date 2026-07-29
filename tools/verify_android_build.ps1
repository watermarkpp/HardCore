param(
    [string]$ApkPath = "",
    [string]$AndroidRoot = "",
    [string]$BaselineApkPath = "",
    [int]$ExpectedVersionCode = 37,
    [string]$ExpectedVersionName = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
$ProjectRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $ProjectRoot "outputs\hardcore\HardCore-integrated-v37-debug.apk"
}
if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK does not exist: $ApkPath"
}
if ([string]::IsNullOrWhiteSpace($BaselineApkPath)) {
    $BaselineApkPath = Join-Path $ProjectRoot "outputs\hardcore\HardCore-debug.apk"
}
if (-not (Test-Path -LiteralPath $BaselineApkPath)) {
    throw "Baseline APK does not exist: $BaselineApkPath"
}
if ([string]::IsNullOrWhiteSpace($AndroidRoot)) {
    $AndroidRoot = $env:ANDROID_BUILD_ROOT
}
if ([string]::IsNullOrWhiteSpace($AndroidRoot)) {
    $AndroidRoot = Join-Path $ProjectRoot "tools\android-build"
}
if (-not (Test-Path -LiteralPath $AndroidRoot)) {
    throw "Android build tools do not exist. Pass -AndroidRoot or set ANDROID_BUILD_ROOT: $AndroidRoot"
}

$JavaHome = Get-ChildItem (Join-Path $AndroidRoot "jdk") -Directory | Select-Object -First 1 -ExpandProperty FullName
$BuildTools = Get-ChildItem (Join-Path $AndroidRoot "sdk\build-tools") -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
$Aapt = Join-Path $BuildTools "aapt.exe"
$ApkSigner = Join-Path $BuildTools "apksigner.bat"
$env:JAVA_HOME = $JavaHome

& $ApkSigner verify --verbose $ApkPath
if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed." }

$Badging = (& $Aapt dump badging $ApkPath) -join "`n"
$Manifest = (& $Aapt dump xmltree $ApkPath AndroidManifest.xml) -join "`n"
$ExpectedBadging = @(
    "name='com.personal.mafaoffline'",
    "versionCode='$ExpectedVersionCode'",
    "sdkVersion:'24'",
    "targetSdkVersion:'36'",
    "application-label:'HardCore'",
    "native-code: 'arm64-v8a'"
)
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersionName)) {
    $ExpectedBadging += "versionName='$ExpectedVersionName'"
}
foreach ($Expected in $ExpectedBadging) {
    if ($Badging -notlike "*$Expected*") { throw "APK metadata is missing: $Expected" }
}
if ($Manifest -notlike "*android:screenOrientation*0xb*") { throw "APK does not use the required landscape user rotation mode." }
if ($Manifest -notlike "*android:resizeableActivity*0x1*") { throw "APK does not enable resizeableActivity." }

& (Join-Path $PSScriptRoot "verify_apk_runtime_resources.ps1") `
    -ApkPath $ApkPath `
    -BaselineApkPath $BaselineApkPath
if ($LASTEXITCODE -ne 0) {
    throw "APK runtime resource probe failed."
}

$File = Get-Item -LiteralPath $ApkPath
$Hash = Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256
Write-Output "ANDROID_APK_VERIFY_PASS"
Write-Output "APK=$($File.FullName)"
Write-Output "SIZE=$($File.Length)"
Write-Output "SHA256=$($Hash.Hash)"
Write-Output ($Badging -split "`n" | Where-Object { $_ -match "^(package:|sdkVersion:|targetSdkVersion:|application-label:|native-code:)" })
