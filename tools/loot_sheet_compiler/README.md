# Loot Sheet Compiler (user spreadsheet drop authority)

Build chain that turns the user's desktop workbook
`%USERPROFILE%\Desktop\HardCore_怪物爆率分表.xlsx` into
`assets/data/drop/dpv2_user_loot_sheet_authority_v1.json`.

The compiler enforces a workbook SHA-256 gate
(`bc234fca54286547b07f64731c9d0e3674aa19a703863c393c356caf97005251`) and
aborts on any other workbook, so the chain is only reproducible against the
user's frozen file.

## Build order

```powershell
# 1. parse the frozen workbook (493556 bytes) -> loot_sheet_parsed.json
pwsh tools/loot_sheet_compiler/parse_xlsx.ps1

# 2. bind the 320 merged "等 N 个独立槽" rows to full slot UID sets
pwsh tools/loot_sheet_compiler/group_merged_rows_v4.ps1

# 3. compile the authority document (hash gate + whitelists inside)
pwsh tools/loot_sheet_compiler/compile_authority.ps1

# 4. previews / comparisons (ad-hoc review aids)
pwsh tools/loot_sheet_compiler/generate_authority_preview.ps1
pwsh tools/loot_sheet_compiler/make_import_preview.ps1
pwsh tools/loot_sheet_compiler/compare_sheet_vs_runtime.ps1
```

After step 3, copy
`outputs/tmp_loot_sheet/dpv2_user_loot_sheet_authority_v1.json` over
`assets/data/drop/dpv2_user_loot_sheet_authority_v1.json` and rerun
`tests/user_loot_sheet_authority_test.tscn` plus
`tests/rv15_provider_validation_counterexamples_test.tscn`.

## Invariants

- E column -> `final_numerator`/`final_denominator` verbatim; D column ->
  `gold_amount` verbatim. No SPB/V5/denominator-policy/v80/v81/global
  multiplier/gold x5 anywhere downstream.
- 67 numeric cells are whitelist-verified against
  `evidence/02_数字爆率67行_分数重建候选.csv` (`verified=67 failed=0`).
- 41 new equipment rows are resolved against
  `evidence/01_新增物品41行.csv` (`resolved=41 failed=0`).
- 320 merged rows bind to full UID sets from
  `evidence/03_合并独立槽320行_待绑定完整UID.csv` and
  `row_to_full_slot_uid_map.json`.
- 7 residue rows (probability with no reward identity) are excluded by the
  parser and recorded as `summary.parser_excluded_residue_rows=7`; the cell
  level evidence is `evidence/04_五张空表与七条残留.csv`. The compile stage
  itself excludes 0 rows (`excluded_residue_rows=0`).
- 5 empty sheets (食人花/蝎子/毒蜘蛛/羊/狼) compile as explicit empty
  profiles with zero slots.
- Duplicate slot UIDs inside one monster are never merged. The second
  occurrence gets a deterministic `_r<sheet_row>` suffix; the log is
  `compile_disambiguation.json` (currently 3 entries: m92 row 23, m94 row
  23, m225 row 34). Slot values are untouched by disambiguation.
- The user workbook is never modified by this chain.
