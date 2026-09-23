# HardCore Project Index

Generated from HEAD: `7e3d5fde42e5aeedf422a5eb1d54905e12649ec0`
Branch: `codex/integration`
Generated: 2026-08-08
Purpose: subsystem/path navigation for model handoff. Read it after current status and historical decisions.

2026-09-23 公共 CPU 优化导航：`docs/repair_v93/CPU_CROWD_REPAIR.md` 记录查询链根因、42 次基线对照、67 图 53,400 次差分和 18 种怪物动画/贴图审查；`DELIVERY.md` 记录合入主树与远端身份。本轮仅交付源码，用户要求暂不打包；贴图、人工数据和版本配置未动。

2026-09-22 v92 导航：`docs/repair_v92/USER_REQUEST_RECONCILIATION.md` 是全部累计要求，`CONTROLLER_REVIEW.md` 是主控对历史候选的逐项裁决；`PERFORMANCE_AND_SKILL_CLOSURE.md`、`UI_AND_SYSTEM_CLOSURE.md`、`LOOT_CLEANUP.md` 和 `evidence/loot_workbook_armor_single_slot_20260922.md` 提供专项证据。当前施工/回归/构建状态先看 `PROJECT_CURRENT_STATUS.md` 顶部，不能使用下列历史 SHA 代替当前 Git。

Current navigation context verified against HEAD: `ec057c52de4c99f59aa31a96dbd790e1fa8c6a7c`

2026-09-22 20:39性能追加：`docs/repair_v92/MONSTER_DENSITY_INVESTIGATION.md` 对应最新“小地图高密度”反馈；`RENDER_CONTROL_TEST.md` 对应独立渲染A/B、正式空安全区入口CPU修复与原生退出故障。两项不得以headless PASS替代手机性能验收。

2026-09-22 21:32追加：`docs/repair_v92/IDLE_MONSTER_CPU_REPAIR.md` 记录闲置范围优先和0.5秒唤醒策略、11项回归及6次采样；密度调查文档新增四次真实移动CPU探针。`NATIVE_EXIT_INVESTIGATION.md` 保存独立退出故障的本机转储定位与上游候选，未关闭风险不隐藏。

2026-09-05 审计升级导航：`docs/AUDIT_UPGRADE_20260905.md` 为完整施工及限制记录，`docs/audits/20260905/MILESTONE_APK.md` 为固定 `52ae0565` 构建与待设备安装交付，`docs/audits/20260905/evidence/` 为已入库验收证据。当前状态优先读取 `PROJECT_CURRENT_STATUS.md` 顶部的新日期章节，不把以下历史导航 SHA 当作当前 HEAD。

## Required Context Order

2026-09-14 v81导航：`docs/loot_ui_20260914/DELIVERY.md`为APK与验收，`IMPLEMENTATION.md`为最终最长行居中规则、已批准设置、Buff与地面名称生产链，`evidence/`保留31场景索引、固定源码4项复验及包内对比。源码锚点`4f4462ad027714acf657c7a2ac28fa4f15a6e293`；设备与既存性能债务单列。

2026-09-06 玩法与音频升级记录：`docs/UPGRADE_20260906.md`；精确音频来源与接线：`docs/audio/20260906/AUDIO_HANDOFF.md`、`SFX_CALLPOINTS.md`；战士范围合同：`docs/combat/warrior_melee_overrides_20260906.md`。安装包与最终验收状态以升级记录为准，不以施工期 PASS 代替最终交付。

1. `PROJECT_CURRENT_STATUS.md` — 当前阶段、已关闭 Gate、HOLD 与下一正式 Gate。
2. `PROJECT_HISTORY_CONTEXT.md` — 历史整改、已裁决方案、被否决路线与 Accepted Debt。
3. `PROJECT_INDEX.md` — 当前代码位置、文件职责与 subsystem 入口。
4. `PROJECT_CORE_CONTRACTS.md` — 仅在涉及 Frozen 核心合同时追加读取。

在上述导航足以定位目标时，禁止默认扫描全仓；先按本索引进入目标 subsystem，再用精确 symbol/caller/callee 搜索扩展调用链。

