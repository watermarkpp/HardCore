$ErrorActionPreference = 'Stop'

$NativeEngineErrorAllowlist = @(
    [ordered]@{ id = 'string_formatting'; pattern = '^ERROR: String formatting error: not all arguments converted during string formatting\.' },
    [ordered]@{ id = 'resources_in_use'; pattern = '^ERROR: \d+ resources still in use at exit' },
    [ordered]@{ id = 'rid_leak'; pattern = '^ERROR: \d+ RID allocations? of type ''PN\d+RendererDummy\d+TextureStorage\d+DummyTextureE'' were leaked at exit\.' },
    [ordered]@{ id = 'null_parameter'; pattern = '^ERROR: Parameter "t" is null\.' }
)

function Read-NativeEvidenceText([string[]]$Paths) {
    $parts = [Collections.Generic.List[string]]::new()
    foreach ($path in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $parts.Add((Get-Content -LiteralPath $path -Raw -Encoding UTF8))
    }
    return ($parts -join "`n")
}

function Get-NativeLogEvidence {
    param(
        [Parameter(Mandatory = $true)][string[]]$RawLogPaths,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$ExpectedSceneId,
        [Parameter(Mandatory = $true)][string]$ExpectedInvocationId
    )
    $text = Read-NativeEvidenceText $RawLogPaths
    $lines = @($text -split "`r?`n" | Where-Object { $_ -ne '' })
    $categories = [ordered]@{}
    $allowlisted = [Collections.Generic.HashSet[int]]::new()
    foreach ($entry in $NativeEngineErrorAllowlist) {
        $matched = [Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $entry.pattern) { $matched.Add($lines[$i]); $allowlisted.Add($i) | Out-Null }
        }
        $categories[$entry.id] = [ordered]@{ count = $matched.Count; lines = @($matched) }
    }
    $unknown = [Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^ERROR:' -and -not $allowlisted.Contains($i)) { $unknown.Add($lines[$i]) }
    }
    $objectDb = @($lines | Where-Object { $_ -match 'Leaked instance: ObjectDB:' -or $_ -match 'ObjectDB.*[Ll]eaked instance' -or $_ -match 'ObjectDB instances leaked at exit' })
    $functionalMarker = @($lines | Where-Object { $_ -match '[A-Z0-9_]+_PASS(?:\b|\s)' }).Count -gt 0
    $receipt = $null
    $receiptReasons = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) {
        $receiptReasons.Add('framework_receipt_missing')
    } else {
        try { $receipt = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
        catch { $receiptReasons.Add('framework_receipt_invalid_json') }
    }
    if ($null -ne $receipt) {
        if ($receipt.scene_id -cne $ExpectedSceneId) { $receiptReasons.Add('framework_receipt_wrong_scene') }
        if ($receipt.invocation_id -cne $ExpectedInvocationId) { $receiptReasons.Add('framework_receipt_wrong_invocation') }
        $checks = @($receipt.checks)
        if ([int]$receipt.count -le 0 -or $checks.Count -le 0 -or [int]$receipt.count -ne $checks.Count) { $receiptReasons.Add('framework_receipt_nonzero_checks_missing') }
        if ($receipt.status -cne 'PASS' -or [int]$receipt.failed -ne 0) { $receiptReasons.Add('framework_receipt_not_pass') }
    }
    # This log classifier cannot attest to source binding, native exit, or
    # per-check validity. Only the upstream runner owns formal admission.
    $formalStatus = 'MISSING'
    $formalReason = if ($receiptReasons.Count -eq 0) { 'upstream_native_and_full_receipt_validation_required' } else { 'legacy_run_bound_checks_missing' }
    [ordered]@{
        status = if ($unknown.Count -eq 0) { 'PASS' } else { 'FAIL' }
        allowlisted_errors = $categories
        unknown_error_lines = @($unknown)
        unknown_error_count = $unknown.Count
        objectdb_leak_warning_lines = @($objectDb)
        objectdb_leak_warning_count = $objectDb.Count
        functional_marker_observed = $functionalMarker
        formal_evidence_status = $formalStatus
        formal_evidence_reason = $formalReason
        receipt_validation_reasons = @($receiptReasons)
        candidate_receipt_correlation = $receiptReasons.Count -eq 0
        upstream_result = 'NOT_RUN'
        raw_log_paths = @($RawLogPaths)
        receipt_path = $ReceiptPath
        expected_scene_id = $ExpectedSceneId
        expected_invocation_id = $ExpectedInvocationId
    }
}
