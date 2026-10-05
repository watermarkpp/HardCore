# Published birth closure implementation plan

Goal: implement current contract `hc.framework.world_status_contract.v2` for the
existing complete base queue and original SummonQueue job. This is C2, following
the fixed C0 evidence. DOT implementation and final performance remain separate.

## Owners and interfaces

- GameRoot remains the only EnemyActor factory and world-transition owner.
- WorldTargetBound remains a compiled view of the existing accepted descriptors;
  its current `_slots` becomes the frozen publication view, not another spawner.
- WorldBootstrapCoordinator owns the same accepted queue and counters. Add an
  explicit collection-open gate, closed before draining; accepted queue items
  remain executable after closure.
- SummonQueue's original job owns its current ordinal's one-shot claim. Do not
  introduce another ticket/grant registry or copy a job into actor metadata.
- A publication-owned immutable monster-input snapshot delegates canonical
  identity/profile/policy reads to their existing authorities once. Root's
  accepted births consume that snapshot; standalone canonical setup keeps its
  existing behavior. No HP, planner, writer, RNG or motion owner changes.

WorldTargetBound API (cold collection and read-only admission):

```text
sync_world(identity)
declare_base(slot, monster_id, position, respawn_seconds, context, actor_id) -> bool
seal() -> bool
admit_base(monster_id, position, respawn_seconds, context) -> {accepted, reason, monster, inputs}
admits_child(owner_slot, child_id) -> bool
monster_inputs(monster_id) -> publication-owned immutable snapshot or null
summon_request_valid(owner_slot, source_id, ids, count, maximum) -> bool
snapshot() -> {proved, sealed, reason, base_slots, maximum_receivers, world, plan_sha256}
```

Snapshot inputs include the canonical entry, appearance, body/behavior/boss rules
and existing movement/range policy projections used during setup. Derive them
through the original identity/EnemyActor policy APIs, freeze once per monster ID,
and reuse across slots. Preserve actual source-locked overrides. Changed global
input cannot alter a current-world respawn or queued child; actual republication
compiles the new input.

## Steps and native evidence

- [x] Add real mapped-world birth admission counterexamples and record RED.
  Unknown/anonymous slots, altered known descriptors, fake summon labels, and
  READY Root/coordinator submissions must leave serial, actors, queues, counters,
  timers, persisted deadlines and the frozen bound unchanged. Verify current-world
  replacement uses published HP input while genuine republication uses new input.
- [x] Compile all base descriptors during the existing operation.call collection;
  fail invalid/nested-unproved closure before descriptor insertion. Seal after
  collection and before either actual actor queue processor. Same-map travel with
  no new world retains the existing sealed plan.
- [x] Guard Root submission before source-index increment and coordinator
  submission before its counters/IDs/queue. Guard factory before serial/persistence/
  timers/allocation/spatial/add_child. Normal vacant same-slot respawn remains legal.
- [x] Freeze setup inputs through the accepted view and reuse them for normal
  respawn and admitted child materialization. Preserve canonical caller rejection.
- [x] Validate summon release against the published source rules. Use the existing
  release serial, life, stable owner slot, shared live+reserved cap and world.
  Boss health-stage producer increments the same existing serial before emission.
- [x] Pass actual job identity only during the immediate materialization call.
  Validate current job/ordinal/world/source/descriptor; consume claim before
  reentrant factory callbacks. Strip ephemeral job fields before duplicating actor
  spawn_context. Preserve cancel_all's existing in-flight transfer and old-life
  surviving children. Do not revalidate source death after successful admission.
- [ ] Publish complete test plans through actual _begin_map_transition and
  _load_zone(..., true, ...) once before accepted work. Multi-target fixtures
  declare their entire target set together; no per-target republish after effects.
- [ ] Update affected current-contract fixtures, preserving historical evidence.
  Exercise original126→127,182→183 and160→156/153/150/128 producers, copied job,
  replay/reentrant claim, old-life shared cap, deferred base and same-map travel.
- [ ] Run direct native RED/GREEN and related startup/loading/respawn/summon/action
  acceptance regressions with formal receipts, fixed source and original deadlines.
  Record scope/remaining failures, internal review, then publish a fixed candidate
  for actual Pro review before final C2–C6 integration acceptance.

## Preservation and constraints

Retain CRLF bytes in large existing files; make only exact functional edits.
Source is frozen during every native test. Parallel work has exclusive file
ownership; the main controller integrates and owns GameRoot/queue changes.
Do not cancel valid old actions, fake epochs, change RNG/geometry/cadence, reduce
the30-target workload, extend35seconds, or mark preserved natural FAIL closed.

## Actual validation and adjacent failure closure

The current byte candidate has eight direct native scenes / 128 checks PASS,
exit0, complete passing receipts and stable source:
`published_birth_candidate_165001_945991`, source content set
`69a45e79cb94ae9fea81d0c92b4ae7e7c5de891ac9499a01bcb5b5c084a72c9a`.
It was tested as dirty work over ff000d78071c7cccc7a068038704da3e2606f76f;
it is not yet a fixed-SHA Pro audit or final release acceptance.

