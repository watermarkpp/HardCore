# Historical special behavior mainline wiring review

This is the pre-repair inventory and its chronological corrections. Current coverage supersedes it in SPECIAL_CURRENT_ACCEPTANCE_REVIEW.md; historical missing claims below are not final acceptance.

Baseline: `codex/integration` at `aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c`.

Scope is the remaining special behavior families only. ID70 special melee and the FireWall/ID160 chain are already reviewed separately. This is a read-only source audit: no production/test edits and no Godot execution. `ACTOR_RUNTIME` means a real EnemyActor branch was exercised; `FAMILY_RUNTIME` means only a family representative or generalized branch; `STATIC_ONLY` means metadata/contract/source inspection; `MISSING` means no exact actor evidence was found.

## Shared settlement rules

`EnemyActor._apply_behavior_profile()` consumes profile fields into `attack_delivery_rule`, `summon_rule`, `area_attack_rule`, `control_on_hit_seconds`, poison `onHit`, `lifeStealRatio`, dormant and burrow state. Ordinary physical/ranged delivery settles through `_apply_attack_damage_impl()` (`enemy.gd:5867-5906`): damage first, then life steal, control-on-hit, and profile poison. This makes the on-hit status contingent on a successful hit branch; a miss exits before poison/control.

Direct target magic is not a direct HP shortcut. `_launch_target_magic()` (`enemy.gd:5487-5555`) creates an immutable release record, `_settle_target_magic_release()` (`5559-5600`) performs the final resolution and life steal, and `_emit_target_magic_descriptor()` (`5603-5621`) emits `target_magic_requested`. The production GameRoot connection must consume this descriptor/release owner; the visual effect is not the damage authority.

Fixed area attackers emit `fixed_area_ground_spike_requested` (`enemy.gd:6785`); GameRoot connects it at `game_root.gd:5305-5308` and settles through `_on_enemy_fixed_area_ground_spike_requested` (`6364+`). Generic summoners emit `summon_requested` only after their warning/cooldown and target/life gates in `enemy.gd:6788-6815`; GameRoot connects them at `game_root.gd:5305`. Boss health-stage summon remains a separate path at `enemy.gd:7703-7725`.

Poison clocks belong to the recipient. Player/Summon monster-source poison uses MonsterSourcePoisonState (2.5s), and legacy Player poison uses Player physics; poisoned enemies use the EnemyActor status clock: `apply_poison()` (`enemy.gd:7475+`) sets status fields; `_physics_process` status maintenance (`7688+`) calls `_apply_poison_tick_damage()` (`7311+`). DOT uses `causes_struck=false`, so it must not add attack delay or walk delay. Generic red/green poison application in GameRoot is separate (`game_root.gd:10985-11037`) and must not be substituted for monster on-hit poison.

## Family matrix

