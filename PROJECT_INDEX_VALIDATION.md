# PROJECT_INDEX Validation

Generated from HEAD: `7e3d5fde42e5aeedf422a5eb1d54905e12649ec0`
Branch: `codex/integration`
Generated: 2026-08-08
Purpose: accuracy self-check of the navigation docs.

## Checks

| check | result |
| --- | --- |
| 文档引用文件路径存在 | PASS |
| 文档引用函数存在 | PASS |
| Registry 路径存在 | PASS |
| Critical 套件名称存在（23 ValidateSet） | PASS |
| 不存在已删除的 Legacy Skill API（`SkillRuntimeRouter.execute`/`CasterSkillRuntime.resolve`） | PASS |
| 不存在旧 MAP_CONFIG 作为正式 Authority（scripts 中 0 处） | PASS |

## 逐项证据

- 文件存在性：对 PROJECT_STRUCTURE.md 核心文件表逐一 `Test-Path`，全部存在（`game_root.gd`、`hud.gd`、`enemy.gd`、`skill_projectile.gd`、`persistent_ground_effect_manager.gd`、`ground_effect.gd`、`fire_wall_field_controller.gd`、`ground_skill_visual_cell.gd`、`monster_visual.gd`、`monster_visual_streaming_coordinator.gd`、`map_coordinate_mapper.gd`、`player.gd`、`player_visual.gd`、`player_state.gd`、`inventory_panel.gd`、`skill_panel.gd`、`equipment_rules.gd`、`region_content.gd`、`runtime_combat_spatial_index.gd`、`map_editor_runtime_bridge.gd`、`map_editor_build_runtime_service.gd`、`map_editor_runtime_map_service.gd`、`map_editor_app.gd`、`world_content_service.gd`、`skills/skill_runtime_router.gd`、`skills/skill_execution_plan_contract.gd`、`skills/skill_footprint_snapshot.gd`、`caster_skill_runtime.gd`）。
- 函数存在性：`game_root._load_zone/_request_map_travel/_spawn_enemy/_spawn_projectile/_spawn_canonical_ground_effect/_spawn_canonical_ground_field/_prepare_safe_logout/_record_player_world_location`、`player.request_skill`、`skill_runtime_router.build_canonical_plan`、`skill_footprint_snapshot.validate_for_consumer/make_absolute_runtime_context`、`monster_visual_streaming_coordinator.begin_map_prefetch/poll_once`、`map_editor_build_runtime_service.build_candidate/publish_runtime_release`、`player_state.save_game/save_safe_logout`、`map_editor_app._on_build_candidate_pressed/_on_publish_runtime_pressed`——均已用 `rg` 核对行号存在。
- Registry：`assets/data/runtime/map_editor/map_runtime_release_registry.json` 存在，含 11 张 `implemented_playable`。
- 套件：`tools/run_godot_tests.ps1` ValidateSet 23 项（critical, warrior, bich, equipment, monster, snapshot_coordinate_critical, snapshot_production_critical, projectile_spatial_critical, safe_logout_critical, persistent_ground_effect_critical, fire_wall_controller_critical, monster_streaming_critical, skill_execution_plan_critical, skill_production_migration_critical, skill_runtime_cleanup_critical, wizard_line_geometry_critical, combat_absolute_ground_critical, combat_projection_fail_closed_critical, formal_map_projection_critical, map_runtime_release_critical, map_runtime_release_transaction_critical, player_visual_contract_critical, skill_panel_layout_critical）。
- Legacy Skill API：`rg "SkillRuntimeRouter.execute\(|CasterSkillRuntime.resolve\(" scripts` 无结果；critical 中 `skill_runtime_no_legacy_api_test` PASS。
- MAP_CONFIG：`rg "MAP_CONFIG" scripts` 无结果。

## 结果

**PASS**（broken file references = 0；broken function references = 0；stale contract references = 0）
