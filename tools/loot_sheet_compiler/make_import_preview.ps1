$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Administrator\Documents\HardCore'
$auth = Get-Content 'outputs\tmp_loot_sheet\dpv2_user_loot_sheet_authority_v1.json' -Raw | ConvertFrom-Json
$eff = Get-Content 'assets\data\drop\dpv2_single_player_effective_probability_v1.json' -Raw | ConvertFrom-Json
$cat = Get-Content 'assets\data\service_item_catalog.json' -Raw | ConvertFrom-Json
$cls = Get-Content 'assets\data\runtime\canonical_monster_catalog.json' -Raw | ConvertFrom-Json
$kindById = @{}
foreach ($it in $cat.runtimeItems) { $kindById[[int]$it.itemId] = [string]$it.kind }
$clsById = @{}
foreach ($k in $cls.entries_by_id.PSObject.Properties.Name) { $clsById[[int]$k] = [string]$cls.entries_by_id.$k.classification }
$ledger = @{}
foreach ($rec in $eff.records) { $ledger[[string]$rec.slot_uid] = $rec }
function Denom-M([int]$itemId, [string]$c) {
    if ($c -eq 'ordinary') { if ($itemId -ge 910001 -and $itemId -le 910006) { return 6L }; if ($itemId -gt 0 -and $kindById[$itemId] -eq 'equipment') { return 3L }; return 1L }
    if ($c -eq 'elite' -or $c -eq 'boss') { if ($itemId -eq 920014 -or $itemId -eq 920016) { return 2L } }
    return 1L
}
$chg = 0; $same = 0; $newSlots = 0; $goldRows = 0; $goldChanged = 0
foreach ($m in $auth.monsters) {
    $c = $clsById[$m.monster_id]
    foreach ($s in $m.slots) {
        if ($s.origin -eq 'new_equip') { $newSlots++; continue }
        if ($s.gold_amount) { $goldRows++; continue }
        $rec = $ledger[$s.slot_uid]
        if (-not $rec) { continue }
        $mult = Denom-M ([int]$s.canonical_item_id) $c
        $en = [double]$rec.effective_numerator; $ed = [double]$rec.effective_denominator * $mult
        $tn = [double]$s.final_numerator; $td = [double]$s.final_denominator
        if ([Math]::Abs($tn * $ed - $en * $td) -lt 0.5) { $same++ } else { $chg++ }
    }
}
# baseline coverage diff
$db = Get-Content 'assets\data\drop\dpv2_direct_baseline_v2.json' -Raw | ConvertFrom-Json
$authUids = @{}
foreach ($m in $auth.monsters) { foreach ($s in $m.slots) { if ($s.origin -ne 'new_equip' -and $s.origin -ne 'v81_fate_blade') { $authUids[$s.slot_uid] = $true } } }
$coveredBaseline = 0; $deleted = @{}
foreach ($p in $db.profiles) { foreach ($s2 in $p.slots) { if ($authUids.ContainsKey([string]$s2.slot_uid)) { $coveredBaseline++ } else { $deleted[[string]$s2.slot_uid] = $true } } }
$preview = [ordered]@{
    authority = [ordered]@{ status = $auth.status; monsters = $auth.monsters.Count; total_slots = ($auth.monsters | ForEach-Object { $_.slots.Count } | Measure-Object -Sum).Sum }
    probability_changes_vs_old_chain = $chg
    probability_same_vs_old_chain = $same
    new_equipment_slots = $newSlots
    gold_rows = $goldRows
    baseline_slots_covered = $coveredBaseline
    baseline_slots_removed_diff = $deleted.Count
    empty_profiles = @('食人花(30)','蝎子(45)','毒蜘蛛(18)','羊(96)','狼(100)')
    excluded_residue = 7
    live_spawn_coverage = [ordered]@{ live_spawn_monsters = 86; live_not_in_sheet = 0; sheet_not_live = 40 }
}
[System.IO.File]::WriteAllText('C:\Users\Administrator\Documents\HardCore\outputs\tmp_loot_sheet\import_preview.json', ($preview | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$preview | ConvertTo-Json -Depth 5
