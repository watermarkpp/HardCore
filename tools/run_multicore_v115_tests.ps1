param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
    [Parameter(Mandatory=$true)][string[]]$TestPaths,
    [Parameter(Mandatory=$true)][string]$GodotExecutable,
    [string[]]$ExternalInputPaths = @(),
    [switch]$VerboseEngine,
    [switch]$ApprovedFullWorld120,
    [switch]$ApprovedSourceSave180,
    [ValidateSet(30,60)][int]$TimeoutSeconds = 30
)
$ErrorActionPreference = 'Stop'
function Get-ExactInputHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}
$effectiveTimeout = $TimeoutSeconds
if ($ApprovedSourceSave180) {
    if ($ApprovedFullWorld120 -or $TimeoutSeconds -ne 60 -or $TestPaths.Count -ne 1 -or
        $TestPaths[0] -cne 'tests/framework/source_save_roundtrip_20261017.tscn') {
        throw 'The approved 180s exception is restricted to one Source save/warehouse roundtrip stage.'
    }
    $effectiveTimeout = 180
}
if ($ApprovedFullWorld120) {
    if ($TimeoutSeconds -ne 60 -or $TestPaths.Count -ne 1 -or
        $TestPaths[0] -cne 'tests/framework/character_source_full_world_20261016.tscn') {
        throw 'The approved 120s exception is restricted to the single full-world cold-launch/exit diagnostic.'
    }
    $effectiveTimeout = 120
}
$testRoot = Split-Path -Parent $PSScriptRoot
$testRun = Join-Path $testRoot ('outputs/v115_multicore/invocations/' + $Label)
if (Test-Path -LiteralPath $testRun) { throw 'This invocation already has evidence.' }
New-Item -ItemType Directory -Path $testRun | Out-Null
$previousLocation = Get-Location
Set-Location -LiteralPath $testRoot
$keys = @('GIT_INDEX_FILE','GIT_OPTIONAL_LOCKS','HARDCORE_AUDIT_LOG_ROOT','HARDCORE_AUDIT_EVIDENCE_ROOT',
    'HARDCORE_AUDIT_RUNTIME_APPDATA','HARDCORE_R3_TESTED_SHA','HARDCORE_R3_CONTENT_SHA256')
