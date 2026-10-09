# Local-only source triage

Status: `NOT_RUN` for remote/full audit coverage. Fixed B01 remains `dbd78d3301c2af6cfd9e070abe8cc847e6353175`. Root corrected an initial membership error caused by Git quoting Chinese filenames: all seven CSVs and three skill Markdown contracts were already in B01/61d, not missing source. The actual local-only set is two Android build/preflight files plus 26 retired grid/test paths. The six new repair fixtures are already in B01. Recommendations below preserve source roles and hash binding; they do not regenerate runtime data or restore the grid design.

## Findings

Root extension check additionally found `tools/android_java_loopback_probe.java`, invoked by the environment helper. The initial reviewable-text extension list omitted Java. The source-preservation overlay adds these two build files; `AUTHORING_INPUT_BINDING.json` also hashes ten already-present authoring files. This does not rerun the unchanged, previously verified Java/export fix.

| group | paths | current reference/use | classification and fixed-source recommendation |
|---|---|---|---|
| Android Java environment | `tools/android_java_environment.ps1` | `tools/build_android_isolated.ps1:358` dot-sources it; `docs/ANDROID_BUILD_ENVIRONMENT.md:6` documents the same build contract. | **Formal build helper, not runtime gameplay.** It must be uploaded or otherwise bound by hash for reproducible Android export/build review. A source review that excludes this file can still review desktop runtime, but must mark Android build coverage `BLOCKED`/`MISSING`. |
| Loot input 01 | `tools/loot_sheet_compiler/evidence/01_新增物品41行.csv` | `tools/loot_sheet_compiler/compile_authority.ps1:74`; README documents it at line 126. | **Required authoring input.** It is consumed by the authority compiler, so it is not evidence-only. Add to the fixed source or a content-addressed build-input bundle and record its raw-byte SHA. |
| Loot input 02 | `tools/loot_sheet_compiler/evidence/02_数字爆率67行_分数重建候选.csv` | `compile_authority.ps1:52`; README line 124. | **Required authoring input.** Pin/upload with the compiler revision; otherwise drop compilation is not reproducible. |
| Loot input 03 | `tools/loot_sheet_compiler/evidence/03_合并独立槽320行_待绑定完整UID.csv` | `group_merged_rows_v4.ps1:39`; `archive_input_bindings_v1.json:9` already records a SHA. | **Required authoring input with existing partial binding.** Preserve the existing hash and bind the actual file bytes to the fixed source or immutable input bundle. |
| Loot input 04 | `tools/loot_sheet_compiler/evidence/04_五张空表与七条残留.csv` | `compile_authority.ps1:101,107`; `prepare_archive_inputs.ps1:76`; `dpv2_user_loot_sheet_authority_v1.json:34`; `archive_input_bindings_v1.json:10`. | **Required authoring/residue input with existing partial binding.** Preserve its existing hash and compiler role. Do not reclassify as retired evidence. |
| Loot evidence 05 | `tools/loot_sheet_compiler/evidence/05_目录计数75处过期.csv` | No current executable reference was found in the compiler or drop runtime search. | **Evidence-only/history candidate.** Preserve it for provenance, but do not make it a runtime or build prerequisite without a new explicit consumer. If retained in the fixed review bundle, label it evidence-only and hash it. |
| Loot evidence 06 | `tools/loot_sheet_compiler/evidence/06_F列八处非联动公式.csv` | No current executable reference was found in the compiler or drop runtime search. | **Evidence-only/history candidate.** Same boundary as 05; retain for audit traceability, not as a compiler input. |
| Loot input 07 | `tools/loot_sheet_compiler/evidence/07_全部具名奖励4876行.csv` | `compile_authority.ps1:94`; `assets/data/drop/technique_drop_source_policy_v1.json:4`. | **Required authoring input.** The drop policy names it as source authority; it must be fixed-source or immutable-input bound. |
| Skill authoring spec | `assets/data/vanilla_176/skill_source_package_v1_0_1/CODEX_施工总指令_v1.md` | Listed in package `manifest.json:15`; README says it is the executable construction instruction. | **Authoring contract.** Not loaded as a runtime file, but required to audit provenance and generated/runtime parity. Upload/hash with the package. |
| Skill authoring spec | `assets/data/vanilla_176/skill_source_package_v1_0_1/MIR2_176_33技能_Codex施工规格_v1.0.1.md` | `manifest.json:20`; README identifies it as the complete human-readable specification. | **Authoring contract.** Keep alongside the machine SOT JSON; do not treat the JSON alone as sufficient review provenance. |
| Skill migration spec | `assets/data/vanilla_176/skill_source_package_v1_0_1/MIR2_176_当前差异与迁移清单_4b6ea4e0.md` | `manifest.json:25`; README identifies it as migration order. | **Authoring/migration contract.** Required to review generated/runtime changes and migration omissions; upload/hash with the package. |
| Retired grid adapter | `scripts/monster_ai_package/grid_crowd_trial.gd` | Preloaded by `tests/crowd_formal_grid_comparison_20261008.gd:108`; formal grid tests call `configure_grid_crowd_trial` at lines 116–123. | **Retired experiment/test-only adapter.** No production consumer was found. Preserve for historical evidence, but do not restore it to Enemy/GameRoot runtime. A remote audit of the old grid evidence remains `BLOCKED` until these local paths are supplied. |
| Retired grid service | `scripts/monster_ai_package/grid_occupancy_service.gd` | Preloaded by `grid_crowd_trial.gd:8`; directly used by `tests/crowd_grid_occupancy_contract_20261008.gd` and related grid fixtures. | **Retired experiment/test-only service.** Same boundary; no production inclusion recommendation. |

