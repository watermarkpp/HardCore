param(
    [string]$ProjectRoot = "",
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$OutputDir,
    [string]$VerifyAgainstDir = ""
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Reconstruct the accepted parser inputs from tracked archive evidence only.
# No desktop workbook, extraction cache, TEMP input, or production-table write.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$evidenceDir = Join-Path $ProjectRoot 'tools/loot_sheet_compiler/evidence'
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
function Archive-String($Value) {
    if ($null -eq $Value) { return '' }
    return [Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
}
function Assert-ExactJson($Actual, $Expected, [string]$Location) {
    if ($null -eq $Actual -or $null -eq $Expected) {
        if ($null -ne $Actual -or $null -ne $Expected) { throw "JSON null mismatch: $Location" }
        return
    }
    if ($Actual -is [System.Array] -or $Expected -is [System.Array]) {
        if (-not ($Actual -is [System.Array]) -or -not ($Expected -is [System.Array])) { throw "JSON array type mismatch: $Location" }
        if ($Actual.Count -ne $Expected.Count) { throw "JSON array length mismatch: $Location" }
        for ($i = 0; $i -lt $Actual.Count; $i++) {
            Assert-ExactJson $Actual[$i] $Expected[$i] "$Location[$i]"
        }
        return
    }
    if ($Actual -is [pscustomobject] -or $Expected -is [pscustomobject]) {
        if (-not ($Actual -is [pscustomobject]) -or -not ($Expected -is [pscustomobject])) { throw "JSON object type mismatch: $Location" }
        $keys = @($Actual.PSObject.Properties.Name)
        $otherKeys = @($Expected.PSObject.Properties.Name)
        if ($keys.Count -ne $otherKeys.Count) { throw "JSON key count mismatch: $Location" }
        foreach ($key in $keys) {
            if ($otherKeys -cnotcontains $key) { throw "JSON key missing: $Location.$key" }
            Assert-ExactJson $Actual.PSObject.Properties[$key].Value $Expected.PSObject.Properties[$key].Value "$Location.$key"
        }
        return
    }
    if ($Actual.GetType() -ne $Expected.GetType() -or $Actual -cne $Expected) { throw "JSON scalar mismatch: $Location" }
}

$manifestPath = Join-Path $evidenceDir 'archive_input_bindings_v1.json'
$manifest = (Read-SealedText $manifestPath $ManifestSha256) | ConvertFrom-Json
if ($manifest.contract_id -cne 'hardcore.loot_sheet.archive_inputs.v1') { throw 'archive contract mismatch' }
if ($manifest.source_hash_mode -cne 'utf8_lf_text') { throw 'archive text hash mode mismatch' }
$sealed = @{}
foreach ($binding in $manifest.source_normalized_sha256.PSObject.Properties) {
    $sealed[$binding.Name] = Read-SealedText (Join-Path $ProjectRoot $binding.Name) ([string]$binding.Value)
}
$prefix = 'tools/loot_sheet_compiler/evidence/'
$rows = $sealed[$prefix + 'workbook_rows_4883.json'] | ConvertFrom-Json
$summary = $sealed[$prefix + 'workbook_summary.json'] | ConvertFrom-Json
$coverage = $sealed[$prefix + 'sheet_coverage_126.json'] | ConvertFrom-Json
$sourceBindings = $sealed[$prefix + 'SOURCE_BINDINGS.json'] | ConvertFrom-Json
$residueCsv = @($sealed[$prefix + '04_五张空表与七条残留.csv'] | ConvertFrom-Csv)
if (
    $summary.source_sha256 -cne $manifest.source_workbook_sha256 -or
    $sourceBindings.source_workbook_sha256 -cne $manifest.source_workbook_sha256
) { throw 'archive source workbook binding mismatch' }
if ($rows.Count -ne 4883 -or $coverage.Count -ne 126) { throw 'archive row/sheet count mismatch' }
$sheetByName = @{}
$rowsBySheet = @{}
foreach ($sheet in $coverage) {
    $name = [string]$sheet.sheet
    if ($sheetByName.ContainsKey($name)) { throw "duplicate archive sheet: $name" }
    $sheetByName[$name] = $sheet
    $rowsBySheet[$name] = [System.Collections.Generic.List[object]]::new()
}
$residueByKey = @{}
$emptyByName = @{}
foreach ($entry in $residueCsv) {
    if ($entry.'位置' -ceq '整表') {
        $emptyByName[[string]$entry.'工作表'] = [int]$entry.'怪物ID'
    } elseif ($entry.'位置' -cmatch '^E([0-9]+)$') {
        $key = "$($entry.'工作表')|$($Matches[1])"
        $residueByKey[$key] = $entry
    } else { throw 'unexpected residue evidence location' }
}
if ($residueByKey.Count -ne 7 -or $emptyByName.Count -ne 5) { throw 'residue/empty evidence count mismatch' }
$nullable = @{}
foreach ($entry in $manifest.nullable_fields) {
    foreach ($field in $entry.fields) {
        $key = "$($entry.sheet)|$($entry.row)|$field"
        if ($nullable.ContainsKey($key)) { throw "duplicate nullable binding: $key" }
        $nullable[$key] = $true
    }
}
$fieldColumns = @{ item_id = 'B'; type = 'C'; gold = 'D'; composition = 'G'; slot_raw = 'H' }
$seenRows = @{}
$seenResidue = @{}
$usedNullable = @{}
foreach ($row in $rows) {
    $name = [string]$row.sheet
    $key = "$name|$($row.row)"
    if (-not $sheetByName.ContainsKey($name) -or $seenRows.ContainsKey($key)) { throw "unknown/duplicate archive row: $key" }
    $seenRows[$key] = $true
    if ([int]$row.monster_id -ne [int]$sheetByName[$name].monster_id -or [int]$row.row -le 5) {
        throw "archive row owner/header mismatch: $key"
    }
    if ([string]::IsNullOrEmpty([string]$row.A)) {
        if (-not $residueByKey.ContainsKey($key)) { throw "unapproved nameless archive row: $key" }
        foreach ($column in @('B', 'C', 'D', 'G', 'H')) {
            if ($null -ne $row.PSObject.Properties[$column].Value) { throw "residue unexpectedly has reward identity: $key/$column" }
        }
        $residue = $residueByKey[$key]
        if ([int]$residue.'怪物ID' -ne [int]$row.monster_id -or
            ([string]$residue.'内容').TrimStart("'") -cne [string]$row.E_expanded_formula) {
            throw "residue identity/formula mismatch: $key"
        }
        $seenResidue[$key] = $true
        continue
    }
    $formula = Archive-String $row.E_expanded_formula
    if ($formula.StartsWith('=')) { $formula = $formula.Substring(1) }
    $record = [ordered]@{
        row = [int]$row.row
        item = Archive-String $row.A
        item_id = Archive-String $row.B
        type = Archive-String $row.C
        gold = Archive-String $row.D
        rate_formula = $formula
        rate_value = Archive-String $row.E_raw.raw
        composition = Archive-String $row.G
        slot_raw = Archive-String $row.H
    }
    foreach ($field in $fieldColumns.Keys) {
        $nullKey = "$key|$field"
        if ($nullable.ContainsKey($nullKey)) {
            if ($record[$field] -cne '' -or $null -ne $row.PSObject.Properties[$fieldColumns[$field]].Value) {
                throw "nullable binding would discard source data: $nullKey"
            }
            $record[$field] = $null
            $usedNullable[$nullKey] = $true
        }
    }
    $rowsBySheet[$name].Add([pscustomobject]$record)
}
$sheets = [System.Collections.Generic.List[object]]::new()
$namedCount = 0
$emptyCount = 0
foreach ($sheet in $coverage) {
    $name = [string]$sheet.sheet
    $sheetRows = $rowsBySheet[$name].ToArray()
    if ($sheetRows.Count -ne [int]$sheet.item_rows) { throw "sheet named-row coverage mismatch: $name" }
    if ($sheetRows.Count -eq 0) {
        if (-not $emptyByName.ContainsKey($name) -or $emptyByName[$name] -ne [int]$sheet.monster_id -or
            $summary.empty_monster_sheet_names -cnotcontains $name -or
            $summary.empty_monster_sheet_ids -notcontains [int]$sheet.monster_id) {
            throw "empty-sheet identity mismatch: $name"
        }
        $emptyCount++
    }
    $namedCount += $sheetRows.Count
    $sheets.Add([pscustomobject][ordered]@{ monster = $name; rows = $sheetRows })
}
if ($namedCount -ne 4876 -or $namedCount -ne [int]$summary.named_reward_rows -or
    $seenResidue.Count -ne 7 -or $emptyCount -ne 5 -or
    $nullable.Count -ne 125 -or $usedNullable.Count -ne 125) { throw 'reconstructed parser coverage mismatch' }
$parsed = [pscustomobject][ordered]@{ sheets = $sheets.ToArray() }
$mapping = & (Join-Path $ScriptDir 'group_merged_rows_v4.ps1') -ProjectRoot $ProjectRoot -OutputDir $OutputDir -ValidateOnly -PassThru
$outputs = [ordered]@{
    'loot_sheet_parsed.json' = $parsed
    'row_to_full_slot_uid_map.json' = $mapping
}
foreach ($name in $outputs.Keys) {
    $compact = ConvertTo-Json -InputObject $outputs[$name] -Depth 30 -Compress
    if ((Get-TextSha256 $compact) -cne $manifest.accepted_compact_json_sha256.PSObject.Properties[$name].Value) {
        throw "reconstructed complete input differs from accepted binding: $name"
    }
    if (-not [string]::IsNullOrWhiteSpace($VerifyAgainstDir)) {
        $referencePath = Join-Path ([System.IO.Path]::GetFullPath($VerifyAgainstDir)) $name
        if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) { throw "comparison input missing: $referencePath" }
        $reference = Get-Content -LiteralPath $referencePath -Raw -Encoding UTF8 | ConvertFrom-Json
        # Compare JSON scalar types, not PowerShell's Int32 vs JSON's Int64.
        $roundTripped = $compact | ConvertFrom-Json
        Assert-ExactJson $roundTripped $reference $name
    }
}
# All source, identity, full-output and optional field comparisons passed.
# Only now create/write the caller's explicitly selected output directory.
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$written = [ordered]@{}
foreach ($name in $outputs.Keys) {
    $text = ConvertTo-Json -InputObject $outputs[$name] -Depth 30
    $path = Join-Path $OutputDir $name
    [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
    $outputSha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $written[$name] = [BitConverter]::ToString(
            $outputSha.ComputeHash([System.IO.File]::ReadAllBytes($path))
        ).Replace('-', '').ToLowerInvariant()
    } finally { $outputSha.Dispose() }
}
Write-Host 'ARCHIVE_INPUT_PREPARATION_PASS sheets=126 named_rows=4876 excluded_residue=7 empty_sheets=5 mappings=320 nullable_fields=125'
foreach ($name in $written.Keys) { Write-Host "$name SHA256=$($written[$name])" }
