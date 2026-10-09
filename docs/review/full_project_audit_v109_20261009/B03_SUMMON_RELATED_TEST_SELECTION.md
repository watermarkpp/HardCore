# B03 summon follow related-test selection

Date: 2026-10-10
Scope: read-only selection for the current summon follow / canonical landing change. No Godot, native, production, or test execution was performed for this report.

## Source binding

The current shared candidate is dirty on runner `HEAD 215f0b2f651a51e6855ee813ddd99221690311a1`; that HEAD is only a runner reference, not a clean candidate commit. The relevant current file fingerprints are:

| file | current SHA-256 | changed responsibility used for selection |
|---|---|---|
| `scripts/summon_actor.gd` | `DB8D27AA627AAB4D1FE286D0DAEF1AEFADB628B9E913D46EED8875255C985F7D` | remote owner-follow landing now asks the canonical GameRoot planner; invalid/no-slot paths defer, hide, and register pending arrival; passive-wake emissions were also added |
| `scripts/game_root.gd` | `D0A177A0253F7B1EA12F197DCCB29494EED1F9A698D7780BC187A6C623986FCB` | canonical follow context, pending-arrival registration/retry, main-pet wiring, map/life/owner identity checks |
| `scripts/enemy.gd` | `4EB42E585F30C3401366184CD240771ACD9BC25A066BCEC9AE859E38A71DDF2A` | current runtime dependency supplied for source binding; no summon-specific selection claim is made from this file alone |
| `tests/framework/summon_follow_landing_contract_20261010_test.gd` | `2B9F6CA3264E5F9888E8A2FDAF247EC187617DB77EA74572CFA9839999D83E34` | direct 26-check formal landing/pending/identity contract |
| `tests/skills/summon_owner_teleport_runtime_test.gd` | `9BF1E2BE61CF8553A091E027741CDE50EE247C00B9C485F4CF724F0334E2154B` | real owner teleport, far follow, stale target state, map-arrival and multi-pet integration; formal-ready bootstrap and production pending registration |
| `tests/summon_actor_state_machine_test.gd` | `69118AAD7A7A215FDC08935928448FEDC430F475ED038A994FFE5E48380D76D0` | ordinary SummonActor state/follow/formation and the far-follow branch |
| `tests/canonical_summon_integration_test.gd` | `49253250E9E9F266A0680A3FCDFBAB067E479703732AD85A9F7340FA24A973DF` | canonical spawn/recall, source identity, map restore and pending persistence |
| `tests/skeleton_multi_summon_contract_test.gd` | `41B33DCC66E7167BAABD5ADBD393A879E713DF77E00188584577993EBCAF48E7` | typed slots, replacement, map restore, legacy migration and multi-summon identity; formal-ready bootstrap |

The authoritative direct31 binding is `outputs/wake_drop_v108_review_followup_20261009/B03_SOURCE_FREEZE_31.json`. It records the operator-frozen candidate and binds `scripts/summon_actor.gd` to `db8d27aa627aab4d1fe286d0daef1aefadb628b9e913d46eed8875255c985f7d` and `scripts/game_root.gd` to `d0a177a0253f7b1ea12f197dccb29494eed1f9a698d7780bc187a6c623986fcb`; these match the current production hashes above. The framework receipt source content is `ae052f313d4a15d631ced26ace909339d26e1f2ceb6af0b88796299e091ae4d0`, and the freeze receipt is the source authority. An older `92A7...` value in the superseded disposition is documentation drift, not evidence against direct31.

## Minimal related selection

| path | status for the current source | reason and exact boundary |
|---|---|---|
| `tests/framework/summon_follow_landing_contract_20261010.tscn` | **PASS** (direct31 functional run); cleanup follow-up **NOT_RUN** | Direct31 is bound by `B03_SOURCE_FREEZE_31.json` to the current `DB8D...`/`D0A177...` production bytes and reports 26/26 checks, native exit 0, and no engine errors. The one leaked `RefCounted` is a fixture-hygiene **FAIL** only; the new fixture cleanup lifecycle needs one separate bounded follow-up. |
| `tests/skills/summon_owner_teleport_runtime_test.tscn` | **MUST_RUN** | Exercises the production GameRoot path rather than only calling the planner: two-frame bootstrap, stale target/attack state, same-map random teleport, final map-arrival relocation, deferred no-slot retry, and the 9-pet high-rank case. It uses canonical `taoist_main_pet` metadata, actual projection Callables, spatial index, and real map positions. This is the required integration check for far follow plus stale-state cleanup. |
| `tests/summon_actor_state_machine_test.tscn` | **MUST_RUN** | At lines 346–365 it places an ordinary `SummonActor` beyond `teleport_range_gu` and invokes `_physics_process` directly, then checks the formation anchor. That branch is now routed through canonical authority and identity guards, so this existing contract can expose an anonymous/non-main-pet compatibility regression. Its two-frame bootstrap and raw ground/screen helpers must remain unchanged; a failure must be classified as either a real compatibility regression or an unsupported fixture identity, never fixed by weakening the assertion. |
| `tests/canonical_summon_integration_test.tscn` | **MUST_RUN** | GameRoot changes touch canonical main-pet application, persistence wiring, map-arrival relocation and source identity. This test covers canonical descriptor spawn, same-instance recall, dual-type coexistence, death replacement, map transition restore, idempotent restore, and blocked spawn. It is the minimal source-identity/pending integration companion to the far-follow tests. |
| `tests/skeleton_multi_summon_contract_test.tscn` | **MUST_RUN** | GameRoot and `SummonActor` changes touch registration and restore paths used by typed main-pet slots. This contract covers two slots, replacement after death, zero-cost recall, capture/apply, partial restore, map reload, equipment-driven slot reduction, and legacy contract migration. It is required to catch a pending/source identity regression that the single-pet teleport test cannot see. |

