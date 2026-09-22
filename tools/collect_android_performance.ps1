[CmdletBinding()]
param(
    [ValidatePattern('^$|^[A-Za-z0-9._:-]{1,128}$')][string]$Serial = '',
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$')]
    [string]$PackageId = 'com.personal.mafaoffline',
    [string]$OutputDirectory = '',
    [string]$Adb = ''
)
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Adb)) {
    $Adb = Join-Path $ProjectRoot 'tools/android-build/sdk/platform-tools/adb.exe'
}
if (-not (Test-Path -LiteralPath $Adb -PathType Leaf)) { throw "ADB not found: $Adb" }
function Read-Adb([string[]]$Arguments) {
    $deviceArgs = @()
    if ($Serial) { $deviceArgs += @('-s', $Serial) }
    $value = & $Adb @deviceArgs @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "ADB read failed: $($value -join ' ')" }
    return ($value -join "`n")
}
# Read-only phone access. No install, patch, settings change, save edit or
# deletion; private data access is limited to local performance reports.
$state = Read-Adb @('get-state')
if ($state.Trim() -ne 'device') { throw 'Connect one unlocked USB-debugging device, or select -Serial.' }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path ([Environment]::GetFolderPath('Desktop')) ('HardCore-phone-performance-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$destination = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$listing = Read-Adb @('shell', 'run-as', $PackageId, 'ls', 'files/device_lab/outbox')
$files = @($listing -split '\r?\n' | Where-Object { $_ -cmatch '^result_local_[0-9]+_[0-9]+\.json$' } | Sort-Object)
$index = @()
foreach ($name in $files) {
    $raw = Read-Adb @('shell', 'run-as', $PackageId, 'cat', "files/device_lab/outbox/$name")
    $document = $raw | ConvertFrom-Json
    if ($document.action -ne 'local_performance_capture') { throw "Unexpected report type: $name" }
    $target = Join-Path $destination $name
    if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite an existing report: $target" }
    [IO.File]::WriteAllText($target, $raw + "`n", [Text.UTF8Encoding]::new($false))
    $index += [ordered]@{ file = $name; sha256 = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash;
        mode = $document.detailMode; complete = $document.complete; elapsedSeconds = $document.elapsed_gameplay_seconds }
}
$manifest = [ordered]@{ status = $(if ($files.Count -gt 0) { 'PASS' } else { 'MISSING' });
    package = $PackageId; exportedAt = (Get-Date -Format o); reportCount = $files.Count; reports = $index }
$indexPath = Join-Path $destination 'collection.json'
if (Test-Path -LiteralPath $indexPath) { throw "Refusing to overwrite $indexPath" }
[IO.File]::WriteAllText($indexPath, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Write-Output "ANDROID_PERFORMANCE_COLLECTION_$($manifest.status) reports=$($files.Count) path=$destination"
