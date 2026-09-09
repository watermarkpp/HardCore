# V3 R3.1 closure evidence

Historical specialist handoff: the sections below preserve the original candidate findings and failures. Current integration status is recorded in `IMPLEMENTATION_REPORT.md` and `ACCEPTANCE_MATRIX.md`; they supersede the pending implementation statements below. W1 special families are now integrated, the full Critical baseline plus all 26 failed-case follow-ups passed, and the three render rounds passed. Final performance and Android input follow-up are still pending; no device acceptance is claimed.

Baseline: `f14f0b058092c5ee977048463fafc0c9fa3902a4` (`codex/bugfix24-v3-close-20260909`). Exact ID50 data authority was split into parent commit `2290fc49e917f4c2a9d1c8cd852bac068e908a15`. The V3 candidate and W4 audio changes already present in `scripts/enemy.gd` were preserved. User-locked monster counts, combat values, maps, speed/interval data, drop data, and W4 audio service were not changed.

## REV01-08 closure matrix

| Review | Candidate behavior and evidence | State |
|---|---|---|
| REV01 | Typed `PlayerCharacter.combat_epoch` is frozen and rechecked for HC melee, generic delayed melee, physical projectile, target magic, area magic, and area attack. Attack start is rejected while transition is active. `combat_epoch_delivery_test` uses real `begin_combat_transition`/`finish_combat_transition`. | PASS |
| REV02 | Production timers and physics frames exercise ordinary ID64 and Boss ID76 at 1.8/1.99/2.0 GU. The first legal attack can start outside preferred distance, recurring attacks settle, and motion closes to the 1.5 GU preferred position without overlap. Boss skill is disabled only to isolate its ordinary physical lane. | PASS |
| REV03 | Locked A release remains bound to A; B is independently shown legal and hittable, retarget stays on B, old A release cannot hit B, and generation mismatch rejects an old release. | PASS |
| REV04 | A real WORLD `StaticBody2D` is inserted into active motion. Slide collision is observed, the legal position is retained, movement ownership is restored, and no unrelated position rewind is used. The older C04 blocked-cell check remains only a static-navigation/final-position unit check. | PASS |
| REV05 | Real U wall and closed ring cover last-known position, temporary motion away from target, terminal no-route versus budget wait, wall removal plus revision refresh, and resumed engagement. Mixed trivial/detour/no-route HC jobs share the same per-frame terrain budget with a real named-delivery EnemyActor using the existing synchronous navigation lane. | PASS |
| REV06 / W1 | Existing `combat_environment_request_integration_test` instantiates the real main scene and calls public `Player.request_skill`: WORLD blocks selection without resource/cooldown commit, open path commits once, and a wall inserted during windup cancels release without damage or duplicate consumption. | PASS |
| REV07 | Strict same-probe/same-prefetch wall comparison ran at 10/20/30. Baseline p95 was `7.432/8.206/8.538 ms`; candidate was `8.995/10.275/11.112 ms`, exceeding every `max(5%,0.5 ms)` threshold. Subsequent measured work reduced repeated static goal/cell/path work with exact bounded caches and a resumable shared static field; `path_test` proves shortest-cost, corner, no-route, capacity, active-request detach, cancellation and context/radius/goal isolation. A one-cell corridor specifically proves that settling the first registered start still relaxes its neighbors so a farther start can cross it. These changes are not a replacement strict A/B result. The attachment also requires open pursuit, sustained close attacks and dense crowd matrices in addition to the existing real-wall probe; those three matrices remain missing. Performance probes stay outside Critical. | **FAIL / OPEN** |
| REV08 | Separate baseline work reproduced the dummy-renderer family intermittently; another worker owns loader diagnosis. This package makes no loader/allowlist change and claims no headless/device equivalence. | OPEN, externally owned |

C07 dynamic occupancy is covered by two live lanes, per-lane release, corner/diagonal blocking, eight-monster physical separation, and real summon interception without a combat-group scan. C08 is covered by contact summon takeover/stability, dead-summon rejection, alternating low-damage anti-ping-pong, and bounded divine-beast threat selection.

