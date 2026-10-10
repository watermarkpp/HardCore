# B07A-006 compiler write-set analysis

Status: PASS for the isolated replay and failure injection. This is a disposable compiler analysis; no project authority, authoring source, runtime generated file, Git state, or engine was changed.

The external finding is bound to source review SHA `684824ac7bb59ac903054b26b3435441b8a2f152`. The current local producer was copied into the isolated replay from worktree HEAD `215f0b2f651a51e6855ee813ddd99221690311a1`; the copied `compile_authority.ps1` SHA256 is `c0f110f15febabf13aa8a297f1969bd0597411104d91e8cd77cf7bfd4693cf7e`. The isolated copy included the complete `tools/loot_sheet_compiler` evidence/archive input set and the required current data inputs: `dpv2_direct_baseline_v2.json`, `equipment_attribute_master.json`, `equipment_female_armor_attribute_evidence.json`, `technique_drop_source_policy_v1.json`, `boss_material_drop_directive_v1.json`, and `runtime/canonical_monster_catalog.json`.

The compiler's real producer is `tools/loot_sheet_compiler/compile_authority.ps1`. It validates the archived parsed workbook rows, baseline slot records, overlays, armor directive, technique policy, boss material directive, and final sheet-equivalent output before reaching the three live writes at lines 630-632:

1. `dpv2_user_loot_sheet_authority_v1.json`
2. `compile_disambiguation.json`
3. `armor_single_slot_audit.json`

There is no shared transaction, temporary publish set, readback journal, rollback, or recovery marker around those writes. The existing Python equipment generator is not a reusable transaction authority: `tools/build_equipment_attribute_master.py` also performs sequential `write_text` calls for its master/runtime/audit outputs. It is relevant evidence of the same gap, but it was not modified or used as a substitute compiler.

## Normal isolated replay

Command, executed from the project root with `pwsh`:

```text
pwsh -NoProfile -ExecutionPolicy Bypass -File <isolated-project>/tools/loot_sheet_compiler/compile_authority.ps1 -ProjectRoot <isolated-project> -OutputDir <isolated-output>
```

Exit code was `0`. The real compiler reported:

```text
EXACT_UID_BINDING_PASS assigned=320 members=1420 blocked=0 inference=none
ARCHIVE_INPUT_PREPARATION_PASS sheets=126 named_rows=4876 excluded_residue=7 empty_sheets=5 mappings=320 nullable_fields=125
ARMOR_SINGLE_SLOT_DIRECTIVE_PASS before=6144 after=6042 removed=102 groups=102 frozen=6 non_armor_unchanged=True
TECHNIQUE_SOURCE_POLICY_PASS removed=1 ... owned_instances=preserved
disambiguated_uids=3
compiled: named=4876 slotRows=5831 newSlots=41 fate=1 overlay=168 excluded=0 emptySheets=[食人花,蝎子,毒蜘蛛,羊,狼] monsters=126
COMPILE_AUTHORITY_PASS
```

The normal output set is under `outputs/wake_drop_v108_review_followup_20261009/b07a_compiler_writeset/replay_output_pwsh5/`. The generated authority SHA256 is `3c371628c2d0f51023a5c059439020f756a3762c88c3ae6ea4fa4a5790c99aff`; disambiguation is `cae2e67d86c7a119fa24b6b0a7804a0f31e984fae2f34d813395f0e460de6182`; armor audit is `b71e42c72067b468f8309a0afdaf2987fd2c55f9dceb5e172ed6a7364350705c`. Input preparation emitted 126 sheets and 4,876 named rows, so the replay did not reduce the workload or alter probability inputs.

## Real write-failure injection

The failure injection used a Windows file handle with `FileShare.None` on a disposable output file. It did not mock the compiler or replace any generated value.

* Locking the first authority output caused exit code `1` before any live output was published. The sentinel authority bytes remained unchanged (`6383933fcc55c70ae28574b628b256d7b1b939181a0fa4db90f955557d20150f`), and no second or third output was created. This is fail-closed only because the first write failed.
* Locking the second output caused exit code `1` at the real `WriteAllText` call on line 631. The first authority file was already replaced with the new 1,973,313-byte authority, the locked second sentinel remained unchanged (`21f4c834e8e609cdea61f23ef7d6afa425435f880b794ca444a3663161cb80a7`), and the third audit file was absent. This is the proven partial-publish state described by B07A-006.

These runs prove the static risk with a real OS lock and the real compiler. They do not simulate process termination or power loss; that branch remains `NOT_RUN`. The isolated replay and logs are preserved under `outputs/wake_drop_v108_review_followup_20261009/b07a_compiler_writeset/`, with `B07A_REPLAY_RECEIPT.json` binding commands, exits, input hashes, output hashes, and source identity.

## Minimal repair recommendation

Keep the existing compiler and all source/probability contracts, but change only publication ownership:

1. Build all three serialized outputs in memory and validate every output by parsing/readback before touching live paths.
2. Write all three to a generation-specific staging directory or sibling temporary paths under the same filesystem, using exclusive creation and exact target names.
3. Write a small journal containing producer/source hash, generation token, target relative paths, previous hashes, and staged hashes; fsync where the platform API permits.
4. Promote the complete set through an existing transaction helper or a clearly ordered recovery protocol. On any failed promote, restore the previous complete set from the journal and return a nonzero result; never leave a new first output paired with an old second/third output.
5. On the next invocation, recover only a journal whose target names, generation, map/source identity, and hashes match exactly. Preserve newer unrelated/manual bytes and fail closed on a third version or corrupt journal.

This is a write-set durability repair only. It must not add a second loot authority, change the 6,083/126/profile/slot/probability inputs, or infer a new drop policy.
