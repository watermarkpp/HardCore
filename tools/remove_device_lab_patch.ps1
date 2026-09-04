[CmdletBinding()]
param(
    [string]$Serial='',
    [string]$PackageId='com.personal.mafaoffline',
    [string]$Adb='adb',
    [switch]$Restart
)
$ErrorActionPreference='Stop'
if($Serial -notmatch '^$|^[A-Za-z0-9._:-]{1,128}$'){throw 'unsafe serial'}
if($PackageId -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$'){throw 'unsafe package'}
$prefix=@();if($Serial){$prefix+=@('-s',$Serial)}
function A([string[]]$x){& $Adb @prefix @x;if($LASTEXITCODE -ne 0){throw "adb failed: $($x -join ' ')"}}
A @('shell','run-as',$PackageId,'rm','-f','files/device_lab/patches/active.json')
if($Restart){A @('shell','am','force-stop',$PackageId);A @('shell','monkey','-p',$PackageId,'-c','android.intent.category.LAUNCHER','1')}
[pscustomobject]@{ok=$true;activePatchRemoved=$true;restart=[bool]$Restart}
