# HardCore Project Structure

Generated from HEAD: `7e3d5fde42e5aeedf422a5eb1d54905e12649ec0`
Branch: `codex/integration`
Generated: 2026-08-08
Purpose: directory responsibilities + core source file map.

## 一级目录

| 目录 | 职责 | 类别 | 是否允许直接修改 |
| --- | --- | --- | --- |
| `scripts/` | 生产 GDScript | production | 按子系统/合同 |
| `tests/` | Godot 测试（.gd/.tscn + helpers/fixtures） | test | 按任务 |
| `tools/` | Runner/注册/构建脚本（PowerShell） | tool | 仅任务授权（Runner 冻结） |
| `assets/` | 数据（runtime/vanilla/art/ui） | production/ref/art | 按数据分级 |
| `scenes/` | Godot 场景（main/character_select 等） | production | 按任务 |
| `artifacts/` | 施工证据（construction_evidence） | evidence | 只读归档（gitignore） |
| `outputs/` | 日志/临时产物 | tool | 可写（gitignore） |
| `docs/` | 设计/审计/快照文档 | doc | 按任务 |
| `map_editor_workspace/` | MSE 编辑器工作区（editor.json/ground） | editor | MSE 工具 |
| `reports/` | 数据审计报告 | doc | 只读参考 |
| `dev_art_sources/` | 原始素材（本地共享，不入 git） | ref | 只读输入 |

不存在 `addons/` 目录。

## scripts 子目录

- `scripts/skills/`：技能运行时/计划/快照/几何（skill_runtime_router、skill_execution_plan_contract、skill_footprint_snapshot、combat_*）
- `scripts/map_editor/`：MSE（app、build/publish service、runtime map service、codec、coordinate、portal 等）
- `scripts/layers/runtime/`：运行时桥接层（map_editor_runtime_bridge、world_content_service、runtime_service_facade、combat_runtime_service）
- `scripts/layers/presentation/`：展示层（gothic_bich_camp_builder 等）
- `scripts/map_assets/`：地图资源目录服务

## 核心源码文件表