| family | profile / IDs | real entry | settlement / eligibility / cleanup | existing evidence | status |
|---|---|---|---|---|---|
| poison/control on-hit | `cave_maggot` (legacy-only), `dung` (legacy-only), `moth_control` 169 | ordinary physical branch → `_apply_attack_damage_impl` → `_apply_on_hit_control`; profile poison where present | Accuracy miss returns before status. Control denominator is base + target anti-poison (`5909-5930`). Legacy profile poison uses recipient `apply_poison`; server-source spit/gas uses recipient `apply_monster_poison`. Recipient clocks own expiry/tick, and poison must not issue struck. | Generic struck/status tests; no exact actor proof for 169 or legacy-only IDs | `MISSING` exact actor; wiring exists, no confirmed defect |
| gas/poison delivery | 46,60,128,168 and family profile variants | `_launch_monster_special_cell_delivery` → special release settlement → `_apply_area_magic_status`/poison or target delivery | Release identity/life/map checks reject stale/dead/out-of-map targets; status application follows successful release. Poison status clock/cleanup is recipient-owned (Player/Summon source poison and Enemy status clocks are distinct). | `w1_special_delivery_runtime_test.gd` covers gas family representatives | `FAMILY_RUNTIME`; exact poison duration/tick and every ID remain uncovered |
| target magic | 220,222,224 | `_launch_target_magic` → immutable release → `_settle_target_magic_release` → `target_magic_requested` → GameRoot target-magic consumer | `_target_magic_recipient_admissible`, range condition, map/life/target validity, release identity; magic resolution occurs before status/life-steal settlement. Stale release must not settle. | Target-magic contract/source tests; no exact actor runtime found for 220/222/224 | `STATIC_ONLY` exact IDs; wiring is present |
| physical projectile | 42,50,62,145,146,150–152,174,186,194,206–207 | `_launch_physical_projectile` or guard-direct projectile → projectile release/settlement → `_apply_attack_damage_impl` | Projectile must retain source/release/life/map eligibility; final hit uses physical accuracy and then on-hit/life-steal where the profile allows. Cleanup is projectile/release-owned. | W1 family runtime covers 146/194 and projectile representatives; ID70 is separate mature flow | `FAMILY_RUNTIME` / `MISSING` exact IDs 50,62,150–152,174,206–207 |
| life steal | 193 (ratio .33), 222 (ratio .20) | physical path `apply_life_steal(dealt_damage)`; magic path applies post-resolution damage in target-magic/area magic settlement | Healing is based on committed damage in the owning attack branch; failed/missed/zero damage must not heal. Recipient/death transitions are handled by normal actor HP authority. | No exact actor runtime evidence for 193 or 222; broad life-steal source/profile checks only | `MISSING` exact actor; no numeric change justified |
| fixed full-area | 180,195 | `_update_area_attack` → `fixed_area_ground_spike_requested` → GameRoot fixed-area consumer | Stationary profile, fixed footprint snapshot, visible combat targets, map/life/death eligibility; release cleanup belongs to fixed-area record/actor life. | `fixed_area_monster_test.gd` actual 180/195 | `ACTOR_RUNTIME` representative; needs repeated target/death/map cleanup receipts |
| ordinary summoner | 126→127, 182→183 | `_update_behavior_summon` warning/cooldown → `summon_requested` → GameRoot `_on_boss_summon_requested`/summon service | Cancels warning when dead/dying/controlled/charmed/dormant/burrowed; validates target life before emit; reserves cooldown before callback; M30 birth queue owns child identity/cap/cleanup. | `fixed_area_monster_test.gd`, `monster_summon_hard_cap_test.gd` actual 126/182 | `ACTOR_RUNTIME`; exact reentrant/map-retirement coverage should remain in regression set |
| self detonation | 183 | `self_detonation` delivery branch → adjacent release/settlement → death/cleanup | Must settle once, use adjacent-map-cell eligibility and source life/map validation; detonation actor must transition through normal death path and not re-enter attack after queued deletion. | No exact actor runtime found for 183; source profile only | `MISSING` |
| dormant/wake | 153–159 variants, 160 Boss; `zuma_boss` profile is legacy-only mapping | dormant gate in EnemyActor; wake-range/target acquisition; ID160 also Boss stone wake | Damage/wake and target acquisition must preserve actor life/map identity; ID160 summon is separate health-stage/SearchEnemyTick logic. | `monster_dormant_damage_wake_test.gd`; `classic_boss_order_test.gd` actual 160/124/76 | `FAMILY_RUNTIME` plus ID160 actor evidence; missing per-variant 153–159 |
| burrow/ambush | 124 touch dragon | dormant/burrow state → wake/ambush area magic path; `attackDelivery.area_magic` → area release | Burrow state is stationary, wake range 128, heal-full-on-emerge per ObjMon2 source; area release validates map/life/locked target and then status/life steal. | `classic_boss_area_magic_outcomes_test.gd`, special runtime ID124 | `ACTOR_RUNTIME` representative; emerge/heal/area timing boundary still needs direct receipt |

## Confirmed defects versus missing coverage

