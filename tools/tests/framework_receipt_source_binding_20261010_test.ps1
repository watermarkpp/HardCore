param([string]$OutputRoot = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot 'tools/test_framework_receipt.ps1')
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $projectRoot ('outputs/test_logs/framework_receipt_source_binding_' + [guid]::NewGuid().ToString('N'))
}
$fullOutput = [IO.Path]::GetFullPath($OutputRoot)
$ownedPrefix = [IO.Path]::GetFullPath((Join-Path $projectRoot 'outputs')).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $fullOutput.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Test output escapes outputs.' }
New-Item -ItemType Directory -Path $fullOutput -ErrorAction Stop | Out-Null
$fixturePath = Join-Path $fullOutput 'receipt.json'
$sourceSha = 'a' * 64
$checks = [Collections.Generic.List[object]]::new()
function Assert-ReceiptCase([string]$Name, $Receipt, [string]$ExpectedSha, [bool]$ExpectedValid, [string]$ExpectedReason = '') {
    $Receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixturePath -Encoding utf8
    $result = Test-FrameworkReceipt -Path $fixturePath -ExpectedRunId 'owned-run' -ExpectedSceneId 'owned_scene' -ExpectedContentSha256 $ExpectedSha
    $ok = $result.valid -eq $ExpectedValid -and (-not $ExpectedReason -or $result.reasons -contains $ExpectedReason)
    $checks.Add([ordered]@{ name = $Name; passed = $ok; actual_valid = $result.valid; actual_reasons = @($result.reasons); expected_valid = $ExpectedValid; expected_reason = $ExpectedReason })
    if (-not $ok) { throw "SOURCE_BINDING_CASE_FAIL: $Name" }
}
function New-ValidReceipt {
    return [ordered]@{ schema_version = 1; run_id = 'owned-run'; scene_id = 'owned_scene'; source_content_sha256 = $sourceSha;
        count = 1; passed = 1; failed = 0; reported_checks = 1; reported_failures = 0; status = 'PASS';
        checks = @([ordered]@{ id = 1; passed = $true; label = 'Actual component check' }) }
}
try {
    Assert-ReceiptCase 'valid-bound-source' (New-ValidReceipt) $sourceSha $true
    Assert-ReceiptCase 'missing-expected-source' (New-ValidReceipt) '' $false 'framework_expected_source_unbound'
    Assert-ReceiptCase 'malformed-expected-source' (New-ValidReceipt) 'unbound' $false 'framework_expected_source_unbound'
    $receipt = New-ValidReceipt; $receipt.Remove('source_content_sha256')
    Assert-ReceiptCase 'missing-receipt-source' $receipt $sourceSha $false 'framework_receipt_source_unbound'
    $receipt = New-ValidReceipt; $receipt.source_content_sha256 = 'missing:source'
    Assert-ReceiptCase 'malformed-receipt-source' $receipt $sourceSha $false 'framework_receipt_source_unbound'
    $receipt = New-ValidReceipt; $receipt.source_content_sha256 = 'b' * 64
    Assert-ReceiptCase 'mismatched-source' $receipt $sourceSha $false 'framework_receipt_wrong_source'
    $receipt = New-ValidReceipt; $receipt.checks[0].passed = $false
    Assert-ReceiptCase 'bound-source-does-not-hide-failed-check' $receipt $sourceSha $false 'framework_checks_failed'
    $receipt = New-ValidReceipt; $receipt.run_id = 'foreign-run'
    Assert-ReceiptCase 'bound-source-does-not-hide-wrong-run' $receipt $sourceSha $false 'framework_receipt_wrong_run'
    $receipt = New-ValidReceipt; $receipt.scene_id = 'foreign_scene'
    Assert-ReceiptCase 'bound-source-does-not-hide-wrong-scene' $receipt $sourceSha $false 'framework_receipt_wrong_scene'
} finally {
    [ordered]@{ scope = 'Actual Test-FrameworkReceipt, no native run'; checks = $checks.ToArray();
        source_sha256 = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'tools/test_framework_receipt.ps1')).Hash;
        test_sha256 = (Get-FileHash -LiteralPath $PSCommandPath).Hash;
        godot = 'NOT_RUN'; device = 'NOT_RUN' } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fullOutput 'receipt_source_binding.result.json') -Encoding utf8
}
Write-Output "FRAMEWORK_RECEIPT_SOURCE_BINDING_PASS checks=$($checks.Count) output=$fullOutput"
