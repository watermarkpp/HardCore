$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Administrator\Documents\HardCore'

$doc = Get-Content 'outputs\tmp_loot_sheet\loot_sheet_parsed.json' -Raw | ConvertFrom-Json
$db = Get-Content 'assets\data\drop\dpv2_direct_baseline_v2.json' -Raw | ConvertFrom-Json
$equ = Get-Content 'assets\data\equipment_attribute_master.json' -Raw | ConvertFrom-Json
$dst = "$env:TEMP\xlsx_baolv"
[xml]$ss = Get-Content "$dst\xl\sharedStrings.xml" -Raw -Encoding UTF8
$strings = @($ss.sst.si | ForEach-Object { if ($_.t) { $_.t } else { (($_.r | ForEach-Object { $_.t }) -join '') } })
[xml]$s1 = Get-Content "$dst\xl\worksheets\sheet1.xml" -Raw -Encoding UTF8
$dirMap = @{}
foreach ($row in $s1.worksheet.sheetData.row) {
    if ([int]$row.r -le 3) { continue }
    $cells = @{}
    foreach ($c in $row.c) { $col = $c.r -replace '\d',''; $v = $c.v; if ($c.t -eq 's') { if ($v -ne $null) { $v = $strings[[int]$v] } }; $cells[$col] = "$v" }
    if ($cells['A'] -and $cells['B']) { $dirMap[$cells['A']] = $cells['B'] }
}

$baseById = @{}
foreach ($p in $db.profiles) { $baseById[[int]$p.canonical_monster_id] = $p }
$slotByUid = @{}
foreach ($p in $db.profiles) { foreach ($s2 in $p.slots) { $slotByUid[[string]$s2.slot_uid] = $s2 } }
$equByName = @{}
foreach ($rec in $equ.records) { if (-not $equByName.ContainsKey($rec.name)) { $equByName[$rec.name] = $rec.itemId } }

function Rate-Fraction($row) {
    $f = "$($row.rate_formula)"; $v = "$($row.rate_value)"
    if ($f -match '^=?(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)$') {
        $n = [double]$Matches[1]; $d = [double]$Matches[2]
        if ($d -gt 0 -and $n -gt 0 -and $n -le $d) { return @([long]$n, [long]$d) }
    }
    if ($v -match '^\d') {
        $x = [double]$v
        if ($x -gt 0 -and $x -le 1) {
            for ($d = 2; $d -le 100000; $d++) {
                $n = [Math]::Round($x * $d)
                if ($n -ge 1 -and [Math]::Abs($x - $n / $d) -lt 1e-12) { return @([long]$n, [long]$d) }
            }
        }
    }
    return $null
}

