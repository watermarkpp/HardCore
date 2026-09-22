$ErrorActionPreference = 'Continue'
$treeB = 'C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4r2-baseline'
$treeA = 'C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4r2'
$exe = "$treeA\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe"
$out = 'C:\Users\Administrator\Documents\HardCore-m30-causal'
New-Item -ItemType Directory -Force -Path "$out\raw","$out\logs" | Out-Null
$HEAD_B = '519dca099e0ac134f3e6e753ed27e2aeeb659e9f'
$HEAD_A = '796d83af5f59d6aa38c8f332c7cdde907a8dd3de'
$HEAD_C = 'bf887623691e3817683a12c8b5aa6df018323155'
$ledger = "$out\run_ledger.jsonl"
Set-Content -Path $ledger -Value $null
function Run-Case($tree, $head, $scenario, $count, $label, $pair, $side, $seq) {
  $env:APPDATA = "$tree\.godot\runtime_appdata"; $env:LOCALAPPDATA = "$tree\.godot\runtime_appdata"
  $env:HARDCORE_REV07_SCENARIOS = $scenario; $env:HARDCORE_REV07_COUNTS = $count
  $env:HARDCORE_REV07_LABEL = $label; $env:HARDCORE_REV07_HEAD = $head
  $started = (Get-Date).ToString('o')
  $p = Start-Process -FilePath $exe -ArgumentList @('--headless','--path',$tree,'res://tests/hc_monster_ai/m30_sampling_copy.tscn') -WorkingDirectory $tree -PassThru -RedirectStandardOutput "$out\logs\$label.stdout.log" -RedirectStandardError "$out\logs\$label.stderr.log"
  $done = $p.WaitForExit(60000)
  if (-not $done) { $p.Kill(); $status = 'TIMEOUT' } else { $status = if ($p.ExitCode -eq 0) { 'OK' } else { "EXIT$($p.ExitCode)" } }
  if ($status -eq 'OK') {
    $json = "$tree\outputs\hc_monster_ai_package\rev07_$label.json"
    if (Test-Path $json) { Copy-Item $json "$out\raw\rev07_$label.json" -Force } else { $status = 'NO_JSON' }
  }
  $ended = (Get-Date).ToString('o')
  @{seq=$seq; pair=$pair; side=$side; label=$label; head=$head.Substring(0,8); tree=(Split-Path $tree -Leaf); scenario=$scenario; count=$count; started_at=$started; ended_at=$ended; status=$status} | ConvertTo-Json -Compress | Add-Content $ledger
  Write-Host "$seq $label $status"
}
git -C $treeB checkout -q --detach $HEAD_B
git -C $treeA checkout -q --detach $HEAD_A
Run-Case $treeB $HEAD_B 'open_pursuit' '12' 'warmB' '-' 'warmup' 0
Run-Case $treeA $HEAD_A 'open_pursuit' '12' 'warmA' '-' 'warmup' 0
$seq = 1
# Phase A: sustained x30, 5 pairs, alternating exactly as ruled
$pairsA = @(@('before','after'),@('after','before'),@('before','after'),@('after','before'),@('before','after'))
for ($i = 0; $i -lt 5; $i++) {
  foreach ($side in $pairsA[$i]) {
    $tree = if ($side -eq 'before') { $treeB } else { $treeA }
    $head = if ($side -eq 'before') { $HEAD_B } else { $HEAD_A }
    Run-Case $tree $head 'sustained_close_attacks' '30' ("c30_p{0}_{1}" -f ($i + 1), $side) ($i + 1) $side $seq
    $seq++
  }
}
# Phase B: sustained x12, 3 pairs, alternating
$pairsB = @(@('before','after'),@('after','before'),@('before','after'))
for ($i = 0; $i -lt 3; $i++) {
  foreach ($side in $pairsB[$i]) {
    $tree = if ($side -eq 'before') { $treeB } else { $treeA }
    $head = if ($side -eq 'before') { $HEAD_B } else { $HEAD_A }
    Run-Case $tree $head 'sustained_close_attacks' '12' ("c12_p{0}_{1}" -f ($i + 1), $side) ($i + 1) $side $seq
    $seq++
  }
}
# Phase C: drift check, current bf887 sustained x30 x3 (not a new baseline)
git -C $treeA checkout -q --detach $HEAD_C
Run-Case $treeA $HEAD_C 'open_pursuit' '12' 'warmC' '-' 'warmup' 0
for ($r = 1; $r -le 3; $r++) {
  Run-Case $treeA $HEAD_C 'sustained_close_attacks' '30' ("drift_r{0}" -f $r) $r 'drift' $seq
  $seq++
}
Write-Host 'CAUSAL_DONE'
