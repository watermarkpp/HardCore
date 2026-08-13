[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [string]$Serial='',
    [string]$PackageId='com.personal.mafaoffline',
    [string]$Adb='adb',
    [switch]$Restart
)
$ErrorActionPreference='Stop'
if($Serial -notmatch '^$|^[A-Za-z0-9._:-]{1,128}$'){throw 'unsafe serial'}
if($PackageId -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$'){throw 'unsafe package'}
$manifestFull=[IO.Path]::GetFullPath($ManifestPath)
$manifest=Get-Content -LiteralPath $manifestFull -Raw -Encoding UTF8|ConvertFrom-Json
if([int]$manifest.schemaVersion -ne 1 -or [string]$manifest.patchId -notmatch '^[A-Za-z0-9_.-]{1,96}$'){throw 'invalid manifest'}
if([string]$manifest.file -notmatch '^[A-Za-z0-9_.-]{1,96}\.pck$'){throw 'invalid patch filename'}
$pck=Join-Path (Split-Path -Parent $manifestFull) ([string]$manifest.file)
if(-not(Test-Path -LiteralPath $pck -PathType Leaf)){throw 'patch PCK missing'}
$hash=(Get-FileHash -LiteralPath $pck -Algorithm SHA256).Hash.ToUpperInvariant()
if($hash -ne ([string]$manifest.sha256).ToUpperInvariant() -or (Get-Item $pck).Length -ne [long]$manifest.size){throw 'patch identity mismatch'}
if((Get-Item $pck).Length -le 0 -or (Get-Item $pck).Length -gt 64MB){throw 'patch size outside allowed range'}
$prefix=@();if($Serial){$prefix+=@('-s',$Serial)}
function A([string[]]$x){& $Adb @prefix @x;if($LASTEXITCODE -ne 0){throw "adb failed: $($x -join ' ')"}}
$nonce=[Guid]::NewGuid().ToString('N')
$remote="/data/local/tmp/hardcore_patch_$nonce"
A @('push',$pck,"$remote.pck")
A @('push',$manifestFull,"$remote.json")
A @('shell','run-as',$PackageId,'mkdir','-p','files/device_lab/patches')
# Preserve the previous manifest, then atomically publish the verified pair.
& $Adb @prefix @('shell','run-as',$PackageId,'cp','files/device_lab/patches/active.json','files/device_lab/patches/previous.json') 2>$null
A @('shell','run-as',$PackageId,'cp',"$remote.pck","files/device_lab/patches/$($manifest.file)")
A @('shell','run-as',$PackageId,'cp',"$remote.json",'files/device_lab/patches/active.json.tmp')
A @('shell','run-as',$PackageId,'mv','files/device_lab/patches/active.json.tmp','files/device_lab/patches/active.json')
A @('shell','rm','-f',"$remote.pck","$remote.json")
if($Restart){A @('shell','am','force-stop',$PackageId);A @('shell','monkey','-p',$PackageId,'-c','android.intent.category.LAUNCHER','1')}
[pscustomobject]@{ok=$true;patchId=$manifest.patchId;sha256=$hash;restart=[bool]$Restart}
