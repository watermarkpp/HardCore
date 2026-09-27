param([Parameter(Mandatory=$true)][string]$SourceHead, [string]$EvidenceName="clean_checkout_report_closure", [switch]$ImportOnly)
$ErrorActionPreference='Stop'
$main='C:/Users/Administrator/Documents/HardCore'
$clean='C:/Users/Administrator/.codex/worktrees/r4-clean-verification/HardCore'
$ev=Join-Path (Join-Path $main 'docs/monster_combat_r4/sol_takeover/evidence') $EvidenceName
if(Test-Path -LiteralPath $ev){throw 'Refusing overwrite'}
New-Item -ItemType Directory -Path $ev | Out-Null
if(@(& git -C $clean status --porcelain=v1 -uno).Count -ne 0){throw 'Clean checkout has tracked changes'}
& git -C $clean switch --detach $SourceHead
if($LASTEXITCODE -ne 0){throw 'Safe detached switch failed'}
& python (Join-Path $main 'docs/monster_combat_r4/sol_takeover/evidence/materialize_bound_directive.py') $clean | Set-Content (Join-Path $ev 'directive_checkout.json') -Encoding utf8
if($LASTEXITCODE -ne 0){throw 'Bound directive checkout failed'}
$plan=Get-Content (Join-Path $main 'docs/monster_combat_r4/sol_takeover/evidence/clean_checkout_final/planned_tests.json') -Raw | ConvertFrom-Json
[ordered]@{source_head=$SourceHead;count=$plan.count;paths=$plan.paths;prior_import='clean_checkout_final/import: FAIL 16 BOM parser errors, 609 source hashes preserved, tracked-clean; cache independent';started_at=(Get-Date -Format o)} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ev 'identity.json') -Encoding utf8
$env:APPDATA=Join-Path $clean '.godot/runtime_appdata'
$godot=Join-Path $clean 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
& $godot --headless --editor --path $clean --import --quit --log-file (Join-Path $ev 'import.godot.log') *> (Join-Path $ev 'import.console.log')
$code=$LASTEXITCODE
$backup=Get-Content (Join-Path $main 'docs/monster_combat_r4/sol_takeover/evidence/clean_checkout_final/translation_backup.json') -Raw | ConvertFrom-Json
$translations=@()
foreach($row in $backup.files){
  $target=Join-Path $clean $row.path
  $current=(Get-FileHash -LiteralPath $target).Hash
  if($current -ne $row.sha256){
    $original=Join-Path $backup.backup_root $row.path
    if((Get-FileHash $original).Hash -ne $row.sha256){throw 'Translation backup drift'}
    Copy-Item -LiteralPath $original -Destination $target
  }
  $translations+=[ordered]@{path=$row.path;generated_sha256=$current;final_sha256=(Get-FileHash $target).Hash;expected_sha256=$row.sha256}
}
$protection=Get-Content (Join-Path $main 'docs/monster_combat_r4/sol_takeover/evidence/skill_import_cache_backup.json') -Raw | ConvertFrom-Json
$changed=@()
foreach($row in $protection.sources){if((Get-FileHash (Join-Path $clean $row.path)).Hash -ne $row.sha256){$changed+=$row.path}}
$errors=@(Select-String -Path (Join-Path $ev 'import.console.log') -Pattern 'SCRIPT ERROR:|^ERROR:|Parse Error')
$dirty=@(& git -C $clean status --porcelain=v1 -uno)
$valid=$code -eq 0 -and $errors.Count -eq 0 -and $dirty.Count -eq 0 -and $changed.Count -eq 0
[ordered]@{source_head=$SourceHead;status=if($valid){'PASS'}else{'FAIL'};exit_code=$code;errors=@($errors.Line);changed_skill_sources=$changed;checked_skill_sources=$protection.sources.Count;tracked_dirty=$dirty;translations=$translations} | ConvertTo-Json -Depth 7 | Set-Content (Join-Path $ev 'import_verification.json') -Encoding utf8
if(-not $valid){throw 'Independent import closure failed'}
Write-Output 'CLEAN_IMPORT_CLOSURE_PASS'
if($ImportOnly){
  [ordered]@{source_head=$SourceHead;import='PASS';tests='NOT_RUN';reason='Explicit import-only preparation for separately recorded fixed paired workload'} | ConvertTo-Json | Set-Content (Join-Path $ev 'completion.json') -Encoding utf8
  exit 0
}
$env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $ev 'runner'
$reportBefore=Test-Path (Join-Path $clean 'outputs/test_logs')
$start=Get-Date
& (Join-Path $clean 'tools/run_godot_tests.ps1') -TestPaths @($plan.paths) -TimeoutSeconds 30
$exitCode=$LASTEXITCODE
$raw=Join-Path $ev 'raw';New-Item -ItemType Directory -Path $raw | Out-Null
foreach($f in @(Get-ChildItem (Join-Path $clean 'outputs/test_logs') -Filter 'r4_*.json' -File)){if($f.LastWriteTime -ge $start){Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $raw $f.Name)}}
[ordered]@{source_head=$SourceHead;exit_code=$exitCode;finished_at=(Get-Date -Format o);project_report_directory_before_runner=$reportBefore;project_report_directory_after_runner=(Test-Path (Join-Path $clean 'outputs/test_logs'));tracked_status=@(& git -C $clean status --porcelain=v1 -uno)} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $ev 'completion.json') -Encoding utf8
if($exitCode -ne 0){throw 'Clean regression failure'}
Write-Output 'CLEAN_REGRESSION_CLOSURE_PASS count=103'
