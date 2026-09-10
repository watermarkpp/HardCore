param()
# Alternating REV07 full-frame collection: v72 baseline vs M30-R4 candidate.
$ErrorActionPreference = 'Stop'
$b64 = 'C:\Users\Administrator\Documents\HardCore-worktrees\m30r4-v72-baseline'
$cand = 'C:\Users\Administrator\Documents\HardCore-worktrees\m30-r4-flash'
$head64 = '909821c928ddb66e5fd48f7cef718baa2e8bfe03'
$headCand = '6116e85b04288f6d2612b2d7f9b7b58ee3e239cf'
$runs = @(
    @{ tree = $b64;  label = 'v72_r1';  head = $head64 },
    @{ tree = $cand; label = 'cand_r1'; head = $headCand },
    @{ tree = $b64;  label = 'v72_r2';  head = $head64 },
    @{ tree = $cand; label = 'cand_r2'; head = $headCand },
    @{ tree = $b64;  label = 'v72_r3';  head = $head64 },
    @{ tree = $cand; label = 'cand_r3'; head = $headCand },
    @{ tree = $b64;  label = 'v72_r4';  head = $head64 },
    @{ tree = $cand; label = 'cand_r4'; head = $headCand }
)
foreach ($run in $runs) {
    $env:HARDCORE_REV07_HEAD = $run.head
    $env:HARDCORE_REV07_LABEL = $run.label
    Write-Output "=== RUN label=$($run.label) tree=$($run.tree) ==="
    Set-Location $run.tree
    & .\tools\run_godot_tests.ps1 -TimeoutSeconds 60 -TestPaths @('tests/hc_monster_ai/performance_comparison_test.tscn') 2>&1 |
        Tee-Object -FilePath (Join-Path $run.tree "outputs\m30r4_evidence\rev07_run_$($run.label).log") |
        Select-String -Pattern 'HC_REV07_FULL_FRAME_PASS|\[(PASS|FAIL)\]|TEST_SUMMARY' | ForEach-Object { $_.Line }
    Write-Output "RUN_EXIT label=$($run.label) exit=$LASTEXITCODE"
}
Write-Output 'REV07_ALTERNATING_COLLECTION_DONE'
