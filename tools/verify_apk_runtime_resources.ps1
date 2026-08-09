param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [Parameter(Mandatory = $true)]
    [string]$BaselineApkPath,

    [int]$ExpectedVersionCode = 0,

    [string]$ExpectedVersionName = "",

    [string]$ExpectedCommit = "",

    [switch]$RequireRuntimeChangesFromBaseline
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Resolve-ExistingFile {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-ArchiveEntry {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$EntryName,
        [string]$ArchiveLabel
    )

    $Entry = $Archive.GetEntry($EntryName)
    if ($null -eq $Entry -or $Entry.Length -le 0) {
        throw "$ArchiveLabel is missing a non-empty entry: $EntryName"
    }
    return $Entry
}

function Read-ArchiveText {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$EntryName,
        [string]$ArchiveLabel
    )

    $Entry = Get-ArchiveEntry -Archive $Archive -EntryName $EntryName -ArchiveLabel $ArchiveLabel
    $Reader = New-Object System.IO.StreamReader($Entry.Open(), [System.Text.Encoding]::UTF8, $true)
    try {
        return $Reader.ReadToEnd().TrimEnd([char]0)
    }
    finally {
        $Reader.Dispose()
    }
}

function Get-ArchiveEntrySha256 {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$EntryName,
        [string]$ArchiveLabel
    )

    $Entry = Get-ArchiveEntry -Archive $Archive -EntryName $EntryName -ArchiveLabel $ArchiveLabel
    $Stream = $Entry.Open()
    $Hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Bytes = $Hasher.ComputeHash($Stream)
        return ([System.BitConverter]::ToString($Bytes) -replace "-", "")
    }
    finally {
        $Hasher.Dispose()
        $Stream.Dispose()
    }
}

function Assert-ChangedFromBaseline {
    param(
        [System.IO.Compression.ZipArchive]$CurrentArchive,
        [System.IO.Compression.ZipArchive]$BaselineArchive,
        [string]$EntryName
    )

    $CurrentHash = Get-ArchiveEntrySha256 -Archive $CurrentArchive -EntryName $EntryName -ArchiveLabel "current APK"
    if (-not $RequireRuntimeChangesFromBaseline) {
        return
    }
    $BaselineEntry = $BaselineArchive.GetEntry($EntryName)
    if ($null -eq $BaselineEntry -or $BaselineEntry.Length -le 0) {
        return
    }
    $BaselineHash = Get-ArchiveEntrySha256 -Archive $BaselineArchive -EntryName $EntryName -ArchiveLabel "baseline APK"
    if ($CurrentHash -eq $BaselineHash) {
        throw "Critical APK entry is unchanged from the baseline APK: $EntryName"
    }
}

