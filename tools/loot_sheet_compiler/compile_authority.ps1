$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Administrator\Documents\HardCore'
$doc = Get-Content 'outputs\tmp_loot_sheet\loot_sheet_parsed.json' -Raw | ConvertFrom-Json
$db = Get-Content 'assets\data\drop\dpv2_direct_baseline_v2.json' -Raw | ConvertFrom-Json
$grp = Get-Content 'outputs\tmp_loot_sheet\row_to_full_slot_uid_map.json' -Raw | ConvertFrom-Json
$equ = Get-Content 'assets\data\equipment_attribute_master.json' -Raw | ConvertFrom-Json
$rv = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'evidence'

# workbook sha
$xlsxSha = (Get-FileHash "$env:USERPROFILE\Desktop\HardCore_怪物爆率分表.xlsx" -Algorithm SHA256).Hash
if ($xlsxSha -ne 'BC234FCA54286547B07F64731C9D0E3674AA19A703863C393C356CAF97005251') { throw "workbook sha mismatch: $xlsxSha" }

# --- 67 numeric whitelist: sheet+row+candidate must match parser output ---
$wl = @{}
foreach ($line in (Get-Content "$rv\02_数字爆率67行_分数重建候选.csv" -Encoding UTF8 | Select-Object -Skip 1)) {
    if (-not $line.Trim()) { continue }
    $f = $line -split ',', 0
    if ($f.Count -lt 6) { continue }
    $wl["$($f[0])|$($f[2].TrimStart('E'))"] = $f[5]
}
$whitelistVerified = 0; $whitelistFailed = @()
foreach ($s in $doc.sheets) { foreach ($r in $s.rows) {
    $f = "$($r.rate_formula)"
    if ($f -match '^=?\d') { continue }   # has formula
    $key = "$($s.monster)|$($r.row)"
    if (-not $wl.ContainsKey($key)) { $whitelistFailed += "UNLISTED-NUMERIC $key '$($r.item)'"; continue }
    $cand = $wl[$key]
    if ($cand -match '^(\d+)/(\d+)$') {
        $cn = [double]$Matches[1]; $cd = [double]$Matches[2]
        $v = "$($r.rate_value)"
        if ($v -match '^\d' -and [Math]::Abs($cn / $cd - [double]$v) -gt 1e-12) { $whitelistFailed += "VALUE-DIFF $key cand=$cand stored=$v" } else { $whitelistVerified++ }
    } else { $whitelistFailed += "BAD-CAND $key $cand" }
} }
"whitelist: verified=$whitelistVerified failed=$($whitelistFailed.Count)"
$whitelistFailed | Select-Object -First 5

# --- 41 new-item rows whitelist ---
$newRows = @{}
foreach ($line in (Get-Content "$rv\01_新增物品41行.csv" -Encoding UTF8 | Select-Object -Skip 1)) {
    if (-not $line.Trim()) { continue }
    $f = $line -split ',', 0
    if ($f.Count -lt 5) { continue }
    $newRows["$($f[0])|$($f[2])"] = $f[3]
}
$equByName = @{}
foreach ($rec in $equ.records) { if (-not $equByName.ContainsKey($rec.name)) { $equByName[$rec.name] = [int]$rec.itemId } }
$newResolved = 0; $newFailed = @()
foreach ($s in $doc.sheets) { foreach ($r in $s.rows) {
    if ("$($r.slot_raw)") { continue }
    $key = "$($s.monster)|$($r.row)"
    if (-not $newRows.ContainsKey($key)) { $newFailed += "ORPHAN-NOT-IN-WL $key '$($r.item)'"; continue }
    $name = $newRows[$key]
    if (-not $equByName.ContainsKey($name)) { $newFailed += "NO-ITEM-ID $key '$name'"; continue }
    $newResolved++
} }
"new rows: resolved=$newResolved failed=$($newFailed.Count)"
$newFailed | Select-Object -First 5

# --- sheet -> mid mapping from 07 full rows CSV (fallback: grouping, 04 empty) ---
$dirFromSheet = @{}
foreach ($line in (Get-Content "$rv\07_全部具名奖励4876行.csv" -Encoding UTF8 | Select-Object -Skip 1)) {
    if (-not $line.Trim()) { continue }
    $f = $line -split ',', 0
    if ($f.Count -lt 3) { continue }
    $mid = 0; if ($f[1] -match '^\d+$') { $mid = [int]$f[1] }
    if ($mid -gt 0) { $dirFromSheet[$f[0]] = $mid }
}
foreach ($line in (Get-Content "$rv\04_五张空表与七条残留.csv" -Encoding UTF8 | Select-Object -Skip 1)) {
    if (-not $line.Trim()) { continue }
    $f = $line -split ',', 0
    if ($f[2] -eq '整表' -and ($f[1] -match '^\d+$')) { $dirFromSheet[$f[0]] = [int]$f[1] }
}
$residueRows = @{}
foreach ($line in (Get-Content "$rv\04_五张空表与七条残留.csv" -Encoding UTF8 | Select-Object -Skip 1)) {
    if (-not $line.Trim()) { continue }
    $f = $line -split ',', 0
    if ($f[2] -match '^E(\d+)$') { $residueRows["$($f[0])|$($Matches[1])"] = $f[3] }
}

