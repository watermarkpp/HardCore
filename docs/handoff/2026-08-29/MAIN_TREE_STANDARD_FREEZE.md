# HardCore Main Tree Standard Freeze — 2026-08-29

## Authority

- Formal working branch: `codex/integration`
- Formal runtime/map baseline: `00f6e5e6525a4a07679b41eb482a2cfd05fdd068`
- Consolidation commits before this record:
  - `03463a0cee370562813d3adf7d45f76cac58d25a` — preserve the Heavenly Taoist calibration capture
  - `550b1cf5` — preserve the monster replay probe and Magic Shield visual capture
- The annotated tag `standard-20260829-main-tree` identifies the immutable final commit containing this record.

Future normal development is performed in this main tree. A temporary worktree may be created for isolated work, but accepted results must be integrated back into `codex/integration` and the temporary worktree must then be removed. Runtime-safe changes may be delivered as hot patches; changes outside the patch boundary require a new APK.

## Consolidation result

- All 73 non-main worktrees were audited at commit and working-copy level before removal.
- The complete maps working state, including map editor workspaces, editor tools, asset catalogs, calibration data, tests, deliberate deletions, and historical backup files, is preserved at `archive/maps-complete-working-state-20260829` (`6bac984e76e173f6e332a610eb1f63098a564b68`).
- Current formal map placement data is already represented by canonical formal map IDs in the main tree. Legacy alias workspaces were not restored because doing so would reintroduce stale semantic IDs and fail the formal placement gate.
- DeepSeek and DSH worktrees were individually audited. Their final map editor, footprint calibration, XZSC import/calibration, deletion protection, and canonical monster editor changes are already in the ancestry of the formal baseline or are patch-equivalent. No additional DeepSeek/DSH production commit is missing.
- Old 217-monster Authority branches were not merged into the current 156-active-monster model.
- The rejected guard-culling experiment `55d961fe` and unverified startup-preload WIP `6095e3bc` were not included in the standard version.
- The only missing reusable calibration/test entries found by the all-worktree audit were imported into the main tree:
  - `tests/equipment_heavenly_taoist_direct_runtime_pilot_capture.gd/.tscn`
  - `tests/monster_draft_replay_probe.gd/.tscn`
  - `tests/magic_shield_visual_capture.gd/.tscn`

## Recovery refs

The following remote archive refs preserve material that was intentionally not enabled in the standard runtime:

- `archive/maps-complete-working-state-20260829` — complete maps/editor/calibration working snapshot
- `archive/map-monster-placement-phase0-artifacts-20260829` — phase-0 candidate and planning artifacts
- `archive/stashed-calibration-evidence-20260829` — historical map-scale and helmet-calibration evidence
- `archive/equipment-wip-20260829`
- `archive/equipment-bronze-repair-wip-20260829`
- `archive/equipment-god-magic-236-wip-20260829`
- `archive/equipment-prayer-224-directions-wip-20260829`
- `archive/monsters-combat-gu-final-audit-wip-20260829`
- `archive/p3-monster-runtime-audit-wip-20260829`
- `archive/professions-skills-wip-20260829`
- `archive/ui-single-ring-system-wip-20260829`
- `archive/visual-lab-frozen-wip-20260829`
- `archive/release-1.18.4-monster-map-wip-20260829`

Historical DeepSeek/DSH branch refs remain available for audit. They are evidence, not current runtime Authority.

## Verification

- Formal precise map placement gate: `PASS`, `1/1`, `engine_log_errors=0`
- Monster draft replay probe: `PASS`, `1/1`, `engine_log_errors=0`
- Magic Shield visual capture: `PASS`, `1/1`, `engine_log_errors=0`
- Heavenly Taoist capture emitted its formal PASS marker; its full GameRoot runner was affected by pre-existing local import/cache omissions and is not claimed as production acceptance.

Device acceptance remains user-owned. Consolidation itself does not alter the installed phone package.
