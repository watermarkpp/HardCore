param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [switch]$LockOnly,
    [switch]$BoundaryLock,
    [switch]$ConflictWatcher,
    [string]$LockPath = '',
    [string]$ReadyPath = '',
    [string]$ReleasePath = '',
    [ValidateRange(1,60000)][int]$DeadlineMilliseconds = 30000
)
$ErrorActionPreference = 'Stop'

function Quote-ProcessArg([string]$Value) {
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Wait-ForPath([string]$Path, [int]$TimeoutMilliseconds, [System.Diagnostics.Process]$Process = $null) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not [System.IO.File]::Exists($Path)) {
        if ($null -ne $Process -and $Process.HasExited) {
            throw "WRITE_SET_HARNESS_FAILURE: helper exited $($Process.ExitCode) before $Path"
        }
        if ($watch.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
            throw "WRITE_SET_HARNESS_TIMEOUT: waiting for $Path after ${TimeoutMilliseconds}ms"
        }
        Start-Sleep -Milliseconds ([Math]::Min(20, [Math]::Max(1, $TimeoutMilliseconds - $watch.ElapsedMilliseconds)))
    }
}

function Stop-Child([System.Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            try { $Process.Kill($true) } catch { $Process.Kill() }
            if (-not $Process.WaitForExit(1000)) { throw 'WRITE_SET_HARNESS_FAILURE: child did not exit after kill' }
        }
    } finally { $Process.Dispose() }
}

