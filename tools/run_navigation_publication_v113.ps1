param(
    [Parameter(Mandatory=$true)][int[]]$MapIds,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
    [ValidateSet(30,60)][int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'
$navRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $navRoot
$navEvidence = Join-Path $navRoot 'outputs/crowd_compute_optimization_v113_20261013'
$navFolder = Join-Path $navEvidence "publications/$Label"
if (Test-Path -LiteralPath $navFolder) { throw 'Evidence label already exists.' }
New-Item -ItemType Directory -Path $navFolder -Force | Out-Null
$navManifest = Join-Path $navEvidence 'NAVIGATION_MAP_MANIFEST.json'
$navAllowlist = Join-Path $navEvidence 'NAVIGATION_OUTPUT_ALLOWLIST.json'
$navRows = (Get-Content -LiteralPath $navAllowlist -Raw | ConvertFrom-Json).maps
$navScene = 'tests/framework/publish_monster_navigation_v113.tscn'
$navScript = 'tests/framework/publish_monster_navigation_v113.gd'
$navKeys = @('GIT_INDEX_FILE','GIT_OPTIONAL_LOCKS','HARDCORE_AUDIT_LOG_ROOT','HARDCORE_AUDIT_EVIDENCE_ROOT',
    'HARDCORE_AUDIT_RUNTIME_APPDATA','HARDCORE_R3_TESTED_SHA','HARDCORE_R3_CONTENT_SHA256',
    'HARDCORE_NAVIGATION_MANIFEST','HARDCORE_NAVIGATION_MAP_ID','HARDCORE_NAVIGATION_OUTPUT_DIR','ComSpec')
$navOld = @{}
foreach ($key in $navKeys) { $navOld[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
$navIndex = (& git rev-parse --path-format=absolute --git-path index).Trim()
$navIndexBefore = (Get-FileHash -LiteralPath $navIndex -Algorithm SHA256).Hash
$navSource = @()
$navResults = @()
$navCleanupErrors = @()
$navAllowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$navExit = 1
function Resolve-NavPath([string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or ($Relative -split '[/\\]') -contains '..') { throw 'Invalid relative path.' }
    $resolved = [IO.Path]::GetFullPath((Join-Path $navRoot $Relative))
    if (-not $resolved.StartsWith($navRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Path outside v113 workspace.' }
    $cursor = $navRoot
    foreach ($part in ($Relative -split '[/\\]')) {
        $cursor = Join-Path $cursor $part
        $flags = [IO.File]::GetAttributes($cursor)
        if ($flags -band [IO.FileAttributes]::ReparsePoint) { throw "Publication path traverses reparse point: $Relative" }
    }
    return $resolved
}
function Nav-Row([string]$Relative) {
    $absolute = Resolve-NavPath $Relative
    $stream = [IO.File]::OpenRead($absolute)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
    finally { $stream.Dispose(); $hasher.Dispose() }
    return [ordered]@{path=$Relative;sha256=$hash;bytes=([IO.FileInfo]::new($absolute)).Length}
}
try {
    if (@($MapIds | Sort-Object -Unique).Count -ne $MapIds.Count) { throw 'Duplicate target map.' }
    foreach ($id in $MapIds) {
        $matches = @($navRows | Where-Object map_id -eq $id)
        if ($matches.Count -ne 1) { throw "Map outside authorized manifest: $id" }
        foreach ($file in $matches[0].allowed_formal_outputs) { [void]$navAllowed.Add([string]$file.path) }
    }
    $env:GIT_OPTIONAL_LOCKS = '0'
    $env:GIT_INDEX_FILE = Join-Path $navFolder 'publication_scene.index'
    & git read-tree HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create isolated index.' }
    foreach ($file in @($navScene,$navScript)) {
        $blob = (& git hash-object -w --no-filters -- $file).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Cannot hash publication host.' }
        & git update-index --add --cacheinfo "100644,$blob,$file"
        if ($LASTEXITCODE -ne 0) { throw 'Cannot register publication host.' }
    }
    $navFiles = @(& git -c core.quotepath=false ls-files -- scripts assets/data map_editor_workspace project.godot tools/run_godot_tests.ps1 tools/test_framework_receipt.ps1 tools/test_native_log_evidence.ps1 tools/test_windows_process_ownership.ps1)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate protected inputs.' }
    $navFiles += @(& rg --files scripts assets/data map_editor_workspace)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate untracked inputs.' }
    $navFiles += @($navScene,$navScript,'tests/framework/helpers/check_receipt.gd','tools/run_navigation_publication_v113.ps1',
        'tools/map_editor/rebuild_monster_navigation_profiles_v113.gd','tools/map_editor/rebuild_monster_navigation_profiles_v113.tscn',
        'outputs/crowd_compute_optimization_v113_20261013/NAVIGATION_MAP_MANIFEST.json',
        'outputs/crowd_compute_optimization_v113_20261013/NAVIGATION_OUTPUT_ALLOWLIST.json')
    $navFiles = @($navFiles | ForEach-Object { $_.Replace('\','/') })
    foreach ($file in ($navFiles | Sort-Object -Unique)) {
        if (-not $navAllowed.Contains($file)) { $navSource += Nav-Row $file }
    }
    $navSourcePath = Join-Path $navFolder 'SOURCE_MANIFEST.json'
    $navSource | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $navSourcePath -Encoding utf8
    $env:HARDCORE_R3_TESTED_SHA = (& git rev-parse HEAD).Trim()
    $env:HARDCORE_R3_CONTENT_SHA256 = (Get-FileHash -LiteralPath $navSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $env:HARDCORE_NAVIGATION_MANIFEST = $navManifest
    [Environment]::SetEnvironmentVariable('COMSPEC',$null,'Process')
    $env:ComSpec = 'C:\Windows\System32\cmd.exe'
    $navInitialOutputs = @(foreach ($file in $navAllowed) { Nav-Row $file })
    $navStorePath = Resolve-NavPath 'assets/data/runtime/map_editor/wall_render_store'
    $navStoreBefore = @([IO.Directory]::GetFiles($navStorePath,'*',[IO.SearchOption]::AllDirectories) | Sort-Object)
    $navStoreBefore | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $navFolder 'WALL_STORE_ENTRIES_BEFORE.json') -Encoding utf8
    [ordered]@{head=$env:HARDCORE_R3_TESTED_SHA;source_content_sha256=$env:HARDCORE_R3_CONTENT_SHA256;map_ids=$MapIds;
        manifest=Nav-Row 'outputs/crowd_compute_optimization_v113_20261013/NAVIGATION_MAP_MANIFEST.json';
        allowlist=Nav-Row 'outputs/crowd_compute_optimization_v113_20261013/NAVIGATION_OUTPUT_ALLOWLIST.json';
        initial_outputs=$navInitialOutputs;real_index_before=$navIndexBefore;timeout_per_map_seconds=$TimeoutSeconds} |
        ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $navFolder 'SOURCE_BINDING.json') -Encoding utf8
    foreach ($id in $MapIds) {
        $entry = @($navRows | Where-Object map_id -eq $id)[0]
        $invocation = Join-Path $navFolder "map_$id"
        New-Item -ItemType Directory -Path $invocation -Force | Out-Null
        $before = @(foreach ($file in $navInitialOutputs) { Nav-Row $file.path })
        $before | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $invocation 'OUTPUTS_BEFORE.json') -Encoding utf8
        $attributes = @{}
        $selected = @($entry.allowed_formal_outputs | ForEach-Object { [string]$_.path })
        try {
            foreach ($file in $selected) {
                $absolute = Resolve-NavPath $file
                $attributes[$file] = (Get-Item -LiteralPath $absolute).Attributes
                $backup = Join-Path $invocation ('backup/' + $file)
                New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
                [IO.File]::Copy($absolute,$backup,$false)
                if ((Get-FileHash -LiteralPath $backup).Hash -ne (Get-FileHash -LiteralPath $absolute).Hash) { throw 'Backup verification failed.' }
                (Get-Item -LiteralPath $absolute).IsReadOnly = $false
            }
            $env:HARDCORE_NAVIGATION_MAP_ID = [string]$id
            $env:HARDCORE_NAVIGATION_OUTPUT_DIR = $invocation
            $env:HARDCORE_AUDIT_LOG_ROOT = Join-Path $invocation 'logs'
            $env:HARDCORE_AUDIT_EVIDENCE_ROOT = Join-Path $invocation 'native'
            $env:HARDCORE_AUDIT_RUNTIME_APPDATA = Join-Path $navRoot '.godot/runtime_appdata/navigation_publication_v113'
            & (Join-Path $PSScriptRoot 'run_godot_tests.ps1') -TestPaths @($navScene) -TimeoutSeconds $TimeoutSeconds
            $nativeExit = $LASTEXITCODE
        } finally {
            foreach ($file in $attributes.Keys) {
                try { (Get-Item -LiteralPath (Resolve-NavPath $file)).Attributes = $attributes[$file] }
                catch { $navCleanupErrors += "Attribute restoration $file : $($_.Exception.Message)" }
            }
        }
        $after = @(foreach ($file in $navInitialOutputs) { Nav-Row $file.path })
        $changes = @(foreach ($old in $before) { $new = @($after | Where-Object path -eq $old.path)[0]; if ($new.sha256 -ne $old.sha256) { $old.path } })
        $unexpected = @($changes | Where-Object { $_ -notin $selected })
        $row = [ordered]@{map_id=$id;native_exit=$nativeExit;changed_outputs=$changes;unexpected_outputs=$unexpected;after=$after}
        $row | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $invocation 'OUTPUT_PROTECTION.json') -Encoding utf8
        $navResults += $row
        if ($nativeExit -ne 0 -or $unexpected.Count -gt 0 -or $navCleanupErrors.Count -gt 0) { throw "Publication failed for $id; evidence retained, no automatic rollback over unknown data." }
    }
    $navExit = 0
} catch {
    $_ | Out-String | Set-Content -LiteralPath (Join-Path $navFolder 'WRAPPER_FAILURE.txt') -Encoding utf8
    Write-Output $_
} finally {
    try {
        $changedInputs = @()
        foreach ($file in $navSource) {
            try {
                $current = Nav-Row $file.path
                if ($current.sha256 -ne $file.sha256) { $changedInputs += $file.path }
            } catch { $changedInputs += $file.path; $navCleanupErrors += "Input verification $($file.path) : $($_.Exception.Message)" }
        }
        $storeEntryChanges = @()
        if ($null -ne $navStoreBefore) {
            $navStoreAfter = @([IO.Directory]::GetFiles((Resolve-NavPath 'assets/data/runtime/map_editor/wall_render_store'),'*',[IO.SearchOption]::AllDirectories) | Sort-Object)
            $storeEntryChanges = @(Compare-Object -ReferenceObject $navStoreBefore -DifferenceObject $navStoreAfter)
            if ($storeEntryChanges.Count -gt 0) { $navCleanupErrors += 'Wall store file inventory changed.' }
        }
        $navIndexAfter = ''
        try { $navIndexAfter = (Get-FileHash -LiteralPath $navIndex -Algorithm SHA256).Hash }
        catch { $navCleanupErrors += "Index verification: $($_.Exception.Message)" }
        if ($changedInputs.Count -gt 0 -or $navIndexAfter -ne $navIndexBefore -or $navCleanupErrors.Count -gt 0) { $navExit = 1 }
        [ordered]@{status= $(if ($navExit -eq 0) {'PASS'} else {'FAIL'});exit_code=$navExit;source_unchanged=($changedInputs.Count -eq 0);
            changed_inputs=$changedInputs;wall_store_entry_changes=$storeEntryChanges;cleanup_errors=$navCleanupErrors;real_index_preserved=($navIndexAfter -eq $navIndexBefore);real_index_before=$navIndexBefore;
            real_index_after=$navIndexAfter;results=$navResults} | ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $navFolder 'PROTECTION.json') -Encoding utf8
    } catch {
        $navExit = 1
        Write-Output "Final protection recording failed: $($_.Exception.Message)"
    } finally {
        foreach ($key in $navKeys) {
            try { [Environment]::SetEnvironmentVariable($key,$navOld[$key],'Process') }
            catch { $navExit = 1; Write-Output "Environment restoration failed: $key" }
        }
    }
}
exit $navExit
