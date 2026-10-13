param(
    [ValidateSet(10,20,30,40)][int]$Active = 10,
    [ValidateSet('scattered','clustered')][string]$Density = 'scattered',
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Label,
    [switch]$Profile,
    [ValidateSet('timer','coverage','abi')][string]$TestKind = 'coverage'
)
$ErrorActionPreference = 'Stop'
$densityRootPath = Split-Path -Parent $PSScriptRoot
$densityOutPath = Join-Path $densityRootPath 'outputs/native_batch_ab_v113_20261012'
$densityRunPath = Join-Path $densityOutPath "invocations/$Label"
if (Test-Path -LiteralPath $densityRunPath) { throw 'Label already has evidence. Use a new label for a new attempt.' }
New-Item -ItemType Directory -Path $densityRunPath -Force | Out-Null
Set-Location -LiteralPath $densityRootPath
$densitySceneBase = if ($TestKind -eq 'abi') {'tests/framework/native_contact_abi_v113_20261013'} elseif ($TestKind -eq 'timer') {'tests/framework/native_coverage_timer_contract_20261013'} else {'tests/framework/native_batch_coverage_v113_20261013'}
$densityScenePaths = @(($densitySceneBase + '.gd'), ($densitySceneBase + '.tscn'))
$densityScene = $densitySceneBase + '.tscn'
$densityTimeout = if ($TestKind -ne 'coverage') {30} else {60}
$densityPolicyKeys = @('HARDCORE_PURSUIT_PROCESS_BUDGET_MODE','HARDCORE_NEW_STEP_DECISION_INTERVAL_MS',
    'HARDCORE_OWNER_DECISION_INTERVAL_MS','HARDCORE_ORDINARY_CONTACT_INSTANT_SETTLE',
    'HARDCORE_ORDINARY_ATTACK_VISUAL_MOVE_OVERRIDE','HARDCORE_ENEMY_RESIDUAL_PHASE_PROBE',
    'HARDCORE_ATTACK_AB_MODE','HARDCORE_OWNER_OPTIONAL_BUDGET','HARDCORE_PURSUIT_PROCESS_BUDGET_TRACE',
    'HARDCORE_V92_MAP_ID','HARDCORE_V92_FORMAL_CAST','HARDCORE_V92_FIRE_WALL','HARDCORE_PROFILE_FRAME_ONLY',
    'HARDCORE_V92_LABEL','HARDCORE_V82_FIRE_WALL','HARDCORE_V82_DETAIL_PROBE','HARDCORE_NATIVE_AB_AOE')
$densityOwnedKeys = @('GIT_INDEX_FILE','GIT_OPTIONAL_LOCKS','HARDCORE_AUDIT_LOG_ROOT',
    'HARDCORE_AUDIT_EVIDENCE_ROOT','HARDCORE_AUDIT_RUNTIME_APPDATA','HARDCORE_R3_TESTED_SHA',
    'HARDCORE_R3_CONTENT_SHA256','HARDCORE_NATIVE_AB_ACTIVE','HARDCORE_NATIVE_AB_DENSITY',
    'HARDCORE_NATIVE_AB_LABEL','HARDCORE_NATIVE_AB_PROFILE','HARDCORE_NATIVE_COVERAGE','ComSpec') + $densityPolicyKeys
