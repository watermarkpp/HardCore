param([string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
# Packaging must never silently ship an optimized map with a stale plan.
# The runtime continues to reject invalid plans; rebuild derived assets using
# tools/map_editor/publish_wall_render_plans.gd after publishing edited maps.
$Root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$PlanDirectory = Join-Path $Root 'assets/data/runtime/map_editor/wall_render_plans'
$Plans = @(Get-ChildItem -LiteralPath $PlanDirectory -Filter '*.wall_render_plan.json')
if ($Plans.Count -eq 0) { throw 'No wall render plans found.' }
$CheckedHashes = @{}
function Assert-ContentHash([string]$RelativePath, [string]$ExpectedHash) {
    $Path = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    if (-not $Path.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Render plan path escapes project: $RelativePath"
    }
    if (-not $CheckedHashes.ContainsKey($Path)) {
        $CheckedHashes[$Path] = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    if ($CheckedHashes[$Path] -ne $ExpectedHash) {
        throw "Stale wall render content: $RelativePath. Republish its derived wall render plan before packaging."
    }
}
foreach ($File in $Plans) {
    $Plan = Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $Key = $File.Name.Replace('.wall_render_plan.json', '')
    if ($Plan.map_key -ne $Key) { throw "Wall render map key mismatch: $Key" }
    Assert-ContentHash "assets/data/runtime/map_editor/$Key.runtime.json" $Plan.source_runtime_json_sha256
    foreach ($Entry in @($Plan.atlas_pages) + @($Plan.shadow_chunks)) {
        Assert-ContentHash ([string]$Entry.path).Replace('res://', '') $Entry.sha256
    }
    foreach ($Source in $Plan.source_image_sha256.PSObject.Properties) {
        Assert-ContentHash $Source.Name.Replace('res://', '') $Source.Value
    }
}
Write-Output "WALL_RENDER_BUILD_BINDINGS_PASS maps=$($Plans.Count) unique_files=$($CheckedHashes.Count)"
