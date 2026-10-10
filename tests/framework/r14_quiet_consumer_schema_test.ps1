param(
    [Parameter(Mandatory=$true)][string]$SnapshotPath
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$collector = Join-Path $PSScriptRoot "..\..\tools\collect_r14_quiet.ps1"
$source = Get-Content $collector -Raw
if($source -notmatch 'frame_sample_overflowed = \$pd\.frame_sample_overflowed') {
    throw "collector does not consume the producer's singular overflow field"
}
if($source -match 'frame_samples_overflowed') {
    throw "collector still contains the obsolete plural overflow field"
}

$snapshot = Get-Content $SnapshotPath -Raw | ConvertFrom-Json
$pd = $snapshot.performance_diagnostics
if($null -eq $pd){ throw "snapshot has no performance_diagnostics" }

# Parse the collector with PowerShell's real AST and execute the complete
# ordered assignment expression. The consumer field list stays owned by the
# collector; this test only locates and evaluates that production assignment.
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if($null -ne $parseErrors -and $parseErrors.Count -gt 0){ throw "collector parse failed: $($parseErrors[0].Message)" }
$assignment = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $node.Left.VariablePath.UserPath -eq 'hard' -and
    $node.Right -is [System.Management.Automation.Language.CommandExpressionAst] -and
    $node.Right.Expression -is [System.Management.Automation.Language.ConvertExpressionAst] -and
    $node.Right.Expression.Child -is [System.Management.Automation.Language.HashtableAst]
}, $true)
if($null -eq $assignment){ throw "collector hard-gate assignment AST not found" }
$consumer = [scriptblock]::Create($assignment.Extent.Text + "`n`$hard")
$hard = & $consumer
if($null -eq $hard -or $hard -isnot [System.Collections.IDictionary]){ throw "collector hard-gate assignment did not return a map" }
$expectedOverflow = [int]$pd.frame_samples_dropped -gt 0
if([bool]$hard.frame_sample_overflowed -ne $expectedOverflow) {
    throw "overflow state was not preserved from real producer snapshot"
}
if([int]$hard.frame_samples_dropped -ne [int]$pd.frame_samples_dropped) {
    throw "dropped count changed during host consumption"
}
if([bool]$hard.frame_percentiles_exact -ne [bool]$pd.frame_percentiles_exact) {
    throw "exactness state changed during host consumption"
}
if(($expectedOverflow -and [bool]$hard.frame_percentiles_exact) -or ((-not $expectedOverflow) -and -not [bool]$hard.frame_percentiles_exact)) {
    throw "producer exactness contract is inconsistent with overflow state"
}
Write-Output "R14_QUIET_CONSUMER_SCHEMA_PASS snapshot=$SnapshotPath strict_mode=2.0 overflow=$expectedOverflow"
