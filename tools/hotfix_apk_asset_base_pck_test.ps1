[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tool = Join-Path $root 'tools/hotfix_apk_asset_base_pck.ps1'
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    throw "hotfix tool missing: $tool"
}

$result = @(& $tool -InventoryOnly)
if ($LASTEXITCODE -ne 0) {
    throw "InventoryOnly exited with code $LASTEXITCODE"
}
if ($result.Count -ne 1) {
    throw "InventoryOnly returned $($result.Count) records instead of one"
}
$record = $result[0]
if (-not [bool]$record.ok -or [string]$record.mode -ne 'inventory') {
    throw 'InventoryOnly did not report success'
}
if ([string]$record.apkSha256 -ne '26584B871F61B2F6EC2DDDAF52432263E7D68A6B8BEA35B2A3196D59D5B21664') {
    throw "unexpected APK SHA-256: $($record.apkSha256)"
}
if ([string]$record.sourceCommit -ne '52ae0565856c2d99a28639b2bf0c6278186e0858') {
    throw "unexpected source commit: $($record.sourceCommit)"
}
if ([int]$record.resourceCount -ne 16001 -or [long]$record.resourceBytes -ne 510109897) {
    throw "unexpected APK asset inventory: count=$($record.resourceCount) bytes=$($record.resourceBytes)"
}
if ([int]$record.duplicatePathCount -ne 0 -or [int]$record.unsafePathCount -ne 0) {
    throw 'APK asset path safety inventory was not clean'
}
if ([int]$record.embeddedPckCount -ne 0 -or -not [bool]$record.hasSparsePck -or -not [bool]$record.hasProjectBinary) {
    throw 'APK asset container sentinel inventory changed'
}
$badSourceFailed = $false
$badSourceOutput = @()
try {
    $badSourceOutput = @(& $tool -InventoryOnly -SourceCommit ('0' * 40) 2>&1)
}
catch {
    $badSourceFailed = $true
    $badSourceOutput = @($_.Exception.Message)
}
if ((-not $badSourceFailed -and $LASTEXITCODE -eq 0) -or (($badSourceOutput | Out-String) -notmatch 'SourceCommit is fixed')) {
    throw 'non-milestone source commit was not rejected'
}
Write-Output "HOTFIX_APK_ASSET_BASE_STATIC_PASS resources=$($record.resourceCount) bytes=$($record.resourceBytes) sha256=$($record.apkSha256)"
