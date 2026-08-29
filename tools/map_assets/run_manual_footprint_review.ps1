param(
    [string]$AssetPrefix = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (
    Resolve-Path (
        Join-Path $PSScriptRoot '..\..'
    )
).Path

$Candidates = @(
    (
        Join-Path `
            $RepoRoot `
            'tools\godot-4.7\Godot_v4.7-stable_win64.exe'
    ),
    (
        Join-Path `
            $RepoRoot `
            'tools\godot-4.7\Godot_v4.7-stable_win64_console.exe'
    )
)

$Godot = $null

foreach ($Candidate in $Candidates) {
    if (Test-Path -LiteralPath $Candidate) {
        $Godot = $Candidate
        break
    }
}

if (-not $Godot) {
    throw 'Godot 4.7 executable not found'
}

$GodotArgs = @(
    '--path',
    $RepoRoot,
    'res://tools/map_assets/manual_footprint_review.tscn'
)

if (-not [string]::IsNullOrWhiteSpace($AssetPrefix)) {
    $GodotArgs += '--'
    $GodotArgs += "--asset-prefix=$AssetPrefix"
}

& $Godot @GodotArgs

exit $LASTEXITCODE
