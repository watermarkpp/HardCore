# B03 teleport fixture alignment

## Scope

This fixture-only correction is bound to `SOURCE_FREEZE_32` and published source `878775d18f6660eddaf086dc8edfdf3ad6fa80c4`. Production files were not changed and no Godot/native run was performed.

## Failure and correction

The preimage `tests/skills/summon_owner_teleport_runtime_test.gd` had SHA256 `9BF1E2BE61CF8553A091E027741CDE50EE247C00B9C485F4CF724F0334E2154B`. Its stale target used `game.player.global_position + Vector2(2000.0, 2000.0)` for monster ID 38. That raw screen-space offset is outside the formal published-world birth/placement contract, so `_spawn_enemy` correctly rejected it and the assertion reported `stale summon-target fixture failed to spawn`.

The test now imports `tests/helpers/formal_world_skill_fixture.gd` and uses its authoritative `FIXTURE_GROUND_POSITION` (`Vector2(40.5, 13.5)`) through `game._canonical_ground_gu_to_screen_px`. This is the same mapped target geometry used by the formal skill fixtures and keeps the real GameRoot spawn admission, projection, collision, map, and capacity checks active. The existing stale-target seeding, two initial pets, nine-pet high-rank case, HP checks, teleport assertions, pending-arrival retry, and map-arrival checks are unchanged.

The adjusted test SHA256 is recorded below after the source review. The preimage is preserved at `B03_TELEPORT_FIXTURE_ALIGNMENT.preimage.gd` with the original SHA above.

## Verification boundary

Static review only: the new point is an authoritative formal ground coordinate converted by the production projection API. No assertion was removed, no timeout or load was changed, and no production fallback or mock was introduced. Godot/native validation remains `NOT_RUN` pending root's frozen-source runner.

Adjusted test SHA256: `5CFCA18AD3ABC1C586251DAF884B296AB3C89447C180726A04F8C122AEC8AE0F`.


## Related35 correction

The first formal coordinate replacement still produced a null actor because `_spawn_enemy` is a published birth transaction, not a generic point sampler. Its admission requires the current sealed base slot, generation, canonical projection, capability inputs, and spawn footprint; a coordinate that is legal for one formal target descriptor is not sufficient for an invented ID38 base spawn. The related35 failure is preserved.

The fixture now selects a live non-boss EnemyActor already admitted by the formal READY world, preferring ID38 when that actual published actor exists, and otherwise using the first valid current-map actor. It then clears other ambient enemies while retaining that admitted actor as the stale target reference. This removes the second invented birth authority while preserving every stale-target, HP, two-pet/nine-pet, teleport, arrival, and pending-retry assertion. No production code, load, timeout, or assertion was changed.

Current test SHA256: `D53EA8ADC010F7E7950DC402A22B61A52A88BB695815A3B06C512F8B15BF72AA` (includes stale-reference physics isolation).
