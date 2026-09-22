param(
    # RV15 internal-test build review: parameterize every path. The default
    # project root resolves from THIS script's location, so an isolated tree
    # can never read or write the old hard-coded C:\ directory.
    [string]$ProjectRoot = "",
    [string]$WorkbookPath = "",
    [string]$OutputDir = "",
    # Optional acceptance comparison: compile, then diff the sheet-compiled
    # portion (sheet_row / new_equip / v81_fate_blade) against a reference
    # authority document by stable UID before writing anything.
    [string]$VerifyAgainstAuthority = ""
)
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'outputs\tmp_loot_sheet'
}
$rv = Join-Path $ScriptDir 'evidence'

# Recreate compiler inputs from the sealed, versioned workbook evidence.
# A clean checkout must not depend on an earlier machine's outputs or TEMP.
$preparedInputDir = Join-Path $OutputDir 'source_inputs'
& (Join-Path $ScriptDir 'prepare_archive_inputs.ps1') -ProjectRoot $ProjectRoot -OutputDir $preparedInputDir
$doc = Get-Content (Join-Path $preparedInputDir 'loot_sheet_parsed.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$db = Get-Content (Join-Path $ProjectRoot 'assets\data\drop\dpv2_direct_baseline_v2.json') -Raw | ConvertFrom-Json
$grp = Get-Content (Join-Path $preparedInputDir 'row_to_full_slot_uid_map.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$equ = Get-Content (Join-Path $ProjectRoot 'assets\data\equipment_attribute_master.json') -Raw | ConvertFrom-Json

# workbook sha: real workbook when provided, otherwise the versioned archive
# binding recorded in evidence/SOURCE_BINDINGS.json (archived parsed-rows mode).
$sourceMode = "archived_parsed_rows"
if ([string]::IsNullOrWhiteSpace($WorkbookPath)) {
    $bindings = Get-Content (Join-Path $rv 'SOURCE_BINDINGS.json') -Raw | ConvertFrom-Json
    $xlsxSha = [string]$bindings.source_workbook_sha256
    if ($xlsxSha -ne 'bc234fca54286547b07f64731c9d0e3674aa19a703863c393c356caf97005251') {
        throw "archived workbook sha mismatch: $xlsxSha"
    }
} else {
    if (-not (Test-Path -LiteralPath $WorkbookPath -PathType Leaf)) { throw "workbook missing: $WorkbookPath" }
    $xlsxSha = (Get-FileHash $WorkbookPath -Algorithm SHA256).Hash
    $sourceMode = "live_workbook"
}
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
$stat = @{ named = 0; compiled = 0; gold = 0; newSlots = 0; fate = 0; emptySheets = @(); excludedResidue = 0; unexpectedExcluded = @() }
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
            if ($a -eq $null) { $stat.excludedResidue++; $stat.unexpectedExcluded += "GROUP-MISSING $($s.monster)|$($r.row)"; continue }
            foreach ($uid0 in ($a.slotUids -split '\|')) {
                $uid = Resolve-Uid $uid0 ([int]$r.row)
                $base = $slotByUid[$uid0]
                if (-not $base) { $stat.excludedResidue++; $stat.unexpectedExcluded += "BASE-UID-MISSING $uid0"; continue }
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
            if (-not $base) { $stat.excludedResidue++; $stat.unexpectedExcluded += "BASE-UID-MISSING $uid0"; continue }
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
        if ($itemId -eq -999) { $stat.excludedResidue++; $stat.unexpectedExcluded += "NEW-ITEM-UNRESOLVED $($s.monster)|$($r.row) '$name'"; continue }
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

# --- deterministic overlay synthesis (RV15 user-directive approved input) ---
# The versioned overlay input carries the complete stable slot record for
# every approved overlay slot; re-running the synthesis on an already
# synthesized document is impossible here because this script always
# rebuilds from the parsed rows first (idempotent by construction).
$overlayInputPath = Join-Path $rv 'user_directive_overlay_slots.json'
$overlayInput = Get-Content $overlayInputPath -Raw | ConvertFrom-Json
$overlaySlots = $overlayInput.slots
$overlayByMid = @{}
foreach ($os in $overlaySlots) {
    $mk = [int]$os.monster_id
    if (-not $overlayByMid.ContainsKey($mk)) { $overlayByMid[$mk] = New-Object System.Collections.Generic.List[object] }
    $overlayByMid[$mk].Add($os)
}
$overlayApplied = 0; $overlayConflicts = @()
foreach ($m in $monstersOut) {
    $mk = [int]$m.monster_id
    if (-not $overlayByMid.ContainsKey($mk)) { continue }
    foreach ($os in $overlayByMid[$mk]) {
        if ($seenUids.ContainsKey([string]$os.slot_uid)) { $overlayConflicts += "OVERLAY-UID-CONFLICT $($os.slot_uid)"; continue }
        $seenUids[[string]$os.slot_uid] = $true
        $m.slots.Add([ordered]@{
            slot_uid = [string]$os.slot_uid
            final_numerator = [int]$os.final_numerator
            final_denominator = [int]$os.final_denominator
            overflow_priority = [int]$os.overflow_priority
            protected_drop = [bool]$os.protected_drop
            origin = "user_directive_overlay"
            canonical_item_id = [int]$os.canonical_item_id
        })
        $overlayApplied++
    }
}
$overlayTotal = [int]$overlayInput.summary.user_directive_overlay_slots
if ($overlayApplied -ne $overlayTotal) { $overlayConflicts += "OVERLAY-TALLY-MISMATCH applied=$overlayApplied expected=$overlayTotal" }

# The archived sheet remains immutable input. This explicit, versioned user
# correction removes only the sealed armor slot UIDs after sheet/overlay build.
# Archived row/group expansion must not reconstruct a second independent draw
# after the user's deletion. Output aliases identify the exact retained armor;
# they do not authorize restoring either a deleted row or another source slot.
$armorDirectivePath = Join-Path $rv 'armor_single_slot_directive_v92.json'
$armorDirective = Get-Content -LiteralPath $armorDirectivePath -Raw | ConvertFrom-Json
function Assert-ArmorDirective([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ARMOR_SINGLE_SLOT_DIRECTIVE_REJECTED: $Message" }
}
function Get-CanonicalSlotJson($Slot) {
    $names = if ($Slot -is [System.Collections.IDictionary]) { @($Slot.Keys | Sort-Object) } else { @($Slot.PSObject.Properties.Name | Sort-Object) }
    $value = [ordered]@{}
    foreach ($name in $names) { $value[$name] = $Slot.$name }
    return ($value | ConvertTo-Json -Depth 8 -Compress)
}
function Get-TextSha256([string]$Text) {
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}
Assert-ArmorDirective ($armorDirective.schema -eq 'hardcore.loot.armor_single_slot_directive.v1') 'schema mismatch'
Assert-ArmorDirective ($armorDirective.directive_id -eq 'armor.single_slot.user.20260922.v92') 'directive ID mismatch'
$armorMasterPath = Join-Path $ProjectRoot ([string]$armorDirective.identity_basis.equipment_master_path)
$armorPairPath = Join-Path $ProjectRoot ([string]$armorDirective.identity_basis.female_pair_evidence_path)
Assert-ArmorDirective ($armorDirective.identity_basis.sha256_scope -eq 'utf8_lf_text') 'identity hash scope mismatch'
Assert-ArmorDirective ((Get-TextSha256 ([IO.File]::ReadAllText($armorMasterPath).Replace("`r`n", "`n"))) -eq $armorDirective.identity_basis.equipment_master_sha256) 'equipment master changed; review exact IDs before recompiling'
Assert-ArmorDirective ((Get-TextSha256 ([IO.File]::ReadAllText($armorPairPath).Replace("`r`n", "`n"))) -eq $armorDirective.identity_basis.female_pair_evidence_sha256) 'female pairing evidence changed'
$armorPairEvidence = Get-Content -LiteralPath $armorPairPath -Raw | ConvertFrom-Json
$armorMasterById = @{}
foreach ($record in $equ.records) {
    if ([string]$record.category -eq [string]$armorDirective.identity_basis.armor_category) { $armorMasterById[[int]$record.itemId] = $record }
}
$armorOutputBySource = @{}
foreach ($identity in $armorDirective.armor_output_identities) {
    $sourceId = [int]$identity.source_item_id
    $outputId = [int]$identity.output_item_id
    Assert-ArmorDirective (-not $armorOutputBySource.ContainsKey($sourceId)) "duplicate armor identity $sourceId"
    Assert-ArmorDirective ($armorMasterById.ContainsKey($sourceId) -and $armorMasterById.ContainsKey($outputId)) "unknown armor identity $sourceId -> $outputId"
    $sourceRecord = $armorMasterById[$sourceId]
    $outputRecord = $armorMasterById[$outputId]
    Assert-ArmorDirective ($sourceRecord.name -ceq $identity.source_name -and $sourceRecord.genderRestriction -ceq $identity.source_gender -and $outputRecord.name -ceq $identity.output_name) "armor identity metadata mismatch $sourceId"
    if ([string]$sourceRecord.genderRestriction -eq 'female') {
        $pairProperty = $armorPairEvidence.records.PSObject.Properties[[string]$sourceId]
        Assert-ArmorDirective ($null -ne $pairProperty -and [int]$pairProperty.Value.pairedPrimary.itemId -eq $outputId) "unproven female pairing $sourceId"
    } else {
        Assert-ArmorDirective ($sourceId -eq $outputId -and [string]$sourceRecord.genderRestriction -eq 'male') "invalid male armor identity $sourceId"
    }
    $armorOutputBySource[$sourceId] = $outputId
}
Assert-ArmorDirective ($armorOutputBySource.Count -eq $armorMasterById.Count -and $armorOutputBySource.Count -eq 24) 'armor identity coverage mismatch'
$armorMonsters = @{}
$armorBeforeByMonster = @{}
$armorBeforeTotal = 0
$armorNonArmorBefore = New-Object System.Collections.Generic.List[string]
foreach ($m in $monstersOut) {
    $mid = [int]$m.monster_id
    Assert-ArmorDirective (-not $armorMonsters.ContainsKey($mid)) "duplicate monster $mid"
    $armorMonsters[$mid] = $m
    $armorBeforeByMonster[$mid] = @($m.slots | ForEach-Object { [string]$_.slot_uid })
    $armorBeforeTotal += $m.slots.Count
    foreach ($slot in $m.slots) {
        if (-not $armorOutputBySource.ContainsKey([int]$slot.canonical_item_id)) { $armorNonArmorBefore.Add("$mid|$(Get-CanonicalSlotJson $slot)") }
    }
}
Assert-ArmorDirective ($armorBeforeTotal -eq [int]$armorDirective.summary.before_total_slots) 'pre-directive slot count mismatch'
$armorExceptions = @{}
$expectedExceptionSources = @{ 235 = 140; 236 = 144; 237 = 142; 238 = 141; 239 = 145; 240 = 143 }
foreach ($exception in $armorDirective.frozen_exceptions) {
    $mid = [int]$exception.monster_id
    $sourceId = [int]$exception.source_item_id
    Assert-ArmorDirective ($expectedExceptionSources.ContainsKey($mid) -and $expectedExceptionSources[$mid] -eq $sourceId) "unapproved exception $mid/$sourceId"
    Assert-ArmorDirective (-not $armorExceptions.ContainsKey($mid) -and @($exception.expected_slots).Count -eq 1) "duplicate or malformed exception $mid"
    Assert-ArmorDirective ($armorMonsters.ContainsKey($mid)) "exception monster missing $mid"
    $actual = @($armorMonsters[$mid].slots | Where-Object { [int]$_.canonical_item_id -eq $sourceId })
    Assert-ArmorDirective ($actual.Count -eq 1 -and (Get-CanonicalSlotJson $actual[0]) -ceq (Get-CanonicalSlotJson $exception.expected_slots[0])) "frozen exception changed $mid/$sourceId"
    Assert-ArmorDirective ([int]$exception.output_item_id -eq $armorOutputBySource[$sourceId]) "exception output mismatch $mid"
    $armorExceptions[$mid] = [string]$actual[0].slot_uid
}
Assert-ArmorDirective ($armorExceptions.Count -eq 6) 'six dark-boss exception coverage mismatch'
$armorRemoveUids = @{}
$armorGroupKeys = @{}
foreach ($group in $armorDirective.groups) {
    $mid = [int]$group.monster_id
    $outputId = [int]$group.output_item_id
    $groupKey = "$mid|$outputId"
    Assert-ArmorDirective (-not $armorGroupKeys.ContainsKey($groupKey) -and $armorMonsters.ContainsKey($mid)) "duplicate/unknown directive group $groupKey"
    $armorGroupKeys[$groupKey] = $true
    $actualSlots = @($armorMonsters[$mid].slots | Where-Object { $armorOutputBySource.ContainsKey([int]$_.canonical_item_id) -and $armorOutputBySource[[int]$_.canonical_item_id] -eq $outputId })
    Assert-ArmorDirective ($actualSlots.Count -gt 1 -and $actualSlots.Count -eq @($group.expected_slots).Count) "directive group cardinality mismatch $groupKey"
    for ($index = 0; $index -lt $actualSlots.Count; $index++) {
        Assert-ArmorDirective ((Get-CanonicalSlotJson $actualSlots[$index]) -ceq (Get-CanonicalSlotJson $group.expected_slots[$index])) "slot identity/probability/order drift $groupKey index=$index"
    }
    $maleCandidates = @($actualSlots | Where-Object { [int]$_.canonical_item_id -eq $outputId -and [string]$armorMasterById[[int]$_.canonical_item_id].genderRestriction -eq 'male' })
    $retained = if ($maleCandidates.Count -gt 0) { $maleCandidates[0] } else { $actualSlots[0] }
    Assert-ArmorDirective ([string]$retained.slot_uid -ceq [string]$group.keep_slot_uid) "retained slot violates approved policy $groupKey"
    $removeSet = @{}
    foreach ($uid in $group.remove_slot_uids) {
        Assert-ArmorDirective (-not $removeSet.ContainsKey([string]$uid) -and -not $armorRemoveUids.ContainsKey([string]$uid)) "duplicate removal UID $uid"
        $removeSet[[string]$uid] = $true
        $armorRemoveUids[[string]$uid] = $mid
    }
    Assert-ArmorDirective ($removeSet.Count -eq $actualSlots.Count - 1 -and -not $removeSet.ContainsKey([string]$retained.slot_uid)) "invalid removal set $groupKey"
    foreach ($slot in $actualSlots) {
        Assert-ArmorDirective ([long]$slot.final_numerator -eq [long]$retained.final_numerator -and [long]$slot.final_denominator -eq [long]$retained.final_denominator -and [int]$slot.overflow_priority -eq [int]$retained.overflow_priority -and [bool]$slot.protected_drop -eq [bool]$retained.protected_drop) "different probability or selection policy needs review $groupKey"
        Assert-ArmorDirective ([string]$slot.slot_uid -eq [string]$retained.slot_uid -or $removeSet.ContainsKey([string]$slot.slot_uid)) "unlisted source slot $groupKey"
        Assert-ArmorDirective (-not $armorExceptions.ContainsValue([string]$slot.slot_uid)) "frozen dark-boss slot listed for removal $groupKey"
    }
}
Assert-ArmorDirective ($armorGroupKeys.Count -eq [int]$armorDirective.summary.duplicate_groups -and $armorRemoveUids.Count -eq [int]$armorDirective.summary.removed_slots) 'directive tally mismatch'
$armorRemoved = 0
$armorAfterTotal = 0
$armorNonArmorAfter = New-Object System.Collections.Generic.List[string]
foreach ($m in $monstersOut) {
    $mid = [int]$m.monster_id
    $kept = New-Object System.Collections.Generic.List[object]
    $outputsSeen = @{}
    foreach ($slot in $m.slots) {
        $uid = [string]$slot.slot_uid
        $sourceId = [int]$slot.canonical_item_id
        if ($armorRemoveUids.ContainsKey($uid)) {
            Assert-ArmorDirective ($armorRemoveUids[$uid] -eq $mid -and $armorOutputBySource.ContainsKey($sourceId)) "removal ownership/category mismatch $uid"
            Assert-ArmorDirective ([string]$slot.origin -eq 'sheet_row') "unexpected removed-slot origin $uid"
            $armorRemoved++
            $stat.compiled--
            continue
        }
        $kept.Add($slot)
        if ($armorOutputBySource.ContainsKey($sourceId)) {
            $outputId = $armorOutputBySource[$sourceId]
            Assert-ArmorDirective (-not $outputsSeen.ContainsKey($outputId)) "unresolved duplicate armor $mid/$outputId"
            $outputsSeen[$outputId] = $true
        } else { $armorNonArmorAfter.Add("$mid|$(Get-CanonicalSlotJson $slot)") }
    }
    $expectedOrder = @($armorBeforeByMonster[$mid] | Where-Object { -not $armorRemoveUids.ContainsKey($_) }) -join '|'
    Assert-ArmorDirective ((@($kept | ForEach-Object { [string]$_.slot_uid }) -join '|') -ceq $expectedOrder) "remaining slot order changed $mid"
    $m['slots'] = $kept
    $armorAfterTotal += $kept.Count
}
Assert-ArmorDirective ($armorRemoved -eq [int]$armorDirective.summary.removed_slots -and $armorAfterTotal -eq [int]$armorDirective.summary.after_total_slots) 'applied removal tally mismatch'
$nonArmorBeforeSha = Get-TextSha256 ($armorNonArmorBefore -join "`n")
$nonArmorAfterSha = Get-TextSha256 ($armorNonArmorAfter -join "`n")
Assert-ArmorDirective ($nonArmorBeforeSha -eq $nonArmorAfterSha) 'non-armor slot content/order changed'
$armorDirectiveSha = ((Get-FileHash -LiteralPath $armorDirectivePath -Algorithm SHA256).Hash).ToLowerInvariant()
$armorAudit = [ordered]@{ directive_id = [string]$armorDirective.directive_id; directive_sha256 = $armorDirectiveSha; before_slots = $armorBeforeTotal; after_slots = $armorAfterTotal; removed_slots = $armorRemoved; groups = $armorGroupKeys.Count; frozen_exception_slots = $armorExceptions.Count; non_armor_slots = $armorNonArmorAfter.Count; non_armor_before_sha256 = $nonArmorBeforeSha; non_armor_after_sha256 = $nonArmorAfterSha; remaining_slot_order_unchanged = $true }

$out = [ordered]@{
    schema = "hardcore.dpv2.user_loot_sheet_authority.v1"
    authority_id = "dpv2.user_loot_sheet.v1"
    status = "PENDING_ACTIVATION"
    source = [ordered]@{
        sheet_file = "HardCore_怪物爆率分表.xlsx"
        sheet_sha256 = $xlsxSha.ToLower()
        source_mode = $sourceMode
        overlay_input = "tools/loot_sheet_compiler/evidence/user_directive_overlay_slots.json"
        overlay_source = [string]$overlayInput.source
        armor_single_slot_directive = "tools/loot_sheet_compiler/evidence/armor_single_slot_directive_v92.json"
        armor_single_slot_directive_sha256 = $armorDirectiveSha
        baseline_commit = "84ab22742eee1589ac105a8ff175da8623778f37"
        probability_contract = "sheet_E_is_final_per_slot_pre_rng_probability_no_spb_no_v5_no_denominator_policy_no_v80_no_v81_no_global_multiplier_no_gold_x5"
        gold_contract = "sheet_D_is_final_gold_amount"
    }
    summary = [ordered]@{
        named_rows = $stat.named
        slot_rows_compiled = $stat.compiled
        new_equipment_slots = $stat.newSlots
        fate_blade_slots = $stat.fate
        user_directive_overlay_slots = $overlayApplied
        armor_single_slot_removed_slots = $armorRemoved
        armor_single_slot_groups = $armorGroupKeys.Count
        total_effective_slots = $armorAfterTotal
        excluded_residue_rows = $stat.excludedResidue
        parser_excluded_residue_rows = $residueRows.Count
        residue_rows_source = "evidence/04_五张空表与七条残留.csv"
        empty_sheets = $stat.emptySheets
        monsters = $monstersOut.Count
    }
    monsters = $monstersOut
}

# --- acceptance gates: any failure aborts the build, nothing is written ---
$acceptanceFailures = @()
if ($whitelistFailed.Count -gt 0) { $acceptanceFailures += "whitelist_failed=$($whitelistFailed.Count)" }
if ($newFailed.Count -gt 0) { $acceptanceFailures += "newrows_failed=$($newFailed.Count)" }
if ($stat.unexpectedExcluded.Count -gt 0) { $acceptanceFailures += "unexpected_excluded=$($stat.unexpectedExcluded.Count)" }
if ($overlayConflicts.Count -gt 0) { $acceptanceFailures += "overlay_conflicts=$($overlayConflicts.Count)" }
if ($residueRows.Count -ne 7) { $acceptanceFailures += "authorized_residue_expected_7_got_$($residueRows.Count)" }

if ($acceptanceFailures.Count -gt 0) {
    Write-Output "COMPILE_AUTHORITY_REJECTED"
    $acceptanceFailures | ForEach-Object { Write-Output "  REJECT: $_" }
    $whitelistFailed | Select-Object -First 5 | ForEach-Object { Write-Output "  WL: $_" }
    $newFailed | Select-Object -First 5 | ForEach-Object { Write-Output "  NEW: $_" }
    $stat.unexpectedExcluded | Select-Object -First 5 | ForEach-Object { Write-Output "  EXC: $_" }
    $overlayConflicts | Select-Object -First 5 | ForEach-Object { Write-Output "  OVL: $_" }
    exit 1
}

# --- optional reference comparison of the sheet-compiled portion ---
if (-not [string]::IsNullOrWhiteSpace($VerifyAgainstAuthority)) {
    $ref = Get-Content $VerifyAgainstAuthority -Raw | ConvertFrom-Json
    $refSheet = @{}
    foreach ($m in $ref.monsters) { foreach ($s in $m.slots) {
        if ([string]$s.origin -eq 'sheet_row' -or [string]$s.origin -eq 'new_equip' -or [string]$s.origin -eq 'v81_fate_blade') {
            $refSheet[[string]$s.slot_uid] = $s
        }
    } }
    $newSheet = @{}
    foreach ($m in $monstersOut) { foreach ($s in $m.slots) {
        if ([string]$s.origin -ne 'user_directive_overlay') { $newSheet[[string]$s.slot_uid] = $s }
    } }
    $diffs = @()
    foreach ($uid in $refSheet.Keys) {
        if (-not $newSheet.ContainsKey($uid)) { $diffs += "MISSING-IN-REBUILD $uid"; continue }
        $a = $refSheet[$uid]; $b = $newSheet[$uid]
        $aItem = if ($a.canonical_item_id) { [int]$a.canonical_item_id } else { 0 }
        $aGold = if ($a.gold_amount) { [long]$a.gold_amount } else { 0 }
        $bItem = if ($b.canonical_item_id) { [int]$b.canonical_item_id } else { 0 }
        $bGold = if ($b.gold_amount) { [long]$b.gold_amount } else { 0 }
        if ([int]$a.final_numerator -ne [int]$b.final_numerator -or
            [int]$a.final_denominator -ne [int]$b.final_denominator -or
            $aItem -ne $bItem -or $aGold -ne $bGold -or
            [int]$a.overflow_priority -ne [int]$b.overflow_priority -or
            [bool]$a.protected_drop -ne [bool]$b.protected_drop) {
            $diffs += "VALUE-DIFF $uid"
        }
    }
    foreach ($uid in $newSheet.Keys) { if (-not $refSheet.ContainsKey($uid)) { $diffs += "EXTRA-IN-REBUILD $uid" } }
    if ($diffs.Count -gt 0) {
        Write-Output "COMPILE_AUTHORITY_VERIFY_FAILED diff_count=$($diffs.Count)"
        $diffs | Select-Object -First 10 | ForEach-Object { Write-Output "  DIFF: $_" }
        exit 1
    }
    Write-Output "COMPILE_AUTHORITY_VERIFY_PASS sheet_compiled=$($newSheet.Count) identical_to_reference"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$JsonOut = $out | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText((Join-Path $OutputDir 'dpv2_user_loot_sheet_authority_v1.json'), $JsonOut, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $OutputDir 'compile_disambiguation.json'), ($disambiguated | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText((Join-Path $OutputDir 'armor_single_slot_audit.json'), ($armorAudit | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
Write-Output "ARMOR_SINGLE_SLOT_DIRECTIVE_PASS before=$armorBeforeTotal after=$armorAfterTotal removed=$armorRemoved groups=$($armorGroupKeys.Count) frozen=$($armorExceptions.Count) non_armor_unchanged=$($nonArmorBeforeSha -eq $nonArmorAfterSha)"
Write-Output "source_mode=$sourceMode sheet_sha=$($xlsxSha.ToLower().Substring(0,16))..."
Write-Output "disambiguated_uids=$($disambiguated.Count)"
Write-Output "compiled: named=$($stat.named) slotRows=$($stat.compiled) newSlots=$($stat.newSlots) fate=$($stat.fate) overlay=$overlayApplied excluded=$($stat.excludedResidue) emptySheets=[$emptyNames] monsters=$($monstersOut.Count)"
Write-Output "COMPILE_AUTHORITY_PASS"