$densityOldEnvironment = @{}
foreach ($densityKey in $densityOwnedKeys) {
    $densityOldEnvironment[$densityKey] = [Environment]::GetEnvironmentVariable($densityKey, 'Process')
}
$densityRealIndex = (& git rev-parse --path-format=absolute --git-path index).Trim()
$densityIndexBefore = (Get-FileHash -LiteralPath $densityRealIndex -Algorithm SHA256).Hash
$densityExit = 1
try {
    foreach ($densityKey in $densityPolicyKeys) { [Environment]::SetEnvironmentVariable($densityKey,$null,'Process') }
    $env:GIT_OPTIONAL_LOCKS = '0'
    $env:GIT_INDEX_FILE = Join-Path $densityRunPath 'scene_registration.index'
    & git read-tree HEAD
    foreach ($densityScenePath in $densityScenePaths) {
        $densityBlob = (& git hash-object -w --no-filters -- $densityScenePath).Trim()
        & git update-index --add --cacheinfo "100644,$densityBlob,$densityScenePath"
        if ($LASTEXITCODE -ne 0) { throw 'Could not register the exact scene in the isolated test index.' }
    }
    $densityManifestFiles = @(& git ls-files -- scripts assets/data project.godot tools/run_godot_tests.ps1 tools/test_framework_receipt.ps1 tools/test_native_log_evidence.ps1 tools/test_windows_process_ownership.ps1)
    $densityManifestFiles += @('scripts/monster_ai_package/native_batch_bridge_v113.gd')
    if (Test-Path -LiteralPath 'research/native/crowd_batch_v113') {
        $densityManifestFiles += @(Get-ChildItem -LiteralPath 'research/native/crowd_batch_v113' -Recurse -File | Where-Object {$_.Extension -in @('.cpp','.h','.json','.gdextension','.dll') -or $_.Name -eq 'SConstruct'} | ForEach-Object { [IO.Path]::GetRelativePath($densityRootPath, $_.FullName).Replace('\','/') })
    }
    $densityManifestFiles += $densityScenePaths + @('tests/phone_crowd_baseline_20261008.gd',
        'tests/world_crowd_firewall_profile_test.gd','tests/framework/helpers/check_receipt.gd','tools/run_native_density_v113.ps1','tools/run_native_coverage_v113.ps1','research/coverage_v113/coverage_probe.gd')
    $densityManifest = @(foreach ($densityRelativePath in ($densityManifestFiles | Sort-Object -Unique)) {
        $densitySourcePath = Join-Path $densityRootPath $densityRelativePath
        if (Test-Path -LiteralPath $densitySourcePath -PathType Leaf) {
            [ordered]@{path=$densityRelativePath;bytes=(Get-Item -LiteralPath $densitySourcePath).Length;
                sha256=(Get-FileHash -LiteralPath $densitySourcePath -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
    })
    $densityManifestPath = Join-Path $densityRunPath 'SOURCE_MANIFEST.json'
    [IO.File]::WriteAllText($densityManifestPath,($densityManifest | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    $densityContentHash = (Get-FileHash -LiteralPath $densityManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $env:HARDCORE_R3_TESTED_SHA = (& git rev-parse HEAD).Trim()
    $env:HARDCORE_R3_CONTENT_SHA256 = $densityContentHash
    $env:HARDCORE_AUDIT_LOG_ROOT = Join-Path $densityRunPath 'logs'
    $env:HARDCORE_AUDIT_EVIDENCE_ROOT = Join-Path $densityRunPath 'native'
    $env:HARDCORE_AUDIT_RUNTIME_APPDATA = Join-Path $densityRootPath '.godot/runtime_appdata/native_density_v113'
    $env:HARDCORE_NATIVE_AB_ACTIVE = [string]$Active
    $env:HARDCORE_NATIVE_AB_DENSITY = $Density
    $env:HARDCORE_NATIVE_AB_LABEL = $Label
    $env:HARDCORE_NATIVE_AB_PROFILE = if ($Profile) {'1'} else {'0'}
    $env:HARDCORE_NATIVE_COVERAGE = '1'
    [Environment]::SetEnvironmentVariable('COMSPEC',$null,'Process')
    [Environment]::SetEnvironmentVariable('ComSpec','C:\Windows\System32\cmd.exe','Process')
    $densityBinding = [ordered]@{baseline=$env:HARDCORE_R3_TESTED_SHA;source_content_sha256=$densityContentHash;
        active=$Active;density=$Density;label=$Label;profile=[bool]$Profile;
        command="tools/run_godot_tests.ps1 -TestPaths $densityScene -TimeoutSeconds $densityTimeout";test_kind=$TestKind;coverage_probe=$true;
        source_manifest=$densityManifestPath;runtime_data=$env:HARDCORE_AUDIT_RUNTIME_APPDATA;
        cleared_policy_environment=$densityPolicyKeys;real_index_before=$densityIndexBefore.ToLowerInvariant()}
    $densityBinding | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $densityRunPath 'SOURCE_BINDING.json') -Encoding utf8
    & (Join-Path $PSScriptRoot 'run_godot_tests.ps1') -TestPaths $densityScene -TimeoutSeconds $densityTimeout
    $densityExit = $LASTEXITCODE
} finally {
    $densityIndexAfter = (Get-FileHash -LiteralPath $densityRealIndex -Algorithm SHA256).Hash
    [ordered]@{real_index_before=$densityIndexBefore.ToLowerInvariant();real_index_after=$densityIndexAfter.ToLowerInvariant();
        real_index_preserved=($densityIndexBefore -eq $densityIndexAfter);native_runner_exit=$densityExit} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $densityRunPath 'INDEX_PROTECTION.json') -Encoding utf8
    foreach ($densityKey in $densityOwnedKeys) { [Environment]::SetEnvironmentVariable($densityKey,$densityOldEnvironment[$densityKey],'Process') }
    if ($densityIndexBefore -ne $densityIndexAfter) { throw 'The actual worktree index changed.' }
}
exit $densityExit
