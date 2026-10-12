Set-StrictMode -Version 2.0

function Read-AndroidReleaseIdentityFromExportPreset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    $PackageMatch = [regex]::Match($Text, '(?m)^package/unique_name="([^"]+)"\r?$')
    $LabelMatch = [regex]::Match($Text, '(?m)^package/name="([^"]+)"\r?$')
    $VersionCodeMatch = [regex]::Match($Text, '(?m)^version/code=(\d+)\r?$')
    $VersionNameMatch = [regex]::Match($Text, '(?m)^version/name="([^"]+)"\r?$')
    if (-not $PackageMatch.Success) { throw 'Android export preset has no package/unique_name.' }
    if (-not $LabelMatch.Success) { throw 'Android export preset has no package/name.' }
    if (-not $VersionCodeMatch.Success) { throw 'Android export preset has no version/code.' }
    if (-not $VersionNameMatch.Success) { throw 'Android export preset has no version/name.' }
    [pscustomobject]@{
        Package = $PackageMatch.Groups[1].Value
        Label = $LabelMatch.Groups[1].Value
        VersionCode = [int]$VersionCodeMatch.Groups[1].Value
        VersionName = $VersionNameMatch.Groups[1].Value
    }
}

function Resolve-AndroidVerifierIdentityArguments {
    param(
        [string]$ExpectedPackage = '',
        [string]$ExpectedLabel = ''
    )
    if ([string]::IsNullOrWhiteSpace($ExpectedPackage)) { $ExpectedPackage = 'com.personal.mafaoffline' }
    if ([string]::IsNullOrWhiteSpace($ExpectedLabel)) { $ExpectedLabel = 'HardCore' }
    [pscustomobject]@{
        ExpectedPackage = $ExpectedPackage
        ExpectedLabel = $ExpectedLabel
    }
}

function Test-AndroidReleaseIdentityTransition {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePackage,
        [Parameter(Mandatory = $true)][string]$BaselinePackage,
        [Parameter(Mandatory = $true)][long]$CandidateVersionCode,
        [Parameter(Mandatory = $true)][long]$BaselineVersionCode,
        [switch]$AllowNewPackageInstall
    )
    if ([string]::IsNullOrWhiteSpace($CandidatePackage) -or [string]::IsNullOrWhiteSpace($BaselinePackage)) {
        throw 'Android package identity cannot be empty.'
    }
    if ($CandidateVersionCode -le 0) { throw 'Android candidate version code must be positive.' }
    if ($CandidatePackage -cnotin @('com.personal.mafaoffline', 'com.personal.hardcore.next') -or
        $BaselinePackage -cnotin @('com.personal.mafaoffline', 'com.personal.hardcore.next')) {
        throw 'APK package is outside the approved legacy and new-game release identities.'
    }
    if ($CandidatePackage -ceq $BaselinePackage) {
        if ($CandidateVersionCode -le $BaselineVersionCode) {
            throw 'Same-package update requires a higher version code.'
        }
        return $true
    }
    if (-not $AllowNewPackageInstall -or $BaselinePackage -cne 'com.personal.mafaoffline' -or
        $CandidatePackage -cne 'com.personal.hardcore.next') {
        throw 'Different-package APK requires an approved legacy baseline and explicit new-install mode.'
    }
    return $true
}
