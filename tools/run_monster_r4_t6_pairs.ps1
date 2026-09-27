param(
    [string]$BaseRoot = 'C:/Users/Administrator/.codex/worktrees/r4-fixed-baseline/HardCore',
    [string]$CandidateRoot = 'C:/Users/Administrator/Documents/HardCore',
    [string]$OutputRoot = 'C:/Users/Administrator/Documents/HardCore/docs/monster_combat_r4/sol_takeover/evidence/t6_pairs'
)
$ErrorActionPreference = 'Stop'
$probe = 'tests/hc_monster_combat_r4/t6_real_load_probe.gd'
if ((Get-FileHash -LiteralPath (Join-Path $BaseRoot 'tools/run_godot_tests.ps1')).Hash -ne (Get-FileHash -LiteralPath (Join-Path $CandidateRoot 'tools/run_godot_tests.ps1')).Hash) {throw 'Runner test overlay differs'}
$baseHead = (& git -C $BaseRoot rev-parse HEAD).Trim()
$candidateHead = (& git -C $CandidateRoot rev-parse HEAD).Trim()
$probeHash = (Get-FileHash -LiteralPath (Join-Path $CandidateRoot $probe) -Algorithm SHA256).Hash
if ((Get-FileHash -LiteralPath (Join-Path $BaseRoot $probe) -Algorithm SHA256).Hash -ne $probeHash) {throw 'Probe overlay differs'}
if ($baseHead -ne '1381d2838a3736f4a06699dd24a8cf4a10714950') {throw 'Fixed BASE drift'}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$sharedInputs=[ordered]@{}
foreach ($dataPath in @('assets/data/drop/dpv2_user_loot_sheet_authority_v1.json','assets/data/equipment_attribute_master.json','assets/data/runtime/canonical_monster_catalog.json','scripts/drop/user_loot_sheet_provider.gd')) {
    $candidateHash=(Get-FileHash -LiteralPath (Join-Path $CandidateRoot $dataPath)).Hash
    if ((Get-FileHash -LiteralPath (Join-Path $BaseRoot $dataPath)).Hash -ne $candidateHash) {throw "Declared shared input differs: $dataPath"}
    $sharedInputs[$dataPath]=$candidateHash
}
$identity = [ordered]@{
    base_head=$baseHead; candidate_head=$candidateHead; probe_sha256=$probeHash
    random_input_version='all_gameplay_actors_spawn_casts_drop_identities_production_hot.v5'
    shared_input_sha256=$sharedInputs
    hot_mode='PlayerState.test_mode=false; unique isolated profile initialized through real save_game(false); native death clocks, drop throttling and background loot enabled. Bootstrap alone uses test_mode.'
    runner_sha256=(Get-FileHash -LiteralPath (Join-Path $CandidateRoot 'tools/run_godot_tests.ps1')).Hash
    engine_sha256=(Get-FileHash -LiteralPath (Join-Path $CandidateRoot 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe')).Hash
    scene_timeout_seconds=60; heavy_reason='600 paired physics/process callbacks can span 1200 ticks (20s) plus full native bootstrap/warmup and teardown'; modes=@('small','large_pets','aoe_death_loot'); scales=@(10,20,30); frames=600; seed=20260927
    aa_per_condition=2; ab_pairs_per_condition=3; order='AA then AB/BA/AB, one process at a time'
    cache='Independent already-imported trees; fresh engine process per sample; same shared read-only source art and engine; OS file cache not forcibly purged'
    measurement='Desktop headless callback intervals and script CPU only; engine monitor averages not per-frame P95; GPU and device NOT_RUN'
    baseline_overlay='Identical test script/scene and runner only; GameRoot test subclass freezes native wall-time cast seed input. Native death callback and planning inherited; test-only QUEUED identity input pinned before all persistence/affix consumers. All production dispatch/physics inherited; no BASE production modification.'
    base_status=(@(& git -C $BaseRoot status --porcelain=v1) -join "`n")
    candidate_status=(@(& git -C $CandidateRoot status --porcelain=v1) -join "`n")
    started_at=(Get-Date -Format o)
}
$identity | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'identity.json') -Encoding utf8
$runs = [System.Collections.Generic.List[object]]::new()
function Invoke-Sample([string]$Side,[string]$Mode,[int]$Scale,[string]$Phase,[int]$Round) {
    $root = if ($Side -eq 'BASE') {$BaseRoot} else {$CandidateRoot}
    $label = "$Mode-$Scale-$Phase-$Round-$Side"
    $dest = Join-Path $OutputRoot $label
    if (Test-Path -LiteralPath $dest) {throw "Evidence path already exists: $dest"}
    New-Item -ItemType Directory -Path $dest | Out-Null
    $env:HARDCORE_R4_LOAD_NAMESPACE=Split-Path -Leaf $OutputRoot
    $env:HARDCORE_R4_LOAD_MODE=$Mode
    $env:HARDCORE_R4_LOAD_COUNT=[string]$Scale
    $env:HARDCORE_R4_LOAD_HEAD=if ($Side -eq 'BASE') {$baseHead} else {$candidateHead}
    $env:HARDCORE_R4_LOAD_LABEL=$label
    $env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $dest 'runner'
    & (Join-Path $root 'tools/run_godot_tests.ps1') -TestPaths @('tests/hc_monster_combat_r4/t6_real_load_probe.tscn') -TimeoutSeconds 60
    $exitCode=$LASTEXITCODE
    $loadPath=Join-Path $root 'outputs/test_logs/r4_t6_load.json'
    if (Test-Path -LiteralPath $loadPath) {Copy-Item -LiteralPath $loadPath -Destination (Join-Path $dest 'load.json')}
    $runs.Add([ordered]@{label=$label; side=$Side; mode=$Mode; scale=$Scale; phase=$Phase; round=$Round; exit_code=$exitCode; completed_at=(Get-Date -Format o)})
    $runs | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'runs.json') -Encoding utf8
    if ($exitCode -ne 0) {throw "Invalid load sample: $label"}
    $data=Get-Content -LiteralPath (Join-Path $dest 'load.json') -Raw | ConvertFrom-Json
    if ($data.label -ne $label -or $data.frames.Count -ne 600 -or $data.failures.Count -ne 0) {throw "Stale/invalid result: $label"}
    if ($data.production_hot_test_mode -ne $false -or $data.isolated_profile_id -ne "r4-t6-$label") {throw 'Production hot-path isolation contract failed'}
    if ($data.random_input_version -ne 'all_gameplay_actors_spawn_casts_drop_identities_production_hot.v5' -or $data.random_inputs.player_seed -ne 20260928 -or $data.random_inputs.durability_seed -ne 20260929) {throw 'Random inputs not pinned'}
    if ($data.random_inputs.drop_session -ne '20260927000000000000000000000000') {throw 'Drop session input not pinned'}
    if ($Mode -eq 'aoe_death_loot') {
        $deathInputs=@($data.random_inputs.death_identity_inputs)
        if ($deathInputs.Count -ne $data.death_signals -or @($deathInputs.fixed_key | Sort-Object -Unique).Count -ne $deathInputs.Count -or @($data.random_inputs.equipment_identity_inputs).Count -eq 0) {throw 'Death/affix identity input incomplete'}
    }
    if ($data.isolated_profile_namespace -ne (Split-Path -Leaf $OutputRoot)) {throw 'Profile namespace differs from matrix identity'}
    $expectedCasts=if ($Mode -eq 'large_pets') {2} elseif ($Mode -eq 'aoe_death_loot') {6} else {0}
    if (@($data.random_inputs.canonical_cast_inputs).Count -ne $expectedCasts) {throw 'Canonical cast seeds not recorded for every actual cast'}
    $enemyInputs=@($data.random_inputs.actors | Where-Object {$_.kind -eq 'enemy'})
    $petInputs=@($data.random_inputs.actors | Where-Object {$_.kind -eq 'pet'})
    if ($enemyInputs.Count -ne $Scale + $data.replacements -or $data.random_inputs.spawn_hooks.Count -ne $enemyInputs.Count) {throw 'Spawn randomization hook incomplete'}
    if ($Mode -eq 'large_pets' -and $petInputs.Count -ne 2) {throw 'Pet randomization input missing'}
    if ((& git -C $root rev-parse HEAD).Trim() -ne $env:HARDCORE_R4_LOAD_HEAD) {throw 'Source changed during sample'}
    Write-Output "T6_SAMPLE_COMPLETE $label"
}
foreach ($mode in @('small','large_pets','aoe_death_loot')) {
    foreach ($scale in @(10,20,30)) {
        foreach ($round in @(1,2)) {Invoke-Sample 'BASE' $mode $scale 'AA' $round}
        foreach ($round in @(1,2,3)) {
            $order=if ($round -eq 2) {@('CAND','BASE')} else {@('BASE','CAND')}
            foreach ($side in $order) {Invoke-Sample $side $mode $scale 'AB' $round}
        }
    }
}
Write-Output "T6_PAIR_MATRIX_COMPLETE runs=$($runs.Count)"
