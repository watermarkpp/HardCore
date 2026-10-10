$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'tools\test_native_log_evidence.ps1')
$evidence = Join-Path $root 'outputs\b26_runner_export_guards'
$nonce = Join-Path $evidence ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $nonce -Force | Out-Null
$records = [Collections.Generic.List[object]]::new()
try {
    $log = Join-Path $nonce 'malformed_failed_count.log'
    $receiptPath = Join-Path $nonce 'malformed_failed_count.json'
    Set-Content -LiteralPath $log -Value 'B26_GUARD_PASS checks=1' -Encoding UTF8
    [ordered]@{ scene_id='b26_guard_scene'; invocation_id='b26_guard_invocation'; status='PASS'; count=1; failed='not-a-number'; checks=@(@{passed=$true}) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
    $malformed = Get-NativeLogEvidence -RawLogPaths @($log) -ReceiptPath $receiptPath -ExpectedSceneId 'b26_guard_scene' -ExpectedInvocationId 'b26_guard_invocation'
    if ($malformed.candidate_receipt_correlation) { throw 'malformed failed count was admitted' }
    if (@($malformed.receipt_validation_reasons) -notcontains 'framework_receipt_failed_count_invalid') { throw 'malformed failed count was not classified' }
    $records.Add([ordered]@{ case='malformed_failed_count_is_classified'; status='PASS'; reasons=@($malformed.receipt_validation_reasons) })

    $validReceipt = Join-Path $nonce 'valid.json'
    [ordered]@{ scene_id='b26_guard_scene'; invocation_id='b26_guard_invocation'; status='PASS'; count=1; failed=0; checks=@(@{passed=$true}) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validReceipt -Encoding UTF8
    $valid = Get-NativeLogEvidence -RawLogPaths @($log) -ReceiptPath $validReceipt -ExpectedSceneId 'b26_guard_scene' -ExpectedInvocationId 'b26_guard_invocation'
    if (-not $valid.candidate_receipt_correlation) { throw 'valid failed count was rejected' }
    $records.Add([ordered]@{ case='numeric_zero_failed_count_is_admitted'; status='PASS' })

    $zipRoot = Join-Path $nonce 'zip_dispose'
    New-Item -ItemType Directory -Path $zipRoot -Force | Out-Null
    $payload = Join-Path $zipRoot 'payload.txt'
    Set-Content -LiteralPath $payload -Value 'b26' -Encoding UTF8
    $candidateZip = Join-Path $zipRoot 'candidate.zip'
    Compress-Archive -LiteralPath $payload -DestinationPath $candidateZip -Force
    $candidate = Join-Path $zipRoot 'candidate.apk'
    Move-Item -LiteralPath $candidateZip -Destination $candidate -Force
    $corruptBaseline = Join-Path $zipRoot 'corrupt-baseline.apk'
    Set-Content -LiteralPath $corruptBaseline -Value 'not a zip' -Encoding UTF8
    $verifyExit = 0
    $verifyReason = ''
    try { & (Join-Path $root 'tools\verify_apk_runtime_resources.ps1') -ApkPath $candidate -BaselineApkPath $corruptBaseline 2>$null } catch { $verifyExit = 1; $verifyReason = $_.Exception.Message }
    $moved = Join-Path $zipRoot 'candidate-moved.apk'
    Move-Item -LiteralPath $candidate -Destination $moved -Force
    if ($verifyExit -ne 1 -or $verifyReason -notmatch '(?i)zip|archive|central directory|end of central directory' -or -not (Test-Path -LiteralPath $moved) -or (Test-Path -LiteralPath $candidate)) { throw 'current archive remained locked or baseline open failure was not identified' }
    $records.Add([ordered]@{ case='current_archive_disposed_on_baseline_open_failure'; status='PASS'; verifier_exit=$verifyExit; baseline_open_reason=$verifyReason; moved=$true })

    $verifierPath = Join-Path $root 'tools\verify_apk_runtime_resources.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $verifierAst = [System.Management.Automation.Language.Parser]::ParseFile($verifierPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) { throw 'verifier AST parse failed' }
    foreach ($name in @('Get-ArchiveEntry', 'Get-ArchiveEntrySha256', 'Assert-ChangedFromBaseline')) {
        $functionAst = $verifierAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true) | Select-Object -First 1
        if ($null -eq $functionAst) { throw "verifier function missing: $name" }
        Invoke-Expression $functionAst.Extent.Text
    }
    $comparisonRoot = Join-Path $nonce 'comparison'
    New-Item -ItemType Directory -Path $comparisonRoot -Force | Out-Null
    $samePayload = Join-Path $comparisonRoot 'same.txt'; Set-Content -LiteralPath $samePayload -Value 'same' -Encoding UTF8
    $changedDir = Join-Path $comparisonRoot 'changed_payload'; New-Item -ItemType Directory -Path $changedDir -Force | Out-Null
    $changedPayload = Join-Path $changedDir 'same.txt'; Set-Content -LiteralPath $changedPayload -Value 'changed' -Encoding UTF8
    $newDir = Join-Path $comparisonRoot 'new_payload'; New-Item -ItemType Directory -Path $newDir -Force | Out-Null
    $newPayload = Join-Path $newDir 'payload.txt'; Set-Content -LiteralPath $newPayload -Value 'new' -Encoding UTF8
    $sameZip = Join-Path $comparisonRoot 'same.zip'; Compress-Archive -LiteralPath $samePayload -DestinationPath $sameZip -Force
    $changedZip = Join-Path $comparisonRoot 'changed.zip'; Compress-Archive -LiteralPath $changedPayload -DestinationPath $changedZip -Force
    $newZip = Join-Path $comparisonRoot 'new.zip'; Compress-Archive -LiteralPath $newPayload -DestinationPath $newZip -Force
    $sameArchive = [System.IO.Compression.ZipFile]::OpenRead($sameZip)
    $changedArchive = [System.IO.Compression.ZipFile]::OpenRead($changedZip)
    $newArchive = [System.IO.Compression.ZipFile]::OpenRead($newZip)
    try {
        $RequireRuntimeChangesFromBaseline = $true
        $AllowedUnchangedEntries = @('same.txt')
        $allowedResult = [bool](Assert-ChangedFromBaseline -CurrentArchive $sameArchive -BaselineArchive $sameArchive -EntryName 'same.txt')
        $changedResult = [bool](Assert-ChangedFromBaseline -CurrentArchive $changedArchive -BaselineArchive $sameArchive -EntryName 'same.txt')
        $newEntryResult = [bool](Assert-ChangedFromBaseline -CurrentArchive $newArchive -BaselineArchive $sameArchive -EntryName 'payload.txt')
        if ($allowedResult -or -not $changedResult -or -not $newEntryResult) { throw 'verifier changed-count classification failed' }
    } finally {
        $sameArchive.Dispose(); $changedArchive.Dispose(); $newArchive.Dispose()
    }
    $records.Add([ordered]@{ case='verifier_changed_count_allowed_changed_and_new_entry'; status='PASS'; allowed_count=0; changed_count=1; new_entry_count=1 })

    $savedAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
    $savedXdg = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME', 'Process')
    $sentinelAppData = 'B26_SENTINEL_APPDATA'
    $sentinelXdg = 'B26_SENTINEL_XDG'
    [Environment]::SetEnvironmentVariable('APPDATA', $sentinelAppData, 'Process')
    [Environment]::SetEnvironmentVariable('XDG_DATA_HOME', $sentinelXdg, 'Process')
    $runnerExit = 0
    $restoredAppData = $false
    $restoredXdg = $false
    try {
        & (Join-Path $root 'tools\run_godot_tests.ps1') -TestPaths @('tests/hc_polygon_navigation_test.tscn') -TimeoutSeconds 1 *> (Join-Path $nonce 'runner_environment.log')
        $runnerExit = [int]$LASTEXITCODE
        $restoredAppData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process') -ceq $sentinelAppData
        $restoredXdg = [Environment]::GetEnvironmentVariable('XDG_DATA_HOME', 'Process') -ceq $sentinelXdg
        $runnerLog = Get-Content -LiteralPath (Join-Path $nonce 'runner_environment.log') -Raw -ErrorAction Stop
        if ($runnerLog -notmatch 'Godot Engine v4\.7\.stable\.official\.5b4e0cb0f' -or $runnerLog -notmatch 'RUNNER_RESULTS_JSON=') { throw 'runner environment case did not reach native launch/evidence stage' }
    } finally {
        [Environment]::SetEnvironmentVariable('APPDATA', $savedAppData, 'Process')
        [Environment]::SetEnvironmentVariable('XDG_DATA_HOME', $savedXdg, 'Process')
    }
    if (-not $restoredAppData -or -not $restoredXdg) { throw 'runner did not restore process environment variables' }
    $records.Add([ordered]@{ case='same_process_runner_restores_environment'; status='PASS'; runner_exit=$runnerExit; native_launch_observed=$true; appdata_restored=$restoredAppData; xdg_restored=$restoredXdg; xdg_scope='Windows process sentinel; Linux path not run on this host' })
    $result = [ordered]@{ status='PASS'; cases=@($records); helper='tools/test_native_log_evidence.ps1'; godot_run='EXECUTED_SHORT_FAILURE_TARGET' }
} catch {
    $result = [ordered]@{ status='FAIL'; cases=@($records); error=$_.Exception.Message; godot_run='EXECUTED_SHORT_FAILURE_TARGET' }
    throw
} finally {
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $nonce 'b26_runner_export_guards_test.json') -Encoding UTF8
}