$monstersOut = New-Object System.Collections.Generic.List[object]
$stat = @{ slots = 0; fromBaseline = 0; newEquip = 0; itemIdOverridden = 0; missingUid = 0 }
$newSeqByMid = @{}
foreach ($s in $doc.sheets) {
    $idStr = $dirMap[$s.monster]
    if ($idStr -notmatch '^\d+$') { continue }
    $mid = [int]$idStr
    $slotsOut = New-Object System.Collections.Generic.List[object]
    foreach ($r in $s.rows) {
        $slotRaw = "$($r.slot_raw)"
        $frac = Rate-Fraction $r
        if (-not $frac) { continue }
        $tn = [long]$frac[0]; $td = [long]$frac[1]
        $isGold = ("$($r.type)" -eq '金币')
        $rowItem = "$($r.item)"
        # expand to concrete slot uids
        $uids = New-Object System.Collections.Generic.List[string]
        $isNew = $false
        if ($slotRaw -match '^([\w\.]+) 等(\d+)个独立槽$') {
            $first = $Matches[1]; $n = [int]$Matches[2]
            if ($first -match '^(.*\.slot_)(\d+)$') {
                $prefix = $Matches[1]; $num = [int]$Matches[2]
                for ($i = 0; $i -lt $n; $i++) {
                    $cand = $prefix + ($num + $i).ToString('D3')
                    if ($slotByUid.ContainsKey($cand)) { $uids.Add($cand) }
                }
            }
            if ($uids.Count -eq 0) { $uids.Add($first) }
        } elseif ($slotRaw) {
            $uids.Add(($slotRaw -replace '\s+等.*$',''))
        } else {
            # Rows without a slot uid are NEW equipment slots. Exception: the
            # v81 fate_blade row carries a real slot uid in column H even though
            # it sits in the wrong monster sheet; rows whose uid resolves to a
            # baseline slot are handled by the normal path below.
            $isNew = $true
        }
        if ($isNew) {
            $itemId = -1
            if (-not $isGold) {
                $nameKey = ($rowItem -replace '\s*×\d+$','').Trim()
                if ($equByName.ContainsKey($nameKey)) { $itemId = [int]$equByName[$nameKey] }
            }
            if (-not $newSeqByMid.ContainsKey($mid)) { $newSeqByMid[$mid] = 0 }
            $newSeqByMid[$mid]++
            $slotsOut.Add([ordered]@{
                slot_uid = "dpv2.user.sheet.m$mid.slot_n$($newSeqByMid[$mid].ToString('D3'))"
                canonical_item_id = $itemId
                final_numerator = $tn; final_denominator = $td
                gold_amount = $(if ($isGold) { [long]$r.gold } else { $null })
                overflow_priority = 300; protected_drop = $false
                origin = "new_equip"; source_sheet_row = [int]$r.row
            })
            $stat.slots++; $stat.newEquip++
            continue
        }
        foreach ($uid in $uids) {
            $base = $slotByUid[$uid]
            if (-not $base) {
                # v81 user-addition slots live outside the direct baseline;
                # the sheet row supplies their final rate, the v81 contract
                # supplies monster/item identity.
                if ($uid -match '^dpv2\.user\.v81\.m(\d+)\.fate_blade$') {
                    $slotsOut.Add([ordered]@{
                        slot_uid = $uid
                        canonical_item_id = 110
                        final_numerator = $tn; final_denominator = $td
                        gold_amount = $null
                        overflow_priority = 600
                        protected_drop = $false
                        origin = "v81_fate_blade"; source_sheet_row = [int]$r.row
                    })
                    $stat.slots++; $stat.fromBaseline++
                } else { $stat.missingUid++ }
                continue
            }
            # slot identity (monster + item) always comes from the baseline slot
            # the uid belongs to; the sheet only supplies the final rate (and
            # gold amount). Merged rows carry one item name for many slots, so
            # the table B column never overrides merged slots.
            $itemId = [int]$base.canonical_item_id
            if ($isGold) { $itemId = -1 }
            $slotsOut.Add([ordered]@{
                slot_uid = $uid
                canonical_item_id = $itemId
                final_numerator = $tn; final_denominator = $td
                gold_amount = $(if ($isGold) { [long]$r.gold } elseif ($base.gold_amount) { $null } else { $null })
                overflow_priority = [int]$base.overflow_priority
                protected_drop = [bool]$base.protected_drop
                origin = "sheet_row"; source_sheet_row = [int]$r.row
            })
            $stat.slots++; $stat.fromBaseline++
        }
    }
    $monstersOut.Add([ordered]@{
        monster_id = $mid
        monster_name = $s.monster
        slots = $slotsOut
    })
}

$out = [ordered]@{
    schema = "hardcore.dpv2.user_loot_sheet_authority.v1"
    authority_id = "dpv2.user_loot_sheet.v1"
    status = "PENDING_ACTIVATION_PREVIEW"
    source = @{
        sheet_file = "HardCore_怪物爆率分表.xlsx"
        sheet_sha256 = (Get-FileHash "$env:USERPROFILE\Desktop\HardCore_怪物爆率分表.xlsx" -Algorithm SHA256).Hash
        generated_at = (Get-Date).ToString('o')
    }
    summary = @{
        monsters = $monstersOut.Count
        slots = $stat.slots
        from_baseline_slots = $stat.fromBaseline
        new_equipment_slots = $stat.newEquip
        item_id_overridden_from_table = $stat.itemIdOverridden
        missing_baseline_uid = $stat.missingUid
    }
    monsters = $monstersOut
}
$outDir = 'C:\Users\Administrator\Documents\HardCore\outputs\tmp_loot_sheet'
[System.IO.File]::WriteAllText("$outDir\dpv2_user_loot_sheet_authority_v1.PREVIEW.json", ($out | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
"GENERATED: monsters=$($monstersOut.Count) slots=$($stat.slots) fromBaseline=$($stat.fromBaseline) newEquip=$($stat.newEquip) itemIdOverridden=$($stat.itemIdOverridden) missingUid=$($stat.missingUid)"
