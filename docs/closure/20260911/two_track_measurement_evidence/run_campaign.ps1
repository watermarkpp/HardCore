$ErrorActionPreference = 'Continue'
$aft = 'C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4r2'
$bef = 'C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4r2-baseline'
$exe = "$aft\tools\godot-4.7\Godot_v4.7-stable_win64_console.exe"
$out = 'C:\Users\Administrator\Documents\HardCore-m30-campaign'
New-Item -ItemType Directory -Force -Path "$out\raw","$out\logs" | Out-Null
$sides = @(@{tree=$aft; name='after'; head='bf887623'}, @{tree=$bef; name='before'; head='8dd1d092'})
# Warmup imports per tree (not counted as data)
foreach ($side in $sides) {
  $env:APPDATA = "$($side.tree)\.godot\runtime_appdata"; $env:LOCALAPPDATA = "$($side.tree)\.godot\runtime_appdata"
  $env:HARDCORE_REV07_SCENARIOS = 'open_pursuit'; $env:HARDCORE_REV07_COUNTS = '12'
  $env:HARDCORE_REV07_LABEL = "warmup_$($side.name)"; $env:HARDCORE_REV07_HEAD = $side.head
  $p = Start-Process -FilePath $exe -ArgumentList @('--headless','--path',$side.tree,'res://tests/hc_monster_ai/m30_sampling_copy.tscn') -WorkingDirectory $side.tree -PassThru -RedirectStandardOutput "$out\logs\warmup_$($side.name).stdout.log" -RedirectStandardError "$out\logs\warmup_$($side.name).stderr.log"
  if (-not $p.WaitForExit(150000)) { $p.Kill(); Write-Host "warmup_$($side.name) TIMEOUT" } else { Write-Host "warmup_$($side.name) exit=$($p.ExitCode)" }
}
$scen = @('open_pursuit','sustained_close_attacks')
$counts = @('12','15','30')
foreach ($side in $sides) {
  foreach ($round in 1..3) {
    foreach ($sc in $scen) {
      foreach ($cnt in $counts) {
        $label = "{0}_r{1}_{2}_{3}" -f $side.name, $round, $sc, $cnt
        $env:APPDATA = "$($side.tree)\.godot\runtime_appdata"; $env:LOCALAPPDATA = "$($side.tree)\.godot\runtime_appdata"
        $env:HARDCORE_REV07_SCENARIOS = $sc; $env:HARDCORE_REV07_COUNTS = $cnt
        $env:HARDCORE_REV07_LABEL = $label; $env:HARDCORE_REV07_HEAD = $side.head
        $p = Start-Process -FilePath $exe -ArgumentList @('--headless','--path',$side.tree,'res://tests/hc_monster_ai/m30_sampling_copy.tscn') -WorkingDirectory $side.tree -PassThru -RedirectStandardOutput "$out\logs\$label.stdout.log" -RedirectStandardError "$out\logs\$label.stderr.log"
        $done = $p.WaitForExit(60000)
        if (-not $done) { $p.Kill(); $status = 'TIMEOUT' } else { $status = if ($p.ExitCode -eq 0) { 'OK' } else { "EXIT$($p.ExitCode)" } }
        if ($status -eq 'OK') {
          $json = "$($side.tree)\outputs\hc_monster_ai_package\rev07_$label.json"
          if (Test-Path $json) { Copy-Item $json "$out\raw\rev07_$label.json" -Force } else { $status = 'NO_JSON' }
        }
        Write-Host "$label $status"
      }
    }
  }
}
Write-Host 'CAMPAIGN_DONE'
