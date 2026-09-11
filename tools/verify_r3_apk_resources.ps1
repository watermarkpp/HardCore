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
        'game_root', 'player', 'player_state', 'audio_runtime_service', 'device_lab_patch_bootstrap',
        'inventory_panel', 'warehouse_panel', 'shop_panel', 'item_detail_presenter',
        'item_drop_instance_rules', 'loot_visual_effect', 'loot_pickup',
        'monster_display_formatter', 'monster_overhead', 'enemy', 'summon_actor',
        'monster_source_poison_state', 'runtime_combat_spatial_index',
        'circular_touch_button', 'virtual_joystick',
        'caster_skill_sky_strike_visual_effect',
        'monster_ai_package/policy', 'monster_ai_package/path_search',
        'monster_ai_package/path_scheduler', 'monster_ai_package/delivery_geometry',
        'ui_selection_dismiss_guard', 'audio_preferences', 'ui_runtime_layout_overrides',
        'touch_scroll_support', 'character_select', 'gothic_confirmation_panel',
        'system_menu_panel', 'equipment_character_preview', 'loading_transition_overlay',
        'monster_target_magic_effect', 'layers/runtime/combat_runtime_service',
        'item_detail_docked_presenter', 'ui_item_detail_dock', 'ui_item_selection_visual'
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
    $SpecialFamilies = @{
        directional_spit_map = @(18, 103, 104, 185, 146)
        gas_adjacent = @(46, 60, 128, 168)
        line_magic = @(79)
        mixed_target_tile = @(76, 77, 160, 235, 236, 239)
        guard_direct_projectile = @(194)
    }
    foreach ($Kind in $SpecialFamilies.Keys) {
        foreach ($MonsterId in $SpecialFamilies[$Kind]) {
            $Entry = $Catalog.entries_by_id.PSObject.Properties[[string]$MonsterId].Value
            if ($Entry.combat.behavior_profile.attackDelivery.kind -cne $Kind) {
                throw "R3 APK canonical monster $MonsterId special-delivery mapping mismatch"
            }
        }
    }
    foreach ($MonsterId in 226..234) {
        $Entry = $Catalog.entries_by_id.PSObject.Properties[[string]$MonsterId].Value
        $Enabled = $Entry.combat.behavior_profile.combatEnabled
        if ($Enabled -isnot [bool] -or $Enabled) {
            throw "R3 APK canonical monster $MonsterId noncombat gate missing"
        }
    }
    # UI R5 + M30 closure additions (2026-09-11): layout contract, HUD runtime
    # textures and character skill icons must ship with their compiled imports.
    $LayoutEntry = Require-Entry 'assets/assets/data/ui/manual_layout_overrides.json'
    $LayoutStream = $LayoutEntry.Open()
    try {
        $LayoutBytes = [byte[]]::new($LayoutEntry.Length)
        $Read = 0
        while ($Read -lt $LayoutBytes.Length) {
            $Before = $Read
            $Read += $LayoutStream.Read($LayoutBytes, $Read, $LayoutBytes.Length - $Read)
            if ($Read -le $Before) {
                throw "UI R5 layout contract entry is truncated: read $Read of $($LayoutBytes.Length) bytes"
            }
        }
    } finally {
        $LayoutStream.Dispose()
    }
    $LayoutHash = [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash($LayoutBytes)).Replace('-', '')
    if ($LayoutHash -cne 'DDFDBFC3418D8286EE6264AC24FB725B5BB0B5E1285410EE62CC31837B349496') {
        throw "UI R5 layout contract hash mismatch in APK: $LayoutHash"
    }
    $HudTextures = @(
        'ui/gothic_hud/v2/runtime/target_bar_v2.png',
        'ui/gothic_hud/v2/runtime/utility_stack_v2.png',
        'ui/gothic_hud/v2/runtime/joystick_v2.png',
        'ui/gothic_hud/v2/runtime/bottom_chassis_v2.png',
        'ui/gothic_hud/v2/runtime/round_action_frame_v3.png',
        'art/characters/taoist/skill_icons/defense.png',
        'art/characters/taoist/skill_icons/magic_defense.png',
        'art/monsters/effects/monster_target_magic/cow_mage_thunder_magic2.png'
    )
    foreach ($Texture in $HudTextures) {
        $Import = Read-Entry "assets/assets/$Texture.import"
        $Match = [regex]::Match($Import, 'path="res://([^"\r\n]+\.ctex)"')
        if (-not $Match.Success) { throw "UI R5 texture has no compiled import: $Texture" }
        $null = Require-Entry ('assets/' + $Match.Groups[1].Value)
    }
    $null = Require-Entry 'assets/assets/ui/gothic_hud/v2/runtime/circular_icon_mask.gdshader'
    Write-Output "R3_APK_RESOURCE_CLOSURE_PASS scripts=$($Scripts.Count) svg_import_closures=$($Visuals.Count) ui_r5_textures=$($HudTextures.Count)"
} finally {
    $Archive.Dispose()
}