$previous = @{}
foreach ($key in $keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
$realIndex = (& git rev-parse --path-format=absolute --git-path index).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve actual index.' }
$indexBefore = (Get-FileHash -LiteralPath $realIndex -Algorithm SHA256).Hash
$manifest = @()
$nativeExit = 1
try {
    $env:GIT_OPTIONAL_LOCKS = '0'
    $env:GIT_INDEX_FILE = Join-Path $testRun 'scene_registration.index'
    & git read-tree HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize isolated index.' }
    $testFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $queue = [Collections.Generic.Queue[string]]::new()
    foreach ($scene in $TestPaths) {
        if ($scene -cnotmatch '^tests/[A-Za-z0-9_/-]+\.tscn$') { throw "Invalid exact scene: $scene" }
        foreach ($file in @($scene, [IO.Path]::ChangeExtension($scene,'.gd').Replace('\','/'))) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing test source: $file" }
            $queue.Enqueue($file)
        }
    }
    while ($queue.Count -gt 0) {
        $file = $queue.Dequeue()
        if (-not $testFiles.Add($file)) { continue }
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing test dependency: $file" }
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $testRoot $file)), 'res://(tests/[^"\r\n]+\.(?:gd|tscn))')) {
            $queue.Enqueue($match.Groups[1].Value)
        }
    }
    foreach ($file in $testFiles) {
        $blob = (& git hash-object -w --no-filters -- $file).Trim()
        if ($LASTEXITCODE -ne 0) { throw "Cannot hash test: $file" }
        & git update-index --add --cacheinfo "100644,$blob,$file"
        if ($LASTEXITCODE -ne 0) { throw "Cannot register isolated test: $file" }
    }
    # Hash working bytes, including new domain scripts, not only HEAD blobs.
    $sources = @(& rg --files scripts assets/data)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate source inputs.' }
    foreach ($inputFile in $ExternalInputPaths) {
        if (($inputFile -cnotmatch '^(?:assets|tests|outputs)/[A-Za-z0-9_./-]+$' -and $inputFile -cne 'override.cfg') -or $inputFile.Contains('..') -or
            -not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
            throw "Invalid or missing exact external input: $inputFile"
        }
        $sources += $inputFile
    }
    $sources += @(& rg --files --no-ignore -g '*.import' assets)
    if ($LASTEXITCODE -gt 1) { throw 'Cannot enumerate asset import metadata.' }
    foreach ($cache in @('.godot/global_script_class_cache.cfg','.godot/uid_cache.bin')) {
        if (Test-Path -LiteralPath $cache -PathType Leaf) { $sources += $cache }
    }
    if (Test-Path -LiteralPath '.godot/imported' -PathType Container) {
        $sources += @(& rg --files --no-ignore .godot/imported)
        if ($LASTEXITCODE -gt 1) { throw 'Cannot enumerate imported runtime inputs.' }
    }
    $sources += @($testFiles) + @('project.godot','tests/framework/helpers/check_receipt.gd',
        'tools/run_multicore_v115_tests.ps1','tools/run_godot_tests.ps1',
        'tools/test_framework_receipt.ps1','tools/test_native_log_evidence.ps1','tools/test_windows_process_ownership.ps1')
    $manifest = @(foreach ($file in ($sources | Sort-Object -Unique)) {
        $full = Join-Path $testRoot $file
        [ordered]@{path=$file.Replace('\','/');bytes=([IO.FileInfo]::new($full)).Length;
            sha256=(Get-ExactInputHash $full)}
    })
    $manifestPath = Join-Path $testRun 'SOURCE_MANIFEST.json'
    [IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    $env:HARDCORE_R3_TESTED_SHA = (& git rev-parse HEAD).Trim()
    $env:HARDCORE_R3_CONTENT_SHA256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $env:HARDCORE_AUDIT_LOG_ROOT = Join-Path $testRun 'logs'
    $env:HARDCORE_AUDIT_EVIDENCE_ROOT = Join-Path $testRun 'native'
    $env:HARDCORE_AUDIT_RUNTIME_APPDATA = Join-Path $testRoot '.godot/runtime_appdata/multicore_v115'
    [ordered]@{baseline=$env:HARDCORE_R3_TESTED_SHA;source_content_sha256=$env:HARDCORE_R3_CONTENT_SHA256;
        source_manifest=$manifestPath;real_index_before=$indexBefore.ToLowerInvariant();
        approved_full_world_120=[bool]$ApprovedFullWorld120;approved_source_save_180=[bool]$ApprovedSourceSave180;
        command=@('tools/run_godot_tests.ps1','-GodotExecutable',$GodotExecutable,'-TestPaths')+$TestPaths+@('-TimeoutSeconds',[string]$effectiveTimeout)+$(if($ApprovedFullWorld120){@('-ApprovedFullWorld120')}elseif($ApprovedSourceSave180){@('-ApprovedSourceSave180')}else{@()})} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $testRun 'SOURCE_BINDING.json') -Encoding utf8
    $runnerArgs = @{GodotExecutable=$GodotExecutable;TestPaths=$TestPaths;TimeoutSeconds=$effectiveTimeout}
    if ($ApprovedFullWorld120) { $runnerArgs.ApprovedFullWorld120 = $true }
    if ($ApprovedSourceSave180) { $runnerArgs.ApprovedSourceSave180 = $true }
    if ($VerboseEngine) { $runnerArgs.Verbose = $true }
    & (Join-Path $PSScriptRoot 'run_godot_tests.ps1') @runnerArgs
    $nativeExit = $LASTEXITCODE
} finally {
    $changed = @(foreach ($row in $manifest) {
        $full = Join-Path $testRoot $row.path
        if (-not [IO.File]::Exists($full)) { $row.path }
        elseif ((Get-ExactInputHash $full) -ne $row.sha256) { $row.path }
    })
    $indexAfter = (Get-FileHash -LiteralPath $realIndex -Algorithm SHA256).Hash
    [ordered]@{real_index_before=$indexBefore.ToLowerInvariant();real_index_after=$indexAfter.ToLowerInvariant();
        real_index_preserved=($indexBefore -eq $indexAfter);source_unchanged=($manifest.Count -gt 0 -and $changed.Count -eq 0);
        changed_sources=$changed;native_runner_exit=$nativeExit} | ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $testRun 'PROTECTION.json') -Encoding utf8
    foreach ($key in $keys) {
        if ($null -eq $previous[$key]) {
            # PowerShell 7.5 retains empty environment values on Windows;
            # Git treats an empty GIT_INDEX_FILE as a real invalid filename.
            Remove-Item -LiteralPath ('Env:' + $key) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')
        }
    }
    Set-Location -LiteralPath $previousLocation
    if ($indexBefore -ne $indexAfter) { throw 'Actual index changed.' }
    if ($manifest.Count -gt 0 -and $changed.Count -gt 0) { throw 'Test source freeze was violated.' }
}
exit $nativeExit