1. **Confirmed timing defect:** ID160 health-stage summon is currently checked synchronously from damage commit (`_apply_damage_core → _apply_health_stage_mechanics`) while original `TScultureKingMonster.Run` checks only on SearchEnemyTick/action boundary. This is the known FireWall/large-hit reentrancy issue; it is not evidence that the first HP threshold itself is wrong.
2. **No confirmed poison, projectile, target-magic or life-steal numeric defect:** the production entry and settlement consumers exist, but exact actor receipts are missing for many profile IDs. A static profile PASS cannot be promoted to full actor acceptance.
3. **Coverage gap:** self-detonation ID183 has no exact actor runtime evidence found. Its source rule is explicit, but one-shot death/adjacent target settlement is unverified.
4. **Coverage gap:** exact on-hit poison/control behavior for ID169 and legacy-only gas profiles is unverified; current generic status code has the expected miss/expiry/DOT separation.
5. **Coverage gap:** target-magic IDs220/222/224 and projectile IDs50/62/150–152/174/206–207 lack exact actor receipts. The shared release path is present, so this is coverage debt, not a proven broken branch.
6. **No source-based permission to alter tick, regen, or set-target context:** status ticks are consumed by the EnemyActor clock; target eligibility is release-owned; no unverified metadata should override these owners.

## Reusable regression scenarios for the next native run

- `tests/monster_summon_hard_cap_test.gd`: IDs126,182 and ID160 summon cap/reentrant birth.
- `tests/fixed_area_monster_test.gd`: IDs180,195 fixed-area actor path and stationary eligibility.
- `tests/monster_dormant_damage_wake_test.gd`: dormant damage/wake boundary.
- `tests/classic_boss_order_test.gd`: IDs76,124,160 Boss order, wake and summon pool.
- `tests/classic_boss_area_magic_outcomes_test.gd`: ID124 area magic outcome.
- `tests/hc_monster_ai/w1_special_delivery_runtime_test.gd`: gas, spit, line magic, mixed tile and guard projectile family paths.
- `tests/monster_special_delivery_runtime_test.gd`: ID70 and ID124 delivery runtime (ID70/FireWall mature flows are not re-audited here).
- `tests/monster_struck_runtime_test.gd`, `tests/monster_struck_policy_test.gd`: ordinary struck and timing continuation; needed when adding exact poison/projectile actors.
- `tests/source176_r3/all_skill_reaction_paths_test.gd`, `tests/source176_r3/source_direct_phase_trace_test.gd`: source reaction/release gate regression.

Acceptance for the next run must bind each result to the actor ID, source/release ID, map generation, target eligibility decision, status tick timestamps, HP receipt and native exit. Device acceptance remains separate.

## Correction after exact-test inventory

The earlier matrix used `MISSING` too broadly. Exact positive actor evidence already exists and must be retained in the final matrix:

- ID183 exact positive actor path: `tests/monster_explosion_spider_runtime_test.gd:18-45` creates real ID183, enters `_physics_process`, asserts adjacent target HP loss and `_death_pending` self-death. Remaining gap is remote invalid target and duplicate settlement, covered by the new draft.
- IDs220/222/224 exact target-magic actor path: `tests/monster_target_magic_attack_test.gd:18-108` exercises ID220 release/delay, ID222 delayed release and life steal, and `tests/monster_target_magic_attack_test.gd:180-243` exercises ID224 release, settlement and presentation identity. Remaining gap is explicit zero/miss/stale no-heal and per-release receipt boundaries.
- ID222 source arithmetic: `tests/monster_magic_lifesteal_test.gd:7-20` verifies the post-MAC integer life-steal helper; it is not a substitute for the attack settlement receipt.
- ID193 existing coverage is only direct helper/map setup: `tests/fengmo_area_test.gd:25-43`; the physical attack, miss and zero-damage settlement extension remains unverified.
- ID169 is excluded from the formal runtime catalog; the attempted positive-control fixture was invalid and freed. Current test records the absent formal binding, not positive control acceptance.

The new runnable drafts are in `outputs/monster_upgrade_20261007/special_actor_draft/`; they remain `NOT_RUN` until root selects and installs them under `tests/`.
