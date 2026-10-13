param(
    [ValidateSet('CONTROL','CANDIDATE','SHADOW')][string]$Mode = 'CANDIDATE',
    [ValidateSet(10,20,30,40)][int]$Active = 30,
    [ValidateSet('scattered','clustered')][string]$Density = 'clustered',
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
    [string[]]$TestPaths = @('tests/framework/crowd_compute_density_v113_20261013.tscn'),
    [ValidateSet(30,60)][int]$TimeoutSeconds = 60,
    [switch]$CaptureFootprints,
    [string]$StaticCorpusPath = ''
)
$ErrorActionPreference = 'Stop'
$computeRoot = Split-Path -Parent $PSScriptRoot
$computeOut = Join-Path $computeRoot 'outputs/crowd_compute_optimization_v113_20261013'
$computeRun = Join-Path $computeOut "invocations/$Label"
if ((Test-Path -LiteralPath $computeRun) -or (Test-Path -LiteralPath (Join-Path $computeOut "runs/$Label.json"))) { throw 'Label already has evidence.' }
New-Item -ItemType Directory -Path $computeRun -Force | Out-Null
Set-Location -LiteralPath $computeRoot
$computePolicyKeys = @('HARDCORE_PURSUIT_PROCESS_BUDGET_MODE','HARDCORE_NEW_STEP_DECISION_INTERVAL_MS',
    'HARDCORE_OWNER_DECISION_INTERVAL_MS','HARDCORE_ORDINARY_CONTACT_INSTANT_SETTLE',
    'HARDCORE_ORDINARY_ATTACK_VISUAL_MOVE_OVERRIDE','HARDCORE_ENEMY_RESIDUAL_PHASE_PROBE',
    'HARDCORE_ATTACK_AB_MODE','HARDCORE_OWNER_OPTIONAL_BUDGET','HARDCORE_PURSUIT_PROCESS_BUDGET_TRACE',
    'HARDCORE_V92_MAP_ID','HARDCORE_V92_FORMAL_CAST','HARDCORE_V92_FIRE_WALL','HARDCORE_PROFILE_FRAME_ONLY',
    'HARDCORE_V92_LABEL','HARDCORE_V82_FIRE_WALL','HARDCORE_V82_DETAIL_PROBE','HARDCORE_NATIVE_AB_AOE')
$computeKeys = @('GIT_INDEX_FILE','GIT_OPTIONAL_LOCKS','HARDCORE_AUDIT_LOG_ROOT','HARDCORE_AUDIT_EVIDENCE_ROOT',
    'HARDCORE_AUDIT_RUNTIME_APPDATA','HARDCORE_R3_TESTED_SHA','HARDCORE_R3_CONTENT_SHA256',
    'HARDCORE_NATIVE_AB_ACTIVE','HARDCORE_NATIVE_AB_DENSITY','HARDCORE_NATIVE_AB_LABEL','HARDCORE_NATIVE_AB_PROFILE',
    'HARDCORE_COMPUTE_AB_MODE','HARDCORE_COMPUTE_CAPTURE_FOOTPRINTS','HARDCORE_COMPUTE_INVOCATION_PATH','HARDCORE_COMPUTE_STATIC_CORPUS_PATH','ComSpec') + $computePolicyKeys
