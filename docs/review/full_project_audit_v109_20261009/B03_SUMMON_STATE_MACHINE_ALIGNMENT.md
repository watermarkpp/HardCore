# B03 summon state-machine alignment

Date: 2026-10-10

Targeted fixture: `tests/summon_actor_state_machine_test.gd`

## Preimage and scope

The exact preimage SHA-256 before this targeted edit was:

`69118AAD7A7A215FDC08935928448FEDC430F475ED038A994FFE5E48380D76D0`

Only the two far-follow sections were changed. Independent unit geometry,
HP/stat, target acquisition, attack release, stealth, and unrelated mapper
cases were left intact. No production source, scene, or native evidence was
modified, and the fixture was not run in this turn.

## Alignment performed

Before each far-follow action, the fixture now binds the existing test actors
to the real GameRoot owner contract: current `game.current_map_id`, canonical
ground/screen projection callables, `taoist_main_pet` identity, persistence
contract metadata, and distinct pet slots. It obtains the formal
`_canonical_summon_follow_landing_plan()` first, then asserts the relocation
matches that plan and passes the canonical landing validator. The legacy
mapper is restored immediately after each targeted section so later unit
geometry checks retain their original isolated coordinate contract.

The prior exact-anchor assertion is therefore replaced only at the seam where
the current production authority may select a legal adjacent/fallback tile.
The state and two-pet separation assertions remain. The later attack-side far
follow receives the same formal plan binding and restores the legacy mapper
before expiry assertions.

## Status

Static targeted diff: prepared. Current fixture SHA-256:

`FF96E436905A6AE76BC1EC07E94A0342F9EADA890BB45B71BE0B1A63DC679E15`

Native status for this edit: `NOT_RUN`. The startup boundary now uses the
existing `FormalWorldSkillFixture.wait_for_formal_world()` helper, and the
formal validator receives an explicit `Array[SummonActor]`; this avoids a
partial-bootstrap or inferred-Array fixture result. Any remaining failures outside the two
formal far-follow sections remain unresolved and must stay classified rather
than being weakened.
