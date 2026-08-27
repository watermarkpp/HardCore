# DPV2-21CQ-X1 Phase 0 Current Dependency Audit

Status: `CURRENT_CHAIN_AUDITED / PRODUCTION_STILL_V1`

Baseline branch and HEAD:

```text
codex/integration
30316eb16117c7267e35bfb6eede53ec08ee4f28
```

## Current production chain

```text
external user workbook (not tracked)
  -> tools/import_canonical_monster_drop_excel.py
  -> assets/data/canonical_monster_drop_source_v2.json (217 / 9590)
  -> tools/build_canonical_monster_catalog.py
  -> assets/data/runtime/canonical_monster_catalog.json (156 / 7032)
  -> scripts/game_data.gd
  -> Item Tier + Monster Drop Role + global scale
  -> scripts/layers/runtime/loot_runtime_service.gd
  -> per-slot RNG
  -> post-RNG ground overflow selection (hard cap 9)
  -> scripts/game_root.gd::_on_enemy_died
```

The historical path `scripts/data/build_dpv2_baseline_v2.gd` does not exist in
this HEAD and is not a current generator or loader.

## Production dependencies

| Path | Current responsibility |
| --- | --- |
| `project.godot` | `LootRuntime` autoload |
| `scripts/game_data.gd` | loads and hash-binds all four DPV2 authorities; resolves item identity, Role/Tier probability and global scale |
| `scripts/layers/runtime/loot_runtime_service.gd` | loops every enabled source row, rolls RNG, then applies ground overflow |
| `scripts/game_root.gd` | calls `roll_monster_drops` on death and spawns selected item/gold rewards |
| `assets/data/drop/dpv2_item_tier_authority_v1.json` | 233 item denominators and the current runtime bridge to positive canonical item IDs |
| `assets/data/drop/dpv2_monster_role_authority_v1.json` | 131 enabled / 25 NON_LOOT plus Role factors |
| `assets/data/drop/dpv2_global_drop_rate_authority_v1.json` | active `global_drop_rate_scale`, currently `1x` |
| `assets/data/drop/dpv2_drop_runtime_authority_v1.json` | source hashes, fixed counts, overflow policies and 9-slot limit |

Current production probability is:

```text
min(1, role_factor * global_scale / tier_base_denominator)
```

The source row `chance/source_rate` is provenance only and is not used by the
production probability resolver.

## Generator dependencies

- `tools/import_canonical_monster_drop_excel.py`: deterministic external Excel
  to tracked logical source. Its required workbook is not in Git.
- `tools/build_canonical_monster_catalog.py`: reads the tracked source plus
  Tier, Role, global scale and `special_normal` binding; emits 156 profiles and
  7032 rows.
- `tools/activate_dpv2_drop_runtime.py`: reads catalog + Tier/Role/global and
  emits runtime overflow Authority plus `special_normal` hash bindings.
- `tools/monster_drop_authoring_overlay.py`: strict direct `1/N` authoring
  overlay; currently contains zero enabled rows.

Catalog generation and activation form a legacy fixed-point dependency:
catalog validation consumes generated `special_normal` hashes, while activation
recomputes its source-slot partition from the catalog.

## Test and audit dependencies

- `tests/dpv2_drop_runtime_policy_test.gd`
- `tests/monster_drop_p1a_runtime_contract_test.gd`
- `tests/monster_gold_drop_runtime_test.gd`
- `tests/monster_world_integration_test.gd`
- `tests/special_normal_spawn_authority_test.gd`
- `tools/monster_drop_p1a_runtime_export.gd`
- `tools/analyze_monster_drop_p1a.py`
- `tools/validate_dpv2_a07_*`
- `tools/run_dpv2_final_gate.ps1`

These gates currently freeze `7032 / 5995 / 1037 / 233 / 156 / 131 / 25` and
must be replaced by source-derived V2 totals before final cutover. The number
7032 is not a valid direct-source completeness target.

## Current runtime behavior worth preserving

- Every enabled resolved slot receives an independent RNG draw.
- Duplicate rows are not merged.
- The ground cap is applied only after all RNG draws.
- Gold quantity is represented separately from item identity.
- `drop_profile_id` is a stable monster-to-profile reference.

## Migration blockers and protected boundaries

1. The tracked input is a UTF-8 logical JSON reconstruction, not physical
   MonItems; source reports must say so explicitly.
2. Fifty-three project canonical item IDs are currently injected through the
   Tier table. V2 slots must carry a validated `canonical_item_id` before Tier
   can be removed.
3. The current 25 NON_LOOT decisions disable 1037 rows and must become explicit
   monster mapping decisions; they cannot be inferred from class or file state.
4. `special_normal` spawn classification/respawn/placement must survive, while
   its Tier/Role drop binding must later be removed.
5. Current overflow selection sorts by numeric priority only;
   `protected_drop` is telemetry, not the primary selection key.
6. Gold requires an explicit reward-kind branch in the V2 schema.
7. Current DPV2 hash/manifest information is distributed between runtime
   Authority, catalog sources, `special_normal`, and A0.7 validators; there is
   no single direct-baseline manifest.
8. `assets/data/source_priority_policy.json` has no dedicated monster-drop
   probability lane. A V2-only lane must not change attribute, AI, respawn,
   map or placement source priority.

Phase 0 makes no Production Runtime, catalog, Tier/Role, map, monster, equipment
or probability change.