This is a bounded five-scene selection: the four requested existing contracts plus the new direct landing contract. No broad summon or combat suite is required solely because of this change. Existing unrelated audio, projectile, loot, grid, and budget receipts remain reusable only when their own source/input bindings are unchanged.

## Fixture-only preflight corrections

Before any rerun, exact preimages and their hashes were saved under `outputs/wake_drop_v108_review_followup_20261009/summon_related_preimages_33/`. Two stale two-frame bootstraps were replaced with the existing `FormalWorldSkillFixture.wait_for_formal_world()` readiness contract:

- `summon_owner_teleport_runtime_test.gd`: `67B74C...` -> `9BF1E2...`.
- `skeleton_multi_summon_contract_test.gd`: `62E3C3...` -> `41B33D...`.

The owner-teleport fixture also stopped clearing and manually appending `_pending_main_pet_arrivals`; it now asserts the production `_register_pending_main_pet_arrival()` admission before invoking the existing retry path. All original load, two-pet/nine-pet, stale-state, position, HP, and lifecycle assertions remain. `canonical_summon_integration_test.gd` already used the formal-ready helper and was not changed (`492532...`). These edits are fixture readiness/ownership corrections only; their functional status is **NOT_RUN** until the root-owned freeze executes them.

## Fixture facts that must remain intact

- The summon state-machine and multi-summon tests intentionally wait for two `process_frame` ticks after adding `main.tscn`; this is a stale/bootstrap-sensitive boundary, not disposable padding. Do not shorten it or replace it with a direct constructor-only fixture.
- The owner-teleport test intentionally uses far raw screen offsets (`800,300`, `-700,450`, and the high-rank offsets) to cross the production teleport threshold. These are integration inputs, not a license to substitute a nearby point.
- The tests use typed arrays and actual projection/index Callables. Literal typed arrays and `taoist_main_pet` metadata are identity-contract setup; they must remain in place so pending registration and restore are exercised through the production route.
- The canonical and multi-summon tests use real canonical descriptor/source IDs and map reload/restore. They must not be reduced to direct calls of private landing helpers.

## Existing evidence and failure classification

The retained framework direct31 evidence and source binding are at:

- `outputs/test_logs/v109_direct31_summon_landing/evidence/4c81bd9b-f742-4a37-949a-145d70aad48d/summon_follow_landing_contract_20261010_test.result.json`
- `outputs/test_logs/v109_direct31_summon_landing/evidence/4c81bd9b-f742-4a37-949a-145d70aad48d/native_result.json`
- `docs/review/full_project_audit_v109_20261009/B03_SUMMON_CLEANUP_TRIAGE.md`

That receipt reports `PASS`, 26/26 checks, native exit 0, and zero engine-log errors. The same run reports one leaked `RefCounted` at teardown. The correct ledger is functional **PASS** plus cleanup **FAIL**; it is not evidence of a production summon leak. Because `B03_SOURCE_FREEZE_31.json` proves the current production bytes, direct31 functional reuse is **PASS**. The current framework fixture bytes differ only for the post-run cleanup follow-up; that follow-up is **NOT_RUN** until the root-owned frozen candidate is rerun.

A future result must keep these distinctions:

- parser/type/bootstrap failure: fixture **FAIL**, no gameplay conclusion;
- canonical landing, pending, identity, or follow assertion failure: functional **FAIL** requiring source/fixture diagnosis;
- one generic teardown `RefCounted` warning with all 26 checks passing: cleanup **FAIL**, functional **PASS**, production leak **NOT_RUN**;
- no run against the current fixed source: **NOT_RUN** or **MISSING**, never PASS by historical receipt.

## Selection conclusion

The minimal current-source regression gate is the five scenes above. The direct31 landing receipt is a useful historical functional result but is not current-source proof until the `DB8D...` summon bytes and `D0A177...` GameRoot bytes are bound to the run. No production or test edits were made by this selection review; native/device/performance acceptance remains **NOT_RUN**.
