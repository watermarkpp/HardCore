$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'tools\test_native_log_evidence.ps1')
$evidenceRoot = Join-Path $root 'outputs\wake_drop_v108_review_followup_20261009\b07b_log_evidence'
$nonceRoot = Join-Path $evidenceRoot ([Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $nonceRoot -Force | Out-Null
$records = [Collections.Generic.List[object]]::new()
function Write-Fixture([string]$Name, [string]$Text, [object]$Receipt) {
    $log = Join-Path $nonceRoot ($Name + '.log')
    $receiptPath = Join-Path $nonceRoot ($Name + '.json')
    Set-Content -LiteralPath $log -Value $Text -Encoding UTF8
    if ($null -ne $Receipt) { $Receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8 }
    return @($log, $receiptPath)
}
try {
    $validReceipt = [ordered]@{ scene_id='scene_a'; invocation_id='invoke_a'; run_id='run_a'; status='PASS'; count=3; failed=0; checks=@(@{passed=$true},@{passed=$true},@{passed=$true}) }
    $allowlistedText = @'
ERROR: String formatting error: not all arguments converted during string formatting.
ERROR: 2 resources still in use at exit
ERROR: 1 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.
ERROR: Parameter "t" is null.
Leaked instance: ObjectDB:123 - RefCounted
WARNING: ObjectDB instances leaked at exit (run with --verbose for details).
SCENE_PASS checks=3
'@
    $paths = Write-Fixture 'allowlisted' $allowlistedText $validReceipt
    $allowed = Get-NativeLogEvidence -RawLogPaths @($paths[0]) -ReceiptPath $paths[1] -ExpectedSceneId 'scene_a' -ExpectedInvocationId 'invoke_a'
    if ($allowed.status -ne 'PASS' -or $allowed.formal_evidence_status -ne 'MISSING' -or -not $allowed.candidate_receipt_correlation -or $allowed.unknown_error_count -ne 0 -or $allowed.objectdb_leak_warning_count -ne 2) { throw 'allowlist/upstream ownership case failed' }
    foreach ($category in $allowed.allowlisted_errors.Values) { if ($category.count -ne 1) { throw 'allowlist category count mismatch' } }
    $records.Add([ordered]@{ case='four_allowlist_categories_and_objectdb_warning'; status='PASS'; counts=$allowed.allowlisted_errors })

    $paths = Write-Fixture 'unknown_legacy' "ERROR: Unknown failure from engine`nLEGACY_SCENE_PASS checks=2" $null
    $unknown = Get-NativeLogEvidence -RawLogPaths @($paths[0]) -ReceiptPath $paths[1] -ExpectedSceneId 'scene_b' -ExpectedInvocationId 'invoke_b'
    if ($unknown.status -ne 'FAIL' -or $unknown.formal_evidence_status -ne 'MISSING' -or -not $unknown.functional_marker_observed -or $unknown.formal_evidence_reason -ne 'legacy_run_bound_checks_missing') { throw 'unknown/legacy gating failed' }
    $records.Add([ordered]@{ case='unknown_error_and_legacy_marker'; status='PASS'; formal=$unknown.formal_evidence_status })

    $foreignReceipt = [ordered]@{ scene_id='other_scene'; invocation_id='other_invocation'; status='PASS'; count=2; failed=0; checks=@(@{passed=$true},@{passed=$true}) }
    $paths = Write-Fixture 'foreign_receipt' 'FOREIGN_SCENE_PASS checks=2' $foreignReceipt
    $foreign = Get-NativeLogEvidence -RawLogPaths @($paths[0]) -ReceiptPath $paths[1] -ExpectedSceneId 'scene_c' -ExpectedInvocationId 'invoke_c'
    if ($foreign.formal_evidence_status -ne 'MISSING' -or $foreign.status -ne 'PASS') { throw 'foreign receipt gating failed' }
    $records.Add([ordered]@{ case='foreign_pass_receipt_is_formal_missing'; status='PASS'; formal=$foreign.formal_evidence_status })

    $paths = Write-Fixture 'foreign_rid' "ERROR: 1 RID allocations of type 'UnrelatedRendererResource' were leaked at exit." $null
    $foreignRid = Get-NativeLogEvidence -RawLogPaths @($paths[0]) -ReceiptPath $paths[1] -ExpectedSceneId 'scene_d' -ExpectedInvocationId 'invoke_d'
    if ($foreignRid.status -ne 'FAIL' -or $foreignRid.unknown_error_count -ne 1 -or $foreignRid.allowlisted_errors.rid_leak.count -ne 0) { throw 'unrelated RID must remain an unallowlisted error' }
    $records.Add([ordered]@{ case='unrelated_rid_error_is_not_allowlisted'; status='PASS' })

    $result = [ordered]@{ status='PASS'; cases=@($records); helper='tools/test_native_log_evidence.ps1';
        helper_sha256=(Get-FileHash -LiteralPath (Join-Path $root 'tools/test_native_log_evidence.ps1')).Hash;
        test_sha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;
        command='powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/tests/native_log_evidence_20261010_test.ps1';
        godot_run='NOT_RUN'; upstream_formal_decision='NOT_GRANTED' }
} catch {
    $result = [ordered]@{ status='FAIL'; cases=@($records); error=$_.Exception.Message; helper='tools/test_native_log_evidence.ps1'; godot_run='NOT_RUN' }
    throw
} finally {
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $nonceRoot 'native_log_evidence_test.json') -Encoding UTF8
}
