# W1 exact delivery regression

## Scope and frozen boundaries

This scene verifies exact monster_id routing for existing EnemyActor delivery paths. It does not modify production scripts, formal data, global schema, allowlists, caches, or the 12 DATA_HOLD IDs. It is authored in the UI specialist tree against base cf1d2718befdef7e6cc2fb274fd91ce0759d105f. **Status: main integration PASS (165323_920_2428).** Exact data bca42553/68a45462 and the dd31a610 combat gate are present. Test HEAD d114eb53 plus two uncommitted fixture target reacquisitions was verified; this is not clean-HEAD evidence.

## Exact matrix

| exact monster_id | canonical service class/race | delivery | range |
|---|---|---|---:|
| 50 | TDualAxeMonster/87 | physical_projectile | 7 GU |
| 42, 145, 186 | TArcherMonster/104 | physical_projectile | 7 GU |
| 62, 174 | TThornDarkMonster/93 | physical_projectile | 7 GU |
| 224 | TElectronicScolpionMon/200 | target_magic | 2 GU |
| 226, 227, 234 | TCentipedeKingMonster/107 (class candidate only) | fixed noncombat actor negative case; **no delivery asserted** | — |
| 228–233 | UNRESOLVED (DATA_HOLD; no actor class) | fixed noncombat actor negative case; **no delivery asserted** | — |

Physical delivery freezes effectId monster.physical_arrow.v1 and obstaclePolicy environment_can_fly_line. The source `0.6 + 0.05 * Chebyshev` value is feedback/presentation timing; it does not by itself prove an HP settlement delay. The runtime fixture separately checks a 4 GU target's 0.8s delayed HP settlement and WORLD/epoch cancellation. The Archer `m_nAttackMax=6` and ThornDark `m_nAttackMax=3` source values are consecutive burst attack/damage-count values, not range; every physical case retains the formal 7 GU gate. ID224 checks monster.target_lightning.v1, magic defense, and the runtime's 200 ms delay; full-health cast requires the 2 GU axis boundary, low HP permits the interior, and the inherited adjacent ordinary attack remains physical. IDs 226–234 are excluded from area, poison, and burrow assertions; their test only checks the exact fixed-noncombat gate, no autonomous attack/release/audio, damage reception, and preserved drop identity.

Each physical ID uses real EnemyActor.setup(GameData.get_monster_by_id(id), ...), signal capture, no instant damage, delayed settlement, a same-WORLD moving-target hit, WORLD-change rejection, and old PlayerCharacter.combat_epoch rejection. ID50 additionally inserts a real `StaticBody2D` on `WorldSpatialRules.WORLD_LAYER`: the wall blocks launch and a wall inserted after launch blocks release, with no damage in either case. The environment provider reports open ground in this fixture, so these are physics-server WORLD checks rather than a fake point lookup or an alternate map ID. ID224 separately verifies a same-WORLD moving-target hit, real WORLD-body launch/release blocking, and epoch/map delayed rejection.

### 226–234 fixed-noncombat hold boundary

The test records three independent facts and does not merge them into a combat rule:

1. **Original service-class binding (candidate):** exact IDs 226/227/234 carry `server_race=107`, `pascal_class=TCentipedeKingMonster`, `class_binding_status=CANDIDATE`, and `class_binding_authority=B_CANDIDATE` in `monster_runtime_authority_v1.json`. The exact source row is `dev_art_sources/reference/mir2_database_candidates/mylgd_mir2server_176/Mud2/DB/Monster.DB` (IDs 226/227/234, source-row ordinals 266/268/269), with factory/class evidence `UsrEngn.pas:1831-1938` and class rule `ObjMon2.pas:442-582`. This accepted candidate route is sufficient to keep the IDs addressable, but it does not authorize inheriting that class's attack.
2. **No actor-class binding for 228–233:** these six exact IDs have `targeting.server_race=null`, `pascal_class=null`, `class_binding_status=DATA_HOLD`, `class_binding_authority=UNKNOWN`, and no `class_binding_source`; the authority explicitly says no exact Monster.DB row and that a reused base-row Race cannot authorize target acquisition. Their race-107 movement compatibility row is not an actor mapping.
3. **Human fixed-noncombat behavior:** all nine canonical exact-ID entries are `classification=special`, `attack_min=0`, `attack_max=0`, `behavior_profile_id=w1_fixed_noncombat` after integration, and `boss_rule={}`. All nine have movement `stationary=true`, `base_move_speed_gu_per_sec=0`, and `movement_authority_override.authority=HUMAN_FROZEN`, `kind=stationary_entity`, source `user.authority.monster_movement_speed.2026-08-30`, reason `treasure chest is a fixed non-combat entity`. That is affirmative human noncombat intent, but the current runtime still lacks the exact-ID `combatEnabled=false` attack gate; `EnemyActor.setup` clamps raw zero stats to `attack_min>=1` at `scripts/enemy.gd:481-482`, and `stationary` only freezes movement. The new negative actor matrix observes behavior instead of naming an unlanded field: each real actor must emit no autonomous attack/release/audio, remain stationary, retain `drop_profile_id`, and still accept damage. No area, poison, or burrow behavior is asserted. `ObjMon2.pas`'s `TCentipedeMonster.AttackTarget`/`MakePosion` is class-rule evidence only and cannot be inherited from race 107.

