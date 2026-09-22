# W1 exact-ID data mapping

This package is based on `2290fc49e917f4c2a9d1c8cd852bac068e908a15` in
`codex/bugfix24-w1-data-20260909`.

## Mappings

| Exact `monsterId` | Profile | Binding | Delivery/range |
| --- | --- | --- | --- |
| `42`, `145`, `186` | `w1_archer_projectile` | race `104`, `TArcherMonster` (`B_CANDIDATE`) | `physical_projectile`, 7 GU, `euclidean_circle` |
| `62` | `w1_thorn_dark_projectile_62` | race `93`, `TThornDarkMonster` (`B_CANDIDATE`) | `physical_projectile`, 7 GU, `euclidean_circle`; original profile fields retained |
| `174` | `w1_thorn_dark_projectile_174` | race `93`, `TThornDarkMonster` (`B_CANDIDATE`) | `physical_projectile`, 7 GU, `euclidean_circle`; no ID62 field inheritance |
| `224` | `w1_electronic_scolpion_target_magic` | race `200`, `TElectronicScolpionMon` (`B_CANDIDATE`) | `target_magic`, 2 GU `chebyshev_square`, `magic_defense`, `sourceContactMeleeFallback=true` |
| `226`–`234` | `w1_fixed_noncombat` | no actor-class binding | top-level `combatEnabled=false`; `movement.stationary=true`; no delivery/range |

The profile map is exact `profileByMonsterId`; no name, suffix, or class
fallback is introduced. ID62 has an independent profile retaining its base
`dark_warrior` `timing`, `serviceBehavior`, `runtimeProjection.moveSpeed`, and
`collisionRadius` leaves. ID174 has a separate delivery/class profile and does
not inherit those ID62 leaves. The chest IDs are each mapped explicitly through
the shared fixed profile. IDs `228`–`233` receive no actor class. No chest is given
Centipede area, poison, burrow, or projectile behavior. The existing mappings
for `50`, `150`, `152`, `206`, `220`, and `222` are retained.

## Source and compatibility evidence

The exact identity candidates use distribution
`candidate.mylgd_mir2server_176`, with declared tier
`explicit_user_requested_candidate_after_routed_source_exhaustion`, route status
`accepted_by_M00R_after_all_routed_server_data_sources_failed_version_scope_or_field_coverage`,
and authority `B_CANDIDATE`. The file is
`dev_art_sources/reference/mir2_database_candidates/mylgd_mir2server_176/Mud2/DB/Monster.DB`
(SHA-256 `a8a2919b2f05f95459c01a67c9326f3d86fb954ecdc5dbb095e96cba237515b0`).
It is not labelled `tier=primary`; this follows the
`monster_runtime_authority_v1.json` `classic_176_db_candidate` contract. This
candidate identity route is recorded separately from the primary Pascal class rule:

- `ObjAxeMon.pas` SHA-256 `9D42ABF6B34B7A74FBD2AD802B08629CC67E0864CABDA694E13764DE750F28C0`:
  `TThornDarkMonster` declaration/constructor at lines `19–24,184–194`,
  `TArcherMonster` declaration/constructor at `26–31,198–204`, and shared
  `FlyAxeAttack`/`AttackTarget` at `41–100`/`65–100`.
- `UsrEngn.pas` SHA-256
  `E9E1735511CE0AEC8F90E52D38F504FD7430DF1AA490D6E82B29D62D7C6E84D3`:
  race `93` dispatch at line `1882`, race `104` at `1908`, race `200` at
  `1928`. `M2Share.pas` SHA-256
  `9E1505BE616D55A362151150BA92712B9C8439F0A32E35B13C666AE07A33C085`
  defines `MONSTER_THONEDARK=93` at line `159`.
- `ObjMon.pas` SHA-256
  `E32425C0C056CD83E0DD449F752813C613E829DA4EABC21C26CBAD45FFA59CE2`:
  `TElectronicScolpionMon` is declared at `119–128`, with `LightingAttack`
  and `Run` at `1820–1881`. `ObjBase.pas` SHA-256
  `65D59610B8A1F7F4DCF76058A753651D1A97997AD273FC4DF8E468E65A989262`
  (verified with `Get-FileHash -Algorithm SHA256`) supplies the adjacent
  `GetAttackDir` fallback at `18449–18502`.

`m_nAttackMax=6/3` is a consecutive burst count, not range. The source applies
HP immediately and sends delayed feedback; HardCore keeps its existing
target-bound delayed settlement with WORLD/combat-epoch validation. The
2-GU magic profile preserves the low-HP/or-exact-axis-two activation and the
adjacent physical fallback.

