param(
    [string]$BaseRoot = 'C:/Users/Administrator/.codex/worktrees/r4-fixed-baseline/HardCore',
    [string]$CandidateRoot = 'C:/Users/Administrator/Documents/HardCore',
    [string]$OutputRoot = 'C:/Users/Administrator/Documents/HardCore/docs/monster_combat_r4/sol_takeover/evidence/common_natural_final'
)
$ErrorActionPreference = 'Stop'
$relativeRoot = 'tests/hc_monster_combat_r4'
$probe = "$relativeRoot/r3_common_natural_probe.gd"
$scene = "$relativeRoot/r3_common_natural_probe.tscn"
$baseHead = (& git -C $BaseRoot rev-parse HEAD).Trim()
$candidateHead = (& git -C $CandidateRoot rev-parse HEAD).Trim()
if ($baseHead -ne '1381d2838a3736f4a06699dd24a8cf4a10714950') {throw 'BASE drift'}
if (Test-Path -LiteralPath $OutputRoot) {throw 'Do not overwrite prior evidence'}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
foreach ($relative in @($probe, $scene)) {
    Copy-Item -LiteralPath (Join-Path $CandidateRoot $relative) -Destination (Join-Path $BaseRoot $relative)
    & git -C $BaseRoot add -f -- $relative
    if ($LASTEXITCODE -ne 0) {throw 'BASE test overlay staging failed'}
    & git -C $CandidateRoot add -f -- $relative
    if ($LASTEXITCODE -ne 0) {throw 'Candidate probe staging failed'}
    if ((Get-FileHash -LiteralPath (Join-Path $BaseRoot $relative)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $CandidateRoot $relative)).Hash) {throw 'Probe bytes differ'}
}
[ordered]@{
    base_head=$baseHead; candidate_head=$candidateHead
    probe_sha256=(Get-FileHash -LiteralPath (Join-Path $CandidateRoot $probe)).Hash
    scene_sha256=(Get-FileHash -LiteralPath (Join-Path $CandidateRoot $scene)).Hash
    runner_sha256=(Get-FileHash -LiteralPath (Join-Path $CandidateRoot 'tools/run_godot_tests.ps1')).Hash
    base_overlay='Identical test wrapper only. No BASE production changes.'
    scope='20 actual synchronous record-consuming super calls, actual natural engine clock. Full terminal attribution on R3 NOT_RUN; zero HP not inferred as miss.'
    ids=@(24,76,238,239); timeout_seconds=60; order='BASE/CAND/CAND_ON for each ID, serial; same-seed actual CAND observer OFF/ON equivalence; separate actual 24 pursuit in BASE/CAND'
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot 'identity.json') -Encoding utf8
$runs = [System.Collections.Generic.List[object]]::new()
foreach ($id in @(24,76,238,239)) {
    foreach ($side in @('BASE','CAND','CAND_ON')) {
        $root = if ($side -eq 'BASE') {$BaseRoot} else {$CandidateRoot}
        $head = if ($side -eq 'BASE') {$baseHead} else {$candidateHead}
        $dest = Join-Path $OutputRoot "$id-$side"
        New-Item -ItemType Directory -Path $dest | Out-Null
        $env:HARDCORE_R4_COMPARE_ID=[string]$id
        $env:HARDCORE_R4_COMPARE_HEAD=$head
        $env:HARDCORE_R4_COMPARE_OBSERVER=if ($side -eq 'CAND_ON') {'1'} else {'0'}
        $env:HARDCORE_R4_COMPARE_CHASE='0'
        $env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $dest 'runner'
        & (Join-Path $root 'tools/run_godot_tests.ps1') -TestPaths @($scene) -TimeoutSeconds 60
        $code=$LASTEXITCODE
        $dataPath=Join-Path $root 'outputs/test_logs/r4_common_natural.json'
        if (Test-Path -LiteralPath $dataPath) {Copy-Item -LiteralPath $dataPath -Destination (Join-Path $dest 'natural.json')}
        $runs.Add([ordered]@{id=$id;side=$side;head=$head;exit_code=$code;completed_at=(Get-Date -Format o)})
        $runs | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot 'runs.json') -Encoding utf8
        if ($code -ne 0) {throw "Natural source probe failed: $id-$side"}
        $data=Get-Content -LiteralPath (Join-Path $dest 'natural.json') -Raw | ConvertFrom-Json
        if ($data.id -ne $id -or $data.head -ne $head -or $data.rows.Count -ne 20 -or $data.failures.Count -ne 0) {throw 'Stale/invalid natural evidence'}
        if ((& git -C $root rev-parse HEAD).Trim() -ne $head) {throw 'Source drift'}
        Write-Output "R4_COMMON_NATURAL_COMPLETE $id-$side"
    }
    $off=Get-Content -LiteralPath (Join-Path $OutputRoot "$id-CAND/natural.json") -Raw | ConvertFrom-Json
    $on=Get-Content -LiteralPath (Join-Path $OutputRoot "$id-CAND_ON/natural.json") -Raw | ConvertFrom-Json
    foreach ($field in @('hp','rng_final','player_rng_final','starts','settlements')) {
        if ($off.$field -ne $on.$field) {throw "Actual observer equivalence failed: $id-$field"}
    }
    for ($i=0; $i -lt 20; $i++) {
        foreach ($field in @('damage','seq','hp_before','hp_after','hp_delta','effective_interval_s')) {
            if ($off.rows[$i].$field -ne $on.rows[$i].$field) {throw "Observer release mismatch: $id-$i-$field"}
        }
    }
    if ($on.observer_overflowed -or $on.observer_event_count -le 0) {throw 'Observer ON did not observe actual damage'}
    Write-Output "R4_COMMON_OBSERVER_EQUIVALENCE_PASS $id"
}
foreach ($side in @('BASE','CAND')) {
    $root=if ($side -eq 'BASE') {$BaseRoot} else {$CandidateRoot}
    $head=if ($side -eq 'BASE') {$baseHead} else {$candidateHead}
    $dest=Join-Path $OutputRoot "24-CHASE-$side"
    New-Item -ItemType Directory -Path $dest | Out-Null
    $env:HARDCORE_R4_COMPARE_ID='24'
    $env:HARDCORE_R4_COMPARE_HEAD=$head
    $env:HARDCORE_R4_COMPARE_OBSERVER='0'
    $env:HARDCORE_R4_COMPARE_CHASE='1'
    $env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $dest 'runner'
    & (Join-Path $root 'tools/run_godot_tests.ps1') -TestPaths @($scene) -TimeoutSeconds 30
    $code=$LASTEXITCODE
    Copy-Item -LiteralPath (Join-Path $root 'outputs/test_logs/r4_common_natural.json') -Destination (Join-Path $dest 'natural.json')
    $runs.Add([ordered]@{id=24;side=$side;chase=$true;head=$head;exit_code=$code;completed_at=(Get-Date -Format o)})
    $runs | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot 'runs.json') -Encoding utf8
    if ($code -ne 0) {throw 'Actual pursuit failed'}
    $data=Get-Content -LiteralPath (Join-Path $dest 'natural.json') -Raw | ConvertFrom-Json
    if ($data.rows.Count -ne 1 -or -not $data.chase -or $data.position_changes -lt 10 -or $data.failures.Count -ne 0 -or $data.head -ne $head) {throw 'Invalid actual pursuit evidence'}
}
