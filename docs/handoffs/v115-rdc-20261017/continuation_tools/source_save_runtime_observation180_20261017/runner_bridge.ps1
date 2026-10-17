param([Parameter(Mandatory=$true)][string]$Config,[switch]$ValidateOnly)
$ErrorActionPreference='Stop'
$c=Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
function Full([string]$p){if(-not [IO.Path]::IsPathRooted($p)){throw 'Absolute isolation path required.'};return [IO.Path]::GetFullPath($p).TrimEnd('\','/')}
$root=Full ([string]$c.authorized_root)
$snapshot=Full ([string]$c.snapshot)
if(-not $snapshot.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Snapshot escapes authorized output.'}
$gitDir=Full ([string]$c.git_dir);$gitWork=Full ([string]$c.git_work_tree);$gitIndex=Full ([string]$c.git_index);$ceiling=Full ([string]$c.git_ceiling)
if($gitDir -ine (Join-Path $snapshot '.git') -or $gitWork -ine $snapshot -or $gitIndex -ine (Join-Path $gitDir 'private.index') -or $ceiling -ine $root){throw 'Exact Git isolation configuration mismatch.'}
foreach($path in @($snapshot,$gitDir,$gitIndex)){
 $cursor=$path
 while($cursor.Length -ge $root.Length){
  $item=Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
  if($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse isolation path refused.'}
  if($cursor -ieq $root){break};$cursor=Split-Path -Parent $cursor
 }
}
foreach($name in @('HEAD','config','objects','refs','codex-isolated.json')){if(-not(Test-Path -LiteralPath (Join-Path $gitDir $name))){throw 'Incomplete isolated repository; no Git command permitted.'}}
$fixedIndex='C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore1/index'
$before=(Get-FileHash -LiteralPath $fixedIndex -Algorithm SHA256).Hash.ToLowerInvariant()
if($before -cne '3180f91855b8bc8d7a22848592ff9f95f2d19574a73f7a3eea90e962f7151b22'){throw 'Parent real-index baseline mismatch; no runner.'}
$keys=@(Get-ChildItem Env: | Where-Object Name -Like 'GIT_*' | Select-Object -ExpandProperty Name)+@('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_CEILING_DIRECTORIES','GIT_OPTIONAL_LOCKS','GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL') | Sort-Object -Unique
$prior=@{};foreach($key in $keys){$prior[$key]=[Environment]::GetEnvironmentVariable($key,'Process');Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue}
$code=1
try {
 $env:GIT_DIR=$gitDir;$env:GIT_WORK_TREE=$snapshot;$env:GIT_INDEX_FILE=$gitIndex;$env:GIT_CEILING_DIRECTORIES=$root;$env:GIT_OPTIONAL_LOCKS='0';$env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_CONFIG_GLOBAL='NUL'
 $top=(& git -C $snapshot rev-parse --show-toplevel).Trim();if($LASTEXITCODE -ne 0){throw 'Private top-level lookup failed.'}
 $resolvedDir=(& git -C $snapshot rev-parse --absolute-git-dir).Trim();if($LASTEXITCODE -ne 0){throw 'Private git-dir lookup failed.'}
 $resolvedIndex=(& git -C $snapshot rev-parse --git-path index).Trim();if($LASTEXITCODE -ne 0){throw 'Private index lookup failed.'}
 if((Full $top) -ine $snapshot -or (Full $resolvedDir) -ine $gitDir -or (Full $resolvedIndex) -ine $gitIndex){throw 'Resolved private Git paths mismatch.'}
 if($ValidateOnly){Write-Output 'ISOLATED_RUNNER_PREFLIGHT_PASS';$code=0}
 else{
  # Human-authorized external functional bound for the exact six stages.
  # The separate full-world120s exception stays unchanged.
  $gate=Get-Content -LiteralPath (Join-Path $root 'STAGE_BUDGET_GATE.json') -Raw | ConvertFrom-Json
  if($gate.status -cne 'PASS' -or $gate.scene -cne 'tests/framework/source_save_roundtrip_20261017.tscn' -or $gate.timeout_seconds -ne 180){throw 'BLOCKED: exact Source save stage180 authorization missing; no Godot launch.'}
  $params=@{Label=[string]$c.label;TestPaths=@('tests/framework/source_save_roundtrip_20261017.tscn');GodotExecutable=[string]$c.engine;ExternalInputPaths=@($c.external_inputs);VerboseEngine=$true;TimeoutSeconds=60;ApprovedSourceSave180=$true}
  & (Join-Path $snapshot 'tools/run_multicore_v115_tests.ps1') @params
  $code=$LASTEXITCODE
 }
} finally {
 $after=(Get-FileHash -LiteralPath $fixedIndex -Algorithm SHA256).Hash.ToLowerInvariant()
 foreach($key in $keys){Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue;if($null -ne $prior[$key]){[Environment]::SetEnvironmentVariable($key,$prior[$key],'Process')}}
 if($before -cne $after){throw 'Parent index changed during isolated preflight.'}
}
exit $code