For `226`–`234`, the authority is
`assets/data/monster_runtime_authority_v1.json`, `HUMAN_FROZEN`, exact IDs,
reason `treasure chest is a fixed non-combat entity`. The formal runtime gate
must inspect `combatEnabled` before target acquisition, attack release, and
attack audio; missing is legacy-compatible `true`, while a present invalid
value fails closed. Damage reception and drop handling remain available.

## Verification and integration

- `C:\Windows\py.exe -3.12 tools/build_canonical_monster_catalog.py` —
  `CANONICAL_MONSTER_CATALOG_BUILD_PASS` (156 identities, 153 runtime allowed,
  7032 drop rows).
- `C:\Windows\py.exe -3.12 tools/build_canonical_monster_catalog.py --check` —
  `CANONICAL_MONSTER_CATALOG_CHECK_PASS` with the same counts.
- Semantic comparison against the base canonical catalog passes with zero
  differences outside the explicit whitelist (`serviceClass`, `attackDelivery`,
  `runtimeProjection.attack_range_gu`, and the fixed noncombat fields) and the
  expected `monster_behavior_profiles.json` source-hash cascade. Timing,
  movement, collision, dormant, summon, stats, and drop leaves are unchanged.
  Generated input hash:
  `4B9FB9223CD73021285C7E1F9A853F76AD0AD824F6928ED84E2518D5CE8BC805`.
- `C:\Windows\py.exe -3.12 tools/verify_source_priority_policy.py` was not
  runnable in this isolated tree because the required read-only manifest
  `outputs/resource_catalog/complete_local_mir_sources/manifest.json` is absent.
  No cache/output manifest was created.
- Godot/import was not run by this data package.

Integration must consume `MonsterIdentity.behavior_profile` by exact ID, route
the new range records through the existing range adapter, and update the
Sol-owned expected-range contract for `42,62,145,174,186,224`. The generic
Enemy gate should leave the chest actor damageable and droppable while blocking
autonomous combat. No production Enemy or test file is changed here.


## 第二包：W1 special delivery families

This independent package adds exact-ID mappings only for the following 17 IDs;
`profileByMonsterId` and `monster_attack_range_policy_v1.json` are both keyed by
these stable IDs, with no name/suffix/class fallback:

| IDs | Profile / kind | Formal range | Primary class evidence |
| --- | --- | --- | --- |
| 18, 103, 104, 185 | `w1_spit_spider` / `directional_spit_map` | 2.0 GU, `source_spit_map_5x5`, 2 cells | `TSpitSpider`, race 82 |
| 146 | `w1_spit_elf_warrior_146` / `directional_spit_map` | 2.0 GU, `source_spit_map_5x5`, 2 cells | `TElfWarriorMonster`, race 114; inherited geometry, poison disabled |
| 46, 60 | gas profiles / `gas_adjacent` | 1.0 GU, adjacent Chebyshev cell | `TGasAttackMonster`, race 90 |
| 128, 168 | `w1_gas_moth_128_168` / `gas_adjacent` | 1.0 GU, adjacent Chebyshev cell | `TGasMothMonster`, race 105; hidden reveal denominator 3 |
| 79 | `w1_line_lighting_zombi_79` / `line_magic` | 6.0 GU, strict axis boundary, 9-cell line | `TLightingZombi`, race 94 |
| 76, 77, 235, 236, 239 | cow profiles / `mixed_target_tile` | 1.0 GU, adjacent Chebyshev cell | `TCowKingMonster`, race 92; physical/magic ratio 0.5/0.5 |
| 160 | `w1_mixed_sculture_king_160` / `mixed_target_tile` | 1.0 GU, adjacent Chebyshev cell | `TScultureKingMonster`, race 102; physical/magic ratio 0.0/1.0 |
| 194 | `w1_guard_archer_194` / `guard_direct_projectile` | Manhattan view range 12.0 GU | `TArcherGuard`, race 112 |

The Pascal class rule is `source.original_gameofmir.server_suite` with
`tier=primary`; candidate Monster.DB identity remains separately recorded as
`distribution=candidate.mylgd_mir2server_176`, `authority=B_CANDIDATE`, exact
ID route, SHA-256
`a8a2919b2f05f95459c01a67c9326f3d86fb954ecdc5dbb095e96cba237515b0`. The
primary source hashes are `ObjMon.pas`
`E32425C0C056CD83E0DD449F752813C613E829DA4EABC21C26CBAD45FFA59CE2`,
`ObjMon2.pas`
`983C098130D7A83B34F19746FC484609DCEF975344864C435526D254F98D0BCD`,
`ObjBase.pas`
`65D59610B8A1F7F4DCF76058A753651D1A97997AD273FC4DF8E468E65A989262`,
`UsrEngn.pas`
`E9E1735511CE0AEC8F90E52D38F504FD7430DF1AA490D6E82B29D62D7C6E84D3`, and
`M2Share.pas`
`9E1505BE616D55A362151150BA92712B9C8439F0A32E35B13C666AE07A33C085`.