| 文件 | Subsystem | 职责 | 正式入口/消费者 | 状态 |
| --- | --- | --- | --- | --- |
| `scripts/game_root.gd` | World | 世界生命周期/地图加载与 travel/玩家输入/技能编排/enemy 生成/safe logout | 主场景 main.tscn；`_load_zone`、`_request_map_travel`、`_spawn_enemy`、`_prepare_safe_logout` | CORE |
| `scripts/layers/runtime/map_editor_runtime_bridge.gd` | Map Runtime | registry 驱动正式可玩真值/readiness/投影上下文 | game_root、mapper | CORE |
| `scripts/map_coordinate_mapper.gd` | Coordinate | 正式投影 profile 解析（runtime absolute） | game_root、战斗实体 | CORE |
| `scripts/ground_unit_space.gd` | Coordinate | Ground GU/屏幕像素合同 + 投影 contract id | 全战斗层 | CORE |
| `scripts/skills/skill_runtime_router.gd` | Skill | Canonical Plan 唯一入口（build_canonical_plan） | caster_runtime、game_root | CORE |
| `scripts/skills/skill_execution_plan_contract.gd` | Skill | 计划合同/校验 | router | CORE |
| `scripts/caster_skill_runtime.gd` | Skill | 施法执行（canonical plan → result） | game_root | CORE |
| `scripts/skills/skill_footprint_snapshot.gd` | Snapshot | Schema V2 + STRICT_V2 校验 + 绝对上下文 | 全部战斗实体 | CORE |
| `scripts/runtime_combat_spatial_index.gd` | Spatial | map_id + 全局 Ground GU 桶 | enemy/projectile/ground/firewall | CORE |
| `scripts/skill_projectile.gd` | Projectile | 投射物（BroadPhase → Snapshot exact） | game_root `_spawn_projectile` | CORE |
| `scripts/persistent_ground_effect_manager.gd` | GroundEffect | 持续地面效果调度（共享 SpatialIndex） | game_root | CORE |
| `scripts/ground_effect.gd` | GroundEffect | GroundSkillEffect 节点 | manager | CORE |
| `scripts/fire_wall_field_controller.gd` | FireWall | 火墙伤害归属（VisualCell 纯视觉） | game_root `_spawn_canonical_ground_field` | CORE |
| `scripts/ground_skill_visual_cell.gd` | FireWall | 纯视觉单元 | controller | SUPPORT |
| `scripts/enemy.gd` | Enemy | EnemyActor（runtime_map_id + 投影回调注入） | game_root `_spawn_enemy` | CORE |
| `scripts/monster_visual.gd` | MonsterVisual | 怪物外观（客户端资源 profile） | enemy | CORE |
| `scripts/monster_visual_streaming_coordinator.gd` | MonsterVisual | 全局 streaming poll（prefetch/apply） | game_root/enemy | CORE |
| `scripts/player.gd` | Player | PlayerCharacter（request_skill） | game_root | CORE |
| `scripts/player_visual.gd` | PlayerVisual | actor composite z=0 平面 | player | CORE |
| `scripts/player_state.gd` | Save | 存档/角色 roster/safe logout 写盘 | game_root/UI | CORE |
| `scripts/hud.gd` | UI | GameHUD（lazy panels + touch scroll） | game_root | CORE |
| `scripts/inventory_panel.gd` | UI | 背包（InventoryScroll lazy） | hud | CORE |
| `scripts/skill_panel.gd` | UI | 技能面板（AssignmentHint autowrap） | hud | CORE |
| `scripts/equipment_rules.gd` | Equipment | 装备规则/视觉排序合同 | 装备层 | CORE |
| `scripts/region_content.gd` | Map Data | RegionContent（reference/规划数据） | 参考/UI | REFERENCE_DATA |
| `scripts/layers/runtime/world_content_service.gd` | Map Data | WorldContent autoload（reference 数据） | 参考 | REFERENCE_DATA |
| `scripts/map_editor/map_editor_build_runtime_service.gd` | Map Editor | Build Candidate + Publish Release（事务） | MSE App | CORE |
| `scripts/map_editor/map_editor_runtime_map_service.gd` | Map Editor | runtime load/validate/checksum | bridge/publish | CORE |
| `scripts/map_editor/map_editor_app.gd` | Map Editor | MSE UI（Build/Publish 两步） | 编辑器 | TOOL |
| `tools/run_godot_tests.ps1` | Testing | headless Runner（23 suites） | 开发 | TOOL |
| `tools/tests/test_suite_registration.ps1` | Testing | 套件注册检查 | 开发 | TOOL |

## GameRoot 特殊处理（勿因大而拆分）

GameRoot 职责区与关键函数：

- World lifecycle：`_ready`(272)、`_begin_initial_world_bootstrap`(961)、`_check_world_ready_contract`(1228)
- Map load/travel：`_load_zone`(1460)、`travel_to_map`(803)、`_request_map_travel`(807)、`_begin_map_transition`(1018)、`_run_map_transition`(1034)
- Player input / skill orchestration：`_on_player_skill`(297 连接)、`_resolve_projection_profile_for_map`(6268)
- Enemy/runtime 生成：`_spawn_enemy`(1920)、`_spawn_projectile`(6479)、`_spawn_canonical_ground_effect`(5846)、`_spawn_canonical_ground_field`(5749)
- Safe logout：`_prepare_safe_logout`(576)、`_record_player_world_location`(6195)

> 不要因为 GameRoot 大就默认拆分。

## assets 数据真值分类

- 正式 runtime 数据：`assets/data/runtime/map_editor/`（`<key>.runtime.json` + `map_runtime_release_registry.json`）
- 正式地图权威：**仅** `assets/data/runtime/map_editor/map_runtime_release_registry.json`（`release_state == implemented_playable` 才可玩）
- 参考/规划数据（≠ 可玩权威）：`assets/data/vanilla_176/`（map_content/maps 等）、`scripts/region_content.gd`、`scripts/layers/runtime/world_content_service.gd`（WorldContent/RegionContent）
- 美术资源：`assets/art/`（maps/monsters/items/characters/ui）
- 数据分级总表：`assets/data/source_priority_policy.json`（来源优先级 lane）

> WorldContent / RegionContent / maps.json ≠ formal map playable authority。
