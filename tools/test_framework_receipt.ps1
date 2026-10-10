function Test-FrameworkReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedSceneId,
        [string]$ExpectedContentSha256 = ''
    )
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ valid = $false; reasons = @('framework_receipt_missing') }
    }
    if ((Get-Item -LiteralPath $Path).Length -gt 4MB) {
        return [pscustomobject]@{ valid = $false; reasons = @('framework_receipt_size_limit') }
    }
    try {
        $receipt = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ valid = $false; reasons = @('framework_receipt_invalid_json') }
    }
    foreach ($field in @('schema_version', 'count', 'passed', 'failed', 'reported_checks', 'reported_failures')) {
        $value = $receipt.$field
        if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 0) {
            $reasons.Add('framework_receipt_numeric_type')
        }
    }
    if ($receipt.schema_version -ne 1 -or $receipt.checks -isnot [array]) {
        $reasons.Add('framework_receipt_schema')
    }
    if ($receipt.run_id -cne $ExpectedRunId -or [string]::IsNullOrEmpty($ExpectedRunId)) {
        $reasons.Add('framework_receipt_wrong_run')
    }
    if ($receipt.scene_id -cne $ExpectedSceneId) { $reasons.Add('framework_receipt_wrong_scene') }
    # An empty expected hash is an evidence gap, never an opt-out from source
    # binding. Component callers can retain the reason without running Godot.
    if ($ExpectedContentSha256 -cnotmatch '^[a-f0-9]{64}$') {
        $reasons.Add('framework_expected_source_unbound')
    }
    if ($receipt.source_content_sha256 -isnot [string] -or
        $receipt.source_content_sha256 -cnotmatch '^[a-f0-9]{64}$') {
        $reasons.Add('framework_receipt_source_unbound')
    }
    if ($receipt.source_content_sha256 -cne $ExpectedContentSha256) {
        $reasons.Add('framework_receipt_wrong_source')
    }
    $checks = @($receipt.checks)
    if ($checks.Count -eq 0 -or $receipt.count -le 0) { $reasons.Add('framework_zero_checks') }
    if ($checks.Count -gt 100000) { $reasons.Add('framework_check_count_limit') }
    $passed = 0
    $failed = 0
    $index = 0
    foreach ($check in $checks) {
        $index += 1
        if (($check.id -isnot [int] -and $check.id -isnot [long]) -or $check.id -ne $index -or
            $check.passed -isnot [bool] -or $check.label -isnot [string] -or
            [string]::IsNullOrEmpty($check.label)) {
            $reasons.Add('framework_check_record_invalid')
            break
        }
        if ($check.passed) { $passed += 1 } else { $failed += 1 }
    }
    if ($receipt.count -ne $checks.Count -or $receipt.passed -ne $passed -or $receipt.failed -ne $failed -or
        $receipt.reported_checks -ne $checks.Count -or $receipt.reported_failures -ne $failed) {
        $reasons.Add('framework_check_counts_mismatch')
    }
    if ($failed -gt 0 -or $receipt.status -cne 'PASS') { $reasons.Add('framework_checks_failed') }
    return [pscustomobject]@{ valid = $reasons.Count -eq 0; reasons = $reasons.ToArray() }
}
