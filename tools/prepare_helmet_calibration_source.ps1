param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,

    [Parameter(Mandatory = $true)]
    [int]$ItemId,

    [Parameter(Mandatory = $true)]
    [string]$VisualAssetId,

    [Parameter(Mandatory = $true)]
    [string]$DisplayName,

    [string]$SourceRevision = 'user-transparent-v1'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ResolvedSource = (Resolve-Path -LiteralPath $SourcePng).Path
$OutputRelative = "outputs/helmet_calibration_sources/item_$ItemId"
$OutputDirectory = Join-Path $ProjectRoot ($OutputRelative.Replace('/', '\'))
$DirectionsDirectory = Join-Path $OutputDirectory 'directions'
$SourceCopy = Join-Path $OutputDirectory 'source_8dir.png'
$ManifestPath = Join-Path $OutputDirectory 'active_target.json'
$Directions = @('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW')

New-Item -ItemType Directory -Path $DirectionsDirectory -Force | Out-Null
Copy-Item -LiteralPath $ResolvedSource -Destination $SourceCopy -Force

$Sheet = [System.Drawing.Bitmap]::new($SourceCopy)
try {
    if ($Sheet.Width -lt 8 -or $Sheet.Height -lt 4) {
        throw "Source PNG is too small for an eight-direction 4x2 sheet."
    }
    if (-not [System.Drawing.Image]::IsAlphaPixelFormat($Sheet.PixelFormat)) {
        throw "Source PNG must contain an alpha channel."
    }

    $PreparedFiles = [ordered]@{}
    $PreparedHashes = [ordered]@{}
    for ($Index = 0; $Index -lt 8; $Index++) {
        $Column = $Index % 4
        $Row = [Math]::Floor($Index / 4)
        $X0 = [Math]::Round($Column * $Sheet.Width / 4.0)
        $X1 = [Math]::Round(($Column + 1) * $Sheet.Width / 4.0)
        $Y0 = [Math]::Round($Row * $Sheet.Height / 2.0)
        $Y1 = [Math]::Round(($Row + 1) * $Sheet.Height / 2.0)

        $MinX = $X1
        $MinY = $Y1
        $MaxX = $X0 - 1
        $MaxY = $Y0 - 1
        for ($Y = $Y0; $Y -lt $Y1; $Y++) {
            for ($X = $X0; $X -lt $X1; $X++) {
                if ($Sheet.GetPixel($X, $Y).A -eq 0) {
                    continue
                }
                $MinX = [Math]::Min($MinX, $X)
                $MinY = [Math]::Min($MinY, $Y)
                $MaxX = [Math]::Max($MaxX, $X)
                $MaxY = [Math]::Max($MaxY, $Y)
            }
        }
        if ($MaxX -lt $MinX -or $MaxY -lt $MinY) {
            throw "Direction $($Directions[$Index]) contains no visible pixels."
        }

        $Bounds = [System.Drawing.Rectangle]::new(
            $MinX,
            $MinY,
            $MaxX - $MinX + 1,
            $MaxY - $MinY + 1
        )
        $Cutout = $Sheet.Clone(
            $Bounds,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            $Direction = $Directions[$Index]
            $DirectionPath = Join-Path $DirectionsDirectory "$Direction.png"
            $Cutout.Save(
                $DirectionPath,
                [System.Drawing.Imaging.ImageFormat]::Png
            )
            $PreparedFiles[$Direction] = (
                "res://$OutputRelative/directions/$Direction.png"
            )
            $PreparedHashes[$Direction] = (
                Get-FileHash -LiteralPath $DirectionPath -Algorithm SHA256
            ).Hash.ToLowerInvariant()
        }
        finally {
            $Cutout.Dispose()
        }
    }
}
finally {
    $Sheet.Dispose()
}

$Manifest = [ordered]@{
    schemaVersion = 2
    contractId = 'equipment.world_helmet.calibration.active_target.v1'
    itemId = $ItemId
    visualAssetId = $VisualAssetId
    displayName = $DisplayName
    sourceRevision = $SourceRevision
    sourceSheet = "res://$OutputRelative/source_8dir.png"
    sourceSheetSha256 = (
        Get-FileHash -LiteralPath $SourceCopy -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    sourceGrid = @(4, 2)
    sourceDirectionOrder = $Directions
    sourceMatte = 'transparent_alpha_user_authored'
    sourceResizeFilter = 'lanczos_from_original_once_on_finalize'
    preparedDirectionFiles = $PreparedFiles
    preparedDirectionSha256 = $PreparedHashes
    directionPolicy = 'canonical_order_only_no_direction_scan'
    workflowMode = 'lossless_draft_then_finalize'
}

$ManifestJson = $Manifest | ConvertTo-Json -Depth 8
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($ManifestPath, $ManifestJson + "`n", $Utf8NoBom)
Write-Output $ManifestPath
