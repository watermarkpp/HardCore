param()

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutputDir = Join-Path $ProjectRoot 'outputs\monster_drop_p1a'
$SnapshotPath = Join-Path $OutputDir 'runtime_snapshot.json'
$Godot = Join-Path $ProjectRoot 'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
$ExporterScene = 'res://tools/monster_drop_p1a_runtime_export.tscn'
$P1ARunner = Join-Path $PSScriptRoot 'run_monster_drop_p1a.ps1'
$Analyzer = Join-Path $PSScriptRoot 'analyze_monster_drop_p1a.py'
$RuntimeAppData = Join-Path $ProjectRoot '.godot\monster_drop_p1a_appdata'

if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot console binary not found: $Godot"
}

# Keep Godot's user data inside this worktree and avoid the Windows Path/PATH
# collision that can make the console process fail during shutdown.
$ProcessPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
[Environment]::SetEnvironmentVariable('PATH', $null, 'Process')
[Environment]::SetEnvironmentVariable('Path', $ProcessPath, 'Process')
New-Item -ItemType Directory -Force -Path $RuntimeAppData | Out-Null
[Environment]::SetEnvironmentVariable('APPDATA', $RuntimeAppData, 'Process')

& git -C $ProjectRoot check-ignore -q -- 'outputs/monster_drop_p1a/probe.tmp'
if ($LASTEXITCODE -ne 0) {
    throw 'outputs/monster_drop_p1a is not ignored by Git'
}

if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Invoke-PythonChecked {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & py -3.12 @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: py -3.12 $($Arguments -join ' ')"
    }
}

function Invoke-Exporter {
    param([Parameter(Mandatory = $true)][string]$LogPath)
    & $Godot --headless --path $ProjectRoot --log-file $LogPath $ExporterScene
    if ($LASTEXITCODE -ne 0) {
        throw "direct P1A exporter failed: $LogPath"
    }
    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) {
        throw "runtime snapshot was not written: $SnapshotPath"
    }
    $logText = Get-Content -LiteralPath $LogPath -Raw -Encoding UTF8
    if ($logText -notmatch 'MONSTER_DROP_P1A_RUNTIME_EXPORT_PASS') {
        throw "direct exporter PASS marker missing: $LogPath"
    }
    if ($logText -match '(?im)^(?:ERROR:|SCRIPT ERROR:|USER ERROR:)') {
        throw "direct exporter emitted engine errors: $LogPath"
    }
}

Push-Location $ProjectRoot
try {
    Write-Host '=== Fresh P1A direct-baseline run ==='
    & $P1ARunner
    if ($LASTEXITCODE -ne 0) {
        throw 'fresh P1A runner failed'
    }

    Write-Host '=== Deterministic direct export ==='
    $snapshotHash1 = (Get-FileHash -LiteralPath $SnapshotPath -Algorithm SHA256).Hash
    Invoke-Exporter (Join-Path $OutputDir 'runtime_export_repeat.log')
    $snapshotHash2 = (Get-FileHash -LiteralPath $SnapshotPath -Algorithm SHA256).Hash
    if ($snapshotHash1 -ne $snapshotHash2) {
        throw "direct runtime snapshot is non-deterministic: $snapshotHash1 != $snapshotHash2"
    }

    Write-Host '=== Deterministic direct analysis ==='
    Invoke-PythonChecked @(
        $Analyzer,
        '--snapshot', $SnapshotPath,
        '--output-dir', $OutputDir
    )
    $reportFiles = @(
        'analysis.json',
        'monster_drop_p1a_slots.csv',
        'monster_drop_p1a_monsters.csv',
        'report.md'
    )
    $firstHashes = @{}
    foreach ($name in $reportFiles) {
        $path = Join-Path $OutputDir $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "missing direct P1A report: $path"
        }
        $firstHashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    Invoke-PythonChecked @(
        $Analyzer,
        '--snapshot', $SnapshotPath,
        '--output-dir', $OutputDir
    )
    foreach ($name in $reportFiles) {
        $path = Join-Path $OutputDir $name
        $secondHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($firstHashes[$name] -ne $secondHash) {
            throw "direct P1A report is non-deterministic: $name"
        }
    }

    $analysis = Get-Content -LiteralPath (Join-Path $OutputDir 'analysis.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $source = $analysis.summary.source_corpus
    $runtime = $analysis.summary.compiled_runtime
    $expected = @{
        source_profiles = 156
        source_rows = 7032
        enabled_source = 5995
        non_loot_source = 1037
        malformed_provenance = 1
        compiled_profiles = 156
        enabled_profiles = 131
        non_loot_profiles = 25
        compiled_slots = 5995
        rng_eligible = 5995
    }
    if ([int]$source.profile_count -ne $expected.source_profiles -or
        [int]$source.row_count -ne $expected.source_rows -or
        [int]$source.enabled_source_row_count -ne $expected.enabled_source -or
        [int]$source.non_loot_disabled_source_row_count -ne $expected.non_loot_source -or
        [int]$source.malformed_source_provenance_count -ne $expected.malformed_provenance -or
        [int]$runtime.profile_count -ne $expected.compiled_profiles -or
        [int]$runtime.enabled_profile_count -ne $expected.enabled_profiles -or
        [int]$runtime.non_loot_profile_count -ne $expected.non_loot_profiles -or
        [int]$runtime.slot_count -ne $expected.compiled_slots -or
        [int]$runtime.rng_eligible_slot_count -ne $expected.rng_eligible) {
        throw 'fresh P1A dual-view metrics do not match the frozen contract'
    }

    Write-Host (
        'MONSTER_DROP_P1A_AUDIT_PASS: ' +
        "source=156/7032/5995/1037/1 " +
        "compiled=156/131/25/5995 origins=5926+69 " +
        'reward=5995 probability=5995 rng=5995 deterministic=PASS blockers=0'
    )
    Write-Host "SNAPSHOT_SHA256=$snapshotHash2"
    Write-Host "REPORT_DIR=$OutputDir"
}
finally {
    Pop-Location
}
