# Monster attack delivery progress handoff

Date: 2026-08-24

Status: `READY_FOR_INTEGRATION`

Source branch: `origin/codex/monsters`

Source commit: `722bf580e64bbcfd2fbcfeee95f0def2182d7b64`

Source baseline: `f964851ec6978de4266ed4a241b3db1bc0042a8c`

## Completed scope

- Restored the original transparent `Effect.wil` arrow frames 272..287 for physical archers.
- Physical arrow gameplay checks world collision at release and settlement; its visual continuously stops on `WORLD_MASK` collision.
- Split monster 220 target thunder from monster 222 caster overlay plus flying spell.
- Removed retired IDs 221 and 223 from the 220/222 runtime profile mappings.
- Rebuilt monster 70 as adjacent Race 91 magic melee with magic-defense settlement and world-collision gating; retired ID 71 from runtime activation.
- Rebuilt monster 124 as Race 107 strict Chebyshev square area magic: frozen release targets, exclusive six-GU boundary, 600ms delayed magic-defense settlement, no invented warning circle, and no LOS check because the original server class does not use `CanFly`.
- Rebuilt and checked the canonical monster runtime catalog.
- Preserved all user-approved Red Moon animation, manual grounding, and fixed-area spike artifacts byte-for-byte.

## Acceptance evidence

Final source-branch verification ran on the exact committed HEAD:

- runner `git_head`: `722bf580e64bbcfd2fbcfeee95f0def2182d7b64`
- tests: 12 passed, 0 failed
- engine log errors: 0
- canonical check: `identities=156 runtime_allowed=153`

The detailed source, collision, frozen-hash, and test report is included in the monster commit at:

`reports/monster_attack_delivery_primary_closure_20260824.md`

## Integration actions

1. Merge source commit `722bf580e64bbcfd2fbcfeee95f0def2182d7b64` from `origin/codex/monsters`.
2. Register these integration-owned formal monster-suite entries:
   - `tests/monster_physical_projectile_visual_source_test.tscn`
   - `tests/monster_target_magic_primary_visual_test.tscn`
   - `tests/monster_special_delivery_contract_test.tscn`
   - `tests/monster_special_delivery_runtime_test.tscn`
3. Re-run the 12-test acceptance set and canonical `--check` on the resulting integration HEAD.
4. Do not run a legacy batch generator over the user-approved Red Moon or fixed-area spike assets.

This handoff is a progress report only. The monster source commit has not been merged into `codex/integration` by this report commit.
