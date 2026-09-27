$ErrorActionPreference='Stop'
$main='C:/Users/Administrator/Documents/HardCore'
$base='C:/Users/Administrator/.codex/worktrees/r4-fixed-baseline/HardCore'
$evidence=Join-Path $main 'docs/monster_combat_r4/sol_takeover/evidence/t6_v5_identity_smoke_fresh'
foreach ($side in @('BASE','CAND')) {
  $root=if($side -eq 'BASE'){$base}else{$main}
  $dest=Join-Path $evidence $side
  if(Test-Path -LiteralPath $dest){throw 'Refusing to overwrite smoke evidence'}
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  $env:HARDCORE_R4_LOAD_NAMESPACE='v5-smoke-fresh-20260927'
  $env:HARDCORE_R4_LOAD_MODE='aoe_death_loot';$env:HARDCORE_R4_LOAD_COUNT='10'
  $env:HARDCORE_R4_LOAD_HEAD=(& git -C $root rev-parse HEAD).Trim()
  $env:HARDCORE_R4_LOAD_LABEL="v5-identity-smoke-$side"
  $env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $dest 'runner'
  & (Join-Path $root 'tools/run_godot_tests.ps1') -TestPaths @('tests/hc_monster_combat_r4/t6_real_load_probe.tscn') -TimeoutSeconds 60
  $code=$LASTEXITCODE
  $raw=Join-Path $root 'outputs/test_logs/r4_t6_load.json'
  if(Test-Path -LiteralPath $raw){Copy-Item -LiteralPath $raw -Destination (Join-Path $dest 'load.json')}
  [ordered]@{source_head=$env:HARDCORE_R4_LOAD_HEAD;exit_code=$code;probe_sha256=(Get-FileHash (Join-Path $root 'tests/hc_monster_combat_r4/t6_real_load_probe.gd')).Hash;finished=(Get-Date -Format o)} | ConvertTo-Json | Set-Content (Join-Path $dest 'identity.json') -Encoding utf8
  if($code -ne 0){throw "Smoke failed: $side"}
}