function Convert-ResourcePathToArchiveEntry {
    param([string]$ResourcePath)

    if ([string]::IsNullOrWhiteSpace($ResourcePath) -or -not $ResourcePath.StartsWith("res://")) {
        throw "Expected a res:// resource path, got: $ResourcePath"
    }
    return "assets/" + $ResourcePath.Substring(6).Replace("\", "/")
}

function Assert-ImportedTexture {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$ResourcePath,
        [string]$ArchiveLabel
    )

    $SourceEntryName = Convert-ResourcePathToArchiveEntry -ResourcePath $ResourcePath
    $ImportEntryName = "$SourceEntryName.import"
    $ImportText = Read-ArchiveText -Archive $Archive -EntryName $ImportEntryName -ArchiveLabel $ArchiveLabel
    $Match = [regex]::Match($ImportText, 'path="res://([^"]+\.ctex)"')
    if (-not $Match.Success) {
        throw "$ArchiveLabel import entry has no compiled texture path: $ImportEntryName"
    }
    $CompiledEntryName = "assets/" + $Match.Groups[1].Value.Replace("\", "/")
    [void](Get-ArchiveEntry -Archive $Archive -EntryName $CompiledEntryName -ArchiveLabel $ArchiveLabel)
    return [pscustomobject]@{
        ImportEntry = $ImportEntryName
        CompiledEntry = $CompiledEntryName
    }
}

$ResolvedApkPath = Resolve-ExistingFile -Path $ApkPath -Label "Current APK"
$ResolvedBaselineApkPath = Resolve-ExistingFile -Path $BaselineApkPath -Label "Baseline APK"
if ($ResolvedApkPath -eq $ResolvedBaselineApkPath) {
    throw "Current APK and baseline APK must be different files."
}

$CurrentArchive = [System.IO.Compression.ZipFile]::OpenRead($ResolvedApkPath)
$BaselineArchive = [System.IO.Compression.ZipFile]::OpenRead($ResolvedBaselineApkPath)

try {
    $CompiledScripts = @(
        "assets/scripts/equipment_character_preview.gdc",
        "assets/scripts/inventory_panel.gdc",
        "assets/scripts/character_select.gdc",
        "assets/scripts/player_state.gdc",
        "assets/scripts/hud.gdc",
        "assets/scripts/skill_panel.gdc",
        "assets/scripts/game_root.gdc",
        "assets/scripts/skills/skill_runtime_router.gdc",
        "assets/scripts/skills/runtimes/warrior_skill_runtime.gdc",
        "assets/scripts/skills/runtimes/wizard_skill_runtime.gdc",
        "assets/scripts/skills/runtimes/taoist_skill_runtime.gdc",
        "assets/scripts/caster_skill_animation_player.gdc"
    )
    foreach ($EntryName in $CompiledScripts) {
        Assert-ChangedFromBaseline -CurrentArchive $CurrentArchive -BaselineArchive $BaselineArchive -EntryName $EntryName
    }

    $BuildInfoEntry = "assets/assets/generated/build_info.json"
    $BuildInfo = Read-ArchiveText -Archive $CurrentArchive -EntryName $BuildInfoEntry -ArchiveLabel "current APK" | ConvertFrom-Json
    if ($BuildInfo.git_dirty -ne $false) {
        throw "APK build-info must record git_dirty=false."
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $BuildInfo.git_head -ne $ExpectedCommit) {
        throw "APK build-info commit '$($BuildInfo.git_head)' does not match expected commit '$ExpectedCommit'."
    }
    if ($ExpectedVersionCode -gt 0 -and [int]$BuildInfo.version_code -ne $ExpectedVersionCode) {
        throw "APK build-info version code '$($BuildInfo.version_code)' does not match '$ExpectedVersionCode'."
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersionName) -and $BuildInfo.version_name -ne $ExpectedVersionName) {
        throw "APK build-info version name '$($BuildInfo.version_name)' does not match '$ExpectedVersionName'."
    }

    $WorldHelmetPolicyEntry = "assets/assets/data/equipment_world_helmet_runtime_policy.json"
    Assert-ChangedFromBaseline -CurrentArchive $CurrentArchive -BaselineArchive $BaselineArchive -EntryName $WorldHelmetPolicyEntry
    $WorldHelmetPolicy = Read-ArchiveText -Archive $CurrentArchive -EntryName $WorldHelmetPolicyEntry -ArchiveLabel "current APK" | ConvertFrom-Json
    if ($WorldHelmetPolicy.contractId -ne "equipment.world_helmet.runtime_visibility.v1") {
        throw "Unexpected world helmet runtime contract ID."
    }
    foreach ($PropertyName in @("visible", "frontLayerVisible", "backLayerVisible", "headOcclusionMaskEnabled")) {
        if ($WorldHelmetPolicy.worldHelmet.$PropertyName -ne $false) {
            throw "World helmet runtime policy must keep $PropertyName=false."
        }
    }
    if ($WorldHelmetPolicy.hairAppearance.sex -ne "male" -or
        [int]$WorldHelmetPolicy.hairAppearance.appearance -ne 2 -or
        [int]$WorldHelmetPolicy.hairAppearance.sourceBlock -ne 4) {
        throw "World hair must use the primary male Hair.wil block 4 contract."
    }

    $RequiredHairActions = @("idle", "walk", "attack", "cast", "hit", "death")
    $HairTextureCount = 0
    foreach ($Action in $RequiredHairActions) {
        $ActionNode = $WorldHelmetPolicy.hairAppearance.actions.$Action
        if ($null -eq $ActionNode) {
            throw "World hair contract is missing action: $Action"
        }
        $TextureEntries = Assert-ImportedTexture -Archive $CurrentArchive -ResourcePath ([string]$ActionNode.path) -ArchiveLabel "current APK"
        Assert-ChangedFromBaseline -CurrentArchive $CurrentArchive -BaselineArchive $BaselineArchive -EntryName $TextureEntries.ImportEntry
        Assert-ChangedFromBaseline -CurrentArchive $CurrentArchive -BaselineArchive $BaselineArchive -EntryName $TextureEntries.CompiledEntry
        $HairTextureCount++
    }

    $PresentationModesEntry = "assets/assets/data/equipment_paper_doll_presentation_modes.json"
    [void](Get-ArchiveEntry -Archive $CurrentArchive -EntryName $PresentationModesEntry -ArchiveLabel "current APK")
    $PresentationModes = Read-ArchiveText -Archive $CurrentArchive -EntryName $PresentationModesEntry -ArchiveLabel "current APK" | ConvertFrom-Json
    if ($PresentationModes.modes.classic_avatar.contractId -ne "equipment.paper_doll.avatar_only.v1") {
        throw "Unexpected classic paper-doll contract ID."
    }
    $PaperDollBase = Assert-ImportedTexture -Archive $CurrentArchive -ResourcePath ([string]$PresentationModes.modes.classic_avatar.avatarOnly.base.path) -ArchiveLabel "current APK"
    $PaperDollHair = Assert-ImportedTexture -Archive $CurrentArchive -ResourcePath ([string]$PresentationModes.modes.classic_avatar.avatarOnly.hair.path) -ArchiveLabel "current APK"

    $HeadPatchContractEntry = "assets/assets/data/equipment_classic_avatar_head_patches.json"
    Assert-ChangedFromBaseline -CurrentArchive $CurrentArchive -BaselineArchive $BaselineArchive -EntryName $HeadPatchContractEntry
    $HeadPatchContract = Read-ArchiveText -Archive $CurrentArchive -EntryName $HeadPatchContractEntry -ArchiveLabel "current APK" | ConvertFrom-Json
    if ($HeadPatchContract.contractId -ne "equipment.paper_doll.classic_flattened_head_patch.v1") {
        throw "Unexpected paper-doll head patch contract ID."
    }
    $HeadPatchCount = 0
    foreach ($ItemProperty in $HeadPatchContract.itemsById.PSObject.Properties) {
        $Patch = $ItemProperty.Value.flattenedHeadPatch
        if ($null -eq $Patch -or [string]::IsNullOrWhiteSpace([string]$Patch.path)) {
            throw "Paper-doll helmet $($ItemProperty.Name) has no flattened head patch."
        }
        [void](Assert-ImportedTexture -Archive $CurrentArchive -ResourcePath ([string]$Patch.path) -ArchiveLabel "current APK")
        $HeadPatchCount++
    }
    if ($HeadPatchCount -ne 12) {
        throw "Expected 12 formal paper-doll helmet head patches, found $HeadPatchCount."
    }

    $SkillVisualContractEntry = "assets/assets/data/caster_skill_visuals.json"
    Assert-ChangedFromBaseline -CurrentArchive $CurrentArchive -BaselineArchive $BaselineArchive -EntryName $SkillVisualContractEntry
    $SkillVisualContract = Read-ArchiveText -Archive $CurrentArchive -EntryName $SkillVisualContractEntry -ArchiveLabel "current APK" | ConvertFrom-Json
    if ($SkillVisualContract.animationContract -ne "caster_skill_animation.v1") {
        throw "Unexpected caster skill animation contract ID."
    }

    $SkillFrameImports = @(
        $CurrentArchive.Entries |
            Where-Object {
                $_.FullName -match '^assets/assets/art/characters/caster_skill_frames/.+/frame_[0-9]+\.png\.import$' -and
                $_.Length -gt 0
            } |
            Sort-Object FullName
    )
    if ($SkillFrameImports.Count -ne 586) {
        throw "Expected 586 compiled caster skill frame imports, found $($SkillFrameImports.Count)."
    }
    foreach ($FrameImport in $SkillFrameImports) {
        $FrameResourcePath = "res://" + $FrameImport.FullName.Substring("assets/".Length, $FrameImport.FullName.Length - "assets/".Length - ".import".Length)
        [void](Assert-ImportedTexture -Archive $CurrentArchive -ResourcePath $FrameResourcePath -ArchiveLabel "current APK")
    }
    $SkillProbeTexture = Assert-ImportedTexture -Archive $CurrentArchive -ResourcePath "res://assets/art/characters/caster_skill_frames/teleport_arrival/direction_00/frame_00.png" -ArchiveLabel "current APK"
    Assert-ChangedFromBaseline -CurrentArchive $CurrentArchive -BaselineArchive $BaselineArchive -EntryName $SkillProbeTexture.ImportEntry
    Assert-ChangedFromBaseline -CurrentArchive $CurrentArchive -BaselineArchive $BaselineArchive -EntryName $SkillProbeTexture.CompiledEntry

    $ApkHash = (Get-FileHash -LiteralPath $ResolvedApkPath -Algorithm SHA256).Hash
    $BaselineHash = (Get-FileHash -LiteralPath $ResolvedBaselineApkPath -Algorithm SHA256).Hash
    if ($ApkHash -eq $BaselineHash) {
        throw "Current APK hash is identical to the baseline APK."
    }

    Write-Output "APK_RUNTIME_RESOURCE_PROBE_PASS"
    Write-Output "CONTRACT=release.apk.runtime_resource_probe.v1"
    Write-Output "APK=$ResolvedApkPath"
    Write-Output "APK_SHA256=$ApkHash"
    Write-Output "BASELINE_APK=$ResolvedBaselineApkPath"
    Write-Output "BASELINE_SHA256=$BaselineHash"
    Write-Output "COMPILED_SCRIPTS_VERIFIED=$($CompiledScripts.Count)"
    Write-Output "BUILD_INFO_COMMIT=$($BuildInfo.git_head)"
    Write-Output "BUILD_INFO_VERSION=$($BuildInfo.version_name)"
    Write-Output "RUNTIME_CHANGE_COMPARISON=$($RequireRuntimeChangesFromBaseline.IsPresent)"
    if ($RequireRuntimeChangesFromBaseline) {
        Write-Output "COMPILED_SCRIPTS_CHANGED=$($CompiledScripts.Count)"
    }
    Write-Output "WORLD_HELMET_VISIBLE=false"
    Write-Output "MALE_HAIR_BLOCK=4"
    Write-Output "MALE_HAIR_ACTION_TEXTURES=$HairTextureCount"
    Write-Output "PAPER_DOLL_BASE_IMPORT=$($PaperDollBase.ImportEntry)"
    Write-Output "PAPER_DOLL_HAIR_IMPORT=$($PaperDollHair.ImportEntry)"
    Write-Output "PAPER_DOLL_HEAD_PATCHES=$HeadPatchCount"
    Write-Output "CASTER_SKILL_FRAME_IMPORTS=$($SkillFrameImports.Count)"
}
finally {
    $BaselineArchive.Dispose()
    $CurrentArchive.Dispose()
}
