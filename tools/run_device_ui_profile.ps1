param(
    [string]$Adb = "",
    [string]$Serial = "AADMVB3602042319",
    [string]$Package = "com.personal.mafaoffline",
    [string]$Activity = "com.godot.game.GodotAppLauncher",
    [string]$Apk = "",
    [string]$OutputDir = "",
    [string]$CaptureName = "device_ui_profile",
    [int]$WaitSeconds = 3,
    [switch]$Install
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($Adb)) {
    $Adb = Join-Path $ProjectRoot "tools\android-build\sdk\platform-tools\adb.exe"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot "outputs\android_device"
}
if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) {
    throw "ADB executable does not exist: $Adb"
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$Adb = (Resolve-Path -LiteralPath $Adb).Path
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

function Invoke-Device([string[]]$Arguments) {
    $result = @(& $Adb -s $Serial @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "ADB failed ($LASTEXITCODE): adb -s $Serial $($Arguments -join ' ')`n$($result -join "`n")"
    }
    return ($result -join "`n").Trim()
}

$devices = @(& $Adb devices 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Unable to enumerate ADB devices: $($devices -join "`n")" }
$deviceLine = $devices | Where-Object { $_ -match "^$([regex]::Escape($Serial))\s+device\b" }
if (-not $deviceLine) {
    throw "Required device is not connected or not authorized: $Serial`n$($devices -join "`n")"
}

if ($Install) {
    if ([string]::IsNullOrWhiteSpace($Apk) -or -not (Test-Path -LiteralPath $Apk -PathType Leaf)) {
        throw "-Install requires an existing -Apk path."
    }
    $installOutput = @(& $Adb -s $Serial install -r (Resolve-Path -LiteralPath $Apk).Path 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "APK install failed: $($installOutput -join "`n")" }
}

$wmSize = Invoke-Device @("shell", "wm", "size")
$wmDensity = Invoke-Device @("shell", "wm", "density")
$rotation = Invoke-Device @("shell", "settings", "get", "system", "user_rotation")
$windowState = Invoke-Device @("shell", "dumpsys", "window", "windows")
if ($wmSize -notmatch "Physical size:\s*2664x1200|Override size:\s*2664x1200") {
    throw "Device profile mismatch: expected 2664x1200, got: $wmSize"
}
if ($wmDensity -notmatch "(?:Physical density|Override density):\s*520") {
    throw "Device profile mismatch: expected density 520, got: $wmDensity"
}

Invoke-Device @("shell", "am", "force-stop", $Package) | Out-Null
Invoke-Device @("shell", "am", "start", "-n", "$Package/$Activity") | Out-Null
Start-Sleep -Seconds ([Math]::Max(1, $WaitSeconds))
$resumed = Invoke-Device @("shell", "dumpsys", "activity", "activities")
if ($resumed -notmatch [regex]::Escape("$Package/$Activity")) {
    throw "Formal APK activity was not resumed: $Package/$Activity"
}

$remotePath = "/sdcard/$CaptureName.png"
$localPath = Join-Path $OutputDir "$CaptureName.png"
Invoke-Device @("shell", "screencap", "-p", $remotePath) | Out-Null
$pullOutput = @(& $Adb -s $Serial pull $remotePath $localPath 2>&1)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
    throw "Unable to pull device screenshot: $($pullOutput -join "`n")"
}
Invoke-Device @("shell", "rm", $remotePath) | Out-Null

$metadata = [ordered]@{
    profile = "HardCore.android.device_ui.v1"
    package = $Package
    activity = "$Package/$Activity"
    serial = $Serial
    expected_physical_size = "2664x1200"
    expected_density = 520
    safe_area_reference = @{ left_px = 121; right_px = 129; top_px = 0; bottom_px = 0 }
    wm_size = $wmSize
    wm_density = $wmDensity
    user_rotation = $rotation
    screenshot = $localPath
    capture_name = $CaptureName
    captured_at = (Get-Date).ToUniversalTime().ToString("o")
}
$metadataPath = Join-Path $OutputDir "$CaptureName.json"
$metadata | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $metadataPath -Encoding utf8
Write-Output ("DEVICE_UI_PROFILE_PASS screenshot={0} metadata={1} wm_size={2} wm_density={3} rotation={4}" -f $localPath, $metadataPath, $wmSize, $wmDensity, $rotation)