Preserve the actual earlier failures. The controlled restoration of the reviewed
old cold operations returned exit1 with ten checks / four failures, after the
original infinite safe-home loop was fixed. Both owner files were restored
byte-exact in `finally`. A further same-slot / different-actor-ID counterexample
returned eleven checks / one failure. The compiled original descriptor now
includes its original queue actor ID; foreign IDs cannot requeue the same slot.
This adds no grant registry or hot-path scan of the queue.

The failed publication genuinely reproduced an infinite same-home recovery:
30s native timeout, receipt MISSING. Recovery now republishes the actual home
world once. A failed home publication terminates with a visible error and one
retained input lock; a later real transition takes over that lock and releases
it only at READY. Actual fatal HP delivery and synchronous town revival are
covered. Recovery acceptance is the actual travel return, not a transient
in-flight flag. Preparation clears the old environment before arrival, so a
failure after that boundary cannot release input onto an allegedly intact old
world. A real missing-arrival / unresolvable-home counterexample and successful
retry are covered. Death-settle continuation uses the existing transition serial
to avoid releasing a newer transition's lock; native preemption coverage remains
NOT_RUN, and internal review is distinct from Pro.

Twelve multi-target fixtures now publish their complete original targets once.
Their shared helper preserves the existing single preparation frame, HP,
geometry, checks and deadlines. Additional targets are paused only during that
existing preparation frame and then resume their original physics flag. Full RNG
equivalence is not asserted. Related native regressions are running separately.
Natural two-cohort / T6 lifecycle migration, DOT replacement and final natural
performance failure remain open; these checkboxes do not certify them.

The direct delayed-birth counterexample returned thirteen checks / three
failures: unpublished slot, changed original descriptor and retired generation
all created real wakeups before factory admission. `_respawn_later` now validates
the same published descriptor and current world before Timer creation, and the
factory retains its existing timeout recheck. Actual Boss deferred deadlines,
same-slot replacements and cross-map reentry still use the original writer,
policy and Timer path.

Related twelve-scene run `published_fixture_regressions_165304_599745` had eight
passes and four failures, all retained. Classification and subsequent checks:

- `empty_extension_behavior_test`: preserved
  `outputs/framework_v2/baseline/EMPTY_EXTENSION_BEHAVIOR.json` MISSING. It is not
  in the handoff evidence ZIP. Do not recapture a current candidate as the old
  baseline or claim the comparison passed.
- `feature_admission_release_test`: the earlier late factory used an undeclared
  0.01s delayed-birth parameter and the cold-published source could be dormant.
  Declare the exact original 0.01s parameter before acceptance and use the
  original126 producer with the original awake fixture source. No manual serial
  or synthetic summon signal. Native27checks PASS after correction.
- `feature_mixed_delivery_test`: outer30s expired during eight genuine worlds;
  original per-world/action deadlines are unchanged. The permitted known-heavy
  runner60s completes all eight combinations PASS, not a relaxed combat deadline.
- `combined_effect_lifecycle_test`: passed Root zone generation to the resource
  publisher, which owns a distinct generation. Use the same actual accessor as
  production MonsterVisual and verify the subscription. Pending=0 alone no
  longer fabricates a completion latency: five actual requests/gets and visible
  valid cache must precede it. The native39checks PASS retains30targets,90legacy
  states,360ticks,15seconds and actual resource/death overlap. This is still the
  historical source-keyed Ignite runtime; it does not prove C3's new contract.

`published_timer_and_resource_green` has three native scenes / 79 checks PASS
on its own later byte fingerprint. `published_heavy_regressions` also passes the
eight-combination scene and actual six-map Boss deferred-deadline/reentry scene.
Do not merge these distinct byte phases into a fixed-candidate acceptance claim.
The pipeline's existing active transition guard is moved before processing a
false result: false can mean cancellation of the old generation. The actual
takeover interleaving is NOT_RUN; the source guard and internal review do not
replace that evidence. Final fixed-SHA validation and Pro review remain pending.

CRLF is deliberately preserved. Default Git whitespace checking labels those
retained CR bytes as trailing space; local checking uses
`blank-at-eol,blank-at-eof,space-before-tab,cr-at-eol` to still reject actual new
trailing whitespace. Historical handoff whitespace failures are not rewritten.


The final precommit guard phase `published_final_guard_precommit_171801_583744`
has three native scenes /43checks PASS on its own source d161d862150a0c32a73867a5966644ceabbfd7d502c52dfdf6e663d9fcaf94a5.
It covers the final original-seconds type guard and recovery owner guard.

Internal review then found the actual coordinator-owned queue Array is reused
by the next generation. `published_queue_takeover_red_172125_691173` delivered
the new B descriptor to the retired A callback:10checks/3FAIL. The expanded
`published_queue_takeover_sync_red_172216_101035` also covers synchronous
callback takeover:13checks/6FAIL. Both are complete failed native receipts.
The queue loop now retains its original generation across waits; the same slice
checks it immediately after every callback before counters or further tasks.
Blocking actor drain retains the same guard. No new epoch, queue, quantum or
budget was added. `published_queue_takeover_green_172252_392496` has three native
scenes PASS, including13receiptchecks, original stage order and real map reuse.
The takeover receipt proves coordinator ownership; actual Root UI/death takeover
and physical publisher instance replacement remain NOT_RUN separately.

This source is committed as a reviewable C2 candidate. Formal fixed-HEAD results
will be published in the review evidence, with inherited failures distinguished.
It is not a completed architecture upgrade, Pro audit or APK delivery.
