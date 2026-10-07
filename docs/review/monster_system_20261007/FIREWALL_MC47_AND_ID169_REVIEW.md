# Zuma rank-5 FireWall MC47 and ID169 source correction

Baseline: `codex/integration@aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c` (read-only source/output audit; no Godot).

## FireWall formula and MC47 bound

The authoritative FireWall definition is `assets/data/vanilla_176/skill_source_package_v1_0_1/mir2_176_skills_source_of_truth_v1.json:2151-2168,2181-2195`. It fixes a 1000 ms tick, MAC defense, and `get_power(rank, mpow(magic_db)) + roll_mc()`. The raw magic implementation is `scripts/skills/formulas/mir2_skill_formula.gd:49-75`; `get_power` is `:13-24`. The rank extension path is `scripts/skills/runtimes/wizard_skill_runtime.gd:62-72,120-142`, with `scripts/skills/skill_rank_resolver.gd:61-66` defining `more_multiplier(rank)=1.1^(rank-3)`.

For the formal canonical ID160 fixture, `power=3`, `def_power=3`, and deterministic `mpow=3`; therefore rank 3 base raw is `3 + 3 + MC`. At the requested MC maximum 47:

```text
rank3 raw = 3 + 3 + 47 = 53
rank5 multiplier = 1.1^(5-3) = 1.21
rank5 raw = roundi(53 * 1.21) = roundi(64.13) = 64
fixed Zuma MAC20 => maximum one accepted hit = 64 - 20 = 44 HP
```

The existing formal test uses MC40 (`tests/zuma_rank5_firewall_production_test.gd:11-15`), yielding rank3 raw46, rank5 raw56, and 36 HP after MAC20. A formal MC47 parameterized run should retain the same production chain and assert `rank3_raw=53`, `rank5_raw=64`, `mac=20`, `hp_delta=44`, `tick_interval_ms=1000`; this is a fixture boundary, not device/player MC confirmation.

The controller tick is one accepted claim per `caster:skill:target` and uses `tick_interval=1.0` (`scripts/fire_wall_field_controller.gd:24-29,272-357,383-388`; global claim in `scripts/ground_effect.gd:230-264`). Two overlapping controllers from the same caster still produce one target claim per second. The three-tick formal observation must retain real physics ticks (60-frame gap at the project physics rate), both controller IDs, release IDs, claim key and HP receipt; no device FPS conclusion follows.

For this deterministic MC47 fixture with its specified skill/weapon modifiers only, MaxHP3000/MAC20, the known-damage lower bound with no regen is `ceil(3000/44)=69` accepted ticks, at least 69 seconds. Natural regen is authoritative at `scripts/monster_natural_regen_policy.gd:6-12,26-51,63-66`: every 6 seconds, `floor(MaxHP/75)+1 = 41 HP`, independent of damage. Thus 69 seconds is only a conservative lower bound; it cannot be used as the expected kill time. If ticks and regen are aligned with the first regen after each six damage ticks, the simple deterministic model is 223 net HP per six-second cycle and reaches roughly 81 seconds (the exact kill tick depends on service phase, effect lifetime, and live damage rejection/claim receipts). Current source does not prove a tighter device-confirmed bound.

## ID169 / gas-control correction

`assets/data/monster_behavior_profiles.json:816-897` maps the primary gas/moth class to IDs 128 and 168 (`w1_gas_moth_128_168`), with inherited gas control and hidden reveal. The separate `moth_control` profile maps ID169 (`:1331-1347`), but `docs/review/monster_system_20261007/SPECIAL_BEHAVIOR_MATRIX.json` records `formal_runtime_ids: []` for that profile. Canonical combat data identifies ID169 as 鏈堥瓟铚樿洓0 (`assets/data/canonical_monster_combat_source_v1.json:3144-3164`), so the earlier draft must not call ID169 a currently covered formal actor. The current runtime consumer exists generically (`scripts/enemy.gd:5903-5919` and gas delivery around `:5032-5114`), while exact ID169 actor acceptance remains `MISSING`; this is a dead/legacy profile binding and coverage gap, not proof that the consumer is disconnected. IDs128/168 gas control and their consumer should be reported separately from ID169.

Status: source formula verified; MC40 and MC47 formal native runs PASS in the controller receipts. The numerical bound is specific to the fixture, not a maximum over all equipment or actual player state. Device confirmation NOT_RUN.
