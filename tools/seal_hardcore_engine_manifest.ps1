[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$BaselineManifest = 'outputs/v115_multicore/build_prep/SOURCE_MANIFEST.windows.floor_state.json',
    [string]$EngineRoot = 'C:\Users\Administrator\Documents\HardCore-engine-v115\godot',
    [string[]]$AdditionalEnginePaths = @(),
    [ValidateRange(1,64)][int]$Jobs = 4
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$OutputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputPath))
if (Test-Path -LiteralPath $OutputPath) { throw 'A sealed manifest is immutable; choose a new output filename.' }
$baseline = Get-Content -Raw -LiteralPath (Join-Path $projectRoot $BaselineManifest) | ConvertFrom-Json
$engineHead = (& git -C $EngineRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $engineHead -ne '5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88') { throw 'Engine base differs from the pinned official source.' }
$entries = @(foreach ($entry in $baseline.changed_files) {
    if ($entry.root -eq 'engine' -and $entry.relative_path -notlike 'modules/hardcore_simulation/*') {
        [ordered]@{root='engine';relative_path=$entry.relative_path;sha256=(Get-FileHash -LiteralPath (Join-Path $EngineRoot $entry.relative_path) -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
})
foreach ($path in $AdditionalEnginePaths) {
    if ($path -cnotmatch '^(?:core|main|modules|scene|servers)/[A-Za-z0-9_./-]+\.(?:cpp|h)$' -or $path.Contains('..')) {
        throw "Invalid exact additional engine input: $path"
    }
    if ($entries.relative_path -contains $path) { continue }
    $entries += [ordered]@{root='engine';relative_path=$path;
        sha256=(Get-FileHash -LiteralPath (Join-Path $EngineRoot $path) -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$inputs = @(foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $projectRoot 'native/hardcore_simulation') -File | Where-Object {$_.Extension -in @('.h','.cpp','.py','')} | Sort-Object Name)) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $engineRelative = 'modules/hardcore_simulation/' + $file.Name
    if ((Get-FileHash -LiteralPath (Join-Path $EngineRoot $engineRelative) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash) { throw "Copied engine module is stale: $($file.Name)" }
    $entries += [ordered]@{root='engine';relative_path=$engineRelative;sha256=$hash}
    [ordered]@{root='project';relative_path=('native/hardcore_simulation/'+$file.Name);sha256=$hash}
})
$canonical = (@($entries)+@($inputs) | Sort-Object root,relative_path | ForEach-Object {'{0}/{1}:{2}' -f $_.root,$_.relative_path,$_.sha256}) -join "`n"
$hasher = [Security.Cryptography.SHA256]::Create()
try {$sourceHash=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-','').ToLowerInvariant()} finally {$hasher.Dispose()}
$manifest = [ordered]@{schema='hardcore.v115.source_manifest.v1';project_head=(& git -C $projectRoot rev-parse HEAD).Trim();engine_commit=$engineHead;
    source_scope='engine physics patch and native module only; gameplay APK has a separate source seal';
    source_sha256=$sourceHash;changed_files=$entries;module_inputs=$inputs;
    build_config=[ordered]@{precision='single';windows_arch='x86_64';android_arch='arm64';android_abis=@('arm64-v8a');ndk_version='29.0.14206865';target='editor';platform='windows';jobs=$Jobs}}
$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
[ordered]@{manifest=$OutputPath;manifest_sha256=(Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant();source_sha256=$sourceHash;engine_entries=$entries.Count;module_inputs=$inputs.Count}
