param(
    [int]$FixtureTimeoutSeconds = 3
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Runner = Join-Path $PSScriptRoot 'run_godot_tests.ps1'
$LogRoot = Join-Path $ProjectRoot 'outputs\test_logs'
$PowerShellExe = (Get-Process -Id $PID).Path

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

function Invoke-RunnerChild([string[]]$Arguments) {
    $commandArguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $Runner
    ) + $Arguments
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $PowerShellExe @commandArguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return [ordered]@{
        exit_code = $exitCode
        output = $output
    }
}

function Get-ResultsPath([string]$Output) {
    $match = [regex]::Match($Output, '(?m)^RUNNER_RESULTS_JSON=(.+?)\r?$')
    if (-not $match.Success) {
        return $null
    }
    return $match.Groups[1].Value.Trim()
}

function Assert-Rejected(
    [string]$Name,
    [string[]]$Arguments,
    [System.Collections.Generic.List[string]]$Failures
) {
    $invocation = Invoke-RunnerChild -Arguments $Arguments
    if ($invocation.exit_code -eq 0) {
        $Failures.Add("$Name`: runner unexpectedly accepted invalid arguments")
    }
    if ($invocation.output -match 'RUNNER_RESULTS_JSON=') {
        $Failures.Add("$Name`: rejected invocation still produced a results artifact")
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
$criticalBefore = @(
    Get-ChildItem -LiteralPath $LogRoot -Filter 'runner_results_critical_*.json' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
)
foreach ($case in $Cases) {
    $invocation = Invoke-RunnerChild -Arguments @(
        '-TestPaths', $case.path,
        '-TimeoutSeconds', [string]$FixtureTimeoutSeconds
    )
    $code = $invocation.exit_code
    $expectFail = ($case.expect -eq 'FAIL')
    $runnerPassed = ($code -eq 0)
    if (($expectFail -and $runnerPassed) -or (-not $expectFail -and -not $runnerPassed)) {
        $failures.Add("case $($case.name): expected $($case.expect) but runner exit=$code")
        continue
    }
    if ($invocation.output -notmatch 'TEST_SUMMARY suite=adhoc') {
        $failures.Add("case $($case.name): console summary did not use adhoc suite identity")
    }
    $resultsPath = Get-ResultsPath -Output $invocation.output
    if ([string]::IsNullOrWhiteSpace($resultsPath) -or -not (Test-Path -LiteralPath $resultsPath)) {
        $failures.Add("case $($case.name): adhoc results artifact missing")
        continue
    }
    if ([IO.Path]::GetFileName($resultsPath) -notlike 'runner_results_adhoc_*.json') {
        $failures.Add("case $($case.name): results filename did not use adhoc identity: $resultsPath")
    }
    $json = Get-Content -LiteralPath $resultsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($json.suite -ne 'adhoc') {
        $failures.Add("case $($case.name): JSON suite was '$($json.suite)' instead of adhoc")
    }
    if ($case.reason_token -ne '') {
        $tokenFound = $false
        foreach ($entry in $json.results) {
            if ($entry.test_name -eq $case.name) {
                if ($entry.reason -match [regex]::Escape($case.reason_token)) {
                    $tokenFound = $true
                }
                break
            }
        }
        if (-not $tokenFound) {
            $failures.Add("case $($case.name): reason token '$($case.reason_token)' missing in structured results")
        }
    }
}

# Adhoc paths cannot claim formal suite identity.
Assert-Rejected -Name 'testpaths_with_explicit_suite' -Arguments @(
    '-TestPaths', 'tests/runner_fixtures/case1_pass.tscn',
    '-Suite', 'critical',
    '-TimeoutSeconds', [string]$FixtureTimeoutSeconds
) -Failures $failures

# Timeout policy is enforced before Godot starts.
Assert-Rejected -Name 'timeout_above_maximum' -Arguments @(
    '-TimeoutSeconds', '61'
) -Failures $failures
Assert-Rejected -Name 'timeout_zero' -Arguments @(
    '-TimeoutSeconds', '0'
) -Failures $failures

# Adhoc paths must remain tracked test scenes inside the project tests/ tree.
Assert-Rejected -Name 'testpath_outside_tests' -Arguments @(
    '-TestPaths', 'scenes/main.tscn',
    '-TimeoutSeconds', [string]$FixtureTimeoutSeconds
) -Failures $failures

$criticalAfter = @(
    Get-ChildItem -LiteralPath $LogRoot -Filter 'runner_results_critical_*.json' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
)
$newCriticalArtifacts = @(
    Compare-Object -ReferenceObject $criticalBefore -DifferenceObject $criticalAfter |
        Where-Object SideIndicator -eq '=>' |
        Select-Object -ExpandProperty InputObject
)
if ($newCriticalArtifacts.Count -gt 0) {
    $failures.Add("adhoc fixture runs created critical artifacts: $($newCriticalArtifacts -join ', ')")
}

Start-Sleep -Milliseconds 500
$leftover = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Godot*' })
if ($leftover.Count -gt 0) {
    $failures.Add("leftover Godot processes after self-test: $($leftover.Count)")
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
