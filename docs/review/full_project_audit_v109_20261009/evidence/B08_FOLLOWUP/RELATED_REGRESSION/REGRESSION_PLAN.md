# B08 related native regression selection

Planning only; native NOT_RUN. Source: PlayerState `a95fe0b6875196b92e60a1e429f2915bfcdea9db772399ffe6fd18f18da90185`; GameData `dd452fdb61e07c60b7d187b1a3e48bfd98d2fe03fdc36b39345d214a06c9d7f3`. Main HEAD remains `215f0b2f651a51e6855ee813ddd99221690311a1` and differs from local current source.

## First round

Select these three existing complete real IO scenes at ordinary 30 seconds each, after the current native runner hands off and a current source/input freeze is fixed:

- `tests/world_monster_clock_persistence_test.tscn`
- `tests/world_monster_clock_legacy_migration_test.tscn`
- `tests/profile_business_validation_recovery_test.tscn`

Required skill compatibility followup, preferably fourth in the first round: `tests/skill_progression_save_integration_test.tscn`. The first three alone do not complete the skill migration scope. `tests/framework/profile_identity_generation_test.tscn` is a separate six-check runtime identity supplement, not profile IO.

## Exact scope and fixture boundaries

### tests/world_monster_clock_persistence_test.tscn

_ready 6–73; _test_preserved_backup_recovery 91–126; _test_creation_runtime_rollback 129–156.

PlayerState save_game → checkpoint snapshot/atomic world identity → character writer; real kill journal replay; profile/world/pickup backup watermark; cleanup retention; creation rollback.

All lifecycle calls remain test_mode=false; unique private profile root; 2s cleanup predicate retained. It does not select B through public select_character or deliberately fault admission TMP.

Ordinary timeout: 30s. Source-level asserts: 63 (statement count is not measured execution/check count). Evidence scope: Legacy scene marker/native natural exit/log failure gate; requires external source/input freeze, not a uniform nonzero assertion receipt.

### tests/world_monster_clock_legacy_migration_test.tscn

_ready 8–95; _test_old_writer_roundtrip 106–171; _test_interrupted_import 190–222; _test_pre_generation_migration_replay 225–249.

Legacy inline clock import/archive/rewrite; old writer return; sequence-zero backup replay; actual .tmp/.bak.tmp directory faults; migration resume; original-generation journal retention.

Explicit empty-string pre-generation ledger is supported, not numeric. Actual initial legacy fixture erases both identity headers and converts slot names; preserve this seam. Later old-writer samples retain other writer headers and therefore do not cover every pre-identity variant.

Ordinary timeout: 30s. Source-level asserts: 83 (statement count is not measured execution/check count). Evidence scope: Legacy scene marker/native natural exit/log failure gate; requires external source/input freeze, not a uniform nonzero assertion receipt.

### tests/profile_business_validation_recovery_test.tscn

_run 13–28; all nine _test_* methods 31–434; case setup 437–470.

Business admission rejection before hydration; valid backup and future terminal contracts; external cache-byte changes; profile index preservation; malformed fields; unsafe IDs; real account warehouse recovery; v6–v9 migrations.

All four persistence paths are case-local and test_mode=false. Registered item_id 80 owns renamed historical records; unknown display names alone are not unknown IDs. _valid_profile is intentionally sparse with current required fields and legacy profession seam; do not silently add newer headers that conceal migration coverage.

Ordinary timeout: 30s. Source-level asserts: 109 (statement count is not measured execution/check count). Evidence scope: Legacy scene marker/native natural exit/log failure gate; requires external source/input freeze, not a uniform nonzero assertion receipt.

### tests/skill_progression_save_integration_test.tscn

_ready 4–69; legacy Chinese 72–95; canonical v1 98–126; bounds 129–140.

Current v3 skill snapshot/profile write; false-mode load via prepared private progression; old names/v1 rank conversion; proficiency removal; integral rank clamp; persisted rewrite.

Initial save uses test_mode=true and skips world checkpoint, although save_game/_write_json_atomic still writes real profile and load_save switches false. Existing modern skill_button_assignments remain in old samples, so button assertions do not establish legacy quick_slots migration. SAVE_VERSION assertions use the constant; v8/v2 messages are stale labels.

Ordinary timeout: 30s. Source-level asserts: 28 (statement count is not measured execution/check count). Evidence scope: Legacy scene marker/native natural exit/log failure gate; requires external source/input freeze, not a uniform nonzero assertion receipt.

### tests/framework/profile_identity_generation_test.tscn

_ready 12–36; six check predicates.

Actual PlayerState creation snapshot/restore plus WorldContext capture/match profile/world generation boundaries; exact String generation retained.

test_mode=true, no profile save/read, no public select_character. Valid fixture uses 32 lowercase hex Strings a/b; do not revive numeric generation fixtures. Reuse same-body/WorldContext/Ledger contract evidence if already source-bound and unchanged; otherwise this small supplement is NOT_RUN.

Ordinary timeout: 30s. Source-level asserts: 0 (statement count is not measured execution/check count). Evidence scope: Framework explicit checks/receipt.

## Why retest / what cannot be inferred

Relevant checkpoint writer/identity, prepare-before-hydration admission and detached skill adoption changed; previous fixed-source native evidence cannot cover these new bodies. Unchanged isolated function evidence can still be reused for unrelated identity checks.

