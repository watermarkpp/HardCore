$ErrorActionPreference = 'Stop'
$dst = "$env:TEMP\xlsx_baolv"
if (-not (Test-Path "$dst\xl\workbook.xml")) {
    Expand-Archive -Path "$env:USERPROFILE\Desktop\HardCore_怪物爆率分表.xlsx" -DestinationPath $dst -Force
}
[xml]$ss = Get-Content "$dst\xl\sharedStrings.xml" -Raw -Encoding UTF8
$strings = @($ss.sst.si | ForEach-Object { if ($_.t) { $_.t } else { (($_.r | ForEach-Object { $_.t }) -join '') } })
[xml]$wb = Get-Content "$dst\xl\workbook.xml" -Raw -Encoding UTF8
[xml]$rels = Get-Content "$dst\xl\_rels\workbook.xml.rels" -Raw -Encoding UTF8
$relMap = @{}
foreach ($rel in $rels.Relationships.Relationship) { $relMap[$rel.Id] = $rel.Target }

$result = [ordered]@{ sheets = @() }
$totalRows = 0; $rowsWithSlot = 0; $rowsMultiSlot = 0; $rowsNoSlot = 0
$rowsGold = 0; $rowsNoItemId = 0
foreach ($sheet in $wb.workbook.sheets.sheet) {
    $name = $sheet.name
    if ($name -eq '目录') { continue }
    $target = $relMap[$sheet.id]
    $path = Join-Path $dst "xl\$($target -replace 'xl/','')"
    if (-not (Test-Path $path)) { continue }
    [xml]$sx = Get-Content $path -Raw -Encoding UTF8
    # pass 1: collect shared-formula masters (si -> formula text). Fraction
    # formulas carry no cell references, so no relative-shift is needed.
    $sharedMasters = @{}
    foreach ($row in $sx.worksheet.sheetData.row) {
        foreach ($c in $row.c) {
            foreach ($child in $c.ChildNodes) {
                if ($child.LocalName -ne 'f') { continue }
                $ft = $child.GetAttribute('t')
                $si = $child.GetAttribute('si')
                if ($ft -eq 'shared' -and $child.InnerText) { $sharedMasters["$si"] = $child.InnerText }
            }
        }
    }
    $sheetRows = @()
    foreach ($row in $sx.worksheet.sheetData.row) {
        if ([int]$row.r -le 5) { continue }
        $cells = @{}
        foreach ($c in $row.c) {
            $col = ($c.r -replace '\d','')
            $v = $c.v
            if ($c.t -eq 's') { if ($v -ne $null) { $v = $strings[[int]$v] } else { $v = '' } }
            $formula = ''
            foreach ($child in $c.ChildNodes) {
                if ($child.LocalName -eq 'f') {
                    $ft = $child.GetAttribute('t')
                    $si = $child.GetAttribute('si')
                    if ($ft -eq 'shared' -and -not $child.InnerText) {
                        # shared dependent cell: inherit master formula text
                        if ($sharedMasters.ContainsKey("$si")) { $formula = $sharedMasters["$si"] }
                    } else {
                        $formula = $child.InnerText
                    }
                }
            }
            $cells[$col] = @{ v = "$v"; f = $formula }
        }
        $itemName = $cells['A'].v
        if (-not $itemName) { continue }
        $totalRows++
        $slotRaw = $cells['H'].v
        $isMulti = $slotRaw -match '等\d+个独立槽'
        if ($slotRaw -and -not $isMulti) { $rowsWithSlot++ } elseif ($isMulti) { $rowsMultiSlot++ } else { $rowsNoSlot++ }
        $rewardType = $cells['C'].v
        if ($rewardType -eq '金币') { $rowsGold++ }
        $itemId = $cells['B'].v
        if (-not $itemId -and $rewardType -ne '金币') { $rowsNoItemId++ }
        $sheetRows += [ordered]@{
            row = [int]$row.r
            item = $itemName
            item_id = $itemId
            type = $rewardType
            gold = $cells['D'].v
            rate_formula = $cells['E'].f
            rate_value = $cells['E'].v
            composition = $cells['G'].v
            slot_raw = $slotRaw
        }
    }
    $result.sheets += [ordered]@{ monster = $name; rows = $sheetRows }
}
$json = $result | ConvertTo-Json -Depth 6
$outDir = 'C:\Users\Administrator\Documents\HardCore\outputs\tmp_loot_sheet'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
[System.IO.File]::WriteAllText("$outDir\loot_sheet_parsed.json", $json, [System.Text.UTF8Encoding]::new($false))
"TOTAL_ROWS=$totalRows WITH_SLOT=$rowsWithSlot MULTI_SLOT=$rowsMultiSlot NO_SLOT=$rowsNoSlot GOLD=$rowsGold NO_ITEM_ID=$rowsNoItemId"
"SHEETS=$($result.sheets.Count)"