The strict wall baseline recorded `physics_moves=0` at all 10/20/30 counts (`enemy_terrain_path_accepted=2/2/4`), so zero motion alone is not a candidate-versus-baseline regression signal. The latest non-quiet target-directed shared-field diagnostic produced real candidate movement at 10 and 20 but still had `30: physics_moves=0, REPATH_PENDING=22` at the unchanged 150-frame boundary. This remains a functional wait-window debt alongside the numeric p95 failure; post-window paused-actor drain proves completion but does not replace live movement inside the measurement window.

## Focused runner evidence

All paths below are under `outputs/test_logs` in this worktree.

| Runner JSON | Result |
|---|---|
| `runner_results_adhoc_20260909_131632_033_8660.json` | combat epoch 1/1 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_132956_028_6208.json` | real WORLD obstacle/U/ring 1/1 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_133705_250_2968.json` | map 910001 mobile targeting 1/1 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_134157_482_7840.json` | adjacent crowd workload 1/1 PASS, engine errors 0; not REV07 evidence |
| `runner_results_adhoc_20260909_134838_414_11084.json` | runtime REV02/03/C07 1/1 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_134921_863_5364.json` | W1 public request plus helper 2/2 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_140347_764_20556.json` | ID50 contract PASS; first actor run failed because the test did not restore its target after the deliberate cross-map case. This failure is retained. |
| `runner_results_adhoc_20260909_140826_193_5928.json` | HC plus existing special-navigation mixed budget 1/1 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_142257_376_3772.json` | final canonical-authority ID50 actor plus contract 2/2 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_150351_391_21244.json` / `...150419_649_8316.json` | strict paired REV07 wall baseline/candidate 1/1 each, engine errors 0; numeric threshold FAIL retained |
| `runner_results_adhoc_20260909_155509_379_3996.json` | shared static-field shortest path/context/capacity/cancellation plus existing mixed scheduler path test 1/1 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_161544_208_1180.json` | final shared-field corridor and real scheduler cancellation regression 1/1 PASS, engine errors 0 |
| `runner_results_adhoc_20260909_161720_100_4328.json` | final path/runtime/real-WORLD/physical-projectile/special-delivery set 5/5 PASS, engine errors 0 |

Recommended Critical additions: `tests/hc_monster_ai/combat_epoch_delivery_test.tscn` (30s), `tests/hc_monster_ai/path_test.tscn` (30s), `tests/hc_monster_ai/world_obstacle_runtime_test.tscn` (60s), `tests/hc_monster_ai/runtime_test.tscn` (60s), `tests/mobile_targeting_test.tscn` (60s), and `tests/combat_environment_request_integration_test.tscn` (60s). Dynamic occupancy adjacency: `tests/crowd_grounding_test.tscn`, `tests/monster_cadence_blocked_step_test.tscn`, and `tests/monster_melee_contact_geometry_test.tscn` (30s each). Keep `tests/monster_crowd_performance_test.tscn` and every perf probe outside Critical; they do not prove REV07.

## ID50 exact behavior bridge

Runtime lookup remains exact `monster_id=50`. Identity evidence is `canonical_monster_combat_source_v1.json[50]` with appearance 21 and the unique Crystal service record with AI8. These establish the project identity only. Primary behavior is `M2Share.pas:158` (`MONSTER_DUALAXE=87`), `UsrEngn.pas:1876` (`TDualAxeMonster.Create`), and `ObjAxeMon.pas:41-100` (`FlyAxeAttack`, `CanFly`, immediate `StruckDamage`, then delayed `RM_10101` feedback, and the seven-cell source gate).

`monster_behavior_profiles.json` now owns exact profile `axe_skeleton` and maps it only through `profileByMonsterId[50]`. The canonical builder projects that profile into canonical ID50 `combat.behavior_profile.attackDelivery`: `physical_projectile`, 7 GU, frozen target footpoint, WORLD/CanFly gate, and the existing physical-projectile visual channel. HardCore's 7 GU value uses the project's Euclidean GU circle; the source gate is axis-oriented and even preserves a duplicated X comparison, so the circle is a compatibility projection. The `0.6 + Chebyshev GU * 0.05` value is the source feedback delay; delaying HP settlement is the existing HardCore projectile adapter. `monster.physical_arrow.v1` is its generic physical-projectile visual, not axe-specific source art. `EnemyActor` reads delivery only through `MonsterIdentity.behavior_profile`; it has no private ID50 injection or name path.

