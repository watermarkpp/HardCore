$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'tools\android_release_identity.ps1')

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -cne $Expected) {
        throw "$Message expected=<$Expected> actual=<$Actual>"
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action } catch { return }
    throw "$Message expected an exception"
}

$Preset = @'
[preset.0.options]
version/code=1
version/name="hardcore 2.0 开发版"
package/unique_name="com.personal.hardcore.next"
package/name="HardCore 新篇"
'@
$Identity = Read-AndroidReleaseIdentityFromExportPreset -Text $Preset
Assert-Equal $Identity.Package 'com.personal.hardcore.next' 'package parsed from fixed preset'
Assert-Equal $Identity.Label 'HardCore 新篇' 'label parsed from fixed preset'
Assert-Equal $Identity.VersionCode 1 'version code parsed from fixed preset'
Assert-Equal $Identity.VersionName 'hardcore 2.0 开发版' 'version name parsed from fixed preset'

$LegacyText = @'
version/code=82
version/name="hardcore legacy"
package/unique_name="com.personal.mafaoffline"
package/name="HardCore"
'@
$Legacy = Read-AndroidReleaseIdentityFromExportPreset -Text $LegacyText
$LegacyArgs = Resolve-AndroidVerifierIdentityArguments
Assert-Equal $LegacyArgs.ExpectedPackage 'com.personal.mafaoffline' 'legacy package default'
Assert-Equal $LegacyArgs.ExpectedLabel 'HardCore' 'legacy label default'

Assert-Throws {
    Test-AndroidReleaseIdentityTransition -CandidatePackage 'com.personal.hardcore.next' -BaselinePackage 'com.personal.mafaoffline' -CandidateVersionCode 1 -BaselineVersionCode 113
} 'same-app transition with different package'

Assert-Equal (Test-AndroidReleaseIdentityTransition -CandidatePackage 'com.personal.hardcore.next' -BaselinePackage 'com.personal.mafaoffline' -CandidateVersionCode 1 -BaselineVersionCode 113 -AllowNewPackageInstall) $true 'new package first install'
Assert-Throws {
    Test-AndroidReleaseIdentityTransition -CandidatePackage 'com.example.unrelated' -BaselinePackage 'com.personal.mafaoffline' -CandidateVersionCode 1 -BaselineVersionCode 113 -AllowNewPackageInstall
} 'arbitrary candidate package cannot use approved new-install mode'
Assert-Equal (Test-AndroidReleaseIdentityTransition -CandidatePackage 'com.personal.mafaoffline' -BaselinePackage 'com.personal.mafaoffline' -CandidateVersionCode 114 -BaselineVersionCode 113) $true 'same package update'
Assert-Throws {
    Test-AndroidReleaseIdentityTransition -CandidatePackage 'com.personal.mafaoffline' -BaselinePackage 'com.personal.mafaoffline' -CandidateVersionCode 113 -BaselineVersionCode 113
} 'same package must increase version'
Assert-Throws {
    Test-AndroidReleaseIdentityTransition -CandidatePackage 'com.personal.hardcore.next' -BaselinePackage 'com.example.arbitrary' -CandidateVersionCode 1 -BaselineVersionCode 1 -AllowNewPackageInstall
} 'arbitrary baseline package'
Assert-Throws {
    Test-AndroidReleaseIdentityTransition -CandidatePackage 'com.personal.mafaoffline' -BaselinePackage 'com.personal.hardcore.next' -CandidateVersionCode 114 -BaselineVersionCode 1 -AllowNewPackageInstall -ApprovedLegacyPackage 'com.personal.hardcore.next'
} 'caller cannot reverse the legacy-to-new-game transition'

Write-Output 'ANDROID_RELEASE_IDENTITY_TEST_PASS'