- Public A→failed B checkpoint admission with previous A blocked/unblocked and same-B retry requires the dedicated profile_load_admission_20261010_test current-source evidence; old scenes mostly call load_save directly.
- Failed/new mode catalog preparation, single signal publication and public later setters require the six mode transaction partitions; old IO regression does not substitute for that scope.
- Device/GPU/Android crash durability remains NOT_RUN here.

Business fixture `_valid_profile` has current required fields and exact profile_id; no UUID restriction exists at _valid_profile_storage_id (nonempty, no slash/backslash, not dot paths). Clock generation must be String: empty pre-generation or exact 32 lowercase hex. JSON integral numeric wire values may be float; do not confuse int/float representation with value loss, or relax nonintegral/string validation. Future identity/skill contracts remain terminal, not a reason to fall back silently.

Skill legacy samples keep the modern skill_button_assignments from the initial writer. PlayerState 7474–7501 delegates to SkillLoadoutRules 28–51, whose exact modern contract wins over legacy_center. Existing binding assertions therefore prove retained modern assignments; they do not prove a historical quick_slots-only migration was exercised. Preserve original scenario, and record this missing coverage rather than claiming closure.

## Conditional wrapper grouping / ownership

MISSING: No current-source runtime duration for these five existing scenes collected in this read-only task. Source count is not timing. Full original first; split only justified by retained actual timeout/duration, never increase ordinary 30s.

Business wrappers can be additive: new script extends the existing business test and overrides deferred `_run`; reuse all existing helpers. Own only new `tests/framework/profile_business_validation_recovery_partitions_20261010.gd` plus three exact .tscn paths listed in REGRESSION_PLAN.json. Each wrapper retains state capture/restore, unique root, test_mode=false, formal case-local IO, explicit receipt and natural exit.

- `primary_cache`: `_test_profile_primary_backup_matrix`, `_test_cached_profile_write_detects_external_change`
- `future_index_scalar`: `_test_future_profile_blocks_fallback_and_save`, `_test_profile_index_validation_and_recovery`, `_test_profile_index_update_preserves_unloadable_entries`, `_test_profile_scalar_validation_and_high_level_compatibility`, `_test_invalid_profile_id_cannot_escape_profile_directory`
- `shared_legacy`: `_test_shared_warehouse_validation_and_recovery`, `_test_legacy_versions_and_shapes_migrate`

Clock persistence and legacy scenes contain significant assertions inline in `_ready`. A wrapper that only calls their helper functions would lose the inline contract. If actual timing requires splitting later, assign one worker exclusive ownership of the corresponding existing .gd and new exact wrapper files, extract the inline block without changing predicates, then execute all groups listed in REGRESSION_PLAN.json. Persistence retains all profile/world/pickup modes; legacy retains two old-writer rounds, both filesystem faults and pre-generation replay. Keep every existing 2s cleanup deadline and ordinary 30s external window.

Skill remains whole by default. Later partitioning must give each migration helper its original freshly written base document and persistence roots; splitting dependent helpers over a shared mutable process/profile is not independent evidence. Profile identity is already small and does not need splitting.

Partition union receipts must map every original assertion family to an executed group at one fixed source set. They do not convert a retained full-scene timeout into PASS. No production/test/runner/index edits or native execution were performed here.

## Artifacts / protection

`REGRESSION_PLAN.json`: exact selection, functions, reasons, risks and wrapper groups. `SOURCE_BINDINGS.json`: all precise input SHA256s. `PROPOSED_COMMANDS.ps1.txt`: unexecuted proposed ordinary runner entry. `PLAN_RECEIPT.json`: plan-only verification and protection.

Real index SHA256: `ddacea4eed570faed0a6003c87352552e74e902874b5dee61d8863a2316e29d7`.

## Native67 actual retained result

Read the original runner and freeze/postverify on 2026-10-10. Original complete persistence, legacy migration and business recovery scenes: 3/3 PASS, natural exit 0, timeout=false, stdout/stderr/engine failures all zero. Postverify retains all 2551 actual inputs unchanged and both engine identities; freeze SHA256 equals the runner source_content_sha256.

| Scene | Wrapper start to observed native exit | Ordinary window | Native result | Formal assertion receipt |
|---|---:|---:|---|---|
| `tests/world_monster_clock_persistence_test.tscn` | 6.343897s | 30s | PASS | MISSING |
| `tests/world_monster_clock_legacy_migration_test.tscn` | 6.536362s | 30s | PASS | MISSING |
| `tests/profile_business_validation_recovery_test.tscn` | 6.811042s | 30s | PASS | MISSING |

These observed complete scene costs do not justify splitting them. Every runner row explicitly retains `formal_evidence_status=MISSING`, `legacy_run_bound_checks_missing` and `framework_receipt_missing`; this supplement does not invent complete receipts or execution check counts. The immutable candidate tree is `f5abae6e2fc6eeb19f094654a94311adb5cc309c`, invocation `77778699-c458-4e31-9eaf-241163d2ecff`, source/input freeze digest `6f5f698e68069666e47ca55259a25d0fcc1d4ec81d4345fc6927f3919ab92472`. Full original paths and fingerprints are in NATIVE67_RECORDED_RESULT.json.

Native68 old skill and legal Taoist new admission are pending owner work in this supplement; no result is inferred. Future fixed review SHA semantic acceptance and device validation remain NOT_RUN here.