## Local-only test/fixture paths

The 24 retired fixtures below remain outside the fixed review source. The six repair fixtures in the next subsection are already included in `dbd78d3301c2af6cfd9e070abe8cc847e6353175` with their exact source/input receipts; inclusion is not equivalent to external review coverage.

### Retired grid experiment fixtures

- `tests/crowd_engagement_scaling_20261008.gd`
- `tests/crowd_engagement_scaling_20261008.tscn`
- `tests/crowd_formal_grid_comparison_20261008.gd`
- `tests/crowd_formal_grid_comparison_20261008.tscn`
- `tests/crowd_grid_cost_probe_20261008.gd`
- `tests/crowd_grid_cost_probe_20261008.tscn`
- `tests/crowd_grid_near_guidance_20261008.gd`
- `tests/crowd_grid_near_guidance_20261008.tscn`
- `tests/crowd_grid_occupancy_contract_20261008.gd`
- `tests/crowd_grid_occupancy_contract_20261008.tscn`
- `tests/crowd_grid_partial_terrain_20261008.gd`
- `tests/crowd_grid_partial_terrain_20261008.tscn`
- `tests/crowd_grid_simulation_20261008.gd`
- `tests/crowd_grid_simulation_20261008.tscn`
- `tests/crowd_local_cache_contract_20261008.gd`
- `tests/crowd_local_cache_contract_20261008.tscn`
- `tests/crowd_target_cell_comparison_20261008.gd`
- `tests/crowd_target_cell_comparison_20261008.tscn`
- `tests/crowd_v107_cost_growth_20261008.gd`
- `tests/crowd_v107_cost_growth_20261008.tscn`
- `tests/crowd_v107_detailed_cost_20261008.gd`
- `tests/crowd_v107_detailed_cost_20261008.tscn`
- `tests/helpers/crowd_grid_terrain_cache_probe.gd`
- `tests/helpers/crowd_v107_profile_trace.gd`

These are the paths coupled to the two local `grid_*` scripts. Their presence is not a reason to reintroduce the rejected grid runtime path.

### Follow-up repair fixtures

- `tests/passive_wake_projection_recovery_20261009.gd`
- `tests/passive_wake_projection_recovery_20261009.tscn`
- `tests/passive_wake_stale_target_repair_20261009.gd`
- `tests/passive_wake_stale_target_repair_20261009.tscn`
- `tests/safe_logout_pending_retry_repair_20261009.gd`
- `tests/safe_logout_pending_retry_repair_20261009.tscn`

The v108 follow-up receipts reference these scenes, including the stale-target, projection-recovery, and safe-logout runners. They are meaningful direct fixtures included in the fixed dbd review source. External coverage remains NOT_RUN until actually reviewed; runtime evidence is reused only within its recorded source and input boundaries.

## Recommended fixed-source action

1. Add `tools/android_java_environment.ps1` to the fixed build-input boundary and bind it with `build_android_isolated.ps1`, the engine/export inputs, and raw-byte hashes.
2. The seven CSV files already exist in B01/61d. Preserve exact input bytes and role labels. Raw-byte binding is recorded in the audit package; normalized archive03/04 hashes match their existing authority binding. Do not change that authority contract or regenerate the table merely for auditing. Keep05/06 evidence-only.
3. The three skill Markdown contracts already exist in B01/61d alongside the package manifest and machine SOT. Record hash binding and review them with their consumers; no restoration or generation is needed.
4. Keep the grid adapter/service and 24 grid fixtures outside production. Upload them only for a historical grid-audit batch, marked `NOT_RUN` or `BLOCKED`; do not make them required runtime files.
5. Include the six authorized follow-up fixtures in the fixed review overlay when their direct contracts are part of the fixed review. Until then, retain their existing receipts as source-bound historical evidence and mark remote coverage `MISSING`.

No conclusion here changes gameplay, budget, wake, loot, skill, or build behavior. This document is a dependency and source-boundary triage only.