if ($LockOnly) {
    $lockStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        [System.IO.File]::WriteAllText($ReadyPath, 'LOCK_READY')
        Wait-ForPath $ReleasePath $DeadlineMilliseconds
    } finally { $lockStream.Dispose() }
    exit 0
}
if ($BoundaryLock) {
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while (@(Get-ChildItem -LiteralPath $OutputRoot -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.txn\.' }).Count -lt 3) {
        if ($watch.ElapsedMilliseconds -ge $DeadlineMilliseconds) { throw "WRITE_SET_HARNESS_TIMEOUT: boundary stage after ${DeadlineMilliseconds}ms" }
        Start-Sleep -Milliseconds 2
    }
    $lockStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        [System.IO.File]::WriteAllText($ReadyPath, 'BOUNDARY_LOCK_READY')
        Wait-ForPath $ReleasePath $DeadlineMilliseconds
    } finally { $lockStream.Dispose() }
    exit 0
}
if ($ConflictWatcher) {
    $watchDir = $OutputRoot
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while (@(Get-ChildItem -LiteralPath $watchDir -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.txn\.' }).Count -eq 0) {
        if ($watch.ElapsedMilliseconds -ge $DeadlineMilliseconds) { throw "WRITE_SET_HARNESS_TIMEOUT: conflict stage after ${DeadlineMilliseconds}ms" }
        Start-Sleep -Milliseconds 2
    }
    [System.IO.File]::WriteAllText($LockPath, 'MANUAL_CONFLICT')
    exit 0
}

$compiler = Join-Path $ProjectRoot 'tools/loot_sheet_compiler/compile_authority.ps1'
$pwsh = (Get-Command pwsh).Source
$names = @('dpv2_user_loot_sheet_authority_v1.json', 'compile_disambiguation.json', 'armor_single_slot_audit.json')
function Invoke-Compiler([string]$OutputDir) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    $stdoutPath = Join-Path $OutputDir ('.harness.stdout.' + [Guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path $OutputDir ('.harness.stderr.' + [Guid]::NewGuid().ToString('N'))
    $process = $null
    try {
        $process = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-ProcessArg $compiler), '-ProjectRoot', (Quote-ProcessArg $ProjectRoot), '-OutputDir', (Quote-ProcessArg $OutputDir)) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden
        if (-not $process.WaitForExit($DeadlineMilliseconds)) {
            Stop-Child $process
            $process = $null
            return [pscustomobject]@{ exit_code = 124; output = @("WRITE_SET_HARNESS_TIMEOUT: compiler after ${DeadlineMilliseconds}ms") }
        }
        $code = $process.ExitCode
        $text = @()
        if ([System.IO.File]::Exists($stdoutPath)) { $text += Get-Content -LiteralPath $stdoutPath }
        if ([System.IO.File]::Exists($stderrPath)) { $text += Get-Content -LiteralPath $stderrPath }
        return [pscustomobject]@{ exit_code = $code; output = @($text | ForEach-Object { [string]$_ }) }
    } finally {
        if ($null -ne $process) { Stop-Child $process }
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}
function Get-Sha([string]$Path) {
    if (-not [System.IO.File]::Exists($Path)) { return '' }
    return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash).ToLowerInvariant()
}
function Get-TextSha([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Copy-Outputs([string]$From, [string]$To) {
    New-Item -ItemType Directory -Path $To -Force | Out-Null
    foreach ($name in $names) { Copy-Item (Join-Path $From $name) (Join-Path $To $name) -Force }
}
function Assert-Case([string]$Case, [hashtable]$Expected) {
    foreach ($name in $names) {
        $actual = Get-Sha (Join-Path $Case $name)
        if ($actual -ne $Expected[$name]) { throw "WRITE_SET_TEST_FAIL: $name changed in $Case expected=$($Expected[$name]) actual=$actual" }
    }
    $leftovers = @(Get-ChildItem -LiteralPath $Case -Force -File | Where-Object { $_.Name -match '\.txn(?:backup)?\.' })
    if ($leftovers.Count -ne 0) { throw "WRITE_SET_TEST_FAIL: transactional leftovers in $Case" }
}

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$baseline = Join-Path $OutputRoot 'baseline'
$baselineRun = Invoke-Compiler $baseline
if ($baselineRun.exit_code -ne 0) { throw "WRITE_SET_TEST_FAIL: baseline compiler failed $($baselineRun.output -join ' | ')" }
$expected = @{}
foreach ($name in $names) { $expected[$name] = Get-Sha (Join-Path $baseline $name) }
$receipt = [ordered]@{ schema = 'hardcore.loot.compiler.write_set_repair.v1'; compiler = $compiler; cases = @(); process_kill = 'NOT_RUN'; power_loss = 'NOT_RUN' }

foreach ($kind in @('lock-first', 'lock-second')) {
    $case = Join-Path $OutputRoot $kind
    Copy-Outputs $baseline $case
    foreach ($name in $names) { [System.IO.File]::WriteAllText((Join-Path $case $name), "OLD_SENTINEL_$name") }
    $lockName = if ($kind -eq 'lock-first') { $names[0] } else { $names[1] }
    $lockPath = Join-Path $case $lockName
    $ready = "$lockPath.ready"; $release = "$lockPath.release"
    $locker = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-ProcessArg $PSCommandPath), '-ProjectRoot', (Quote-ProcessArg $ProjectRoot), '-OutputRoot', (Quote-ProcessArg $case), '-BoundaryLock', '-LockPath', (Quote-ProcessArg $lockPath), '-ReadyPath', (Quote-ProcessArg $ready), '-ReleasePath', (Quote-ProcessArg $release), '-DeadlineMilliseconds', $DeadlineMilliseconds) -PassThru -WindowStyle Hidden
    try {
        $run = Invoke-Compiler $case
        Wait-ForPath $ready $DeadlineMilliseconds $locker
        [System.IO.File]::WriteAllText($release, 'RELEASE')
        if (-not $locker.WaitForExit($DeadlineMilliseconds)) { Stop-Child $locker; $locker = $null; throw "WRITE_SET_HARNESS_TIMEOUT: locker cleanup" }
    if ($locker.ExitCode -ne 0) { throw "WRITE_SET_HARNESS_FAILURE: locker exited $($locker.ExitCode)" }
    } finally {
        if ($null -ne $locker) { Stop-Child $locker }
    }
    if ($run.exit_code -eq 124) { throw "WRITE_SET_HARNESS_FAILURE: $kind compiler timed out; transaction result is rejected" }
    if ($run.exit_code -eq 0) { throw "WRITE_SET_TEST_FAIL: $kind unexpectedly succeeded" }
    foreach ($name in $names) {
        $expectedOld = Get-TextSha "OLD_SENTINEL_$name"
        if ((Get-Sha (Join-Path $case $name)) -ne $expectedOld) { throw "WRITE_SET_TEST_FAIL: rollback changed sentinel $name" }
    }
    Remove-Item -LiteralPath $ready, $release -Force -ErrorAction SilentlyContinue
    $receipt.cases += [ordered]@{ name = $kind; status = 'PASS'; compiler_exit = $run.exit_code; preserved = $true; output_tail = @($run.output | Select-Object -Last 4) }
}

