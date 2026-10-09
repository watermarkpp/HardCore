# Full project audit v109 scope

This is a static scope manifest for `full_project_audit_v109_20261009`. It is not an acceptance result and does not bind the final source SHA.

## Binding and inventory

The fixed-commit membership check uses `git -c core.quotePath=false ls-tree`, retaining real Unicode path names. The first check incorrectly treated Git's quoted Chinese filenames as missing; that scope error is corrected. Each entry records membership in parent61d and fixed B01, distinct from current working-tree status. The formal `map_editor_workspace/` is included. Null inventory records are removed.

B01 fixed source is `dbd78d3301c2af6cfd9e070abe8cc847e6353175`, which contains all six followup fixtures and the ten Chinese compiler/skill-authoring files. CSV 05/06 are evidence-only; CSV01/02/03/04/07 have formal compiler consumers. Raw-byte binding of these existing inputs is recorded without regeneration. The two Android environment/preflight files are still only local and are being preserved in a subsequent commit. The remaining 26 local paths are two grid services and 24 retired fixtures; their remote coverage remains NOT_RUN. No grid trial is restored. Later batches use the subsequently supplied commit, while B01 retains its own exact baseline.

Extension followup: the custom `tools/android_java_loopback_probe.java` was not in the initial text-extension inventory. It is called by the helper and is included in the source-preservation overlay and binding. There are 6169 inventory paths: 6141 present in B01, two Android files in the preservation overlay, and 26 retired trial paths retained locally. C++, C#, Kotlin, Gradle and shell extensions were also checked under the workspace exclusions; no additional custom source was found. Third-party SDK/vendor payload remains excluded.

The current checkout reports historical HEAD `215f0b2f651a51e6855ee813ddd99221690311a1`; that value is retained only as an observation. The approved production overlay is bound to B01 SHA `dbd78d3301c2af6cfd9e070abe8cc847e6353175`. A subsequent source-preservation commit includes the two unchanged Android source files and these scope corrections; its exact SHA is recorded in the dispatch/source receipt after creation. The manifest records each included reviewable text file with module assignment, existence, and observed Git presence; current Git presence is not a fixed-61d claim.

Included inventory: 374 scripts/scenes, 1522 reviewable text files under scripts/scenes/assets/tools, 3279 tests, and 117 residual-review files. `map_editor_workspace/` is included as formal authoring input. Missing `build/` and `config/` roots are recorded explicitly as `MISSING_ROOT_PATH`.

