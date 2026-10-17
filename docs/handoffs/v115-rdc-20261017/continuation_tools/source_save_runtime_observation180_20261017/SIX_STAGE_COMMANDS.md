# Source save six-stage execution — prepared, NOT_RUN

Do not execute these commands until parent supplies explicit actual original World **and normal exit PASS**, matching framework/runner/source-manifest evidence, and completed source/index protection. No snapshot has been created by this preparation. Native is58a1 and the actual Windows PE pair is bound in CANDIDATE_BINDING.json. Never reuse an older World snapshot or overlay the frozen chunk8 fixtures.

The exact current binding revision is recorded in `CANDIDATE_BINDING.json`; the previous4035 bundle is preserved byte-for-byte in `UPSTREAM_REVIEWED_BINDING.json`. Historical `source_changes` remain unchanged. The current revision records the authorized Heavy60 semantic classification, current runner SHA and explicit new Native58a/actual-PE identity. All six stages must use the same revision, actual source snapshot and engine pair.

## Commands after the real upstream gate

Fill the three evidence paths with the parent's actual PASS run. The framework receipt must belong to `character_source_full_world_20261016`, native exit0, engine errors0 and matching invocation/run/source. The actual upstream runner's PE pair must match the fixed pair. Its `PROTECTION.json` must have completed with source/index preservation true. The actual tool rechecks matching current production inputs before copying.

```powershell
$o = 'C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore/outputs/v115_multicore/source_save_runtime_observation180_20261017'
$snapshot = "$o/snapshot_world_pass_20261017_01"
$engine = 'C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore/outputs/v115_multicore/codex_resume_20261015_182255/windows_map_reply_observation_20261017_build/Godot_v115-stable_win64_console.exe'
$nativeManifest = 'C:/Users/Administrator/.codex/worktrees/multicore-v115/HardCore/outputs/v115_multicore/codex_resume_20261015_182255/SOURCE_MANIFEST.map_reply_observation_20261017.json'

# REQUIRED: actual parent PASS files. Do not substitute the current FAIL run.
$upstreamReceipt = '<actual PASS framework receipt absolute path>'
$upstreamRunner = '<same actual PASS runner_results absolute path>'
$upstreamManifest = '<same actual PASS SOURCE_MANIFEST.json absolute path>'

function RequireNativeSuccess([string]$stage) {
    if ($LASTEXITCODE -ne 0) { throw "$stage failed; preserve all outputs and diagnose before proceeding." }
}

# Exactly one newly copied physical project. This is still forbidden before the gate above.
python "$o/prepare_snapshot.py" --destination $snapshot --upstream-source-manifest $upstreamManifest --native-manifest $nativeManifest
RequireNativeSuccess 'snapshot preparation'

$common = @('--snapshot', $snapshot, '--engine', $engine,
    '--upstream-receipt', $upstreamReceipt,
    '--upstream-runner', $upstreamRunner,
    '--upstream-source-manifest', $upstreamManifest,
    '--native-manifest', $nativeManifest)

python "$o/run_stage.py" @common --profile warrior --phase deposit --label source_save180_warrior_deposit_20261017_01
RequireNativeSuccess 'warrior deposit'
python "$o/run_stage.py" @common --profile warrior --phase withdraw --label source_save180_warrior_withdraw_20261017_01 --prior-stage "$o/stages/source_save180_warrior_deposit_20261017_01"
RequireNativeSuccess 'warrior withdraw'

python "$o/run_stage.py" @common --profile wizard --phase deposit --label source_save180_wizard_deposit_20261017_01
RequireNativeSuccess 'wizard deposit'
python "$o/run_stage.py" @common --profile wizard --phase withdraw --label source_save180_wizard_withdraw_20261017_01 --prior-stage "$o/stages/source_save180_wizard_deposit_20261017_01"
RequireNativeSuccess 'wizard withdraw'

python "$o/run_stage.py" @common --profile taoist --phase deposit --label source_save180_taoist_deposit_20261017_01
RequireNativeSuccess 'taoist deposit'
python "$o/run_stage.py" @common --profile taoist --phase withdraw --label source_save180_taoist_withdraw_20261017_01 --prior-stage "$o/stages/source_save180_taoist_deposit_20261017_01"
RequireNativeSuccess 'taoist withdraw'
```

Each phase has the exact user-authorized 180s functional bound for `tests/framework/source_save_roundtrip_20261017.tscn`. The wrapper passes its existing `TimeoutSeconds=60` plus the exact `ApprovedSourceSave180` flag; this does not change normal30/known-heavy60 scenes or the separate original fullWorld120 exception.

## What every phase must prove

The first real CharacterSelect entry commits one actual SourceSession/Profile, loads an actual original player view and executes reliable original Profile commands. Deposit unequips the original archived helmet, deposits it into the real warehouse and saves it. Wizard's original overweight rejection must remain visible; only the original prepared medicine deposit may make room, retaining every medicine's count/attributes. No level, requirement, item or weight authority is changed.

Return uses the actual original SystemMenu CHARACTER_SELECT signal. The fixture requires actual terminal profile export, original Native prefix ACK, source object absence, nine-owner unbind, physical old Root/hall absence, fresh original Main authority, exact state adoption and actual terminal default-PCG stream restoration. It checks one actual resumed Main draw and idempotent restore receipt. Then it enters a new actual Host/Session/Profile, captures the current persisted state, compares progression and full-container ownership, and exits through original normal QUIT.

Each profession's withdraw starts a new process from **its own successful deposit** checkpoint and binary witness. It verifies the real equipment in warehouse, withdraws it, equips its original slot, saves and repeats genuine return/reentry/QUIT. Warehouse data cannot leak across professions: each deposit copies only its frozen original corpus, while each withdraw accepts only its matching profession's verified deposit checkpoint. Labels, appdata, control records and scenario inputs are separate, but production source and engine remain the same physical snapshot.

## Evidence and stopping conditions

Only `STAGE_RESULT.json` after actual native0, valid formal receipt, engine errors0, no cleanup leak warning, source/index protection true and correlated phase/profile/witness/checkpoint is a successful stage. Raw logs remain in `stages/<label>/runner.log` and `snapshot/outputs/v115_multicore/invocations/<label>`. The same-profile disk checkpoint and full binary witness are preserved after success. A failed stage may have no `STAGE_RESULT.json`; that is FAIL/BLOCKED, not a missing success to fabricate. Preserve the failed invocation and use a fresh label/snapshot revision only after the exact cause is resolved.

Final acceptance must report all six separate stages, Native/PE/source fingerprints, exact profile IDs/helmet UIDs, level/XP/gold/canonical skills/proficiency and every inventory/equipment/warehouse record/count. Whole-account conservation is based on stable instance IDs plus complete attribute/count signatures; no field subset or approximate numeric equality. Original user data remains read-only; compare it again to the saved 325-file before-protection record after all stages, without restoring/overwriting any discrepancy.
