# W1 exact-ID data mapping

This package is based on `2290fc49e917f4c2a9d1c8cd852bac068e908a15` in
`codex/bugfix24-w1-data-20260909`.

## Mappings

| Exact `monsterId` | Profile | Binding | Delivery/range |
| --- | --- | --- | --- |
| `42`, `145`, `186` | `w1_archer_projectile` | race `104`, `TArcherMonster` (`B_CANDIDATE`) | `physical_projectile`, 7 GU, `euclidean_circle` |
| `62`, `174` | `w1_thorn_dark_projectile` | race `93`, `TThornDarkMonster` (`B_CANDIDATE`) | `physical_projectile`, 7 GU, `euclidean_circle` |
| `224` | `w1_electronic_scolpion_target_magic` | race `200`, `TElectronicScolpionMon` (`B_CANDIDATE`) | `target_magic`, 2 GU `chebyshev_square`, `magic_defense`, `sourceContactMeleeFallback=true` |
| `226`–`234` | `w1_fixed_noncombat` | no actor-class binding | top-level `combatEnabled=false`; `movement.stationary=true`; no delivery/range |

The profile map is exact `profileByMonsterId`; no name, suffix, or class
fallback is introduced. The chest IDs are each mapped explicitly through the
shared fixed profile. IDs `228`–`233` receive no actor class. No chest is given
Centipede area, poison, burrow, or projectile behavior. The existing mappings
for `50`, `150`, `152`, `206`, `220`, and `222` are retained.

## Source and compatibility evidence

The exact identity candidates use
`dev_art_sources/reference/mir2_database_candidates/mylgd_mir2server_176/Mud2/DB/Monster.DB`
(SHA-256 `a8a2919b2f05f95459c01a67c9326f3d86fb954ecdc5dbb095e96cba237515b0`),
with `bindingAuthority=B_CANDIDATE` and exact ID lists. This candidate identity
route is recorded separately from the primary Pascal class rule:

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
  supplies the adjacent `GetAttackDir` fallback at `18449–18502`.

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
  differences outside the specified target-ID behavior profiles and the expected
  `monster_behavior_profiles.json` source-hash cascade. Generated input hash:
  `8DF63FD9C6D1E431741A74CD13C17A97B266601EE8BF5A8EAC4F31E655611163`.
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
