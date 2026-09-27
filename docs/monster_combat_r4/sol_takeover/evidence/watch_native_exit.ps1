param([string]$Case='all_damage_lost_test')
$ErrorActionPreference='Stop'
$main='C:/Users/Administrator/Documents/HardCore'
$clean='C:/Users/Administrator/.codex/worktrees/r4-clean-verification/HardCore'
$out=Join-Path $main ('docs/monster_combat_r4/sol_takeover/evidence/exit_watch_'+$Case)
if(Test-Path $out){throw 'Do not overwrite'}
New-Item -ItemType Directory -Path $out | Out-Null
$env:APPDATA=Join-Path $clean '.godot/runtime_appdata'
$env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $out 'runner'
$pwsh=(Get-Process -Id $PID).Path
$args='-NoProfile -NonInteractive -File "'+(Join-Path $clean 'tools/run_godot_tests.ps1')+'" -TestPaths "tests/hc_monster_combat_r4/'+$Case+'.tscn" -TimeoutSeconds 60'
$p=Start-Process -FilePath $pwsh -ArgumentList $args -WindowStyle Hidden -WorkingDirectory $clean -RedirectStandardOutput (Join-Path $out 'collector.stdout.log') -RedirectStandardError (Join-Path $out 'collector.stderr.log') -PassThru
$engineRows=@{}
$end=(Get-Date).AddSeconds(80)
while(-not $p.HasExited -and (Get-Date) -lt $end){
 $observed=Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' }
 $now=[DateTime]::UtcNow
 foreach($e in $observed){if(-not $engineRows.ContainsKey($e.Id)){ $engineRows[$e.Id]=[ordered]@{id=$e.Id;name=$e.ProcessName;image_path=$e.Path;started_utc=$e.StartTime.ToUniversalTime().ToString('o');first_observed_utc=$now.ToString('o');last_alive_utc=$now.ToString('o');first_absent_utc=$null} }else{$engineRows[$e.Id].last_alive_utc=$now.ToString('o')}}
 foreach($id in @($engineRows.Keys)){if($id -notin @($observed.Id) -and $null -eq $engineRows[$id].first_absent_utc){$engineRows[$id].first_absent_utc=$now.ToString('o')}}
 Start-Sleep -Milliseconds 100
}
if(-not $p.HasExited){throw 'Owned runner did not finish; manual inspect required'}
$p.Refresh()
[ordered]@{source_head=((& git -C $clean rev-parse HEAD)-join '').Trim();case=$Case;runner_exit=$p.ExitCode;engine_processes=@($engineRows.Values);note='Independent process observations; first_absent is upper bound on actual native exit. PASS marker alone is not evidence of exit.'} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out 'process_exit_facts.json') -Encoding utf8
Get-Content (Join-Path $out 'process_exit_facts.json')