The spit source is `TSpitSpider.SpitAttack/AttackTarget`
(`ObjMon.pas:674-729`) plus `TargetInSpitRange`
(`ObjBase.pas:18504-18531`): it scans a 5x5 source `SpitMap`, uses a two-cell
axis gate, and uses magic-defense damage. Poison is only enabled by the base
spider constructor (`ObjMon.pas:660-665`); `TElfWarriorMonster` disables it
(`ObjMon.pas:1718-1724`). The poison descriptor records the source operation
`POISON_DECHEALTH`, 30.0 seconds, `point=1`, `tickDamage=2` (the source applies
`DamageHealth(point+1)` at `ObjBase.pas:4255-4263`), and denominator offset 20.
`M2Share.pas:2073,10368-10371` plus `MirServer/Mir200/!Setup.txt:290` establish
a 2500 ms default/checked-in value while allowing a runtime Setup override;
the data must not claim the interval is immutable.

The gas source is `TGasAttackMonster.sub_4A9C78/AttackTarget`
(`ObjMon.pas:874-918`) and inherited `GetAttackDir`
(`ObjBase.pas:18449-18502`): one adjacent target, magic-defense damage, stone
status for 5.0 seconds, denominator offset 20, and the strict accuracy gate
`Random(speedPoint) < hitPoint`; the poison denominator owner is the target
anti-poison value. The moth class adds only its
separate hidden reveal branch (`ObjMon.pas:1581-1590`), denominator 3 for IDs
128/168. The line source is `TLightingZombi.LightingAttack/Run`
(`ObjMon.pas:1131-1188`), with strict `<6` axis gate and 9-cell advance;
`MagPassThroughMagic` (`ObjBase.pas:2536+`) documents the 600 ms hit feedback
and undead multiplier 1.5. The mixed source uses `HitMagAttackTarget`
(`ObjMon.pas:1039-1047` for cow and `1502-1508` for Sculture); the source HP
settlement/timing remains the project adapter contract. The guard descriptor
sets `useAccuracy=false`: `TArcherGuard` (`ObjMon2.pas:904-923`) has no
`Random(speedPoint) < hitPoint` gate before immediate physical settlement. The
guard source is
`TArcherGuard` (`ObjMon2.pas:889-950`): Manhattan target selection, immediate
physical HP settlement, and presentation delay `{baseSeconds:0.6,
perChebyshevGuSeconds:0.05}`; the latter is not an HP delay.

No `life_type`/`undead` field is present in the formal summon template
`assets/data/vanilla_176/taoist_summon_baseline.json` (`templates.skeleton`,
lines 37-87) or in the primary skill record
`assets/data/vanilla_176/skills_source_of_truth_v1.json`
(`taoist.summon_skeleton`, lines 3447-3570); those records establish
`new_pet_template=skeleton`, `database_names=[BoneFamiliar]`, and stats only.
The primary skills lane therefore cannot prove a summon life type, and the
summon template's `monster_id=145` must not be joined to canonical monster 145
(the latter is an Archer exact ID). An auxiliary-2 Jev release note
(`server.crystal.Jev`, `Jev/README.md:840`, SHA-256
`2C7102B20C278E6356DAB8CA57B48C1D71B2C1FBCFF4928C3FE28AC284C66104`) says
`BoneFamiliar` was classified undead, but that name-only release note is
insufficient to promote a stable summon `life_type`; line79's 1.5 branch must
remain conditional on a separately proven target flag. This package does not
modify skills or summon data.

Existing non-delivery leaves are preserved. In particular ID46/60 keep their
original timing/serviceBehavior/move/collision/onHit fields, ID160 keeps
`largeClientBoss`, `dormant`, and `wakeRange`, the cow variants are independent
profiles, and ID169's shared `moth_control` mapping is untouched. IDs 226-234
remain the existing human-frozen `combatEnabled=false` profiles; their
DATA_HOLD is actor-class identity, not a reason to add combat delivery here.

Integration must consume the typed named kinds from the canonical profile and
range policy, add strict validation/fail-closed handling for malformed named
delivery, and accept the poison shape `decrease_health` plus `point=1`,
`tickDamage=2`, and configurable interval evidence. Sol owns the Enemy/runtime
consumer and expected-range tests; this package changes no Enemy or tests and
runs no Godot/import.

Static checks for this package: parse both source JSON files, run
`C:\Windows\py.exe -3.12 tools/build_canonical_monster_catalog.py` and its
`--check` mode, compare non-target canonical leaves against the base, and run
`git diff --check`. The isolated tree has no source manifest for
`verify_source_priority_policy.py`; the main tree's already-passing policy
check remains the integration evidence.
