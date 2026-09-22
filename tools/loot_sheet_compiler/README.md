# Loot Sheet Compiler

The production authority is compiled from the user's frozen workbook content.
Its archived source workbook SHA256 is
`bc234fca54286547b07f64731c9d0e3674aa19a703863c393c356caf97005251`.
The default build reconstructs its inputs from versioned evidence. It does not
require the original desktop workbook, a temporary extraction directory, or
an earlier machine's untracked `outputs/tmp_loot_sheet` files.

## Build

Run from the repository root, choosing the output directory explicitly:

```powershell
pwsh -NoProfile -File tools/loot_sheet_compiler/compile_authority.ps1 `
  -ProjectRoot . -OutputDir outputs/loot_sheet_rebuild
```

The compiler invokes `prepare_archive_inputs.ps1` into
`<OutputDir>/source_inputs`, then reads the two regenerated standard inputs:

- `loot_sheet_parsed.json`
- `row_to_full_slot_uid_map.json`

The compiler writes its result and diagnostics under the selected output
directory. Review the generated authority and run the relevant authority and
runtime tests before a separately authorized production installation. Preparing
inputs alone never writes a production table.

The optional compiler `-WorkbookPath` is an additional hash check of the same
frozen workbook; it does not authorize importing a different workbook or replace
the archived input preparation. `parse_xlsx.ps1` remains a historical extraction
tool and is not part of the reproducible default build.

## Prepare or verify archived inputs separately

The two preparation scripts support Windows PowerShell 5.1 and PowerShell 7.
They use UTF-8 source files with BOM for Windows PowerShell's Chinese path/column
parsing. All evidence text bindings use `utf8_lf_text`: decode UTF-8, normalize
CRLF to LF, then hash UTF-8 bytes. The original input raw hashes are separately
recorded as provenance and are not checkout-line-ending gates.

```powershell
# OutputDir is mandatory; ProjectRoot defaults to the script's repository.
pwsh -NoProfile -File tools/loot_sheet_compiler/prepare_archive_inputs.ps1 `
  -ProjectRoot . -OutputDir outputs/loot_sheet_source_inputs

# Optional full field/type/null/array-order comparison with an accepted input set.
# This reference is verification-only and is never a reconstruction source.
pwsh -NoProfile -File tools/loot_sheet_compiler/prepare_archive_inputs.ps1 `
  -ProjectRoot . -OutputDir outputs/loot_sheet_source_inputs_checked `
  -VerifyAgainstDir outputs/tmp_loot_sheet

# Independently validate/replay the exact 320-row UID binding.
pwsh -NoProfile -File tools/loot_sheet_compiler/group_merged_rows_v4.ps1 `
  -ProjectRoot . -OutputDir outputs/loot_sheet_uid_binding
```

The scripts fail on missing evidence, source/seal hash drift, invalid ownership,
UID count/order drift, non-exact reconstructed content, or a comparison mismatch.
Preparation validates all inputs and optional comparisons before creating its
output directory. Success prints output SHA256 values and the counts.

## Tracked reconstruction evidence

`evidence/archive_input_bindings_v1.json` is sealed in both scripts and binds:

- `workbook_rows_4883.json`: archived cell values, original numeric E text,
  expanded formulas, row coordinates and exact monster identities.
- `workbook_summary.json` and `sheet_coverage_126.json`: source SHA,
  worksheet order, named/residue row counts and five explicit empty sheets.
- `SOURCE_BINDINGS.json`: original workbook provenance.
- The original merged-row and residue CSVs.
- `row_to_full_slot_uid_map.v1.json`: the complete accepted UID mapping.
- `assets/data/drop/dpv2_direct_baseline_v2.json`: exact baseline records.

The archive has 4,883 rows. Exactly seven CSV-listed nameless residue rows are
excluded, producing 4,876 named rows in 126 worksheets. Five worksheets remain
explicitly empty. The archived cell export does not distinguish absent XML cells
from present empty XML cells. To reproduce the accepted parser representation
exactly, the binding manifest records 125 null fields at 25 exact row coordinates.
These entries may restore only an archived null/empty value; they cannot discard
nonempty source data. The entire reconstructed JSON must also match its sealed
compact-JSON digest.

The merged binding contains 320 rows and 1,420 distinct baseline UIDs. Every
row is checked against the original CSV, and each member UID must exist in the
sealed baseline, belong to the exact monster, preserve baseline order, and retain
the accepted base fraction. Cardinality, representative identity, duplicates
and full JSON are checked.

The old `mode` fields are provenance only. There is no current same-base or
neighbor-search inference. Of the historical assignments, 317 used
`item_base_all`; three used `base_run_from_rep` and contain different items:

| Monster / worksheet row | Exact accepted item IDs |
| --- | --- |
| 92 / 23 | 174, 200 |
| 94 / 23 | 174, 200 |
| 225 / 34 | 224, 223 |

The original CSV gives only representative UIDs; it cannot independently prove
all memberships in those groups. Their precise previously accepted mapping is
preserved as the versioned input, including those three outputs. Rebuilding never
guesses the missing memberships again.

## Probability and identity invariants

- Worksheet E supplies final per-slot probability; D supplies the gold amount.
  The runtime must not apply SPB/V5/classification/v80/v81/global multipliers again.
  Later explicitly authorized directive overlays are separately versioned inputs
  handled by the compiler; the preparation scripts do not modify them.
- 67 numeric cells are checked against
  `evidence/02_数字爆率67行_分数重建候选.csv`.
- 41 new equipment rows are checked against
  `evidence/01_新增物品41行.csv`.
- Seven residue rows are excluded by preparation and recorded as parser exclusions;
  the compile stage should not silently invent additional exclusions.
- Empty sheets 食人花/蝎子/毒蜘蛛/羊/狼 remain explicit empty profiles.
- Duplicate draws retain distinct deterministic output UIDs. Existing
  `_r<sheet_row>` disambiguation is recorded by the compiler; preparation retains
  the full accepted input mapping.
- The 15-item ground-output limit and priority selection are runtime contracts.
  Reconstructing inputs does not change either behavior.
- `evidence/armor_single_slot_directive_v92.json` records the user's deletion of
  duplicate clothing trials after female-to-male output normalization. The compiler
  removes 102 exact UIDs across 37 monsters, retains each surviving slot's original
  probability and order, and verifies the six dark-boss top-clothing exceptions.
  It must not restore deleted draws when expanding the archived worksheet groups.
- Neither preparation script edits the workbook, production authority, baseline,
  equipment master, map data, or the sealed original review evidence.

See `docs/repair_v92/LOOT_COMPILER_REPRODUCIBILITY.md` for exact validation
commands, artifact hashes, source-only and failure-case evidence.
