# B03 summon landing and passive-emitter disposition

The final local repair is based on review parent `878775d18f6660eddaf086dc8edfdf3ad6fa80c4`; integration HEAD `215f0b2f651a51e6855ee813ddd99221690311a1` remains historical. This document replaces the intermediate scaffold description, which is preserved under `outputs/wake_drop_v108_review_followup_20261009/B03_SUMMON_LANDING_DISPOSITION.previous.md`. No generated data, player movement, damage, skill timing, or drop probability is changed by this repair.

## Confirmed production defects and repair

The original far-follow branch wrote the unvalidated formation anchor directly. The root-owned `_canonical_summon_follow_landing_plan()` now checks the live main-pet owner, map, tree, life and transition context. It first validates the original formation anchor with the existing formal footprint/terrain/occupancy authority. A legal original anchor is retained. Only a blocked anchor proceeds through the existing canonical spawn search and bounded teleport fallback. The summon commits a finite legal position using the prior far-follow state semantics, so it does not reset an already accepted attack through the owner's explicit teleport finalizer.

When the current context has no legal landing, the summon keeps its previous position and enters the established hidden pending state. `_register_pending_main_pet_arrival()` admits that exact current pet idempotently and stamps its zone generation. The existing owner-tile-change retry is the sole recovery planner. Map-arrival pending entries receive the same generation binding. No new timer, per-frame full scan or alternate placement authority was added.

Related33 exposed a separate production lifecycle bug: `_load_zone()` clears the map-scoped emitter registry while deferred callbacks from retiring pets can still arrive. `_register_passive_wake_emitter()` now rejects queued, detached or foreign-tree actors and a retiring root. Surviving emitters reuse their three existing signal connections through Callable equality checks. A retiring old-map callback cannot recreate its registry entry. Range 6/9/12, static-only obstruction, invisibility eligibility and immediate legal acquisition remain unchanged.

## Formal contract and fixture alignment

The new framework fixture uses the actual main scene, formal READY, canonical map projection/domain, real background collision authority, shared spatial index and real summons. It covers original-anchor preservation, a real wall at that anchor, a safe alternate landing, radius-eight occupancy with 289 actual summon bodies, no illegal write, idempotent pending registration, same-tile waiting and recovery after a legal owner-tile change. It also rejects wrong-map, wrong-owner and transitioning contexts. Five additional cases exercise signal re-admission and old deferred retirement. The 289-body negative occupancy case is a correctness fixture, not a performance result.

Legacy fixtures were aligned without relaxing their original contracts: they wait for formal READY; the stale target is an already published live actor rather than an invented second spawn; manual formation starts on a validated clear owner/anchor footprint; the second pet's far-follow plan is read after the first pet publishes its landing. The original 120 movement steps, settle distance, body collision, two/three/nine-pet counts, HP, persistence and target cancellation assertions remain. The selected stale actor is only a reference/lifecycle fixture, not an ID38-specific combat test. Its physics is isolated while the test yields, so unrelated incoming damage cannot randomize HP assertions.

## Native results and limits

| Stage | Actual result | Interpretation |
| --- | --- | --- |
| direct27 workset cleanup | PASS, native0, empty stderr | Four owned tree-less fixture nodes are explicitly freed; prior related26 leak evidence retained |
| direct28 | FAIL | Fixture parser inferred a Variant from a dynamic root call; original raw failure retained |
| direct29 | FAIL | Fixture passed an untyped literal to a typed summon-array seam; original raw failure retained |
| direct30 | FAIL, native1 | Fixture used a reference projection/legacy zero mask domain for a formal polygon map |
| direct31 / direct32 | 26 checks PASS, native0 | Each still had one RefCounted warning: cleanup FAIL, owner attribution BLOCKED |
| related33 | 1 PASS / 3 FAIL | Six real duplicate signal errors plus stale-spawn and sequential occupancy fixture errors; all raw evidence retained |
| direct34 | 31 checks PASS, native0, valid framework receipt, empty stderr | Legal landing/recovery plus signal retirement/re-admission; no ObjectDB/RID/resource warning |
| related35 | 2 PASS / 2 FAIL | Canonical coexistence/persistence and multi-skeleton functional PASS; duplicate signal errors gone. Two remaining fixture preconditions failed. PASS cases retain 2/1 RefCounted warnings |
| related36 | 2 PASS, native0, no engine errors | Teleport endpoints preserve two/three/nine pets and state-machine assertions pass after exact fixture input repair. Each retains two RefCounted exit warnings: cleanup FAIL, attribution BLOCKED |

Current direct34 and related35 production dependencies are unchanged in source36. Only the two previously failed legacy fixture scripts changed between source34 and source36, so those cases alone were rerun. Native functional results do not erase earlier failures or cleanup warnings. No performance, Android, device, or whole-project audit PASS is claimed. Unknown RefCounted IDs were not freed or mapped to production owners by guesswork.

## Source and evidence binding

- Latest candidate tree: `fa9f4ebb60379299e69db701d9ff294e729b261a`.
- Source36 freeze SHA256: `ab0b2b5658e260d07ce97b63a149400721f3b1f0e0c24f94b1d0b328128e0b74`; 1,020 actual checkout input fingerprints, with the two local retired grid trial scripts explicitly excluded from the published tree.
- `scripts/game_root.gd`: `af3982647f1fe4edf72c877026317a4866e8d83307c1b3b39e56f75044da4d66`.
- `scripts/summon_actor.gd`: `5108e330504bf7ca9e4a6dfb41295424747db8c92e60de8fdd2965f1930b0664`.
- Formal fixture: `0c8e62bb30a57b9ddeb84a8fc7fd2175edc824a16134f75edd8365f31cad176b`.
- Source36 tree comparison: 1,018 matching blobs, no runtime/source mismatch, two documented retired-grid exclusions.
- Exact retained raw evidence and source stages: `evidence/B03_summon/SHA256_MANIFEST.json`.
- Direct34 framework run `8686778d-8158-489c-a3fa-4f80f0b26567`, invocation `7a5cdce4-3f41-4488-ba17-3bbd6b6c7482`.
- Related35 invocation `cf8dc4c9-383a-4961-b340-61451c075f05`.

The private test index and isolated user-data/log/evidence roots are retained. The main Git index and unrelated dirty work are preserved. Publication, integration, APK109 and DEVICE TEST remain NOT_RUN until their own actual receipts exist.
