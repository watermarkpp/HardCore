param(
    [Parameter(Mandatory = $true)][string]$CompilerPath,
    [Parameter(Mandatory = $true)][string]$FixtureOutput,
    [Parameter(Mandatory = $true)][string]$OutputRoot
)
$ErrorActionPreference = 'Stop'
$names = @('dpv2_user_loot_sheet_authority_v1.json', 'compile_disambiguation.json', 'armor_single_slot_audit.json')
function Get-Sha([string]$Path) { if (-not [IO.File]::Exists($Path)) { return '' }; return ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash).ToLowerInvariant() }
function Seed-Case([string]$Path, [bool]$FirstMissing) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    foreach ($name in $names) {
        $target = Join-Path $Path $name
        if ($FirstMissing -and $name -eq $names[0]) { continue }
        [IO.File]::WriteAllText($target, "OLD_SENTINEL|$([IO.Path]::GetFileNameWithoutExtension($name))")
    }
}
function Get-OldSha([string]$Name) { return (([System.Security.Cryptography.SHA256]::Create()).ComputeHash([Text.Encoding]::UTF8.GetBytes("OLD_SENTINEL|$([IO.Path]::GetFileNameWithoutExtension($Name))")) | ForEach-Object { $_.ToString('x2') }) -join '' }

$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($CompilerPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw "FAULT_TEST_PARSE_FAIL: $($parseErrors -join '; ')" }
$functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
foreach ($function in $functions) { . ([scriptblock]::Create($function.Extent.Text)) }
$entries = foreach ($name in $names) {
    $text = Get-Content -LiteralPath (Join-Path $FixtureOutput $name) -Raw -Encoding UTF8
    $value = $text | ConvertFrom-Json
    [pscustomobject]@{ name = $name; text = $text; schema = if ($name -eq $names[0]) { [string]$value.schema } else { '' } }
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$receipt = [ordered]@{ schema = 'hardcore.loot.compiler.write_set_fault_injection.v1'; compiler_sha256 = (Get-Sha $CompilerPath); fixture = $FixtureOutput; cases = @(); process_kill = 'NOT_RUN'; power_loss = 'NOT_RUN' }

function Invoke-FaultCase([string]$Name, [bool]$FirstMissing, [string]$Fault) {
    $case = Join-Path $OutputRoot $Name
    Seed-Case $case $FirstMissing
    $script:moveCount = 0
    function Move-WriteSetFile([string]$Source, [string]$Destination, [bool]$Overwrite) {
        $script:moveCount++
        if ($Fault -eq 'second-failure' -and $script:moveCount -eq 2) { throw 'INJECTED_SECOND_PUBLICATION_FAILURE' }
        if ($Fault -eq 'manual-third' -and $script:moveCount -eq 2) {
            [IO.File]::WriteAllText((Join-Path $case $names[2]), 'MANUAL_THIRD_VERSION')
            throw 'INJECTED_SECOND_PUBLICATION_FAILURE_AFTER_MANUAL_EDIT'
        }
        if ($Fault -eq 'second-and-rollback' -and $script:moveCount -in @(2, 3)) { throw "INJECTED_MOVE_FAILURE_$($script:moveCount)" }
        if ($Overwrite) { [IO.File]::Move($Source, $Destination, $true) } else { [IO.File]::Move($Source, $Destination) }
    }
    $failed = $false
    try { Publish-ValidatedWriteSet $case $entries | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw "FAULT_TEST_FAIL: $Name unexpectedly succeeded" }
    if ($Fault -eq 'manual-third') {
        if ((Get-Content -LiteralPath (Join-Path $case $names[2]) -Raw) -ne 'MANUAL_THIRD_VERSION') { throw 'FAULT_TEST_FAIL: manual third version overwritten' }
    }
    if ($Fault -eq 'second-and-rollback') {
        $backups = @(Get-ChildItem -LiteralPath $case -Force -File | Where-Object { $_.Name -match '\.txnbackup\.' })
        if ($backups.Count -eq 0) { throw 'FAULT_TEST_FAIL: unrecovered old backup was not retained' }
    } else {
        foreach ($fileName in $names) {
            if ($Fault -eq 'manual-third' -and $fileName -eq $names[2]) { continue }
            if (-not ($FirstMissing -and $fileName -eq $names[0]) -and (Get-Sha (Join-Path $case $fileName)) -ne (Get-OldSha $fileName)) { throw "FAULT_TEST_FAIL: old bytes not restored $Name/$fileName" }
            if ($FirstMissing -and $fileName -eq $names[0] -and [IO.File]::Exists((Join-Path $case $fileName))) { throw "FAULT_TEST_FAIL: missing original recreated $Name" }
        }
    }
    $script:moveCount = $null
    $receipt.cases += [ordered]@{ name = $Name; status = 'PASS'; fault = $Fault; published_moves = if ($Fault -eq 'second-and-rollback') { 1 } else { 1 }; original_missing = $FirstMissing }
}

Invoke-FaultCase 'existing-second-failure' $false 'second-failure'
Invoke-FaultCase 'missing-first-second-failure' $true 'second-failure'
Invoke-FaultCase 'manual-third-at-second-sink' $false 'manual-third'
Invoke-FaultCase 'rollback-move-failure-retains-backup' $false 'second-and-rollback'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'FAULT_INJECTION_RECEIPT.json') -Encoding UTF8
Write-Output 'WRITE_SET_FAULT_INJECTION_PASS'