# --- compile authority ---
$slotByUid = @{}
foreach ($p in $db.profiles) { foreach ($s2 in $p.slots) { $slotByUid[[string]$s2.slot_uid] = $s2 } }
$grpByMid = @{}
foreach ($a in $grp.assigned) { $mk = [string]$a.mid; if (-not $grpByMid.ContainsKey($mk)) { $grpByMid[$mk] = @{} }; $grpByMid[$mk]["$($a.excelRow)"] = $a }

function Rate-Frac($row) {
    $f = "$($row.rate_formula)"
    if ($f -match '^=?(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)$') { return @([long]$Matches[1], [long]$Matches[2]) }
    $v = "$($row.rate_value)"
    if ($v -match '^\d') {
        $x = [double]$v
        for ($d = 2; $d -le 100000; $d++) {
            $n = [Math]::Round($x * $d)
            if ($n -ge 1 -and [Math]::Abs($x - $n / $d) -lt 1e-12) { return @([long]$n, [long]$d) }
        }
    }
    return $null
}

$monstersOut = New-Object System.Collections.Generic.List[object]
$stat = @{ named = 0; compiled = 0; gold = 0; newSlots = 0; fate = 0; emptySheets = @(); excludedResidue = 0 }
$newSeq = @{}
# RV15-J2: the compiled document must never contain the same slot_uid
# twice. The user sheet may legitimately repeat a draw twice (two rows,
# same item and odds); each row keeps its own slot, only the second
# occurrence gets a deterministic sheet-row suffix so both stay addressable.
$seenUids = @{}
$disambiguated = New-Object System.Collections.Generic.List[object]
function Resolve-Uid([string]$uid, [int]$sheetRow) {
    if (-not $seenUids.ContainsKey($uid)) {
        $seenUids[$uid] = $true
        return $uid
    }
    $disambiguated.Add([ordered]@{ original_uid = $uid; sheet_row = $sheetRow; new_uid = "$($uid)_r$($sheetRow)" })
    $seenUids["$($uid)_r$($sheetRow)"] = $true
    return "$($uid)_r$($sheetRow)"
}
foreach ($s in $doc.sheets) {
    $dir = if ($dirFromSheet.ContainsKey($s.monster)) { [int]$dirFromSheet[$s.monster] } else { 0 }
    $slotsOut = New-Object System.Collections.Generic.List[object]
    $hasAny = $false
    foreach ($r in $s.rows) {
        if ($residueRows.ContainsKey("$($s.monster)|$($r.row)")) { $stat.excludedResidue++; continue }
        $slotRaw = "$($r.slot_raw)"
        $frac = Rate-Frac $r
        if (-not $frac) { continue }
        $tn = [long]$frac[0]; $td = [long]$frac[1]
        $isGold = ("$($r.type)" -eq '金币')
        if ($slotRaw -match '^([\w\.]+) 等\d+个独立槽$') {
            $a = $null
            $mk = [string]$dir
            if ($grpByMid.ContainsKey($mk)) { $a = $grpByMid[$mk]["$($r.row)"] }
            if ($a -eq $null) { $stat.excludedResidue++; continue }
            foreach ($uid0 in ($a.slotUids -split '\|')) {
                $uid = Resolve-Uid $uid0 ([int]$r.row)
                $base = $slotByUid[$uid0]
                if (-not $base) { $stat.excludedResidue++; continue }
                $itemId = [int]$base.canonical_item_id
                $slotObj = [ordered]@{ slot_uid = $uid; final_numerator = $tn; final_denominator = $td; overflow_priority = [int]$base.overflow_priority; protected_drop = [bool]$base.protected_drop; origin = "sheet_row"; source_sheet_row = [int]$r.row }
                if ($isGold -or $itemId -le 0) {
                    # Gold slots carry ONLY gold_amount (baseline identity contract).
                    $slotObj["gold_amount"] = [long]$r.gold
                } else {
                    $slotObj["canonical_item_id"] = $itemId
                }
                $slotsOut.Add($slotObj)
                $stat.compiled++
            }
            $hasAny = $true; $stat.named++
            continue
        }
        if ($slotRaw) {
            $uid0 = ($slotRaw -replace '\s+等.*$','')
            if ($uid0 -match '^dpv2\.user\.v81\.m(\d+)\.fate_blade$') {
                $uid = Resolve-Uid $uid0 ([int]$r.row)
                $slotsOut.Add([ordered]@{ slot_uid = $uid; canonical_item_id = 110; final_numerator = $tn; final_denominator = $td; overflow_priority = 600; protected_drop = $false; origin = "v81_fate_blade"; source_sheet_row = [int]$r.row })
                $stat.fate++; $hasAny = $true; $stat.named++
                continue
            }
            $uid = Resolve-Uid $uid0 ([int]$r.row)
            $base = $slotByUid[$uid0]
            if (-not $base) { $stat.excludedResidue++; continue }
            $itemId = [int]$base.canonical_item_id
            $slotObj = [ordered]@{ slot_uid = $uid; final_numerator = $tn; final_denominator = $td; overflow_priority = [int]$base.overflow_priority; protected_drop = [bool]$base.protected_drop; origin = "sheet_row"; source_sheet_row = [int]$r.row }
            if ($isGold -or $itemId -le 0) {
                # Gold slots carry ONLY gold_amount (baseline identity contract).
                $slotObj["gold_amount"] = [long]$r.gold
            } else {
                $slotObj["canonical_item_id"] = $itemId
            }
            $slotsOut.Add($slotObj)
            $stat.compiled++; $hasAny = $true; $stat.named++
            continue
        }
        # new equipment row (no slot uid)
        $name = "$($r.item)" -replace '\s*×\d+$',''
        $itemId = if ($equByName.ContainsKey($name.Trim())) { [int]$equByName[$name.Trim()] } else { -999 }
        if ($itemId -eq -999) { $stat.excludedResidue++; continue }
        if (-not $newSeq.ContainsKey($s.monster)) { $newSeq[$s.monster] = 0 }
        $newSeq[$s.monster]++
        $slotsOut.Add([ordered]@{ slot_uid = "dpv2.user.sheet.m$dir.slot_n$($newSeq[$s.monster].ToString('D3'))"; canonical_item_id = $itemId; final_numerator = $tn; final_denominator = $td; overflow_priority = 300; protected_drop = $false; origin = "new_equip"; source_sheet_row = [int]$r.row })
        $stat.newSlots++; $hasAny = $true; $stat.named++
    }
    if (-not $hasAny -and $s.rows.Count -eq 0) { $stat.emptySheets += $s.monster }
    $monstersOut.Add([ordered]@{ monster_id = $dir; monster_name = $s.monster; slots = $slotsOut })
}
# fix empty sheets mid via directory ids
$emptyNames = $stat.emptySheets -join ','
$out = [ordered]@{
    schema = "hardcore.dpv2.user_loot_sheet_authority.v1"
    authority_id = "dpv2.user_loot_sheet.v1"
    status = "PENDING_ACTIVATION"
    source = [ordered]@{
        sheet_file = "HardCore_怪物爆率分表.xlsx"
        sheet_sha256 = $xlsxSha.ToLower()
        baseline_commit = "84ab22742eee1589ac105a8ff175da8623778f37"
        probability_contract = "sheet_E_is_final_per_slot_pre_rng_probability_no_spb_no_v5_no_denominator_policy_no_v80_no_v81_no_global_multiplier_no_gold_x5"
        gold_contract = "sheet_D_is_final_gold_amount"
    }
    summary = [ordered]@{
        named_rows = $stat.named
        slot_rows_compiled = $stat.compiled
        new_equipment_slots = $stat.newSlots
        fate_blade_slots = $stat.fate
        excluded_residue_rows = $stat.excludedResidue
        parser_excluded_residue_rows = $residueRows.Count
        residue_rows_source = "evidence/04_五张空表与七条残留.csv"
        empty_sheets = $stat.emptySheets
        monsters = $monstersOut.Count
    }
    monsters = $monstersOut
}
$outDir = 'C:\Users\Administrator\Documents\HardCore\outputs\tmp_loot_sheet'
[System.IO.File]::WriteAllText("$outDir\dpv2_user_loot_sheet_authority_v1.json", ($out | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText("$outDir\compile_disambiguation.json", ($disambiguated | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
"disambiguated_uids=$($disambiguated.Count)"
"compiled: named=$($stat.named) slotRows=$($stat.compiled) newSlots=$($stat.newSlots) fate=$($stat.fate) excluded=$($stat.excludedResidue) emptySheets=[$emptyNames] monsters=$($monstersOut.Count)"
"WHITELIST verified=$whitelistVerified failed=$($whitelistFailed.Count)"
"NEWROWS resolved=$newResolved failed=$($newFailed.Count)"
"compiled: named=$($stat.named) slotRows=$($stat.compiled) newSlots=$($stat.newSlots) fate=$($stat.fate) excluded=$($stat.excludedResidue) emptySheets=[$emptyNames]"