## Quick Start

- 项目路径：`C:\Users\Administrator\Documents\HardCore`（Godot 4.7 项目）
- Godot 启动入口：`res://scenes/startup_loading.tscn` → `scenes/character_select.tscn`；进入游戏后加载 `scenes/main.tscn`（game_root）。
- 测试 Runner：`tools\run_godot_tests.ps1`（headless，普通测试显式传 `-TimeoutSeconds 30`；不要把 runner 默认值当成 30 秒）
- 测试注册检查：`tools\tests\test_suite_registration.ps1`
- Python：`C:\Windows\py.exe -3.12`（禁止裸 `python`/`python3`）

```powershell
tools/agent_bootstrap.ps1 -Compact
tools/run_godot_tests.ps1 -Suite critical -TimeoutSeconds 30
tools/tests/test_suite_registration.ps1
```

## “要改什么，就先看什么”

| 任务 | 第一批必读文件 |
| --- | --- |
| 技能释放 | `scripts/game_root.gd`、`scripts/skills/skill_runtime_router.gd`、`scripts/skills/skill_execution_plan_contract.gd`、`scripts/caster_skill_runtime.gd` |
| Wizard Hellfire target-selection regression verification | `scripts/skills/runtimes/wizard_skill_runtime.gd`、`scripts/game_root.gd`（`_canonical_spell_geometry_targets`）、`scripts/skills/caster_spell_geometry.gd`、`assets/data/vanilla_176/skills_source_of_truth_v1.json`（`wizard.hellfire`） |
| Projectile | `scripts/skill_projectile.gd`、`scripts/runtime_combat_spatial_index.gd`、`scripts/skills/skill_footprint_snapshot.gd` |
| 地面持续效果 | `scripts/persistent_ground_effect_manager.gd`、`scripts/ground_effect.gd` |
| FireWall | `scripts/fire_wall_field_controller.gd`、`scripts/ground_skill_visual_cell.gd` |
| 全技能分层与目标上下文 | `scripts/skills/skill_runtime_classification.gd`、`scripts/skills/skill_runtime_router.gd`、`scripts/game_root.gd` |
| 火墙共同动画时钟 | `scripts/caster_skill_animation_batch.gd`、`scripts/caster_skill_animation_player.gd` |
| 宠物攻击与成长 | `scripts/summon_actor.gd`、`scripts/taoist_combat_math.gd`、`scripts/enemy.gd`（毒死亡归属） |
| 怪物资源 | `scripts/monster_visual.gd`、`scripts/monster_visual_streaming_coordinator.gd` |
| Enemy 移动/坐标 | `scripts/enemy.gd`、`scripts/map_coordinate_mapper.gd`、`scripts/runtime_combat_spatial_index.gd` |
| 地图加载 | `scripts/game_root.gd`、`scripts/layers/runtime/map_editor_runtime_bridge.gd` |
| 地图发布 | `scripts/map_editor/map_editor_build_runtime_service.gd`、`assets/data/runtime/map_editor/map_runtime_release_registry.json` |
| 墙体派生发布与绑定 | `scripts/map_editor/map_editor_wall_render_publish_service.gd`、`tools/map_editor/publish_wall_render_plans.gd`、`tools/verify_wall_render_bindings.ps1` |
| 地图编辑器 | `scripts/map_editor/`（MSE App 入口 `map_editor_app.gd`） |
| HUD | `scripts/hud.gd`（class GameHUD）及 `scripts/*_panel.gd` |
| Inventory | `scripts/inventory_panel.gd` |
| Skill Panel | `scripts/skill_panel.gd` |
| Player 视觉 | `scripts/player_visual.gd` |
| Save / Logout | `scripts/player_state.gd`、`scripts/game_root.gd`（`_prepare_safe_logout`、`_record_player_world_location`） |
| Test Runner | `tools/run_godot_tests.ps1` |

## Core Entry Points

