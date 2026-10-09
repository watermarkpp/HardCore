# B02 geometry / metadata trace

**Review scope.** Static review only. No production or test edits and no engine run. The question is whether a zero-cell/zero-coordinate target is a formally reachable attack point, and whether the geometry relationship metadata still matches the authoritative source and runtime consumers. A synthetic `runtime_map_id < 0`, identity projection, arbitrary `(0, 0)` node, or hand-built target dictionary is not treated as a production reachability proof.

## B02-009 — zero-cell target and formal map reachability

### Concrete source seam

`SkillGeometryService.cells()` at `scripts/skills/skill_geometry_service.gd:35-40` uses `Vector2i.ZERO` as both a valid cell and the “target cell not supplied” sentinel:

```gdscript
var center := target_tile if target_tile != Vector2i.ZERO else origin
```

The canonical router passes the same ambiguous default at `scripts/skills/skill_runtime_router.gd:124-129`; the production release path repeats it at `scripts/game_root.gd:9332-9344`. Therefore an explicit target cell `(0, 0)` is indistinguishable from an omitted target cell and falls back to `origin`. This is a real metadata/API ambiguity for any target-centered area whose selected cell is formally `(0,0)`. It is not evidence that the game currently reaches that coordinate during ordinary play.

The correct current production projection path is map-bound. `GameRoot._resolve_projection_profile_for_map()` at `scripts/game_root.gd:12589-12627` selects the formal runtime profile only when the map is runtime-built. `MapCoordinateMapper.resolve_formal_runtime_projection_profile()` at `scripts/map_coordinate_mapper.gd:34-105` rejects reference-only maps and returns the explicit runtime map projection; `GameRoot._try_canonical_screen_px_to_ground_gu()` and its inverse at `scripts/game_root.gd:12630-12712` additionally fail closed on missing/invalid projection. A finite projection result is only a coordinate conversion; it does not establish that the point is walkable, inside the authored map, safe for an actor footprint, or eligible for an attack.

Formal playability is itself gated by `MapEditorRuntimeBridge.has_runtime_map()` / `is_formal_playable()` (`scripts/layers/runtime/map_editor_runtime_bridge.gd:258-301`). Runtime map loading (`370-383`) and the runtime collision/ground data are the authority for map reachability. The current source does not contain a static contract proving that ground cell `(0,0)` is playable in every formal map, and the projection mapper intentionally does not answer that question. The B02 zero-coordinate concern is therefore:

- **Source-proven ambiguity:** explicit zero target cell can be treated as “not supplied”.
- **Current production trigger:** **NOT_PROVEN**. No fixed-source runtime evidence shows an actual formal playable map/actor/target whose selected attack cell is exactly `(0,0)` and whose origin differs.
- **Do not classify as:** “map `(0,0)` is attackable” or “map `(0,0)` is blocked”. Both require an actual runtime map, authored ground/collision profile, actor footprint and formal release path.

A safe future contract would carry `has_target_tile` separately from `target_tile`, or use a nullable/typed option, and then validate the selected cell through the existing runtime ground/collision and release snapshot contracts. It must not special-case zero as globally reachable or globally invalid.

### Consumers and affected behavior

`SkillGeometryService.cells()` is called by `SkillRuntimeRouter` for plan metadata and by GameRoot’s exact ground release preparation. The exact snapshot then flows through `CasterSpellGeometryScript.effective_cells()` and the canonical release snapshot. The ambiguity is relevant to target-centered `ground_exact` skills, especially `wizard.exploding_flame`, `wizard.ice_storm`, `wizard.fire_wall`, Taoist 3x3 support areas, and `taoist.entrapment`; it does not change target-footprint skills unless they are incorrectly supplied a target tile. The current formal target selection and terrain gates remain the authoritative filters.

## B02-010 — relationship-matrix / runtime metadata drift

There is a concrete drift for `wizard.fire_wall`:

| layer | current declaration |
|---|---|
| authoritative SOT `assets/data/vanilla_176/skills_source_of_truth_v1.json` | `geometry.shape = square`, `width_tiles = 3`, `height_tiles = 3`; the `conflict_note` states the 2026-09-13 user request overrides the previous 2x2 project geometry |
| legacy-to-formal adapter `scripts/skills/combat_unit_legacy_adapter.gd:194-207` | maps `width_tiles`/`height_tiles` to `width_grid_steps`/`height_grid_steps` |
| runtime producer `scripts/skills/runtimes/wizard_skill_runtime.gd:62-78` | defaults the field to width/height `3` and carries the SOT stacking/cap metadata |
| GameRoot field owner `scripts/game_root.gd:10903-10998` | builds the canonical field from the release cells and documents/instantiates 9 cells for the 3x3 footprint |
| existing relationship matrix `scripts/skills/skill_spatial_projection_contract.gd:124-128` | still says `source_geometry_frozen_2_by_2_exact_cell_union` |
| prose matrix `docs/combat/spatial_projection_relationship_matrix.md` | still says Fire Wall is a frozen 2x2 ground union |

The runtime producer and formal SOT are aligned at 3x3. The matrix code/prose is stale metadata and must not be used to reduce the production footprint. Existing 3x3 snapshot/field consumers and tests are consistent with the SOT/runtime path; this review does not rewrite them.

Other values must keep their units separate:

- The SOT and runtime adapter use `width_tiles`/`height_tiles` converted to discrete grid steps. The current 3x3 area values are three grid steps per axis, not a claim of three continuous GU.
- The matrix’s `taoist.magic_defense` / `taoist.defense` entries describe radius **3 grid steps**; this is a discrete area contract.
- The matrix’s summon entries describe nearest valid spawn within **2 grid steps**. That is not interchangeable with 2 continuous GU and is filtered by the actual spawn footprint/runtime collision path.
- Continuous GU values are separately declared for line skills such as Hellfire (5 GU × 1 GU) and Laser (8 GU × 1 GU), and ordinary player melee is 1.5 GU in the matrix. Those values must not be inferred from the 3x3/2-grid-step metadata.

The matrix itself is consumed as a classification contract by `SkillSpatialProjectionContract.ENTRIES` and related validators, while actual cell generation is consumed through `SkillGeometryService`, `CasterSpellGeometry`, the runtime skill producers, and GameRoot’s canonical plan. That makes the Fire Wall 2x2 entry a documentation/contract drift risk even though the current producer is 3x3: a future validator or reviewer could incorrectly reject or shrink the correct SOT footprint. The minimal disposition is to update the matrix source through the normal authoring/contract review, with a source hash and regression against the existing 9-cell canonical release; this review does not perform that edit.

## Source fingerprints reviewed

| file | SHA256 |
|---|---|
| `scripts/skills/skill_geometry_service.gd` | `D6FA941D425798978876F9FFC77A5F2A5FE56890D97D11ECE6EE72F13DE3FB8F` |
| `scripts/skills/skill_spatial_projection_contract.gd` | `3640A9F16C753D578BC8958303CFFE08C90F28440CED4F1938948932024533FB` |
| `scripts/skills/runtimes/wizard_skill_runtime.gd` | `07196A335CACF5EC9112446E517ED05A1FBC3A12F2FF5A6F41D5816A712259FE` |
| `scripts/map_coordinate_mapper.gd` | `69F061A030F3C279D5B40AC3BBE3D025A2B565CFC8D94FF7FA5587C59D36847D` |
| `scripts/layers/runtime/map_editor_runtime_bridge.gd` | `6322AAF98410F7578FCD7DD59B33C20FF34CC17A77463EDC20A4115B31784EF5` |
| `docs/combat/spatial_projection_relationship_matrix.md` | `7C7E04869CA65214BF7DB5B576FF5D5AED9E88E81B9911476B9686296D3C1520` |
| `assets/data/vanilla_176/skills_source_of_truth_v1.json` | `7575C45A7BD147F8E60D2EFDB15C6C5E9781445DDC2F748E73DD69ED386A62AB` |

All fingerprints above were measured from the current frozen working-tree bytes at report creation.

## Disposition and validation boundary

- B02-009: `CONDITIONAL_SOURCE_RISK_NOT_PROVEN`; the zero-cell sentinel ambiguity is source-proven, but formal `(0,0)` attack reachability is `NOT_RUN` and not established by synthetic coordinates.
- B02-010: `SOURCE_METADATA_DRIFT_CONFIRMED`; Fire Wall matrix metadata is 2x2 while current SOT/runtime production is 3x3. This is not a production behavior change by itself.
- No native result, formal map-coordinate reachability result, or device result is claimed.
