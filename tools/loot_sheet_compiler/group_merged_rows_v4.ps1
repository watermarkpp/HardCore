$ErrorActionPreference = 'Stop'
Set-Location 'C:\Users\Administrator\Documents\HardCore'
$db = Get-Content 'assets\data\drop\dpv2_direct_baseline_v2.json' -Raw | ConvertFrom-Json
$rv = "$env:TEMP\rv_baolv\HardCore_爆率方案复审与GLM补充包_84ab2274\evidence"

$merged = @()
foreach ($line in (Get-Content "$rv\03_合并独立槽320行_待绑定完整UID.csv" -Encoding UTF8 | Select-Object -Skip 1)) {
    if (-not $line.Trim()) { continue }
    $f = $line -split ',', 0
    if ($f.Count -lt 8) { continue }
    $n = 0; if ($f[6] -match '\d+') { $n = [int]$Matches[0] }
    $merged += [pscustomobject]@{ sheet = $f[0]; mid = [int]$f[1]; excelRow = [int]$f[2]; item = $f[3]; itemId = [int]$f[4]; rate = $f[5]; N = $n; repUid = $f[7] }
}

$seqByMid = @{}
foreach ($p in $db.profiles) {
    $seqByMid[[int]$p.canonical_monster_id] = @($p.slots | ForEach-Object { [pscustomobject]@{
        uid = [string]$_.slot_uid; item = [int]$_.canonical_item_id
        bn = [int]$_.base_numerator; bd = [int]$_.base_denominator } })
}

$assignments = New-Object System.Collections.Generic.List[object]
$blocked = New-Object System.Collections.Generic.List[string]
$usedUids = @{}
foreach ($grp in ($merged | Group-Object mid)) {
    $mid = [int]$grp.Name
    if (-not $seqByMid.ContainsKey($mid)) { $blocked.Add("$mid missing"); continue }
    $seq = $seqByMid[$mid]
    $rows = @($grp.Group | Sort-Object excelRow)
    foreach ($row in $rows) {
        $rep = $row.repUid
        $repSlot = $seq | Where-Object { $_.uid -eq $rep } | Select-Object -First 1
        if (-not $repSlot) { $blocked.Add("NO-REP mid=$mid row=$($row.excelRow)"); continue }
        $free = { param($u) -not $usedUids.ContainsKey($u) }
        $pick = $null; $mode = ''
        # primary: all slots with same item+base as rep, count==N, all free
        $prim = @($seq | Where-Object { $_.item -eq $repSlot.item -and $_.bn -eq $repSlot.bn -and $_.bd -eq $repSlot.bd })
        if ($prim.Count -eq $row.N -and (@($prim | Where-Object { -not (& $free $_.uid) }).Count -eq 0)) { $pick = $prim; $mode = 'item_base_all' }
        if (-not $pick) {
            # degenerate: contiguous same-base run starting AT rep, length N
            $idx = [array]::IndexOf(($seq | ForEach-Object { $_.uid }), $rep)
            $run = @()
            for ($i = $idx; $i -lt [Math]::Min($idx + $row.N, $seq.Count); $i++) {
                if ($seq[$i].bn -ne $repSlot.bn -or $seq[$i].bd -ne $repSlot.bd) { break }
                if (-not (& $free $seq[$i].uid)) { break }
                $run += $seq[$i]
            }
            if ($run.Count -eq $row.N) { $pick = $run; $mode = 'base_run_from_rep' }
        }
        if (-not $pick) {
            # degenerate 2: contiguous same-base run containing rep, length N (rep anywhere)
            $idx = [array]::IndexOf(($seq | ForEach-Object { $_.uid }), $rep)
            for ($start = [Math]::Max(0, $idx - $row.N + 1); $start -le $idx; $start++) {
                $run = @()
                $ok = $true
                for ($i = $start; $i -lt [Math]::Min($start + $row.N, $seq.Count); $i++) {
                    if ($seq[$i].bn -ne $repSlot.bn -or $seq[$i].bd -ne $repSlot.bd) { $ok = $false; break }
                    if (-not (& $free $seq[$i].uid)) { $ok = $false; break }
                    $run += $seq[$i]
                }
                if ($ok -and $run.Count -eq $row.N -and ($start -le $idx) -and ($idx -lt $start + $row.N)) { $pick = $run; $mode = 'base_run_containing_rep'; break }
            }
        }
        if (-not $pick) { $blocked.Add("NO-RUN mid=$mid row=$($row.excelRow) '$($row.item)' N=$($row.N) rep=$rep"); continue }
        $uids = @($pick | ForEach-Object { $_.uid })
        foreach ($u in $uids) { $usedUids[$u] = $true }
        $assignments.Add([pscustomobject]@{ mid = $mid; sheet = $row.sheet; excelRow = $row.excelRow; item = $row.item; rate = $row.rate; N = $row.N; repUid = $rep; slotUids = ($uids -join '|'); mode = $mode })
    }
}
"ASSIGNED: $($assignments.Count) / $($merged.Count)"
"BLOCKED: $($blocked.Count)"
$blocked | Select-Object -First 10
$assignments | Group-Object mode | ForEach-Object { "mode $($_.Name): $($_.Count)" }
$out = [ordered]@{ assigned = $assignments; blocked = $blocked }
[System.IO.File]::WriteAllText('C:\Users\Administrator\Documents\HardCore\outputs\tmp_loot_sheet\row_to_full_slot_uid_map.json', ($out | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
