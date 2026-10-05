param([Parameter(Mandatory = $true)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
if ((Get-Item -LiteralPath $RequestPath).Length -gt 1MB) { throw 'Runner request exceeds size limit.' }
$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($request.timeout -isnot [int] -and $request.timeout -isnot [long]) { throw 'Runner timeout must be an integer.' }
$parameters = @{ TimeoutSeconds = $request.timeout }
if ($request.tests -is [array] -and $request.tests.Count -gt 0 -and -not $request.suite) {
    foreach ($path in $request.tests) { if ($path -isnot [string]) { throw 'Runner test paths must be strings.' } }
    $parameters.TestPaths = [string[]]$request.tests
} elseif ($request.suite -is [string] -and $request.suite -and -not $request.tests) {
    $parameters.Suite = $request.suite
} else { throw 'Select exactly one nonempty test list or suite.' }
& (Join-Path $PSScriptRoot 'run_godot_tests.ps1') @parameters
exit $LASTEXITCODE
