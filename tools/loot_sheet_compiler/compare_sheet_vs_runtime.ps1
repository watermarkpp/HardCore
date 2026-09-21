$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Administrator\Documents\HardCore'

$doc = Get-Content 'outputs\tmp_loot_sheet\loot_sheet_parsed.json' -Raw | ConvertFrom-Json
$eff = Get-Content 'assets\data\drop\dpv2_single_player_effective_probability_v1.json' -Raw | ConvertFrom-Json
$cat = Get-Content 'assets\data\service_item_catalog.json' -Raw | ConvertFrom-Json
$cls = Get-Content 'assets\data\runtime\canonical_monster_catalog.json' -Raw | ConvertFrom-Json
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

# ledger index by slot_uid
$ledger = @{}
foreach ($rec in $eff.records) { $ledger[[string]$rec.slot_uid] = $rec }
# item kind index
$kindById = @{}
foreach ($it in $cat.items) { $kindById[[int]$it.itemId] = [string]$it.kind }
# monster classification index
$clsById = @{}
foreach ($k in $cls.entries_by_id.PSObject.Properties.Name) { $clsById[[int]$k] = [string]$cls.entries_by_id.$k.classification }

function Denom-Multiplier([int]$itemId, [string]$classification) {
    if ($classification -eq 'ordinary') {
        if ($itemId -ge 910001 -and $itemId -le 910006) { return 6 }
        if ($itemId -gt 0 -and $kindById[$itemId] -eq 'equipment') { return 3 }
        return 1
    }
    if ($classification -eq 'elite' -or $classification -eq 'boss') {
        if ($itemId -eq 920014 -or $itemId -eq 920016) { return 2 }
    }
    return 1
}

function Rate-Fraction($row) {
    $f = "$($row.rate_formula)"; $v = "$($row.rate_value)"
    if ($f -match '^=?(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)$') {
        $n = [double]$Matches[1]; $d = [double]$Matches[2]
        if ($d -gt 0 -and $n -gt 0 -and $n -le $d) { return @($n, $d) }
    }
    if ($v -match '^\d') {
        $x = [double]$v
        if ($x -gt 0 -and $x -le 1) {
            # rationalize: search smallest denominator 1..100000
            for ($d = 2; $d -le 100000; $d++) {
                $n = [Math]::Round($x * $d)
                if ($n -ge 1 -and [Math]::Abs($x - $n / $d) -lt 1e-12) { return @([double]$n, [double]$d) }
            }
        }
    }
    return $null
}

$stats = @{ equal = 0; changed = 0; new = 41; ledgerOnly = 0; unresolved = 0 }
$changedRows = New-Object System.Collections.Generic.List[object]
$coveredUids = @{}
foreach ($s in $doc.sheets) {
    $idStr = $dirMap[$s.monster]
    if ($idStr -notmatch '^\d+$') { continue }
    $mid = [int]$idStr
    $classification = $clsById[$mid]
    foreach ($r in $s.rows) {
        $slotRaw = "$($r.slot_raw)"
        $frac = Rate-Fraction $r
        $uids = New-Object System.Collections.Generic.List[string]
        if ($slotRaw -match '^([\w\.]+) 等(\d+)个独立槽$') {
            $first = $Matches[1]; $n = [int]$Matches[2]
            if ($first -match '^(.*\.slot_)(\d+)$') {
                $prefix = $Matches[1]; $num = [int]$Matches[2]
                for ($i = 0; $i -lt $n; $i++) { $uids.Add(($prefix + ($num + $i).ToString('D3'))) }
            } else { for ($i = 0; $i -lt $n; $i++) { $uids.Add($first) } }
        } elseif ($slotRaw) {
            $uids.Add(($slotRaw -replace '\s+等.*$',''))
        } else {
            continue  # orphan (41 new slots) counted separately
        }
        if (-not $frac) { $stats.unresolved += $uids.Count; continue }
        $tn = [double]$frac[0]; $td = [double]$frac[1]
        foreach ($uid in $uids) {
            $coveredUids[$uid] = $true
            $rec = $ledger[$uid]
            if (-not $rec) { $stats.unresolved++; continue }
            $itemId = [int]$rec.canonical_item_id
            $m = Denom-Multiplier $itemId $classification
            $en = [double]$rec.effective_numerator; $ed = [double]$rec.effective_denominator * $m
            # compare tn/td vs en/ed exactly via cross products
            $left = $tn * $ed; $right = $en * $td
            if ([Math]::Abs($left - $right) -lt 0.5) { $stats.equal++ }
            else {
                $stats.changed++
                if ($changedRows.Count -lt 40) {
                    $changedRows.Add([pscustomobject]@{ monster = $s.monster; uid = $uid; item = $r.item; table = "$tn/$td"; current = "$en/$ed" })
                }
            }
        }
    }
}
$stats.ledgerOnly = $ledger.Count - $coveredUids.Count
"EQUAL=$($stats.equal) CHANGED=$($stats.changed) NEW_SHEET_ONLY=$($stats.new) LEDGER_ONLY=$($stats.ledgerOnly) UNRESOLVED=$($stats.unresolved)"
'=== changed samples (first 25) ==='
$changedRows | Select-Object -First 25 | ForEach-Object { "$($_.monster) $($_.uid) '$($_.item)': table=$($_.table) current=$($_.current)" }
$diff = @{ stats = $stats; changed = $changedRows }
[System.IO.File]::WriteAllText('C:\Users\Administrator\Documents\HardCore\outputs\tmp_loot_sheet\compare_result.json', ($diff | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