## Module coverage
- **bootstrap_runtime** — 3 files; roots: project.godot, export_presets.cfg, scenes/main.tscn, scripts/game_root.gd, scripts/game_data.gd. Entrypoints and audit edges are listed in the manifest.
- **enemy_ai_combat** — 35 files; roots: scripts/enemy.gd, scripts/monster_ai_package/, scripts/monster_source176/, assets/data/monster_*.json. Entrypoints and audit edges are listed in the manifest.
- **spatial_geometry_movement** — 3 files; roots: scripts/runtime_combat_spatial_index.gd, scripts/world_spatial_rules.gd, scripts/ground_unit_space.gd, scripts/monster_source176/source_melee_geometry.gd, scripts/monster_source176/source_step_plan.gd. Entrypoints and audit edges are listed in the manifest.
- **damage_status_control** — 6 files; roots: scripts/features/runtime/damage_batch.gd, scripts/features/runtime/effect_runtime.gd, scripts/damage_ledger_observer.gd, scripts/actor_body_policy.gd, scripts/entrapment_boundary_controller.gd. Entrypoints and audit edges are listed in the manifest.
- **skills_magic_area** — 44 files; roots: scripts/caster_skill_runtime.gd, scripts/caster_skill_behavior.gd, scripts/caster_skill_visual_effect.gd, scripts/fire_wall_field_controller.gd, scripts/aoe_engagement_window.gd, scripts/skills/. Entrypoints and audit edges are listed in the manifest.
- **summon_pet_targeting** — 2 files; roots: scripts/summon_actor.gd, scripts/summon_visual_registry.gd, scripts/canonical_summon_integration.gd. Entrypoints and audit edges are listed in the manifest.
- **death_revival_drops** — 115 files; roots: scripts/game_root.gd, scripts/layers/runtime/loot_runtime_service.gd, scripts/features/handlers/death_burst_handler.gd, scripts/drop/, assets/data/drop*, assets/data/monster_drop*. Entrypoints and audit edges are listed in the manifest.
- **equipment_inventory_identity** — 61 files; roots: scripts/identity/, scripts/items/, scripts/equipment_*.gd, scripts/inventory_panel.gd, assets/data/equipment*, assets/data/item*. Entrypoints and audit edges are listed in the manifest.
- **maps_environment_streaming** — 1393 files; roots: assets/maps/, scripts/map_*.gd, scripts/layers/runtime/authored_map_loader.gd, scripts/environment_catalog.gd, assets/data/map*. Entrypoints and audit edges are listed in the manifest.
- **audio_presentation_ui** — 154 files; roots: scripts/audio_*.gd, scripts/*visual*.gd, scripts/hud.gd, scripts/*panel.gd, scripts/features/presentation/, assets/data/audio/, assets/ui/. Entrypoints and audit edges are listed in the manifest.
- **save_input_platform** — 3 files; roots: scripts/player.gd, scripts/save*.gd, scripts/device_lab*.gd, scripts/input*.gd, project.godot, export_presets.cfg. Entrypoints and audit edges are listed in the manifest.
- **authoring_generation_build** — 489 files; roots: tools/build_*.py, tools/build_*.ps1, tools/generate_build_info.ps1, scripts/features/generated/, assets/data/generated/, tools/*catalog*, tools/*authority*. Entrypoints and audit edges are listed in the manifest.
- **diagnostics_budget_observability** — 7 files; roots: scripts/runtime_diagnostics.gd, scripts/layers/runtime/execution/frame_budget.gd, scripts/layers/runtime/combat_diagnostic_log.gd, scripts/layers/runtime/skill_footprint_diagnostic_log.gd. Entrypoints and audit edges are listed in the manifest.
- **verification_and_tests** — 3279 files; roots: tests/, tools/run_godot_tests.ps1, tools/audit_*.py, tools/verify_*.py. Entrypoints and audit edges are listed in the manifest.
- **player_actor_state** — 9 files; roots: scripts/player.gd, scripts/player_state.gd, scripts/character_select.gd. Entrypoints and audit edges are listed in the manifest.
- **source176_skill_packages** — 7 files; roots: scripts/monster_source176/. Entrypoints and audit edges are listed in the manifest.
- **resource_streaming** — 1 files; roots: scripts/layers/runtime/resource*, scripts/*stream*. Entrypoints and audit edges are listed in the manifest.
- **data_authoring_identity** — 433 files; roots: assets/data/. Entrypoints and audit edges are listed in the manifest.
- **presentation_scene_assets** — 7 files; roots: scenes/, assets/shaders/. Entrypoints and audit edges are listed in the manifest.
- **residual_review** — 117 files; roots: explicit file_inventory residual paths. Entrypoints and audit edges are listed in the manifest.

## Included and excluded boundaries

Included: production `scripts/`, `scenes/`, `project.godot`, `export_presets.cfg`, authoring and generated data, map sources and `map_editor_workspace`, identity/drop/equipment/audio/UI/input/save/combat/AI/status/summon/loot/resource-streaming code, build/authoring tools, and verification tests.

Excluded: `.godot/`, outputs and historical reports, artifacts, retired archives, third-party/vendor trees, SDK/downloads, `dev_art_sources`, import-server data, credentials, caches, binary-only art/raw-import material, `.import` sidecars, and tool payloads under `tools/android-build/` or `tools/godot-4.7/`. Generated text remains included, but corrections must trace to its authoring source.

## Acceptance boundary

This package is scope-only. It does not claim PASS, FAIL, native coverage, device coverage, or a performance result. The final package must bind source, engine, scene/input, invocation, receipt, and status for each relevant module. Use `PASS`, `FAIL`, `BLOCKED`, `NOT_RUN`, or `MISSING`; retain negative evidence and do not convert a missing path or residual-review file into coverage.