$computeOld = @{}
foreach ($key in $computeKeys) { $computeOld[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
$computeIndex = (& git rev-parse --path-format=absolute --git-path index).Trim()
$computeIndexBefore = (Get-FileHash -LiteralPath $computeIndex -Algorithm SHA256).Hash
$computeExit = 1
$computeUnchanged = $false
$computeManifest = @()
try {
    foreach ($key in $computePolicyKeys) { [Environment]::SetEnvironmentVariable($key,$null,'Process') }
    $env:GIT_OPTIONAL_LOCKS = '0'
    $env:GIT_INDEX_FILE = Join-Path $computeRun 'scene_registration.index'
    & git read-tree HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Isolated index initialization failed.' }
    $computeSceneFiles = @()
    foreach ($scene in $TestPaths) {
        if ($scene -notmatch '^tests/[A-Za-z0-9_/-]+\.tscn$') { throw "Invalid exact scene path: $scene" }
        $computeSceneFiles += $scene
        $scriptPath = [IO.Path]::ChangeExtension($scene,'.gd').Replace('\','/')
        if (Test-Path -LiteralPath $scriptPath -PathType Leaf) { $computeSceneFiles += $scriptPath }
    }
    foreach ($source in $computeSceneFiles) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing test: $source" }
        $blob = (& git hash-object -w --no-filters -- $source).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Scene hashing failed.' }
        & git update-index --add --cacheinfo "100644,$blob,$source"
        if ($LASTEXITCODE -ne 0) { throw 'Isolated scene registration failed.' }
    }
    $computeFiles = @(& git -c core.quotepath=false ls-files -- scripts assets/data project.godot tools/run_godot_tests.ps1 tools/test_framework_receipt.ps1 tools/test_native_log_evidence.ps1 tools/test_windows_process_ownership.ps1)
    if ($LASTEXITCODE -ne 0) { throw 'Source enumeration failed.' }
    $computeFiles += $computeSceneFiles + @('tests/phone_crowd_baseline_20261008.gd','tests/world_crowd_firewall_profile_test.gd',
        'tests/framework/helpers/check_receipt.gd','tools/run_crowd_compute_v113.ps1',
        'tests/framework/native_batch_density_v113_20261012.gd','tests/framework/native_batch_density_v113_20261012.tscn')
    $computeFiles += @(Get-ChildItem -LiteralPath (Join-Path $computeRoot 'tests/framework') -Filter '*compute*v113*' -File | ForEach-Object { 'tests/framework/' + $_.Name })
    $computeFiles += @(Get-ChildItem -LiteralPath (Join-Path $computeRoot 'tests/framework/helpers') -Filter 'static_polygon_*.gd' -File | ForEach-Object { 'tests/framework/helpers/' + $_.Name })
    # Bind test inheritance and helper references too, not only production files.
    $computeTestQueue = [Collections.Generic.Queue[string]]::new()
    $computeSeenTests = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($source in $computeFiles) { if ($source.StartsWith('tests/')) { $computeTestQueue.Enqueue($source) } }
    while ($computeTestQueue.Count -gt 0) {
        $source = $computeTestQueue.Dequeue()
        if (-not $computeSeenTests.Add($source)) { continue }
        $absolute = Join-Path $computeRoot $source
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Missing test dependency: $source" }
        $computeFiles += $source
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($absolute),'res://(tests/[^"\r\n]+\.(?:gd|tscn))')) {
            $computeTestQueue.Enqueue($match.Groups[1].Value)
        }
    }
    $computeManifest = @(foreach ($source in ($computeFiles | Sort-Object -Unique)) {
        $absolute = Join-Path $computeRoot $source
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "Required source missing: $source" }
        [ordered]@{path=$source; bytes=(Get-Item -LiteralPath $absolute).Length; sha256=(Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    $computeManifestPath = Join-Path $computeRun 'SOURCE_MANIFEST.json'
    [IO.File]::WriteAllText($computeManifestPath,($computeManifest | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    $env:HARDCORE_R3_TESTED_SHA = (& git rev-parse HEAD).Trim()
    $env:HARDCORE_R3_CONTENT_SHA256 = (Get-FileHash -LiteralPath $computeManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $env:HARDCORE_AUDIT_LOG_ROOT = Join-Path $computeRun 'logs'
    $env:HARDCORE_AUDIT_EVIDENCE_ROOT = Join-Path $computeRun 'native'
    $env:HARDCORE_AUDIT_RUNTIME_APPDATA = Join-Path $computeRoot '.godot/runtime_appdata/crowd_compute_v113'
    $env:HARDCORE_NATIVE_AB_ACTIVE = [string]$Active
    $env:HARDCORE_NATIVE_AB_DENSITY = $Density
    $env:HARDCORE_NATIVE_AB_LABEL = $Label
    $env:HARDCORE_NATIVE_AB_PROFILE = '0'
    $env:HARDCORE_COMPUTE_AB_MODE = $Mode
    $env:HARDCORE_COMPUTE_CAPTURE_FOOTPRINTS = if ($CaptureFootprints) {'1'} else {'0'}
    $env:HARDCORE_COMPUTE_INVOCATION_PATH = $computeRun
    $computeCorpus = $null
    if ($StaticCorpusPath) {
        $env:HARDCORE_COMPUTE_STATIC_CORPUS_PATH = (Resolve-Path -LiteralPath $StaticCorpusPath).Path
        $computeCorpus = [ordered]@{path=$env:HARDCORE_COMPUTE_STATIC_CORPUS_PATH; bytes=(Get-Item -LiteralPath $env:HARDCORE_COMPUTE_STATIC_CORPUS_PATH).Length;
            sha256=(Get-FileHash -LiteralPath $env:HARDCORE_COMPUTE_STATIC_CORPUS_PATH -Algorithm SHA256).Hash.ToLowerInvariant()}
    } else { $env:HARDCORE_COMPUTE_STATIC_CORPUS_PATH = '' }
    [Environment]::SetEnvironmentVariable('COMSPEC',$null,'Process')
    [Environment]::SetEnvironmentVariable('ComSpec','C:\Windows\System32\cmd.exe','Process')
    [ordered]@{baseline=$env:HARDCORE_R3_TESTED_SHA; source_content_sha256=$env:HARDCORE_R3_CONTENT_SHA256;
        mode=$Mode; active=$Active; density=$Density; label=$Label; capture_footprints=[bool]$CaptureFootprints; corpus=$computeCorpus;
        command=@('tools/run_godot_tests.ps1','-TestPaths')+$TestPaths+@('-TimeoutSeconds',[string]$TimeoutSeconds);
        source_manifest=$computeManifestPath; runtime_data=$env:HARDCORE_AUDIT_RUNTIME_APPDATA;
        cleared_policy_environment=$computePolicyKeys; real_index_before=$computeIndexBefore.ToLowerInvariant()} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $computeRun 'SOURCE_BINDING.json') -Encoding utf8
    & (Join-Path $PSScriptRoot 'run_godot_tests.ps1') -TestPaths $TestPaths -TimeoutSeconds $TimeoutSeconds
    $computeExit = $LASTEXITCODE
} catch {
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $computeRun 'WRAPPER_FAILURE.txt') -Encoding utf8
    throw
} finally {
    $computeChanges = @(foreach ($row in $computeManifest) {
        $absolute = Join-Path $computeRoot $row.path
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { $row.path }
        elseif ((Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.sha256) { $row.path }
    })
    $computeUnchanged = $computeManifest.Count -gt 0 -and $computeChanges.Count -eq 0
    $computeIndexAfter = (Get-FileHash -LiteralPath $computeIndex -Algorithm SHA256).Hash
    [ordered]@{real_index_before=$computeIndexBefore.ToLowerInvariant(); real_index_after=$computeIndexAfter.ToLowerInvariant();
        real_index_preserved=($computeIndexBefore -eq $computeIndexAfter); source_unchanged=$computeUnchanged;
        changed_sources=$computeChanges; native_runner_exit=$computeExit} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $computeRun 'PROTECTION.json') -Encoding utf8
    foreach ($key in $computeKeys) { [Environment]::SetEnvironmentVariable($key,$computeOld[$key],'Process') }
    if ($computeIndexBefore -ne $computeIndexAfter) { throw 'Actual index changed.' }
    if ($computeManifest.Count -gt 0 -and -not $computeUnchanged) { throw 'Source freeze validation failed.' }
}
exit $computeExit
