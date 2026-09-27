param([Parameter(Mandatory=$true)][string]$SourceHead)
$ErrorActionPreference='Stop'
$root='C:/Users/Administrator/Documents/HardCore'
$source=$SourceHead
$ev=Join-Path $root 'docs/monster_combat_r4/sol_takeover/evidence'
$state=[ordered]@{critical_source_head='3b21c115da6b8d5ed57e706432912dafcb377748';source_head=$source;critical='PASS';critical_unchanged_production='PASS';clean_import='NOT_RUN';clean_tests='NOT_RUN';performance_matrix='NOT_RUN';performance_acceptance='NOT_RUN'}
function Save-State{$state | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ev 'verification_pipeline_report_closure.json') -Encoding utf8}
try {
 Save-State
 & (Join-Path $ev 'run_clean_fixture_closure.ps1') -SourceHead $source
 if($LASTEXITCODE -ne 0){throw 'Clean closure child failed'}
 $clean=Join-Path $ev 'clean_checkout_report_closure'
 $import=Get-Content (Join-Path $clean 'import_verification.json') -Raw | ConvertFrom-Json
 if($import.status -ne 'PASS'){throw 'Independent import not PASS'}
 $state.clean_import='PASS';Save-State
 $runner=@(Get-ChildItem (Join-Path $clean 'runner') -Filter 'runner_results*.json')
 if($runner.Count -ne 1){throw 'Ambiguous clean runner'}
 $result=Get-Content $runner[0].FullName -Raw | ConvertFrom-Json
 $plan=Get-Content (Join-Path $ev 'clean_checkout_report_closure/identity.json') -Raw | ConvertFrom-Json
 $actual=@($result.results | ForEach-Object {$_.test_path})
 if($result.failed -ne 0 -or $result.engine_log_errors -ne 0 -or $result.passed -ne 103 -or @($actual | Sort-Object -Unique).Count -ne 103 -or @($plan.paths | Where-Object {$_ -notin $actual}).Count -ne 0 -or $result.git_head -ne $source){throw 'Clean actual execution set invalid'}
 $state.clean_tests='PASS';Save-State
 if((& git -C $root rev-parse HEAD).Trim() -ne $source){throw 'Candidate HEAD drift'}
 $matrix=Join-Path $ev 't6_pairs_final_v5'
 & (Join-Path $root 'tools/run_monster_r4_t6_pairs.ps1') -OutputRoot $matrix
 if($LASTEXITCODE -ne 0){throw 'T6 matrix failed'}
 & python (Join-Path $root 'tools/summarize_monster_r4_t6.py') $matrix
 if($LASTEXITCODE -ne 0){throw 'T6 summary failed'}
 $summary=Get-Content (Join-Path $matrix 'summary.json') -Raw | ConvertFrom-Json
 if($summary.status -ne 'PASS' -or $summary.runs -ne 72){throw 'Incomplete matrix'}
 $state.performance_matrix='PASS';Save-State
 Write-Output 'R4_FIXTURE_COLLECTION_COMPLETE; controller review still needed; no merge/push/APK performed'
}catch{
 $state['error']=$_.Exception.Message;Save-State;Write-Error $_;exit 1
}
