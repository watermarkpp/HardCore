param(
    [string]$BaseRoot = 'C:/Users/Administrator/.codex/worktrees/r4-fixed-baseline/HardCore',
    [string]$CandidateRoot = 'C:/Users/Administrator/Documents/HardCore',
    [string]$OutputRoot = 'C:/Users/Administrator/Documents/HardCore/docs/monster_combat_r4/sol_takeover/evidence/r3_radius_pairs'
)
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $OutputRoot) {throw 'Evidence already exists'}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$scene='tests/hc_monster_combat_r4/summon_planner_radius_test.tscn'
$script=$scene -replace '\.tscn$','.gd'
foreach ($path in @($scene,$script)) {
    Copy-Item -LiteralPath (Join-Path $CandidateRoot $path) -Destination (Join-Path $BaseRoot $path)
    & git -C $BaseRoot add -f -- $path
    if ($LASTEXITCODE -ne 0) {throw 'Test overlay staging failed'}
}
[ordered]@{base_head=(& git -C $BaseRoot rev-parse HEAD).Trim();candidate_head=(& git -C $CandidateRoot rev-parse HEAD).Trim();probe_sha256=(Get-FileHash -LiteralPath (Join-Path $CandidateRoot $script)).Hash;scene_sha256=(Get-FileHash -LiteralPath (Join-Path $CandidateRoot $scene)).Hash;scope='Actual planner query radius and release snapshot. Same test-only overlay; no BASE production changes.'} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputRoot 'identity.json') -Encoding utf8
foreach ($side in @('BASE','CAND')) {
    $root=if ($side -eq 'BASE') {$BaseRoot} else {$CandidateRoot}
    $env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $OutputRoot $side
    & (Join-Path $root 'tools/run_godot_tests.ps1') -TestPaths @($scene) -TimeoutSeconds 30
    $code=$LASTEXITCODE
    if ($side -eq 'BASE') {
        $out=Get-Content -LiteralPath (Join-Path $env:HARDCORE_AUDIT_LOG_ROOT 'summon_planner_radius_test.stdout.log') -Raw
        if ($code -eq 0 -or $out -notmatch 'planner_radius=0\.331456' -or $out -notmatch 'planner_radius=0\.464039' -or $out -notmatch 'release_snapshot_radius_mismatch') {throw 'BASE did not fail on expected radius behavior'}
    } elseif ($code -ne 0) {throw 'Candidate radius regression'}
}
