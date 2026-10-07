# ID193 life-steal source audit

Baseline: `codex/integration@aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c`.
Status: READ_ONLY / NOT_RUN / no source or test changes.

## Verified runtime order

The current production physical path is `EnemyActor._apply_attack_damage_impl()` (`scripts/enemy.gd:5867-5906`):

1. `hit_target.take_damage(dealt_damage, ...)` is called with the pre-defense attack input.
2. The target's own HP pipeline performs defense/AC and commits its actual HP mutation.
3. The attacker then calls `apply_life_steal(dealt_damage)` at `enemy.gd:5901`.
4. `apply_life_steal()` (`enemy.gd:7100-7104`) computes `max(1, int(dealt_damage * life_steal_ratio))`, capped by attacker max HP.

Therefore ID193's current runtime basis is the pre-AC `dealt_damage` input, not target actual HP loss. The reported native observation is consistent with this order:

```text
attack input / dealt_damage = 30
player actual HP loss after AC = 19
ID193 ratio = 0.33
current attacker heal = int(30 * 0.33) = 9
```

This is not an automatic fixture failure. It is a verified current production semantic.

The current code also means a shield/absorption or overkill distinction is not represented in the life-steal call: the attacker receives the pre-AC input basis after `take_damage`, subject only to its own max-HP cap. This is a behavior observation, not a recommendation to change it.

## Source-priority result

`assets/data/source_priority_policy.json` routes combat movement/AI/special behavior through `server_rules`, whose primary is `source.original_gameofmir.server_suite` (`reference/original_gameofmir`). `monster_attributes_21cq` is primary only for attributes/timing/life flags and explicitly excludes special delivery.

The ID193 profile in `assets/data/monster_behavior_profiles.json` contains only:

```json
{"lifeStealRatio": 0.33}
```

It has no basis field, no `source`, no `sourceLines`, and no distinction between raw attack input, post-AC damage, actual HP loss, shield absorption, or overkill.

A search of the primary original server source `dev_art_sources/reference/original_gameofmir/M2Server` found no life-steal/vampiric rule or ID193-specific heal settlement in the relevant monster classes or shared damage path. The primary source does contain ordinary health recovery and poison/damage routines, but those do not establish ID193 life-steal semantics. Because primary is present for the server-rules lane, auxiliary sources cannot be promoted merely because they might contain a convenient interpretation.

Result: `MISSING_AUTHORITY` for the semantic basis of the 0.33 ratio. The ratio itself is an authored profile fact, but its consumption basis is not source-proven.

## Raw / committed / actual semantics

| quantity | verified value/meaning |
|---|---|
| raw/dealt input | the `dealt_damage` argument passed into `_apply_attack_damage_impl`; current ID193 observation: 30 |
| target committed amount | target `take_damage()` performs its own AC and HP commit; observed player HP loss: 19 |
| attacker heal basis | current `apply_life_steal(dealt_damage)` uses 30, before target AC |
| current heal | `int(30 * 0.33) = 9`, then attacker max-HP cap |
| shield absorption | no source-authorized semantic found; current code still receives pre-AC `dealt_damage` |
| overkill | no source-authorized semantic found; current code still receives pre-AC `dealt_damage` |
| zero/miss | `_apply_attack_damage_impl()` returns before life-steal on a miss; `apply_life_steal()` rejects `dealt_damage <= 0` |
| target actual HP loss as heal basis | not current runtime behavior and not primary-source proven |

## Decision boundary

The earlier draft assertion `heal == actual_target_loss * 0.33` is too strong for the current source contract and must not be used as an authority. It would intentionally change or reject the verified pre-AC behavior. The correct status is:

- Current runtime: `VERIFIED_PRE_AC_INPUT_BASIS`.
- Primary source semantic authority: `MISSING`.
- Product decision: required before changing to actual-loss/post-AC basis.
- No implementation change recommended from this audit.

If product chooses actual committed loss later, that is a behavior change requiring an explicit source/product ruling and new tests for AC absorption, shield absorption, overkill, zero, and miss. The target-magic ID222 rule remains separate: its existing production branch explicitly calls `apply_source_magic_life_steal(final_damage)` after magic defense resolution.

## Auxiliary server-rules audit (primary missing, no promotion)

The policy was followed in order. The primary `source.original_gameofmir.server_suite` is missing an exact ID193/Rainbow Demon life-steal rule, so auxiliary server sources were searched for an exact registration/class and for the damage-to-AC/HP-to-heal order. No auxiliary result establishes the requested semantic.

| tier | exact registration/class evidence | damage/heal evidence | result |
|---|---|---|---|
| `auxiliary_1` `source.minipizza_mir2.server` | `Shared/Enums.cs:389` maps numeric 193 to `DarkWingedOma`; `Server/MirObjects/MonsterObject.cs:431` leaves `case 193: CrystalBeast` commented. Factory `MonsterObject.cs:146` maps case 60 to `VampireSpider`, not 193. | `Server/MirObjects/MonsterObject.cs:2333-2340` uses generic attacker `HPDrainRatePercent` and `damage - armour`; `Monsters/VampireSpider.cs:183-184` adds pet-derived `VampAmount` to its master. Neither is ID193/Rainbow Demon life steal. | `MISSING` exact ID193 rule; unrelated generic/pet mechanics excluded. |
| `auxiliary_2` `source.suprcode_crystal.server` | Same registry evidence: `Shared/Enums.cs:389` is `DarkWingedOma`; `Server/MirObjects/MonsterObject.cs:431` has commented `CrystalBeast`; factory case 60 is `VampireSpider` (`MonsterObject.cs:146`). No Rainbow Demon/ID193 class or active case found. | `Server/MirObjects/MonsterObject.cs:2641-2648` is generic weapon `HPDrainRatePercent` using `damage - armour`; `Monsters/VampireSpider.cs:182-183` is the same pet VampAmount path. No ID193-specific settlement or actual-HP-loss basis. | `MISSING` exact ID193 rule; generic HPDrain is not authority for profile ratio. |
| `auxiliary_3` `archive_extract.GM.51417ae3bc9f` | Policy allows this tier only for `gm_commands` and `script_examples` (`assets/data/source_priority_policy.json:424`); it cannot establish a general server combat rule. | Not consulted as behavior authority. | `INELIGIBLE` for this target. |

A separate `server_data` candidate search (`reference/mir2_database_candidates/suprcode_crystal_database/cjlaaa`) found only configuration/drop vocabulary such as `Configs/Setup.ini:73` (`VampireName=自爆蜘蛛`) and Rainbow-related item/drop records. That lane is not `server_rules` authority and provides no ID193 heal order, so it is excluded. Mirror entries were not used; quarantine entries are prohibited from runtime evidence by policy.

The auxiliary sources therefore do not resolve whether the ratio is based on pre-AC input, post-AC damage, committed HP loss, shield absorption, or overkill. Keep the verified current runtime observation (`input 30`, target loss `19` after AC, attacker heal `9`) and status `MISSING_AUTHORITY`; do not change production or tests from this audit.
