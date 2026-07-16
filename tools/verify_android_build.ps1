param(
    [string]$ApkPath = "",
    [string]$AndroidRoot = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $ProjectRoot "outputs\legend176\MafaOffline_Bich_Map3_v35-debug.apk"
}
if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK不存在：$ApkPath"
}
if ([string]::IsNullOrWhiteSpace($AndroidRoot)) {
    $AndroidRoot = $env:ANDROID_BUILD_ROOT
}
if ([string]::IsNullOrWhiteSpace($AndroidRoot)) {
    $AndroidRoot = Join-Path $ProjectRoot "tools\android-build"
}
if (-not (Test-Path -LiteralPath $AndroidRoot)) {
    throw "Android构建工具不存在；请传入-AndroidRoot或设置ANDROID_BUILD_ROOT：$AndroidRoot"
}

$JavaHome = Get-ChildItem (Join-Path $AndroidRoot "jdk") -Directory | Select-Object -First 1 -ExpandProperty FullName
$BuildTools = Get-ChildItem (Join-Path $AndroidRoot "sdk\build-tools") -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
$Aapt = Join-Path $BuildTools "aapt.exe"
$ApkSigner = Join-Path $BuildTools "apksigner.bat"
$Adb = Join-Path $AndroidRoot "sdk\platform-tools\adb.exe"
$env:JAVA_HOME = $JavaHome

& $ApkSigner verify --verbose $ApkPath
if ($LASTEXITCODE -ne 0) { throw "APK签名校验失败" }

$Badging = (& $Aapt dump badging $ApkPath) -join "`n"
$Manifest = (& $Aapt dump xmltree $ApkPath AndroidManifest.xml) -join "`n"
foreach ($Expected in @("name='com.personal.mafaoffline'", "versionCode='35'", "versionName='1.16.0-bich-map-runtime'", "sdkVersion:'24'", "targetSdkVersion:'36'", "native-code: 'arm64-v8a'")) {
    if ($Badging -notlike "*$Expected*") { throw "APK元数据缺失：$Expected" }
}
if ($Manifest -notlike "*android:screenOrientation*0xb*") { throw "APK未导出为横屏用户旋转模式" }
if ($Manifest -notlike "*android:resizeableActivity*0x1*") { throw "APK未启用可调整窗口" }

$File = Get-Item -LiteralPath $ApkPath
$Hash = Get-FileHash -LiteralPath $ApkPath -Algorithm SHA256
$Devices = & $Adb devices -l
Write-Output "ANDROID_APK_VERIFY_PASS"
Write-Output "APK=$($File.FullName)"
Write-Output "SIZE=$($File.Length)"
Write-Output "SHA256=$($Hash.Hash)"
Write-Output ($Badging -split "`n" | Where-Object { $_ -match "^(package:|sdkVersion:|targetSdkVersion:|application-label:|native-code:)" })
Write-Output $Devices
