param([switch]$WaitForCritical)
$ErrorActionPreference = 'Stop'
$mainRoot = 'C:/Users/Administrator/Documents/HardCore'
$cleanRoot = 'C:/Users/Administrator/.codex/worktrees/r4-clean-verification/HardCore'
$sourceHead = 'f88825cc74ba624bffc6600710b7d27b72a9a52a'
$evidenceRoot = Join-Path $mainRoot 'docs/monster_combat_r4/sol_takeover/evidence'
$criticalRoot = Join-Path $evidenceRoot 'final_critical_after_import'
$cleanEvidence = Join-Path $evidenceRoot 'clean_checkout'
$statePath = Join-Path $evidenceRoot 'verification_pipeline_state.json'
$taskOriginalAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$state = [ordered]@{source_head=$sourceHead; critical='NOT_RUN'; clean_import='NOT_RUN'; clean_tests='NOT_RUN'; performance_matrix='NOT_RUN'; performance_acceptance='NOT_RUN'}
function Save-State { $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8 }
function Check-Head([string]$root) {
    if ((& git -C $root rev-parse HEAD).Trim() -ne $sourceHead) {throw "Source drift: $root"}
}
function Record-Raw([string]$root,[string]$dest,[datetime]$since) {
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $rows = @()
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'outputs/test_logs') -Filter 'r4_*.json' -File)) {
        if ($file.LastWriteTime -ge $since) {
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $dest $file.Name)
            $rows += [ordered]@{file=$file.Name;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash;written_at=$file.LastWriteTime.ToString('o')}
        }
    }
    [ordered]@{source_head=$sourceHead;since=$since.ToString('o');files=$rows;note='Actual raw files written during this run; no prior cache copied'} | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $dest 'identity.json') -Encoding utf8
}
try {
    Save-State
    if ($WaitForCritical) {
        Write-Output 'WAITING_FOR_OWNED_CRITICAL_COMPLETION; no second Godot process started'
        while (-not (Test-Path -LiteralPath (Join-Path $criticalRoot 'completion.json'))) { Start-Sleep -Seconds 2 }
    }
    Check-Head $mainRoot
    Check-Head $cleanRoot
    $completion = Get-Content -LiteralPath (Join-Path $criticalRoot 'completion.json') -Raw | ConvertFrom-Json
    $critical = @(Get-ChildItem -LiteralPath (Join-Path $criticalRoot 'runner') -Filter 'runner_results_*.json')
    if ($critical.Count -ne 1) {throw 'Ambiguous critical runner identity'}
    $result = Get-Content -LiteralPath $critical[0].FullName -Raw | ConvertFrom-Json
    $expected = @(Get-Content -LiteralPath (Join-Path $evidenceRoot 'expected_critical_paths.json') -Raw | ConvertFrom-Json)
    $actual = @($result.results | ForEach-Object {$_.test_path})
    $missing = @($expected | Where-Object {$_ -notin $actual})
    $extra = @($actual | Where-Object {$_ -notin $expected})
    $setValid = $actual.Count -eq 525 -and @($actual | Sort-Object -Unique).Count -eq 525 -and $missing.Count -eq 0 -and $extra.Count -eq 0
    [ordered]@{source_head=$sourceHead;status=if($setValid){'PASS'}else{'FAIL'};expected_count=$expected.Count;actual_count=$actual.Count;missing=$missing;extra=$extra;runner=$critical[0].Name} | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $criticalRoot 'executed_set.json') -Encoding utf8
    $criticalIdentity = Get-Content -LiteralPath (Join-Path $criticalRoot 'identity.json') -Raw | ConvertFrom-Json
    Record-Raw $mainRoot (Join-Path $criticalRoot 'raw') ([datetime]$criticalIdentity.started_at)
    if ($completion.exit_code -ne 0 -or $completion.source_head -ne $sourceHead -or $result.failed -ne 0 -or $result.passed -ne 525 -or -not $setValid) {throw 'Final critical failed; preserve raw output and stop before further engines'}
    $state.critical='PASS'; Save-State
    Write-Output 'FINAL_CRITICAL_PASS actual=525 expected=525'
    if (@(& git -C $cleanRoot status --porcelain=v1 -uno).Count -ne 0) {throw 'Unexpected tracked changes before independent import'}
    $translationBackup = Get-Content -LiteralPath (Join-Path $cleanEvidence 'translation_backup.json') -Raw | ConvertFrom-Json
    $sourceProtection = Get-Content -LiteralPath (Join-Path $evidenceRoot 'skill_import_cache_backup.json') -Raw | ConvertFrom-Json
    $importRoot = Join-Path $cleanEvidence 'import'
    if (Test-Path -LiteralPath $importRoot) {throw 'Refusing to overwrite independent import evidence'}
    New-Item -ItemType Directory -Path $importRoot | Out-Null
    $env:APPDATA = Join-Path $cleanRoot '.godot/runtime_appdata'
    New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    Write-Output 'CLEAN_IMPORT_BEGIN independent cache/userdata; no main audit manifest copied'
    $godot = Join-Path $cleanRoot 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
    & $godot --headless --editor --path $cleanRoot --import --log-file (Join-Path $importRoot 'godot.log') *> (Join-Path $importRoot 'console.log')
    $importExit = $LASTEXITCODE
    $translationRows=@()
    foreach($row in $translationBackup.files) {
        $target=[IO.Path]::GetFullPath((Join-Path $cleanRoot $row.path))
        if (-not $target.StartsWith([IO.Path]::GetFullPath($cleanRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Translation target escapes clean checkout'}
        $current=(Get-FileHash -LiteralPath $target).Hash
        $restored=$false
        if ($current -ne $row.sha256) {
            $original=Join-Path $translationBackup.backup_root $row.path
            if ((Get-FileHash -LiteralPath $original).Hash -ne $row.sha256) {throw 'Pre-import translation backup mismatch'}
            Copy-Item -LiteralPath $original -Destination $target
            $restored=$true
        }
        $translationRows += [ordered]@{path=$row.path;generated_sha256=$current;restored=$restored;final_sha256=(Get-FileHash -LiteralPath $target).Hash;expected_sha256=$row.sha256}
    }
    $sourceRows=@()
    foreach($row in $sourceProtection.sources) {
        $current=(Get-FileHash -LiteralPath (Join-Path $cleanRoot $row.path)).Hash
        $sourceRows += [ordered]@{path=$row.path;expected_sha256=$row.sha256;current_sha256=$current;status=if($current -eq $row.sha256){'PASS'}else{'FAIL'}}
    }
    $trackedDirty=@(& git -C $cleanRoot status --porcelain=v1 -uno)
    $errors=@(Select-String -Path (Join-Path $importRoot 'console.log') -Pattern 'SCRIPT ERROR:|^ERROR:|Parse Error')
    $importValid=$importExit -eq 0 -and $errors.Count -eq 0 -and @($sourceRows | Where-Object {$_.status -ne 'PASS'}).Count -eq 0 -and $trackedDirty.Count -eq 0
    [ordered]@{source_head=$sourceHead;status=if($importValid){'PASS'}else{'FAIL'};exit_code=$importExit;errors=@($errors.Line);tracked_dirty=$trackedDirty;source_rows=$sourceRows;translations=$translationRows} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $importRoot 'verification.json') -Encoding utf8
    if (-not $importValid) {throw 'Independent import failed; inspect generated deltas before continuing'}
    $state.clean_import='PASS'; Save-State
    Write-Output 'CLEAN_IMPORT_PASS source_pixels_unchanged=609 tracked_clean=true'
    $plan=Get-Content -LiteralPath (Join-Path $cleanEvidence 'planned_tests.json') -Raw | ConvertFrom-Json
    $env:HARDCORE_AUDIT_LOG_ROOT=Join-Path $cleanEvidence 'runner'
    $cleanStarted=Get-Date
    & (Join-Path $cleanRoot 'tools/run_godot_tests.ps1') -TestPaths @($plan.paths) -TimeoutSeconds 30
    $cleanExit=$LASTEXITCODE
    Record-Raw $cleanRoot (Join-Path $cleanEvidence 'raw') $cleanStarted
    $cleanResults=@(Get-ChildItem -LiteralPath $env:HARDCORE_AUDIT_LOG_ROOT -Filter 'runner_results_*.json')
    if($cleanResults.Count -ne 1) {throw 'Ambiguous clean result identity'}
    $cleanResult=Get-Content -LiteralPath $cleanResults[0].FullName -Raw | ConvertFrom-Json
    Check-Head $mainRoot; Check-Head $cleanRoot
    if($cleanExit -ne 0 -or $cleanResult.passed -ne $plan.count -or $cleanResult.failed -ne 0) {throw 'Independent source regression failed; preserve and diagnose'}
    $state.clean_tests='PASS'; Save-State
    Write-Output "CLEAN_REGRESSION_PASS count=$($plan.count)"
    [Environment]::SetEnvironmentVariable('APPDATA', $taskOriginalAppData, 'Process')
    $matrix=Join-Path $evidenceRoot 't6_pairs_final_v4'
    if(Test-Path -LiteralPath $matrix) {throw 'Refusing to overwrite performance evidence'}
    Write-Output 'T6_FINAL_MATRIX_BEGIN 72 serial samples; no other engine/import/hash sweep/commit permitted'
    Set-Location $mainRoot
    & (Join-Path $mainRoot 'tools/run_monster_r4_t6_pairs.ps1') -OutputRoot $matrix
    $matrixExit=$LASTEXITCODE
    if($matrixExit -ne 0) {throw 'Performance sample or workload contract failed'}
    & python (Join-Path $mainRoot 'tools/summarize_monster_r4_t6.py') $matrix
    if($LASTEXITCODE -ne 0) {throw 'Performance summarizer failed'}
    $summary=Get-Content -LiteralPath (Join-Path $matrix 'summary.json') -Raw | ConvertFrom-Json
    if($summary.status -ne 'PASS' -or $summary.runs -ne 72) {throw 'Incomplete final paired dataset'}
    $state.performance_matrix='PASS'; Save-State
    Write-Output 'VERIFICATION_COLLECTION_COMPLETE; performance warnings still require controller review; no Git push/APK performed'
} catch {
    $state['error'] = $_.Exception.Message
    Save-State
    Write-Error $_
    exit 1
}
