# Accepted feature work: capacity and retirement

Status: PASS for the current IceStorm/FireSword admission and managed one-shot
receipt protocol (2026-10-02); independent review pending. This is not a claim
about unimplemented producer families or the legacy raw-batch API.

This implements the already authorized RFC v2 capacity contract. It does not
change target geometry, spawning, damage, cooldowns, or the existing empty
extension path. The current causal baseline is
`capacity_accept_current_red_144042_545895`: 19 checks, three failed assertions.

## Proof obligations

1. Count potential receivers from the world's actual declared spawn slots,
   including temporarily dead slots and authored summons. Read the same exact
   monster identity/rule owners used by the factory. A missing or recursive
   closure is an explicit unproved bound, never zero or infinity by assumption.
2. Current production summons have non-summoning children. The existing queue
   limits children per stable owner slot, including survivors from prior lives.
   A future recursive content graph needs a separate lifetime proof; a static
   graph without cycles alone would not prove a persistent descendant bound.
3. Geometry is sampled at release. Reservations use a count bound, not a frozen
   list of targets. Respawn replaces a slot; movement does not consume a slot.
   Test/private factory calls do not manufacture a new production spawn authority.
4. Before action acceptance, account for pending facts, active states, queued
   state creation, earlier accepted reservations, and deduplication receipts.
   A global count is insufficient: each target's historical and promised source
   identities must fit its state capacity, including refresh of an existing key.
5. Transfer a reservation once through the accepted configuration and sealed
   base batch. No resource/cooldown/HP mutation may precede a capacity rejection.
   An accepted action owns its reservation across its delayed release; cancel,
   owner loss, empty result and complete consumption all have terminal paths.
6. State expiry does not by itself authorize receipt deletion. Only identities
   that cannot create another batch, with a sealed producer and exhausted
   consumer, may retire. Delayed callbacks, retained batch references and a new
   runtime/world must not reopen a retired identity.
7. Keep the legacy low-level transfer counterexamples and their explicit scope.
   They prove atomic queue ownership, not natural-input acceptance. Do not turn
   a caller that already committed HP into evidence of preaccept admission.

## Serial execution

- Preserve the current RED and establish native spawn/closure boundary tests.
- Add bounded reservation ownership to the existing runtime and action lease;
  keep the same planner, HP port, world owner and writer.
- Prove per-target exhaustion, pending/global exhaustion, concurrent reservations,
  refresh identities, legal birth/rebirth during windup, movement, cancellation,
  replay, world change, and empty extensions.
- Run the direct regressions on final bytes. Keep capacity, receipt retirement,
  journal recovery, world-generation persistence, and performance as separate
  acceptance results. Push an immutable, scoped review snapshot after proof.

## Independent remaining work

Journal64 needs its own durable idempotent retirement/recovery protocol.
Nonempty world-clock generation must originate in the production import path.
P6/R3 must include natural input, sustained movement/combat and recovery. Exact
v97 role-B causality still lacks its original input. Android/GPU remains NOT_RUN.

## Native checkpoint

Final source content SHA256:
`494b76d28e19baed12822dca88b8c0da4aeea4f8882b833fe6e24345cf6c0bf6`.
Twenty-two native scenes passed, with 429 explicitly recorded framework checks
and two additional existing assertion-based scenes. No engine errors. Source
and engine fingerprints remained stable in all three final runner invocations.

The original capacity counterexample has three business FAIL assertions before
the fix and passes after preaccept refusal; target-slot history and concurrent
future source promises are both included. Real release-time movement, respawn,
summon materialization and module withdrawal preserve all four derived effects.
The retirement stress run completes 2,200 releases / 66,000 committed facts;
true write-boundary receipt peak is 30, producer peak 1, and 66,000 receipts retire.
This explicitly drives the existing consumer quantum for structural proof and
does not measure P6 budget service or gameplay performance.

Legacy unticketed diagnostic batches retain their historical receipt protocol.
They cannot enter a runtime once normal Player admission has required tickets.
Their direct queue admission checks are not a preaccept gameplay guarantee.
Arbitrary new base factories during an accepted action, recursive summoners and
new feature producer families need an explicit legal production-bound proof.
The current proof uses actual mapped slots and the canonical nonrecursive summon
catalog; no targets are frozen, truncated, rolled back or capped at thirty.
