param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath
)

# Supplement verify_android_build.ps1 with this release's resource closure.
# This does not replace package/signature/build-info or device verification.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ApkPath).Path)

function Require-Entry([string]$Name) {
    $Entry = $Archive.GetEntry($Name)
    if ($null -eq $Entry -or $Entry.Length -le 0) {
        throw "R3 APK missing non-empty entry: $Name"
    }
    return $Entry
}

function Read-Entry([string]$Name) {
    $Entry = Require-Entry $Name
    $Reader = [IO.StreamReader]::new($Entry.Open())
    try { return $Reader.ReadToEnd().TrimEnd([char]0) }
    finally { $Reader.Dispose() }
}

try {
    $Scripts = @(
        'game_root', 'player', 'player_state', 'audio_runtime_service',
        'inventory_panel', 'warehouse_panel', 'shop_panel', 'item_detail_presenter',
        'item_drop_instance_rules', 'loot_visual_effect', 'loot_pickup',
        'monster_display_formatter', 'monster_overhead', 'enemy', 'summon_actor',
        'monster_source_poison_state',
        'caster_skill_sky_strike_visual_effect',
        'monster_ai_package/policy', 'monster_ai_package/path_search',
        'monster_ai_package/path_scheduler'
    )
    foreach ($Script in $Scripts) {
        $null = Require-Entry "assets/scripts/$Script.gdc"
    }
    foreach ($Data in @(
        'item_drop_instance_rules_v1.json', 'item_runtime_authority_v1.json',
        'monster_melee_ai_package_v3.json', 'monster_behavior_profiles.json',
        'monster_attack_range_policy_v1.json', 'runtime/canonical_monster_catalog.json'
    )) {
        $null = Require-Entry "assets/assets/data/$Data"
    }
    $Visuals = @(
        'art/items/service/hp910008/hp_enhanced_inventory.svg',
        'art/items/service/hp910008/hp_enhanced_ground.svg',
        'ui/monster_markers/elite_skull.svg',
        'ui/monster_markers/boss_horned_gold_skull.svg'
    )
    foreach ($Visual in $Visuals) {
        $Import = Read-Entry "assets/assets/$Visual.import"
        $Match = [regex]::Match($Import, 'path="res://([^"\r\n]+\.ctex)"')
        if (-not $Match.Success) { throw "R3 SVG has no compiled texture: $Visual" }
        $null = Require-Entry ('assets/' + $Match.Groups[1].Value)
    }
    $Authority = (Read-Entry 'assets/assets/data/item_runtime_authority_v1.json') | ConvertFrom-Json
    $Items = @($Authority.newItems | Where-Object { [int]$_.itemId -eq 910008 })
    if ($Items.Count -ne 1) { throw 'R3 APK requires one exact item 910008' }
    $Art = $Items[0].art
    if ($Art.inventoryIcon.path -cne 'res://assets/art/items/service/hp910008/hp_enhanced_inventory.svg' -or
        $Art.stateIcon.path -cne $Art.inventoryIcon.path -or
        $Art.groundIcon.path -cne 'res://assets/art/items/service/hp910008/hp_enhanced_ground.svg') {
        throw 'R3 APK item 910008 art binding mismatch'
    }
    $Catalog = (Read-Entry 'assets/assets/data/runtime/canonical_monster_catalog.json') | ConvertFrom-Json
    foreach ($MonsterId in @(50, 42, 145, 186, 62, 174, 150, 152, 206)) {
        $Entry = $Catalog.entries_by_id.PSObject.Properties[[string]$MonsterId].Value
        if ($Entry.combat.behavior_profile.attackDelivery.kind -cne 'physical_projectile') {
            throw "R3 APK canonical monster $MonsterId projectile mapping missing"
        }
    }
    foreach ($MonsterId in @(220, 222, 224)) {
        $Entry = $Catalog.entries_by_id.PSObject.Properties[[string]$MonsterId].Value
        if ($Entry.combat.behavior_profile.attackDelivery.kind -cne 'target_magic') {
            throw "R3 APK canonical monster $MonsterId target-magic mapping missing"
        }
    }
    foreach ($MonsterId in 226..234) {
        $Entry = $Catalog.entries_by_id.PSObject.Properties[[string]$MonsterId].Value
        $Enabled = $Entry.combat.behavior_profile.combatEnabled
        if ($Enabled -isnot [bool] -or $Enabled) {
            throw "R3 APK canonical monster $MonsterId noncombat gate missing"
        }
    }
    Write-Output "R3_APK_RESOURCE_CLOSURE_PASS scripts=$($Scripts.Count) svg_import_closures=$($Visuals.Count)"
} finally {
    $Archive.Dispose()
}
