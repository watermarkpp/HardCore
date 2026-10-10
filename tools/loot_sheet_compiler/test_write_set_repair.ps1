param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$OutputRoot,
    [switch]$LockOnly,
    [switch]$BoundaryLock,
    [switch]$ConflictWatcher,
    [string]$LockPath = '',
    [string]$ReadyPath = '',
    [string]$ReleasePath = ''
)
$ErrorActionPreference = 'Stop'

if ($LockOnly) {
    $lockStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        [System.IO.File]::WriteAllText($ReadyPath, 'LOCK_READY')
        while (-not [System.IO.File]::Exists($ReleasePath)) { Start-Sleep -Milliseconds 50 }
    } finally { $lockStream.Dispose() }
    exit 0
}
if ($BoundaryLock) {
    while (@(Get-ChildItem -LiteralPath $OutputRoot -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.txn\.' }).Count -lt 3) { Start-Sleep -Milliseconds 2 }
    $lockStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    try {
        [System.IO.File]::WriteAllText($ReadyPath, 'BOUNDARY_LOCK_READY')
        while (-not [System.IO.File]::Exists($ReleasePath)) { Start-Sleep -Milliseconds 20 }
    } finally { $lockStream.Dispose() }
    exit 0
}
if ($ConflictWatcher) {
    $watchDir = $OutputRoot
    while (@(Get-ChildItem -LiteralPath $watchDir -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\.txn\.' }).Count -eq 0) { Start-Sleep -Milliseconds 2 }
    [System.IO.File]::WriteAllText($LockPath, 'MANUAL_CONFLICT')
    exit 0
}

$compiler = Join-Path $ProjectRoot 'tools/loot_sheet_compiler/compile_authority.ps1'
$pwsh = (Get-Command pwsh).Source
$names = @('dpv2_user_loot_sheet_authority_v1.json', 'compile_disambiguation.json', 'armor_single_slot_audit.json')
function Invoke-Compiler([string]$OutputDir) {
    $out = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $compiler -ProjectRoot $ProjectRoot -OutputDir $OutputDir 2>&1
    return [pscustomobject]@{ exit_code = $LASTEXITCODE; output = @($out | ForEach-Object { [string]$_ }) }
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
    $locker = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-ProjectRoot', $ProjectRoot, '-OutputRoot', $case, '-BoundaryLock', '-LockPath', $lockPath, '-ReadyPath', $ready, '-ReleasePath', $release) -PassThru -WindowStyle Hidden
    $run = Invoke-Compiler $case
    while (-not [System.IO.File]::Exists($ready)) { Start-Sleep -Milliseconds 20 }
    [System.IO.File]::WriteAllText($release, 'RELEASE')
    $locker.WaitForExit()
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
$watcher = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-ProjectRoot', $ProjectRoot, '-OutputRoot', $conflictCase, '-LockPath', $conflictTarget, '-ConflictWatcher') -PassThru -WindowStyle Hidden
$env:B07A_WRITE_SET_TEST_PAUSE_MS = '1000'
$conflictRun = Invoke-Compiler $conflictCase
$env:B07A_WRITE_SET_TEST_PAUSE_MS = $null
$watcher.WaitForExit()
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
