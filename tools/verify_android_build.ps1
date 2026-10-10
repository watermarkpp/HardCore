param(
    [string]$ApkPath = "",
    [string]$AndroidRoot = "",
    [string]$BaselineApkPath = "",
    [int]$ExpectedVersionCode = 0,
    [string]$ExpectedVersionName = "",
    [string]$ExpectedCommit = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
function Read-AndroidToolUtf8 {
    param([string]$Executable, [string[]]$Arguments)
    # Android inspection tools emit UTF-8 independently of PowerShell's locale.
    # Read both pipes concurrently and keep the actual native failure status.
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = $Arguments -join ' '
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Unable to start Android inspection tool.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Android inspection tool timed out.'
        }
        $text = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw ('Android inspection failed exit={0}: {1}' -f $process.ExitCode, $errorText)
        }
        return $text
    } finally {
        $process.Dispose()
    }
}

$ProjectRoot = Split-Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($ApkPath)) {
    $ApkPath = Join-Path $ProjectRoot "outputs\hardcore\HardCore-candidate-debug.apk"
}
if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK does not exist: $ApkPath"
}
if ([string]::IsNullOrWhiteSpace($BaselineApkPath)) {
    $BaselineApkPath = Join-Path $ProjectRoot "outputs\hardcore\HardCore-slim-v38-debug.apk"
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
$PreviousJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $JavaHome

$CandidateSignature = (& $ApkSigner verify --verbose --print-certs $ApkPath) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed." }
$BaselineSignature = (& $ApkSigner verify --print-certs $BaselineApkPath) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Baseline APK signature verification failed.' }
$CertificatePattern = '(?m)^Signer #[0-9]+ certificate SHA-256 digest:\s*([0-9a-fA-F]+)\s*$'
$CandidateCertificates = @([regex]::Matches($CandidateSignature, $CertificatePattern) | ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Sort-Object)
$BaselineCertificates = @([regex]::Matches($BaselineSignature, $CertificatePattern) | ForEach-Object { $_.Groups[1].Value.ToUpperInvariant() } | Sort-Object)
if ($CandidateCertificates.Count -eq 0 -or ($CandidateCertificates -join ',') -cne ($BaselineCertificates -join ',')) {
    throw 'APK signer differs from the supplied baseline; direct update cannot be accepted.'
}
Write-Output $CandidateSignature

$Badging = Read-AndroidToolUtf8 -Executable $Aapt -Arguments @('dump','badging',([char]34+$ApkPath+[char]34))
$BaselineBadging = Read-AndroidToolUtf8 -Executable $Aapt -Arguments @('dump','badging',([char]34+$BaselineApkPath+[char]34))
$IdentityPattern = "package: name='([^']+)' versionCode='([0-9]+)'"
$CandidateIdentity = [regex]::Match($Badging, $IdentityPattern)
$BaselineIdentity = [regex]::Match($BaselineBadging, $IdentityPattern)
if (-not $CandidateIdentity.Success -or -not $BaselineIdentity.Success -or
    $CandidateIdentity.Groups[1].Value -cne $BaselineIdentity.Groups[1].Value -or
    [long]$CandidateIdentity.Groups[2].Value -le [long]$BaselineIdentity.Groups[2].Value) {
    throw 'Direct update requires the same package identity and a higher version code.'
}
Write-Output "ANDROID_DIRECT_UPDATE_IDENTITY_PASS certificate_sha256=$($CandidateCertificates -join ',')"
$Manifest = Read-AndroidToolUtf8 -Executable $Aapt -Arguments @('dump','xmltree',([char]34+$ApkPath+[char]34),'AndroidManifest.xml')
$ExpectedBadging = @(
    "name='com.personal.mafaoffline'",
    "sdkVersion:'24'",
    "targetSdkVersion:'36'",
    "application-label:'HardCore'",
    "native-code: 'arm64-v8a'"
)
if ($ExpectedVersionCode -gt 0) {
    $ExpectedBadging += "versionCode='$ExpectedVersionCode'"
}
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
    -BaselineApkPath $BaselineApkPath `
    -ExpectedVersionCode $ExpectedVersionCode `
    -ExpectedVersionName $ExpectedVersionName `
    -ExpectedCommit $ExpectedCommit
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
} finally {
    $env:JAVA_HOME = $PreviousJavaHome
}
