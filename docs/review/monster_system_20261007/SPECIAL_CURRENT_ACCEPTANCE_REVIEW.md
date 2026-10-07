# Special behavior current acceptance review

Baseline: `codex/integration@aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c`. Read-only inventory; production and tests were not modified or run in this audit. This review separates latest native evidence supplied by the mainline run from registered metadata and static fixtures.

## Current accepted or near-accepted paths

| behavior | stable IDs | exact reusable scene | current evidence | remaining boundary |
|---|---:|---|---|---|
| Boss summon / health stage | 160 | `tests/zuma_formal_summon_chain_test.tscn`, `tests/classic_boss_order_test.tscn` | latest native report: 4 summon requests, 15 actual births, map retirement handled | retain SearchEnemyTick/health-stage timing and reentrant request receipts after source repair |
| rank-5 FireWall | 160 | `tests/zuma_rank5_firewall_production_test.tscn`, `tests/zuma_rank5_firewall_mc47_production_test.tscn` | formal GameRoot/controller path; MC40 and MC47 fixture contracts exist | native/device result remains separate; preserve global caster:skill:target claim and 60-physics-frame observations |
| self detonation | 183 | `tests/monster_explosion_spider_runtime_test.tscn`, `tests/special_actor_explosion_gap_test.tscn` | latest actor coverage includes real ID183 positive death/adjacent settlement; draft extends remote invalid and duplicate settlement | final run must retain one-shot/death/remote target receipts |
| target magic | 220,222,224 | `tests/monster_target_magic_attack_test.tscn`, `tests/special_actor_target_magic_gap_test.tscn` | latest evidence covers delayed release, MAC/defense settlement, duplicate/life/map eligibility and target magic life steal | keep zero/miss/stale no-heal and immutable release receipt assertions |
| physical life steal | 193 | `tests/special_actor_lifesteal_poison_gap_test.tscn`, `tests/fengmo_area_test.tscn` | latest native semantic is pre-AC input: input30, target loss19, attacker heal9; this is current behavior evidence, not post-AC authority | source semantic remains MISSING; do not replace with actual-loss formula without product/source ruling |
| fixed-area / stationary | 180,195 | `tests/fixed_area_monster_test.tscn`, `tests/fixed_area_release_batch_test.tscn` | actor family path exists | repeat target/death/map retirement receipts remain required |
| burrow / area ambush | 124 | `tests/classic_boss_area_magic_outcomes_test.tscn` | ID124 runtime representative exists | direct emerge/heal/area timing receipt still required |

## Registered behavior still missing exact-ID acceptance

- ID169: `moth_control` profile is bound in `monster_behavior_profiles.json`, but canonical GameData has ID169 as 月魔蜘蛛0 and the formal matrix has `formal_runtime_ids: []`. The generic control consumer exists; ID169 must remain `MISSING`, and must not inherit the ID128/168 gas acceptance claim.
- Gas/poison IDs 46, 60, 128, 168: `tests/hc_monster_ai/w1_special_delivery_runtime_test.tscn` is a family path. Exact poison chance, duration, tick, and cleanup for every ID remain missing.
- Physical projectiles: real EnemyActor projectile delivery now passes IDs42/50/62/145/150/152/174/186/206 including damage, miss, duplicate contact, WORLD wall, map and life rejection. IDs151/207 and any other unrepresented family members remain MISSING. Reusable family scenes are `tests/monster_physical_projectile_attack_test.tscn` and `tests/hc_monster_ai/w1_special_delivery_runtime_test.tscn`.
- Dormant/wake variants 153–159: `tests/monster_dormant_damage_wake_test.tscn` is family evidence only. ID160 has separate Boss evidence and must not be used to promote 153–159.
- Fixed-area 180/195 and ordinary summoners 126/182: actor branches are covered, but full repeated target death, stale map-generation, reentrant release and cleanup receipts remain `MISSING` until the final native regression run.
- Burrow ID124: family actor evidence exists, but exact emerge heal-full, wake range and area-release timing remain `MISSING`.
- Profiles/behaviors named charge, split, rage, corpse/skeleton and stationary variants are registered in the matrix where applicable, but no exact-ID full lifecycle receipt was found in the current acceptance set. Their existing contract/source tests are static or family-level and must not be promoted to actor acceptance.

## Final native run list

Run only on the fixed source selected by root, with isolated runtime data and full receipts:

- `tests/zuma_formal_summon_chain_test.tscn`
- `tests/zuma_rank5_firewall_production_test.tscn`
- `tests/zuma_rank5_firewall_mc47_production_test.tscn`
- `tests/monster_explosion_spider_runtime_test.tscn`
- `tests/special_actor_explosion_gap_test.tscn`
- `tests/monster_target_magic_attack_test.tscn`
- `tests/special_actor_target_magic_gap_test.tscn`
- `tests/special_actor_lifesteal_poison_gap_test.tscn`
- `tests/hc_monster_ai/w1_special_delivery_runtime_test.tscn`
- `tests/monster_physical_projectile_attack_test.tscn`
- `tests/fixed_area_monster_test.tscn`
- `tests/fixed_area_release_batch_test.tscn`
- `tests/monster_summon_hard_cap_test.tscn`
- `tests/monster_dormant_damage_wake_test.tscn`
- `tests/classic_boss_order_test.tscn`
- `tests/classic_boss_area_magic_outcomes_test.tscn`

Every acceptance claim must include exact actor ID, release/source ID, map generation, target life/map decision, status tick timestamps, HP receipt, native exit and source fingerprint. A registered profile, static contract, fixture PASS or family representative cannot promote an exact ID to full acceptance. Android/GPU acceptance remains separate.
