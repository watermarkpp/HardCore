param(
    [string]$BaseRoot = 'C:/Users/Administrator/.codex/worktrees/r4-fixed-baseline/HardCore',
    [string]$CandidateRoot = 'C:/Users/Administrator/Documents/HardCore',
    [string]$OutputRoot = 'C:/Users/Administrator/Documents/HardCore/docs/monster_combat_r4/sol_takeover/evidence/historical_final_pairs'
)
$ErrorActionPreference = 'Stop'
$oldResult=Join-Path $CandidateRoot 'docs/monster_combat_r4/sol_takeover/evidence/historical_current_red/runner_results_adhoc_20260927_135051_727_24196.json'
$paths=@((Get-Content -LiteralPath $oldResult -Raw | ConvertFrom-Json).results | ForEach-Object {$_.test_path})
if ($paths.Count -ne 25 -or @($paths | Sort-Object -Unique).Count -ne 25) {throw 'Historical set drift'}
if (Test-Path -LiteralPath $OutputRoot) {throw 'Do not overwrite evidence'}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$summary = [System.Collections.Generic.List[object]]::new()
foreach ($side in @('BASE','CAND')) {
    $root=if ($side -eq 'BASE') {$BaseRoot} else {$CandidateRoot}
    $head=(& git -C $root rev-parse HEAD).Trim()
    $dest=Join-Path $OutputRoot $side
    New-Item -ItemType Directory -Path $dest | Out-Null
    $hashes=[ordered]@{}
    foreach ($path in @($paths + @('project.godot','scripts/enemy.gd','scripts/player.gd','scripts/game_root.gd','tools/run_godot_tests.ps1'))) {
        $hashes[$path]=(Get-FileHash -LiteralPath (Join-Path $root $path)).Hash
        if ($path.EndsWith('.tscn')) {
            $scriptPath=$path -replace '\.tscn$','.gd'
            if (Test-Path -LiteralPath (Join-Path $root $scriptPath)) {$hashes[$scriptPath]=(Get-FileHash -LiteralPath (Join-Path $root $scriptPath)).Hash}
        }
    }
    [ordered]@{head=$head;side=$side;test_paths=$paths;sha256=$hashes;tracked_diff=(@(& git -C $root diff HEAD --name-status) -join "`n");baseline_policy='Original baseline tests; only shared runner and standalone comparison probes overlaid. No production backport.'} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dest 'identity.json') -Encoding utf8
    $env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $dest 'runner'
    & (Join-Path $root 'tools/run_godot_tests.ps1') -TestPaths $paths -TimeoutSeconds 30
    $code=$LASTEXITCODE
    $results=@(Get-ChildItem -LiteralPath $env:HARDCORE_AUDIT_LOG_ROOT -Filter 'runner_results_*.json' | Sort-Object LastWriteTime)
    if ($results.Count -ne 1) {throw 'Ambiguous runner identity'}
    $data=Get-Content -LiteralPath $results[0].FullName -Raw | ConvertFrom-Json
    if ($data.total -ne 25 -or @($data.results.test_path | Where-Object {$_ -notin $paths}).Count -ne 0) {throw 'Actual executed set differs'}
    $summary.Add([ordered]@{side=$side;head=$head;exit_code=$code;runner=$results[0].Name;passed=$data.passed;failed=$data.failed})
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot 'summary.json') -Encoding utf8
    if ($side -eq 'CAND' -and $code -ne 0) {throw 'Current historical failures require classification'}
}
