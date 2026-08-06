param(
    [int]$FixtureTimeoutSeconds = 3
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $PSScriptRoot 'run_godot_tests.ps1'
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'

$Cases = @(
    @{ name = 'case1_pass'; path = 'tests/runner_fixtures/case1_pass.tscn'; expect = 'PASS'; reason_token = '' },
    @{ name = 'case2_pass_then_assert'; path = 'tests/runner_fixtures/case2_pass_then_assert.tscn'; expect = 'FAIL'; reason_token = 'early_script_error' },
    @{ name = 'case3_pass_then_nonzero_exit'; path = 'tests/runner_fixtures/case3_pass_then_nonzero_exit.tscn'; expect = 'FAIL'; reason_token = 'non_zero_exit_code' },
    @{ name = 'case4_pass_then_hang'; path = 'tests/runner_fixtures/case4_pass_then_hang.tscn'; expect = 'FAIL'; reason_token = 'timeout' },
    @{ name = 'case5_no_pass_exit_zero'; path = 'tests/runner_fixtures/case5_no_pass_exit_zero.tscn'; expect = 'FAIL'; reason_token = 'missing_pass_marker' },
    @{ name = 'case6_engine_log_fatal'; path = 'tests/runner_fixtures/case6_engine_log_fatal.tscn'; expect = 'FAIL'; reason_token = 'engine_log_failures' },
    @{ name = 'case7_parse_error'; path = 'tests/runner_fixtures/case7_parse_error.tscn'; expect = 'FAIL'; reason_token = 'early_script_error' },
    @{ name = 'runner_engine_log_safe_logout_error_fixture'; path = 'tests/runner_fixtures/runner_engine_log_safe_logout_error_fixture.tscn'; expect = 'FAIL'; reason_token = 'engine_log_failures' }
)

function Get-NewestResultsJson {
    return Get-ChildItem -LiteralPath $LogRoot -Filter 'runner_results_*.json' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

$failures = @()
foreach ($case in $Cases) {
    & $Runner -TestPaths @($case.path) -TimeoutSeconds $FixtureTimeoutSeconds *> $null
    $code = $LASTEXITCODE
    $expectFail = ($case.expect -eq 'FAIL')
    $runnerPassed = ($code -eq 0)
    if (($expectFail -and $runnerPassed) -or (-not $expectFail -and -not $runnerPassed)) {
        $failures += "case $($case.name): expected $($case.expect) but runner exit=$code"
        continue
    }
    if ($case.reason_token -ne '') {
        $resultsFile = Get-NewestResultsJson
        $tokenFound = $false
        if ($null -ne $resultsFile) {
            $json = Get-Content -LiteralPath $resultsFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in $json.results) {
                if ($entry.test_name -eq $case.name) {
                    if ($entry.reason -match [regex]::Escape($case.reason_token)) {
                        $tokenFound = $true
                    }
                    break
                }
            }
        }
        if (-not $tokenFound) {
            $failures += "case $($case.name): reason token '$($case.reason_token)' missing in structured results"
        }
    }
}

Start-Sleep -Milliseconds 500
$leftover = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' })
if ($leftover.Count -gt 0) {
    $failures += "leftover Godot processes after self-test: $($leftover.Count)"
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "SELF_TEST_FAIL: $failure" -ForegroundColor Red
    }
    Write-Host "RUNNER_SELF_TEST_SUMMARY passed=0 failed=$($failures.Count)"
    exit 1
}
Write-Host "RUNNER_SELF_TEST_SUMMARY passed=$($Cases.Count) failed=0"
Write-Host "RUNNER_SELF_TEST_PASS"
exit 0
