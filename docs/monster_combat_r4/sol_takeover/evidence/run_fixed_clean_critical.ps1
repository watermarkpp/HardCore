param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$SourceHead,
    [Parameter(Mandatory)][string]$EvidenceRoot,
    [Parameter(Mandatory)][string]$PreviousExpectedPaths
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
if ((Test-Path -LiteralPath $EvidenceRoot) -or
    (git -C $ProjectRoot rev-parse HEAD).Trim() -ne $SourceHead -or
    @(git -C $ProjectRoot status --porcelain --untracked-files=no).Count -ne 0) {
    throw 'Refuse to overwrite evidence or run a changed source checkout.'
}

$prior = @(Get-Content -LiteralPath $PreviousExpectedPaths -Raw | ConvertFrom-Json)
if ($prior.Count -ne 546) { throw 'Unexpected previous formal execution set.' }
$expected = [Collections.Generic.List[string]]::new()
foreach ($entry in $prior) { $expected.Add([string]$entry) }
$insertions = @(
    @{ after='tests/hc_monster_combat_r4/perf_unit_determinism_test.tscn'; before='tests/hc_monster_combat_r4/synchronous_revive_death_token_test.tscn'; path='tests/hc_monster_combat_r4/native_physics_sampling_test.tscn' },
    @{ after='tests/f03_pickup_receipt_lifecycle_test.tscn'; before='tests/f03_native_pickup_lifecycle_test.tscn'; path='tests/f03_warehouse_receipt_boundary_test.tscn' }
)
foreach ($addition in $insertions) {
    $position = $expected.IndexOf($addition.after)
    if ($position -lt 0 -or $expected[$position + 1] -ne $addition.before -or $expected.Contains($addition.path)) {
        throw "Unexpected suite insertion boundary: $($addition.path)"
    }
    $expected.Insert($position + 1, $addition.path)
}
if ($expected.Count -ne 548 -or @($expected | Select-Object -Unique).Count -ne 548) {
    throw 'Unexpected formal execution set after insertion.'
}

New-Item -ItemType Directory -Path $EvidenceRoot | Out-Null
function Write-Json($path, $value) {
    $json = $value | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($path, $json + "`n", [Text.UTF8Encoding]::new($false))
}
$expectedFile = Join-Path $EvidenceRoot 'expected_paths.json'
Write-Json $expectedFile @($expected.ToArray())
$engine = Join-Path $ProjectRoot 'tools/godot-4.7/Godot_v4.7-stable_win64_console.exe'
$runner = Join-Path $ProjectRoot 'tools/run_godot_tests.ps1'
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'Missing exact project Godot console executable.' }
$runtime = Join-Path $ProjectRoot '.godot/runtime_appdata'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$env:APPDATA = $runtime
$importLog = Join-Path $EvidenceRoot 'import.godot.log'
& $engine --headless --editor --path $ProjectRoot --import --quit --log-file $importLog 1> (Join-Path $EvidenceRoot 'import.stdout.log') 2> (Join-Path $EvidenceRoot 'import.stderr.log')
$importExit = $LASTEXITCODE
Write-Json (Join-Path $EvidenceRoot 'import_completion.json') @{
    finished_at = (Get-Date).ToString('o'); source_head = $SourceHead; import_exit = $importExit
}
if ($importExit -ne 0) { throw "Headless import failed: $importExit" }

$identity = [ordered]@{
    started_at = (Get-Date).ToString('o')
    source_head = $SourceHead
    project_root = $ProjectRoot
    suite = 'critical'
    ordinary_timeout_seconds = 30
    source_tree = (git -C $ProjectRoot rev-parse 'HEAD^{tree}').Trim()
    import_exit = $importExit
    runner_sha256 = (Get-FileHash -LiteralPath $runner -Algorithm SHA256).Hash
    engine_sha256 = (Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash
    expected_paths_sha256 = (Get-FileHash -LiteralPath $expectedFile -Algorithm SHA256).Hash
    expected_count = 548
    post_import_status = @(git -C $ProjectRoot status --short)
    boundary = 'Fixed clean source full critical; no forge integration, APK or device claim'
}
Write-Json (Join-Path $EvidenceRoot 'identity.json') $identity
$env:HARDCORE_AUDIT_LOG_ROOT = Join-Path $EvidenceRoot 'runner'
$env:HARDCORE_AUDIT_RUNTIME_APPDATA = $runtime
New-Item -ItemType Directory -Path $env:HARDCORE_AUDIT_LOG_ROOT -Force | Out-Null
$shell = (Get-Command pwsh -ErrorAction Stop).Source
& $shell -NoProfile -File $runner -Suite critical -TimeoutSeconds 30 1> (Join-Path $EvidenceRoot 'full.stdout.log') 2> (Join-Path $EvidenceRoot 'full.stderr.log')
$result = $LASTEXITCODE
Write-Json (Join-Path $EvidenceRoot 'completion.json') @{
    source_head = $SourceHead; exit_code = $result; finished_at = (Get-Date).ToString('o')
}
Write-Host "FULL_CRITICAL_EXIT=$result"
exit $result