This keeps the generated canonical catalog as the single runtime behavior authority. The behavior source and range policy both declare the formal source priority route: primary `original_gameofmir` supplies race87/class/FlyAxe behavior, while exact canonical appearance21 and Crystal AI8 are confined to identity evidence. Runtime performs no name, suffix, alias, or fuzzy lookup. The builder check reports 156 identities, 153 runtime entries, and unchanged 7032 drop rows.

Primary hashes: `ObjAxeMon.pas` `9D42ABF6...28C0`; `M2Share.pas` `9E1505BE...085`; `UsrEngn.pas` `E9E17355...4D3`. Identity data hashes: canonical combat source `81D52DB7...D07D`; Crystal service catalog `E62A7B2C...DAE4`.

## 153-entry delivery inventory boundary

`monster_delivery_inventory.csv` contains exactly 153 runtime entries. It now records, for every ID, the exact actor family, server race, actor source file, dispatch source, current delivery field, runtime route, and any shared actor test. These 153 entries collapse to 32 active `(actor_family, race)` groups; the broader authority file contains 37 groups across 156 records. Twelve active entries still have no authoritative actor binding and are explicitly `UNRESOLVED_ACTOR_AND_DELIVERY` rather than melee.

The 12 unresolved exact IDs are: 41 半兽勇士9 (AI0), 59 骷髅精灵9 (AI0), 78 沃玛教主9 (AI0), 123 邪恶钳虫9 (AI0), 161 祖玛教主9 (AI17), 190 虹魔猪卫9 (AI0), and 228-233 宝箱2-宝箱7 (AI3). Their authority records have neither `targeting.pascal_class/server_race` nor a `class_binding_source`; their delivery fields and actual runtime actor tests are also absent. They remain a separate read-only source-resolution package and are not counted as complete 153-delivery closure.

Current explicit delivery data after the ID50 decision is: physical projectile 50/150/152/206; special melee 70; area magic 124; fixed area 180/195; target magic 220/222. Known same-family gaps remain visible instead of being defaulted: `TArcherMonster/race104` 42/145/186, `TThornDarkMonster/race93` 62/174, `TElectronicScolpionMon/race200` 224, plus actor-specific families such as `TSpitSpider`, `TLightingZombi`, `TGasAttackMonster`, `TExplosionSpider`, `TCowKingMonster`, and `TArcherGuard`. IDs 226-234 have a separate HUMAN_FROZEN stationary-entity/noncombat follow-up decision and receive no centipede/area attack in this V3 commit. A shared channel test proves only the channel contract; each ID remains pending until its exact actor-to-runtime delivery mapping is accepted.

## Candidate file hashes and boundaries

- `scripts/enemy.gd`: `9561BEA5...A88`; includes pre-existing V3/W4 plus this package, so review by targeted hunks.
- `scripts/monster_ai_package/policy.gd`: `983714B7...FD1`.
- `scripts/monster_ai_package/path_scheduler.gd`: `9389C65C...515D`.
- `scripts/monster_ai_package/path_search.gd`: `D645A227...89B9`.
- `assets/data/monster_attack_range_policy_v1.json`: `CF089E70...1CB8`.
- `assets/data/monster_behavior_profiles.json`: `A6EC4ACD...129C4`; exact ID50 `axe_skeleton` behavior authority only.
- `assets/data/runtime/canonical_monster_catalog.json`: `5C3D5680...8C49`; builder `--check` reports 156 identities, 153 runtime entries, 7032 unchanged drop rows.
- `assets/data/monster_melee_ai_package_v3.json`: `FBC3B1F6...05C5`.
- `docs/bugfix24/20260909/monster_delivery_inventory.csv`: `A31CE688...EAFC`.

These SHA-256 values identify raw working-tree bytes. Git may normalize LF/CRLF when creating blobs, so they are not presented as Git object IDs; the commit hash below is the repository identity after staging. The two temporary prefetch overlay files and unrelated generated UID/translation files are outside this package.
