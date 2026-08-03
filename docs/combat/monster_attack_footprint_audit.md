# Monster spatial attack footprint audit

Baseline: `codex/integration@1b14e87549b75e2e77471ee39a00262a0e646044`

Shared contract: `skills.footprint_snapshot.ground_gu_projection.v1`

Monster integration contract: `monster.attack.release_footpoint_projection.v1`

The monster domain uses the shared immutable `SkillFootprintSnapshot` format.
It does not define a second projection representation.

## Invariants

- Every damage projection starts from a real physics footpoint in continuous
  ground GU. Screen PX is presentation only.
- Every target is its existing footpoint plus `combat_radius_gu`; no artificial
  footpoint, radius, range, monster value, or asset was introduced or rewritten.
- One release creates one immutable snapshot. Warning, delayed resolution,
  target testing, diagnostics, and damage all retain its `release_id`.
- `_last_attack_footprint_snapshot` is recorded for the release before contact
  testing, so a released attack that misses remains diagnosable.
- Visible warning/core geometry, where present, is projected from the same
  snapshot that resolves damage.
- AI sensing, aggro, pursuit, target selection, and safe-zone selection are GU
  selection domains, not damage projections.

## Runtime attack inventory

| Runtime path | Relationship | Shared shape | Release geometry | Existing policy preserved |
|---|---|---|---|---|
| Ordinary immediate melee | `release_contact` | `circle` | attacker release footpoint; radius is existing centre reach minus the selected target radius; exact target-footprint intersection | one selected target; approved centre reach and damage unchanged |
| Delayed melee | `release_contact` | `circle` | attacker footpoint at delayed release; same contact projection | existing `0.25 GU` delayed tolerance remains; damage/range unchanged |
| Baked ranged monster release | `projectile_sweep` | `swept_capsule_path` | attacker release footpoint to selected target footpoint, path radius exactly `0 GU` | existing centre-range gate and one selected target; no fabricated width or asset |
| Fixed full-area attacker, IDs 180 and 195 | `ground_exact` | `circle` | attacker footpoint when the warning delay begins; existing `512 PX -> 16 GU` radius | every eligible target footprint intersecting the circle; values and target count unchanged |
| Boss circle special, active ID 124 | `ground_exact` | `circle` | boss footpoint when warning begins; existing `192 PX -> 6 GU` radius | warning and delayed damage use the same snapshot; existing all-target mode, status, cooldown, and damage unchanged |
| Boss cone profile form | `directed_core` | `sector_arc` | boss release footpoint, release-time ground direction, existing radius and half-angle | selected target footprint intersection; warning and delayed damage use the same snapshot |

### Baked ranged profiles

There is no independently emitted enemy projectile actor in the current
runtime. The following primary monster profiles use baked attack presentation
with formal long range and therefore resolve as `projectile_sweep`:

- flame Wooma, IDs 70/71, existing `155 PX` attack range;
- Zuma archers, IDs 150/151/152, existing `205 PX` attack range;
- skeleton archers, IDs 206/207, existing `205 PX` attack range;
- cow mages, IDs 220/221, existing `205 PX` attack range;
- cow priests, IDs 222/223, existing `175 PX` attack range;
- touch dragon ordinary attack, ID 124, existing long-range profile (its Boss
  special remains a separate `ground_exact` circle).

The runtime sweep is damage geometry only. The existing baked monster attack
animation remains presentation. Because no projectile collision width exists
in the primary runtime source, the sweep radius is zero rather than an invented
value. A future independently emitted monster projectile must carry its own
shared `swept_capsule_path` snapshot and sourced radius.

## Visual relationship audit

- Ordinary melee and baked ranged attacks have no explicit visible ground core.
  Body/weapon/projectile-like pixels embedded in an animation remain
  presentation and cannot add damage area.
- Fixed area IDs 180/195 currently have no explicit ground warning renderer.
  Their exact `ground_exact` snapshot still owns all target resolution.
- Boss circle and cone warnings are exact projections of the retained damage
  snapshot. Circle warning tessellation remains 48 segments and sector remains
  24 segments; these presentation details do not change GU boundaries.
- No active monster-owned directed rectangle attack was found. The active
  directed Boss form is a sector arc; no unsupported rectangle was fabricated.
- `_last_attack_footprint_snapshot` is deterministic diagnostic state. No new
  always-visible runtime debug overlay was added by this change.

## Non-spatial and cross-owner paths

| Path | Classification | Disposition |
|---|---|---|
| poison, control, or life-steal after a confirmed hit | `non_spatial` | consumes the confirmed attack; no second footprint |
| health-stage rage | `non_spatial` | numeric state transition |
| summon request | `non_spatial_spawn_request` | does not directly damage; runtime/map owns placement |
| surrounded relocation, burrow, or stone wake | `movement_or_state` | not an attack footprint |
| `monster_visual.gd` animation selection | `presentation_only` | cannot own damage geometry |
| companion attacks in `summon_actor.gd` | `cross_owner_professions_skills` | professions worktree owns them and must consume the shared contract |
| player/companion projectiles in `skill_projectile.gd` | `cross_owner_professions_skills` | professions worktree owns swept contact |

## Closed split paths

- Immediate and delayed melee now publish source-footpoint `release_contact`
  snapshots instead of relying only on a centre-distance damage gate.
- Baked ranged releases now publish a source-to-target `projectile_sweep`
  snapshot instead of being lumped into melee/target-only geometry.
- Fixed area activation and damage retain one warning-time `ground_exact`
  snapshot instead of rebuilding circles independently.
- Boss warning rendering and delayed damage retain the same immutable circle or
  sector snapshot and `release_id`.
- All area, Boss, melee, and ranged contact checks use target combat footprints,
  never target-centre-only checks or screen-space distance.

## Frozen data evidence

The following user-authored files are read-only inputs and must remain byte
identical:

- `assets/data/runtime/monster_ground_alignment_manual_v1.json`
  `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7`
- `assets/data/runtime/monster_ground_contacts.json`
  `AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597`
- `assets/data/runtime/monster_ground_contact_calibrations.json`
  `36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75`