## Stable production interfaces

The test consumes existing symbols and never hand-injects attack_delivery_rule:

- GameData.get_monster_by_id(int) is the sole exact-ID entry; get_monster(name), display names, and variants are not lookup keys.
- MonsterIdentity.behavior_profile(Dictionary) must provide serviceClass, attackDelivery, and A-evidence fields after integration.
- EnemyActor.setup(Dictionary, PlayerCharacter, bool) must apply the exact-ID profile; the test only sets deterministic damage and navigation context.
- EnemyActor.configure_runtime_map_projection(...), configure_terrain_navigation_context(...), ranged_projectile_requested, and target_magic_requested.
- EnemyActor._movement_authority_record_for_id(int) supplies the exact stationary and class-binding evidence for the nine held IDs.
- Existing release paths are exercised through _physics_process, _launch_physical_projectile, _launch_target_magic, and _update_pending_attack. The chest matrix deliberately asserts that no release path or attack audio starts; it does not invent an area/burrow entry point.
- EnemyActor.take_damage(int, Node2D, Dictionary) and can_receive_damage() remain active for fixed noncombat actors; drop identity is read from the actor's exact canonical `drop_profile_id`.
- Delayed isolation uses PlayerCharacter.begin_combat_transition(String), finish_combat_transition(String), combat_epoch, and runtime_map_id metadata.

## Source evidence

The exact family and values come from docs/bugfix24/20260909/W1_32FAMILY_DELIVERY_AUDIT.md (read-only audit produced from the Sol W1 tree f14f0b058092c5ee977048463fafc0c9fa3902a4):

- ObjAxeMon.pas:41-100,182-202 and UsrEngn.pas:1908: 42/145/186 Archer FlyAxeAttack/CanFly, 7-cell gate, and delay; ObjAxeMon.pas:19-25,41-100,184-188: 62/174 thorn-dark inherits the projectile path, with family attack values separate from delivery.
- ObjMon.pas:119-128,1805-1881 and ObjBase.pas:18449-18502: ID224 target lightning activation and inherited adjacent attack.
- ObjMon2.pas:35-45,442-582 and UsrEngn.pas:1911: IDs 226/227/234 are only a candidate CentipedeKing class route; its area/poison/hidden behavior is not inherited by this test. IDs 228–233 have no exact actor-class source row.
- Current EnemyActor execution points are scripts/enemy.gd:437 (setup), :929 (_apply_behavior_profile), :3050 (_world_attack_path_is_clear_for_release), :3182 (_update_pending_attack), :3233 (_launch_physical_projectile), :3395 (_launch_target_magic), :481-482 (zero-stat clamp), :4825 (take_damage), and :4868 (can_receive_damage); the attack animation/audio boundary is :688-691. Existing runtime regression references are tests/monster_physical_projectile_attack_test.gd, tests/monster_target_magic_attack_test.gd, tests/monster_special_delivery_runtime_test.gd, and tests/hc_monster_ai/combat_epoch_delivery_test.gd. The new fixture's wall helper uses `StaticBody2D` plus `CollisionShape2D(RectangleShape2D)` with `WorldSpatialRules.WORLD_LAYER` and waits for a physics frame after insertion/removal.

## Run and acceptance

After Sol exact-ID profile/range/delivery-gate integration and an integration baseline is fixed, run:

    & tools/run_godot_tests.ps1 -TestPaths 'tests/w1_exact_ranged_delivery_test.tscn' -TimeoutSeconds 60

The result must contain `W1_EXACT_RANGED_DELIVERY_PASS` plus nine `W1_SPECIAL_NONCOMBAT_HOLD` lines, with runner JSON/raw logs saved at the same final code/dependency HEAD. Main runner 165323_920_2428 naturally exited 0, 1/1 PASS, engine_log_errors=0. The two earlier failures 165152_613_15408 and 165225_232_17404 are retained: the map-cancellation subcase correctly cleared the target, so the following independent epoch subcase now explicitly reacquires it in both physical and target-magic cases. No production rule or assertion was weakened. A printed PASS marker in the second failed run was rejected by the runner because a script assertion also occurred. Do not downgrade to profile injection, inherit candidate class behavior, or treat blank delivery as melee. The other six DATA_HOLD IDs (`41,59,78,123,161,190`) remain absent; 228–233 are covered only by the fixed-noncombat negative case and still have no actor class or delivery mapping.
