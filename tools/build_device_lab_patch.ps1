[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_.-]{1,96}$')][string]$PatchId,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{7,40}$')][string]$BaseCommit,
    [Parameter(Mandatory=$true)][string[]]$BasePacks,
    [string]$PatchCommit='HEAD',
    [string]$OutputDirectory = 'outputs/device_lab_patches'
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$godot=Join-Path $root 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
if($PatchCommit -ne 'HEAD' -and $PatchCommit -notmatch '^[0-9a-fA-F]{7,40}$'){throw 'invalid patch commit'}
$resolvedBase=(git -C $root rev-parse "$BaseCommit^{commit}").Trim()
$resolvedPatch=(git -C $root rev-parse "$PatchCommit^{commit}").Trim()
if(-not $resolvedBase -or -not $resolvedPatch){throw 'unable to resolve patch commits'}
$head=(git -C $root rev-parse HEAD).Trim()
if($resolvedPatch -ne $head){throw 'PatchCommit must be the checked-out HEAD; build from an isolated worktree for older commits'}
$trackedDirty=@(git -C $root status --porcelain=v1 --untracked-files=no)
if($trackedDirty.Count -gt 0){throw 'tracked worktree must be clean before building a reproducible resource patch'}
$safeBasePacks=@()
foreach($basePack in $BasePacks){
    $packFull=[IO.Path]::GetFullPath($basePack)
    if(-not(Test-Path -LiteralPath $packFull -PathType Leaf) -or [IO.Path]::GetExtension($packFull) -ne '.pck'){throw "invalid base pack: $basePack"}
    $safeBasePacks+=$packFull
}
$runtimePaths=@(git -C $root diff --name-only --diff-filter=ACMRT $resolvedBase $resolvedPatch -- . ':(exclude)tests/**' ':(exclude)tools/**' ':(exclude)docs/**' ':(exclude)outputs/**' ':(exclude)reports/**' ':(exclude)AGENTS.md' ':(exclude)PROJECT_*.md')
if($runtimePaths.Count -eq 0){throw 'patch commit contains no runtime resource changes'}
$outputDir=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $outputDir.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'output directory must stay inside workspace'}
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$pck=Join-Path $outputDir "$PatchId.pck"
$args=@('--headless','--path',$root,'--log-file',(Join-Path $root 'outputs/test_logs/device_lab_patch_build.log'),'--export-patch','Android',$pck,'--patches',($safeBasePacks -join ','))
& $godot @args
if($LASTEXITCODE -ne 0){throw "Device Lab patch build failed: $LASTEXITCODE"}
$item=Get-Item -LiteralPath $pck
$hash=(Get-FileHash -LiteralPath $pck -Algorithm SHA256).Hash.ToUpperInvariant()
$manifest=[ordered]@{schemaVersion=1;patchId=$PatchId;file=$item.Name;size=[long]$item.Length;sha256=$hash;baseCommit=$resolvedBase;patchCommit=$resolvedPatch;basePacks=@($safeBasePacks|ForEach-Object{Split-Path -Leaf $_});resources=@($runtimePaths|ForEach-Object{"res://$($_ -replace '\\','/')"})}
$manifestPath=Join-Path $outputDir "$PatchId.json"
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{ok=$true;patchId=$PatchId;pck=$pck;manifest=$manifestPath;size=$item.Length;sha256=$hash}