- Game boot → `scripts/game_root.gd` → `_ready()`（272）
- World load → `scripts/game_root.gd` → `_load_zone()`（1460）/ `_begin_initial_world_bootstrap()`（961）
- Map travel → `scripts/game_root.gd` → `_request_map_travel()`（807）/ `_begin_map_transition()`（1018）/ `_run_map_transition()`（1034）
- Player skill cast → `scripts/player.gd` → `request_skill()`（325）→ signal `skill_requested` → game_root `_on_player_skill`
- Enemy spawn → `scripts/game_root.gd` → `_spawn_enemy()`（1920）
- Projectile spawn → `scripts/game_root.gd` → `_spawn_projectile()`（6479）
- Ground effect spawn → `scripts/game_root.gd` → `_spawn_canonical_ground_effect()`（5846）
- FireWall spawn → `scripts/game_root.gd` → `_spawn_canonical_ground_field()`（5749）
- Monster streaming → `scripts/monster_visual_streaming_coordinator.gd` → `begin_map_prefetch()`（386）/ `poll_once()`（177）
- Save → `scripts/player_state.gd` → `save_game()`（1039）
- Safe logout → `scripts/game_root.gd` → `_prepare_safe_logout()`（576）+ `scripts/player_state.gd` → `save_safe_logout()`（1365）
- Map Build（候选）→ `scripts/map_editor/map_editor_build_runtime_service.gd` → `build_candidate()`（376）
- Map Publish → 同上 → `publish_runtime_release()`（58）

## Subsystem Map

- World → owner `game_root.gd`；输入 Player/input，输出 zone/actors/READY
- Map Runtime → `map_editor_runtime_bridge.gd`（读取 registry，正式可玩真值）
- Map Editor → `scripts/map_editor/`（MSE App + build/publish service）
- Player → `player.gd`（PlayerCharacter）、`player_visual.gd`
- Skill Runtime → `skills/skill_runtime_router.gd` + `skill_execution_plan_contract.gd` + `caster_skill_runtime.gd`
- Combat Geometry → `skills/combat_*`、`ground_unit_space.gd`
- Projectile → `skill_projectile.gd` + SpatialIndex
- Ground Effect → `persistent_ground_effect_manager.gd` + `ground_effect.gd`
- FireWall → `fire_wall_field_controller.gd` + `ground_skill_visual_cell.gd`
- Enemy → `enemy.gd`（EnemyActor）
- Monster Visual → `monster_visual.gd` + `monster_visual_streaming_coordinator.gd`
- Equipment → `scripts/equipment_rules.gd`、`scripts/equipment_character_preview.gd`
- UI → `hud.gd` + `*_panel.gd`
- Save → `player_state.gd`
- Testing → `tools/run_godot_tests.ps1`、`tools/tests/test_suite_registration.ps1`、`tests/`

## “不要从哪里开始”

- 不要为技能问题先扫描整个 game_root。
- 不要因地图问题扫描全部 assets。
- 不要扫描几千张 PNG。
- 不要重新设计已冻结系统（坐标/Snapshot/地图发布权/actor 视觉平面）。

流程：先 PROJECT_INDEX → `rg` 精确定位 → 只打开相关文件。

## Standard Workflow（Sol）

When receiving a task:

1. Read `PROJECT_CURRENT_STATUS.md`
2. Read the relevant section of `PROJECT_INDEX.md`
3. Read `PROJECT_CORE_CONTRACTS.md` if core behavior is involved
4. Open only the listed subsystem files
5. Use `rg` for additional callers
6. Do not start with repository-wide scans

- v92 最终回归、性能局限及交付身份：`docs/repair_v92/FINAL_VERIFICATION.md`。

- v92 三职业成长与负重：`docs/repair_v92/CHARACTER_GROWTH_REVIEW.md`、`tests/player_growth_live_runtime_test.gd`、`tools/audit_character_growth_v92.py`。
- v92 手机采样/交付：`docs/repair_v92/APK_HANDOFF.md`、`scripts/device_lab_runtime.gd`、`tools/collect_android_performance.ps1`；包内验证 `tools/verify_v92_apk_payload.py`，精确包身份与日志 `docs/repair_v92/evidence/apk_v92/manifest.json`。
