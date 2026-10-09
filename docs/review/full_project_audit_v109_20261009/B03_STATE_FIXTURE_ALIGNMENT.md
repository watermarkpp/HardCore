# B03 State Fixture Alignment

## Scope

Static fixture-only correction for `tests/summon_actor_state_machine_test.gd`. No production script was changed and no Godot/native test was run. The shared worktree already contained unrelated fixture edits before this correction; they are preserved.

Preimage captured before this correction:
- `outputs/release_v108_20261009/B03_state_fixture_alignment/preimage/summon_actor_state_machine_test.gd`
- SHA-256: `FF96E436905A6AE76BC1EC07E94A0342F9EADA890BB45B71BE0B1A63DC679E15`

## Confirmed cause

The far-follow block previously called `_canonical_summon_follow_landing_plan()` for both pets before either pet was moved or processed. The production authority does not reserve both plans as a batch: `_canonical_summon_follow_landing_plan()` builds a pending list containing only the summon being serviced (`scripts/game_root.gd:12259-12285`), and the actual callback then relocates one summon before the next callback is reached. The second plan therefore must observe the first summon’s newly published position and occupancy.

The old fixture made both plans from the same pre-move occupancy and then moved both pets to the same far position. That input ordering could make the second expected plan disagree with the production order, producing the related33 failure at the second-pet position assertion.

## Minimal fixture change

The far-follow section now:

1. Binds both pets to the formal main-pet projection/context.
2. Places and plans the skeleton first.
3. Runs the skeleton’s real `_physics_process(1.0 / 60.0)` so its formal landing/publication occurs.
4. Places and plans the divine beast after that publication.
5. Runs the divine beast’s real physics callback and compares each final position with the plan observed immediately before that callback.
6. Retains the existing separation and formal position-validity assertions.

Changed lines are currently around `tests/summon_actor_state_machine_test.gd:353-390`; the correction is limited to ordering and expected-plan capture. No assertion was removed or relaxed.

## Validation state

- Static source review: complete.
- Godot/native execution: `NOT_RUN` by instruction.
- Existing shared-worktree `git diff --check` reports whitespace on many pre-existing dirty fixture additions; this correction did not normalize or rewrite those unrelated lines.
- Post-edit SHA-256 of the full shared fixture is recorded separately after root review; it must not be treated as a clean isolated patch hash until the pre-existing shared edits are accounted for.

Recommended acceptance is the existing related33 run against the frozen production source, with the original failure receipt retained and the two final positions, separation, and formal legality checks all still required.
## Related35 precondition correction

The related35 receipt failed earlier at line 189, before the dual-pet block. The single-pet loop previously started from the formal world's current player tile without checking the skeleton formation footprint. The existing world-preserving `move_and_slide()` path can legitimately remain blocked there; the later dual-pet legal-patch search was too late to affect this assertion.

The fixture now performs a bounded search over the same formal canonical projection and `WorldSpatialRulesScript.environment_blocks_actor_screen_px()` authority before the single-pet loop. It requires both the owner footprint and the skeleton formation anchor footprint to be clear, then runs the unchanged 120 direct physics steps and unchanged settle-distance assertion. Direction is set to the tested `Vector2.RIGHT` before calculating the offset, so the single-pet and dual-pet projections use the same movement-facing contract. The original dual-pet legal-patch search remains intact.

Preimage for this correction:
- `outputs/release_v108_20261009/B03_state_fixture_alignment/preimage/related35_before_single_formation_fix.gd`
- SHA-256: `1F9D9980980A2A498C9A757176C5E3365C00E5BCF1311AD033E94768FAEAEC83`

This correction is static-only and has not been run in Godot/native.
