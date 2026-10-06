# Post-export APK patch: inject non-imported source files required by
# feature_resource_registry source-byte checks, then realign and re-sign
# with the engine's built-in debug keystore (same cert as all prior builds).
# Usage: inject_sources_resign.ps1 -ApkPath <apk> -StageRoot <stage>
param(
    [Parameter(Mandatory = $true)][string]$ApkPath,
    [Parameter(Mandatory = $true)][string]$StageRoot
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$SourceEntries = @(
    @{ Source = "assets\art\items\service\inventory\client.classic_raw_complete\Items_00014.png"; Entry = "assets/assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png" }
    @{ Source = "assets\audio\sfx\client\137__M26-3.wav"; Entry = "assets/assets/audio/sfx/client/137__M26-3.wav" }
    @{ Source = "assets\audio\sfx\client\10332__M33-3.wav"; Entry = "assets/assets/audio/sfx/client/10332__M33-3.wav" }
)

foreach ($item in $SourceEntries) {
    $src = Join-Path $StageRoot $item.Source
    if (-not (Test-Path $src)) { throw "missing source file: $src" }
}

# Godot/Gradle APK names are UTF-8 even when the ZIP EFS flag is absent.
# Windows PowerShell's locale default must never rename sparse-pack assets.
$zip = [System.IO.Compression.ZipFile]::Open($ApkPath, 'Update', [System.Text.UTF8Encoding]::new($false, $true))
try {
    foreach ($item in $SourceEntries) {
        $src = Join-Path $StageRoot $item.Source
        $existing = $zip.GetEntry($item.Entry)
        if ($null -ne $existing) { $existing.Delete() }
        $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, $item.Entry, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $zip.Dispose() }

$SdkBuildTools = "C:\Users\Administrator\Documents\HardCore\tools\android-build\sdk\build-tools\35.0.1"
$Keystore = "C:\Users\Administrator\.codex\worktrees\pluggable-framework-v2\HardCore\tools\godot-4.7\editor_data\keystores\debug.keystore"
$Aligned = "$ApkPath.aligned"
& (Join-Path $SdkBuildTools "zipalign.exe") -f -p 4 $ApkPath $Aligned
if ($LASTEXITCODE -ne 0) { throw "zipalign failed" }
Move-Item $Aligned $ApkPath -Force
$env:JAVA_HOME = (Get-ChildItem "C:\Users\Administrator\Documents\HardCore\tools\android-build\jdk" -Directory | Select-Object -First 1).FullName
& (Join-Path $SdkBuildTools "apksigner.bat") sign --ks $Keystore --ks-pass pass:android --ks-key-alias androiddebugkey $ApkPath
if ($LASTEXITCODE -ne 0) { throw "apksigner failed" }
$cert = ((& (Join-Path $SdkBuildTools "apksigner.bat") verify --print-certs $ApkPath 2>&1) -join "`n")
$sha = [regex]::Match($cert, 'SHA-256 digest:\s*([0-9a-fA-F]+)').Groups[1].Value.ToLowerInvariant()
if ($sha -ne "c62d0f8239b926f819038845c302143fd24dcfd75ed8d877ed846c430c6f3fcc") { throw "unexpected signing cert: $sha" }
Write-Output "INJECT_RESIGN_OK cert=$sha"
