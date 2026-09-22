param(
    [string]$ProjectRoot = "",
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutputDir,
    [switch]$ValidateOnly,
    [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# The filename is retained for existing callers. This is now a validator/replay
# of the accepted exact UID binding, not the historical grouping heuristic.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$evidenceDir = Join-Path $ProjectRoot 'tools/loot_sheet_compiler/evidence'
$manifestPath = Join-Path $evidenceDir 'archive_input_bindings_v1.json'
$ManifestSha256 = 'fb104571f478b7ab3b39dd618105b8dc1d3e5c141279034ac17f0aa64ba29ec1'

function Get-TextSha256([string]$Text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text.Replace("`r`n", "`n"))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Read-SealedText([string]$Path, [string]$Expected) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "archive input missing: $Path" }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ((Get-TextSha256 $text) -cne $Expected) { throw "archive input SHA256 mismatch: $Path" }
    return $text
}

$manifest = (Read-SealedText $manifestPath $ManifestSha256) | ConvertFrom-Json
if ($manifest.contract_id -cne 'hardcore.loot_sheet.archive_inputs.v1') { throw 'archive contract mismatch' }
if ($manifest.source_hash_mode -cne 'utf8_lf_text') { throw 'archive text hash mode mismatch' }
$mapRelative = 'tools/loot_sheet_compiler/evidence/row_to_full_slot_uid_map.v1.json'
$csvRelative = 'tools/loot_sheet_compiler/evidence/03_合并独立槽320行_待绑定完整UID.csv'
$baselineRelative = 'assets/data/drop/dpv2_direct_baseline_v2.json'
$sealed = @{}
foreach ($relative in @($mapRelative, $csvRelative, $baselineRelative)) {
    $expected = [string]$manifest.source_normalized_sha256.PSObject.Properties[$relative].Value
    $sealed[$relative] = Read-SealedText (Join-Path $ProjectRoot $relative) $expected
}
$mapping = $sealed[$mapRelative] | ConvertFrom-Json
$csvRows = @($sealed[$csvRelative] | ConvertFrom-Csv)
$baseline = $sealed[$baselineRelative] | ConvertFrom-Json
if ($mapping.blocked.Count -ne 0 -or $mapping.assigned.Count -ne 320 -or $csvRows.Count -ne 320) {
    throw 'exact UID binding must contain 320 assigned rows and zero blocked rows'
}
$csvByRow = @{}
foreach ($row in $csvRows) {
    $key = "$($row.'怪物ID')|$($row.'Excel行')"
    if ($csvByRow.ContainsKey($key)) { throw "duplicate merged CSV row: $key" }
    $csvByRow[$key] = $row
}
$slotsByUid = @{}
foreach ($profile in $baseline.profiles) {
    $index = 0
    foreach ($slot in $profile.slots) {
        $uid = [string]$slot.slot_uid
        if ($slotsByUid.ContainsKey($uid)) { throw "duplicate baseline UID: $uid" }
        $slotsByUid[$uid] = @{ mid = [int]$profile.canonical_monster_id; index = $index; slot = $slot }
        $index++
    }
}
$seenRows = @{}
$seenUids = @{}
$modeCounts = @{}
foreach ($assignment in $mapping.assigned) {
    $key = "$($assignment.mid)|$($assignment.excelRow)"
    if ($seenRows.ContainsKey($key) -or -not $csvByRow.ContainsKey($key)) { throw "unexpected/duplicate exact mapping row: $key" }
    $seenRows[$key] = $true
    $row = $csvByRow[$key]
    if (
        [string]$assignment.sheet -cne [string]$row.'工作表' -or
        [string]$assignment.item -cne [string]$row.'展示名' -or
        [string]$assignment.rate -cne [string]$row.'单槽概率' -or
        [string]$assignment.repUid -cne [string]$row.'代表槽ID' -or
        [int]$assignment.N -ne [int]$row.'独立槽个数'
    ) { throw "exact mapping does not match CSV row: $key" }
    if (-not $slotsByUid.ContainsKey([string]$assignment.repUid)) { throw "representative UID missing: $key" }
    $representative = $slotsByUid[[string]$assignment.repUid].slot
    $itemProperty = $representative.PSObject.Properties['canonical_item_id']
    $representativeItem = if ($null -eq $itemProperty) { 0 } else { [int]$itemProperty.Value }
    if ($representativeItem -ne [int]$row.'源物品ID') { throw "representative item ID mismatch: $key" }
    $uids = @(([string]$assignment.slotUids).Split('|'))
    if ($uids.Count -ne [int]$assignment.N -or $uids -cnotcontains [string]$assignment.repUid) {
        throw "exact mapping cardinality/representative mismatch: $key"
    }
    $lastIndex = -1
    foreach ($uid in $uids) {
        if (-not $slotsByUid.ContainsKey($uid) -or $seenUids.ContainsKey($uid)) { throw "unknown/reused exact UID: $uid" }
        $bound = $slotsByUid[$uid]
        if ($bound.mid -ne [int]$assignment.mid -or $bound.index -le $lastIndex) { throw "UID owner/order mismatch: $uid" }
        if (
            [long]$bound.slot.base_numerator -ne [long]$representative.base_numerator -or
            [long]$bound.slot.base_denominator -ne [long]$representative.base_denominator
        ) { throw "accepted UID base fraction drift: $uid" }
        # Full baseline content is SHA-bound above. In particular, retain the
        # three accepted mixed-item groups; do not guess/replace their identities.
        $lastIndex = $bound.index
        $seenUids[$uid] = $true
    }
    $mode = [string]$assignment.mode
    if (-not $modeCounts.ContainsKey($mode)) { $modeCounts[$mode] = 0 }
    $modeCounts[$mode]++
}
if ($seenRows.Count -ne 320 -or $seenUids.Count -ne 1420) { throw 'exact mapping coverage mismatch' }
if ($modeCounts.Count -ne 2 -or $modeCounts['item_base_all'] -ne 317 -or $modeCounts['base_run_from_rep'] -ne 3) {
    throw 'historical mapping provenance drift'
}
$compact = ConvertTo-Json -InputObject $mapping -Depth 30 -Compress
if ((Get-TextSha256 $compact) -cne $manifest.accepted_compact_json_sha256.'row_to_full_slot_uid_map.json') {
    throw 'exact UID mapping no longer equals the accepted complete JSON'
}
if (-not $ValidateOnly) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    # Preserve the archived full map, including ordering and historical mode.
    [System.IO.File]::WriteAllText(
        (Join-Path $OutputDir 'row_to_full_slot_uid_map.json'),
        $sealed[$mapRelative], [System.Text.UTF8Encoding]::new($false)
    )
}
Write-Host 'EXACT_UID_BINDING_PASS assigned=320 members=1420 blocked=0 inference=none'
if ($PassThru) { return $mapping }