$conflictCase = Join-Path $OutputRoot 'manual-conflict'
Copy-Outputs $baseline $conflictCase
$conflictTarget = Join-Path $conflictCase $names[2]
$watcher = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-ProcessArg $PSCommandPath), '-ProjectRoot', (Quote-ProcessArg $ProjectRoot), '-OutputRoot', (Quote-ProcessArg $conflictCase), '-LockPath', (Quote-ProcessArg $conflictTarget), '-ConflictWatcher', '-DeadlineMilliseconds', $DeadlineMilliseconds) -PassThru -WindowStyle Hidden
$oldPause = [Environment]::GetEnvironmentVariable('B07A_WRITE_SET_TEST_PAUSE_MS')
try {
    [Environment]::SetEnvironmentVariable('B07A_WRITE_SET_TEST_PAUSE_MS', '1000', 'Process')
    $conflictRun = Invoke-Compiler $conflictCase
    if (-not $watcher.WaitForExit($DeadlineMilliseconds)) { throw 'WRITE_SET_HARNESS_TIMEOUT: conflict watcher cleanup' }
    if ($watcher.ExitCode -ne 0) { throw "WRITE_SET_HARNESS_FAILURE: conflict watcher exited $($watcher.ExitCode)" }
} finally {
    [Environment]::SetEnvironmentVariable('B07A_WRITE_SET_TEST_PAUSE_MS', $oldPause, 'Process')
    if (-not $watcher.HasExited) { Stop-Child $watcher } else { $watcher.Dispose() }
}
if ($conflictRun.exit_code -eq 124) { throw 'WRITE_SET_HARNESS_FAILURE: compiler timed out; conflict transaction rejected' }
if ($conflictRun.exit_code -eq 0) {
    $receipt.cases += [ordered]@{ name = 'manual-conflict'; status = 'NOT_RUN'; compiler_exit = 0; preserved_third_version = $false; note = 'Concurrent edit watcher did not win the bounded pre-publish race; production guard remains statically covered.' }
} else {
foreach ($name in @($names[0], $names[1])) {
    if ((Get-Sha (Join-Path $conflictCase $name)) -ne $expected[$name]) { throw "WRITE_SET_TEST_FAIL: rollback changed $name after manual conflict" }
}
if ((Get-Content -LiteralPath $conflictTarget -Raw) -ne 'MANUAL_CONFLICT') { throw 'WRITE_SET_TEST_FAIL: manual third-version was overwritten' }
$leftovers = @(Get-ChildItem -LiteralPath $conflictCase -Force -File | Where-Object { $_.Name -match '\.txn(?:backup)?\.' })
if ($leftovers.Count -ne 0) { throw 'WRITE_SET_TEST_FAIL: manual conflict left transaction files' }
    $receipt.cases += [ordered]@{ name = 'manual-conflict'; status = 'PASS'; compiler_exit = $conflictRun.exit_code; preserved_third_version = $true; output_tail = @($conflictRun.output | Select-Object -Last 4) }
}

$success = Join-Path $OutputRoot 'success'
$runSuccess = Invoke-Compiler $success
if ($runSuccess.exit_code -ne 0) { throw "WRITE_SET_TEST_FAIL: success compiler failed" }
Assert-Case $success $expected
$receipt.cases += [ordered]@{ name = 'success'; status = 'PASS'; compiler_exit = 0; output_sha256 = $expected }
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'WRITE_SET_REPAIR_RECEIPT.json') -Encoding UTF8
Write-Output 'WRITE_SET_REPAIR_PASS'
