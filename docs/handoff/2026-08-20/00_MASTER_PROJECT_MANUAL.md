# HardCore 全项目主说明书 — Sol Handoff 2026-08-20

> **版本**: 2026-08-20
> **作者**: DeepSeek (机械执行)
> **审核**: ChatGPT Sol (架构设计)
> **仓库**: `watermarkpp/HardCore` (GitHub)
> **引擎**: Godot 4.7 stable

---

## 0. 阅读顺序与 Authority

Sol 接手后的正确阅读顺序：

1. 本文件 `00_MASTER_PROJECT_MANUAL.md`（当前文档）
2. `handoff_manifest.json`（机器可读状态快照）
3. 旧 `SOL_HANDOFF.md`（仅作历史参考）
4. 各专业分支的 `README.md` 或文档

**Authority 层级**（从高到低）：

| 层级 | 名称 | 说明 |
|------|------|------|
| L1 | Golden Runtime | 已验收 APK + 对应源码，最高历史真值 |
| L2 | Accepted Post-Golden Work | Golden 后已验收并入专业分支的正式施工 |
| L3 | 专业分支 remote tip | `origin/codex/*` 分支最新 SHA，对应子系统最新正式源码 |
| L4 | 本地用户工作 | 地图 workspace、人工校准结果、未提交的地图编辑 |
| L5 | 生成数据 | 必须根据 generator 重建，禁止手改 |

---

## 1. Executive Summary

HardCore 是一个基于 Godot 4.7 的单机等距 ARPG（动作角色扮演游戏），核心参考《传奇 1.76 / Mir2》的多人在线游戏规则，重构为单机可玩版本。

**核心特征**：
- 固定 2:1 等距视角，64×32 像素 tile 格
- 8 方向角色、怪物、动画
- 战士/法师/道士 三职业
- 完整地图编辑器（Mafa Scene Editor）
- 完整地图素材生产管线（切割→校准→正式覆盖）
- 214 怪物、175 装备、142 地图

**当前状态**：地图素材系统已完成大规模人工校准（861+28 素材全部 verified），怪物系统已稳定，装备/技能/UI 处于稳定但待继续开发状态。

---

## 2. 项目目标与游戏形态

- **项目名**: HardCore
- **类型**: 单机等距 ARPG
- **引擎**: Godot 4.7 stable
- **核心参考**: 传奇 1.76 / Mir2
- **游戏形态**: 从多人规则重构为单机可玩版本
- **地图视角**: 固定 2:1 isometric
- **地图格**: 64 × 32 像素
- **角色方向**: 8 方向
- **包 ID**: `com.personal.mafaoffline`（兼容旧安装，品牌名为 HardCore）

Evidence:
- `project.godot` 中 config/name = "HardCore"
- `project.godot` 中 application/package/unique_name

---

## 3. Golden Runtime

Golden Runtime 是项目最高历史真值——已验收的正式 APK 及其对应源码。

| 项目 | 值 |
|------|----|
| Tag | `golden/apk-1.18.3-base-9d6435bc` |
| Golden APK | `hardcore-1.18.3-golden.apk` |
| 输出目录 | `outputs/hardcore/` |
| Hotfix 数量 | 0 |

Evidence:
- `git tag -l 'golden/*'`
- `outputs/hardcore/` 目录内容

---

## 4. Git / Branch / Worktree 架构

### 4.1 永久专业分支

| 分支 | Remote SHA | 最后提交日期 | 职责 |
|------|-----------|-------------|------|
| `main` | `7d36c678` | 2026-08-17 | 文档/发布中心 |
| `codex/integration` | `b7188497` | 2026-08-18 | 跨系统集成、merge、全局服务 |
| `codex/maps` | `edc4e51b` | 2026-08-20 | 地图、素材、编辑器、校准工具 |
| `codex/monsters` | `252d034a` | 2026-08-18 | 怪物数据、AI、动画、掉落 |
| `codex/equipment` | `ba8d4ff3` | 2026-08-18 | 装备属性、数据、美术 |
| `codex/professions-skills` | `162df988` | 2026-08-18 | 职业成长、技能、状态机 |
| `codex/ui-art` | `700e884d` | 2026-08-18 | UI、HUD、美术素材 |

### 4.2 活动 Worktree

| 路径 | 分支 | 状态 |
|------|------|------|
| `HardCore/` | `codex/integration` | CLEAN |
| `HardCore-worktrees/maps` | `codex/maps` | **DIRTY**（用户地图/override/校准数据） |
| `HardCore-worktrees/monsters` | `codex/monsters` | CLEAN |
| `HardCore-worktrees/equipment` | `codex/equipment` | CLEAN |
| `HardCore-worktrees/professions-skills` | `codex/professions-skills` | CLEAN |
| `HardCore-worktrees/ui-art` | `codex/ui-art` | CLEAN |

### 4.3 施工规范

- 所有施工在临时 worktree + 临时 branch 上完成
- 使用 clean landing 方式落入正式分支
- 禁止 force push
- 禁止直接修改 `map_editor_workspace/*`
- 用户地图成果优先保护

### 4.4 环境信息

- `tools/godot-4.7/Godot_v4.7-stable_win64_console.exe` — Godot 可执行文件路径
- `.godot/` — 编辑器缓存（每个 worktree 独立）
- `outputs/test_logs/` — 测试日志输出目录

---

## 5. Repository 关键目录

| 目录 | 职责 |
|------|------|
| `scripts/` | 游戏逻辑、编辑器、服务 GDScript |
| `assets/data/` | 游戏数据（JSON catalog、怪物、装备、技能） |
| `assets/art/` | 美术资源（PNG、动画、地图素材） |
| `assets/maps/` | 运行时地图数据 |
| `map_editor_workspace/` | 地图编辑器工作区（用户地图源文件） |
| `tools/` | 生产工具（Python 导入器、GDScript 工具、测试） |
| `tests/` | Godot 测试（tscn 场景测试） |
| `docs/` | 文档（handoff、设计文档） |
| `outputs/` | 构建输出（APK、测试日志） |

---

## 6. Bootstrap 与硬规则

### 6.1 启动脚本

```powershell
tools\agent_bootstrap.ps1 -Compact
```

### 6.2 核心规则文档

- `AGENTS.md` — 项目协作规则、worktree 所有权、frozen targets
- `docs/CODEX_CONTEXT_SNAPSHOT.md` — 项目基线快照
- `PROJECT_CURRENT_STATUS.md` — 当前状态
- `PROJECT_INDEX.md` — 子系统索引

### 6.3 硬规则

- 禁止 force push
- 禁止 reset/restore/stash/clean 用户 dirty 文件
- 禁止修改 frozen targets
- 禁止手改 generated data
- 禁止在未解决旧地图 refresh bug 前批量打开旧地图

---

## 7. 地图与 Mafa Scene Editor

### 7.1 入口

- Scene: `res://scenes/tools/mafa_scene_editor.tscn`
- 启动: 通过 Godot 打开项目后选择该场景

### 7.2 地图 Workspace 格式

- `map_editor_workspace/<map_id>/<map_id>.editor.json` — 主文件
- `map_editor_workspace/<map_id>/<map_id>.editor.json.bak` — 备份
- 每个地图独立目录，包含 ground/chunks 等子目录

### 7.3 64×32 坐标系统

| 字段 | 说明 |
|------|------|
| `tile` | 地图格坐标 (x, y)，基于 64×32 isometric 网格 |
| `tile_anchor` | 素材锚点 tile 位置 |
| `offset_px` | 像素级偏移，微调视觉位置 |
| `anchor_px` | 素材内部锚点（像素坐标，相对于图片左上角） |
| `placement_anchor_px` | 编辑器放置锚点（由 anchor_policy 计算） |
| `position_mode` | 定位模式，目前为 `tile_anchor` |

### 7.4 当前正式地图

Evidence: `map_editor_workspace/` 目录下包含以下地图：
- `bich_province/` — 比奇省
- `mengzhong_province/` — 盟重省
- `wooma_forest/` — 沃玛森林
- `wooma_temple_1/` 到 `wooma_temple_3/` — 沃玛寺庙
- `orc_tomb_1/` 到 `orc_tomb_3/` — 兽人古墓
- `stone_tomb_1/` 到 `stone_tomb_4/` — 石墓
- `snake_valley/` — 蛇谷
- `corpse_king_hall/` — 尸王殿
- `boss_2/` — Boss 地图
- `bich_mine_1/` — 矿区
- `quest_1/` — 任务地图

---

## 8. 地图素材系统

### 8.1 素材结构

每个地图素材（catalog entry）包含：

| 字段 | 说明 |
|------|------|
| `asset_id` | 唯一稳定 ID |
| `image` | PNG 图片路径 |
| `palette_path` | 编辑器分类路径 |
| `footprint_tiles` | 当前有效占位 (w×h) |
| `base_footprint_tiles` | 100% 基准占位（10% 缩放系统使用） |
| `occupancy_footprint_tiles` | 碰撞占位 |
| `visual_footprint_tiles` | 视觉占位 |
| `anchor_px` | 素材锚点（像素坐标） |
| `placement_anchor_px` | 放置锚点 |
| `anchor_mode` | `foot_tile` 或其它 |
| `approved_scale` | 默认视觉缩放比例 |
| `placeable` | 是否在素材库中可见 |

### 8.2 素材 Catalog

主 catalog: `assets/data/assets/map_asset_catalog.json`
Extension catalogs: 按分类独立存放，路径在 `EXTENSION_CATALOG_PATHS` 中注册
- `scripts/map_assets/map_asset_catalog_service.gd` — 加载服务

### 8.3 10% 素材缩放 Contract

- **Contract ID**: `maps.asset_visual_scale.base_relative_10pct.v1`
- **步进比例**: 10%（相对于 base_scale）
- **核心原则**: visual scale 是 authority，integer footprint 由 base_footprint × (visual_scale / base_scale) 四舍五入推导
- **关键代码**: `MapEditorInstanceService.stepped_visual_scale()` 和 `footprint_for_visual_scale()`
- **base_footprint_tiles 重要性**: 人工校准后的 footprint 必须同时写入 `base_footprint_tiles`，否则 10% 缩放会使用旧 catalog base 计算

Evidence:
- `scripts/map_editor/map_editor_instance_service.gd` 中的 `UNIFORM_VISUAL_SCALE_CONTRACT_ID`
- `resize_instance()` 函数中的 `base_footprint` 解析逻辑

### 8.4 Anchor Policy（锚点策略）

- **Policy ID**: `footprint_bottom_vertex_v1`
- **source anchor**: 素材自身 `anchor_px`（人工校准的值）
- **placement anchor**: 编辑器实际放置使用的锚点，由 `footprint_bottom_vertex_v1` 公式自动计算
- **foot_tile 模式**: 对于 `anchor_mode == "foot_tile"` 的素材，placement anchor 会考虑 footprint 的底部顶点

Evidence:
- `scripts/map_assets/map_asset_placement_anchor_policy.gd`

### 8.5 Grounding Policy（接地策略）

- **Policy ID**: `bottom_contact_grounding_v1`
- **用途**: 从素材 PNG 的 alpha 通道自动计算 footprint、anchor、ground contact
- **实现**: `tools/map_assets/decor_grounding_policy.py`

---

## 9. 人工 Geometry Calibration

### 9.1 工具

- **入口**: `tools/map_assets/run_manual_footprint_review.ps1`
- **主脚本**: `tools/map_assets/manual_footprint_review.gd`
- **Canvas**: `tools/map_assets/manual_footprint_review_canvas.gd`

### 9.2 Review State

- **路径**: `assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json`
- **Contract ID**: `maps.manual_footprint_review_v1`
- **状态**: `pending` / `verified` / `rework`

### 9.3 Override（正式覆盖）

- **路径**: `assets/data/expansions/personal_expansion_001/map_asset_overrides.json`
- **作用**: 人工校准的 footprint/anchor 正式写入这里，覆盖 catalog 默认值
- **关键字段**: `footprint_tiles`, `base_footprint_tiles`, `occupancy_footprint_tiles`, `visual_footprint_tiles`, `anchor_px`, `placeable`

### 9.4 快捷键

| 键 | 功能 |
|----|------|
| W/A/S/D | 调整 footprint width/depth |
| I/J/K/L | 调整 anchor X/Y |
| Enter | 保存 verified 并下一个 |
| PageUp/PageDown | 上/下一个素材 |
| Delete | 从素材库删除（设置 placeable=false） |

### 9.5 当前素材统计

**注意**: 以下数据基于 `codex/maps` 远端 `edc4e51b`。本地 maps worktree 可能因用户 dirty 而不同。

- 总 catalog asset 数: `MapAssetCatalogService.all_assets().size()` = 932
- 当前可摆放素材（placeable=true + image 非空）: 889
- 人工 verified 素材: 889
- 人工 pending 素材: 0
- 人工删除（placeable=false）: 84
- ground_brush anchor 豁免: 2

### 9.6 素材生产管线

```
源图（PNG/ZIP）→ 切割 → Alpha 检查 → Grounding 自动计算 → 
独立 Extension Catalog → Catalog Service 注册 → 
人工 Footprint 校准 → Override 正式写入 → 编辑器使用
```

---

## 10. XZSC 资产

### 10.1 分类

| 分类 | 素材数 | 状态 |
|------|--------|------|
| 囚笼 | 8 | **已完成** — 独立切割，人工校准，正式 override |
| 雕塑 | 28 | **已完成** — curved seam 切割，人工校准 27，用户删除 1 |
| 旗帜 | 16 | 已导入，pending |
| 棺材 | 16 | 已导入，pending |
| 武器架 | 32 | 已导入，pending |
| 火炬 | 16 | 已导入，pending |
| 烛台 | 48 | 已导入，pending |

### 10.2 囚笼最终状态

- **Package**: `mse_xzsc_cage_8_v1`
- **Catalog**: `assets/data/assets/map_xzsc_cage_asset_catalog.json`
- **切割方式**: `fixed_row_specific_4x2_alpha_trim_v1`
- **素材数**: 8
- **人工校准**: 已完成
- **正式 override**: 已写入

### 10.3 雕塑最终状态

- **Package**: `mse_xzsc_sculpture_v3`
- **Catalog**: `assets/data/assets/map_xzsc_sculpture_asset_catalog.json`
- **切割方式**: `curved_minimum_alpha_seam_partition_v3`
- **素材数**: 28
- **人工校准**: 27 verified + 1 user-deleted
- **正式 override**: 已写入（27 个 geometry + 1 个 placeable=false）

---

## 11. 当前地图与世界结构

### 11.1 地图模板

- 模板文件: `assets/data/map_design/map_blank_templates.json`
- 每个地图有 `map_id` 和 `runtime_map_id`（可能不同）

### 11.2 入口/出口系统

- 地图通过 portal 连接
- 商店、NPC、传送门等入口点定义在 map editor 中

---

## 12. 怪物系统

### 12.1 数据来源

- `assets/data/vanilla_176/monsters.json` — 原始传奇 1.76 怪物数据
- `assets/data/vanilla_176/monster_db.json` — Monster.DB 来源
- 生成脚本处理后生成正式 catalog

### 12.2 当前统计

- **Monster catalog**: `assets/data/assets/monster_catalog.json`
- 可通过 `MonsterService.get_canonical_count()` 获取正式数量

### 12.3 分类

- `runtime_allowed`: 可在游戏中出现的怪物
- `runtime_spawnable`: 可在场景中刷新的怪物
- `classification`: 普通/精英/Boss/特殊

### 12.4 权威分支

- `codex/monsters@252d034a` — 最新正式怪物数据
- Golden runtime 已确认怪物系统稳定

---

## 13. 怪物掉落

- 掉落数据来源: 原版传奇 1.76 掉落槽位 + 单机高爆率调整
- 正式数据: `assets/data/assets/drop_catalog.json`
- 生成脚本: `tools/map_design/` 中的生成工具
- 调用: `DropService` 在运行时解析掉落配置

---

## 14. 职业与技能

### 14.1 三职业

| 职业 | 核心文件 | 说明 |
|------|---------|------|
| 战士 | `scripts/warrior_combat_math.gd` | 近战、刺杀、烈火 |
| 法师 | 技能树 | 远程、魔法、群攻 |
| 道士 | 技能树 | 召唤、毒、治疗 |

### 14.2 技能运行机制

- `scripts/skill_*.gd` — 技能实现
- `scripts/skill_projectile.gd` — 飞行物
- `scripts/summon_actor.gd` — 召唤物
- 核心技能几何:
  - 刺杀剑术: 8 方向，玩家面向直线
  - 地狱火: 8 方向，玩家面向直线火焰
  - 疾光电影: 8 方向，直线穿透

### 14.3 技能视觉

- `scripts/layers/runtime/combat_runtime_service.gd` — 战斗运行时
- 技能特效: `assets/art/characters/**/effects/**`
- 雷电术、疾光电影、地狱火等已有视觉实现

---

## 15. 装备系统

### 15.1 装备槽

- 主装备: 武器、衣服、头盔、项链、手镯（一对）、戒指（一对）
- 特殊: 勋章、腰带、靴子（设计阶段，未完全落地）
- 圣物/徽章: **DESIGN ONLY**，未在代码中实现

### 15.2 属性

- 正式属性: `assets/data/equipment_attribute_master.json`
- 来源: 原版传奇 1.76 数据
- 随机属性: 部分装备支持随机附加属性

### 15.3 装备身份

- `item_id` — 稳定 ID
- 纸娃娃渲染: `scripts/equipment_character_preview.gd`
- 世界装备: 地图上可见的装备模型

---

## 16. UI / HUD / Art

### 16.1 UI 系统

- `scripts/hud.gd` — HUD 主控
- `scripts/*_panel.gd` — 各面板（背包、角色、技能等）
- `assets/ui/**` — UI 素材

### 16.2 美术

- 角色: 8 方向，`assets/art/characters/**`
- 怪物: `assets/art/monsters/**`
- 地图素材: `assets/art/maps/**`
- 装备: `assets/art/items/**`

### 16.3 UI Drift 问题

- 历史问题: 2026-08-17 handoff 报告了 UI drift
- 当前状态: **UNKNOWN** — 需要从 `codex/ui-art` 重新验证

---

## 17. Runtime / Export / APK

### 17.1 启动方式

- PC/Godot: 直接运行项目
- Android/APK: 使用 export preset 构建

### 17.2 导出配置

- `project.godot` 中的 export 配置
- Android 包名: `com.personal.mafaoffline`
- 品牌名: HardCore

### 17.3 Golden APK

- 路径: `outputs/hardcore/hardcore-1.18.3-golden.apk`
- Tag: `golden/apk-1.18.3-base-9d6435bc`

---

## 18. 测试与验证

### 18.1 测试运行

```powershell
# 运行指定测试
powershell -ExecutionPolicy Bypass -File tools\run_godot_tests.ps1 -TestPaths 'tests/<test_name>.tscn'

# 运行全部测试
tools\godot-4.7\Godot_v4.7-stable_win64_console.exe --headless --path . --script tests/run_all_tests.gd
```

### 18.2 关键测试

| 测试 | 文件 | 说明 |
|------|------|------|
| Uniform Scale 10% | `tests/mse_uniform_asset_scale_10pct_test.tscn` | 地图素材缩放 |
| Instance Resize | `tests/mse_instance_resize_regression_test.tscn` | 实例缩放回归 |
| 怪物 | `tests/`（monster 目录） | 怪物数据验证 |
| 技能 | `tests/`（skill 目录） | 技能运行验证 |

### 18.3 测试环境

- Godot 可执行文件: `tools/godot-4.7/Godot_v4.7-stable_win64_console.exe`
- 测试日志: `outputs/test_logs/`
- 运行模式: console + headless

---

## 19. Generated Data Authority

### 19.1 生成数据列表

| 数据文件 | 生成器 | 禁止手改 |
|---------|--------|---------|
| `assets/data/assets/map_asset_catalog.json` | importer scripts | YES |
| `assets/data/assets/monster_catalog.json` | monster generator | YES |
| 各种 extension catalog JSON | 对应 importer | YES |
| `assets/data/expansions/personal_expansion_001/map_asset_overrides.json` | 人工校准工具 | NO（人工产出） |

### 19.2 规则

- 所有 `assets/data/assets/*.json` 中的 catalog 文件是 generated artifact
- 禁止手工编辑 JSON 数组/对象
- 人工校准结果写入 `map_asset_overrides.json`（这是用户产出）
- 主 `map_asset_catalog.json` 禁止直接修改

---

## 20. Git 施工与 Landing 流程

### 20.1 标准流程

1. 创建临时 worktree + branch（基于 `origin/codex/*`）
2. 在临时 branch 上施工
3. 创建 clean landing worktree（基于最新 `origin/codex/*`）
4. 只 checkout 施工 branch 中的正式文件
5. 提交 landing
6. push landing branch
7. ff-only 更新正式分支

### 20.2 禁止操作

- 禁止 force push
- 禁止直接在 maps worktree 上施工
- 禁止 reset/restore/stash/clean 用户 dirty 文件
- 禁止直接 merge 未在远端验证的 commit

---

## 21. 最近施工时间线（2026-08-17 至 2026-08-20）

| 日期 | SHA | 分支 | 消息 | 作用 |
|------|-----|------|------|------|
| 08-20 | `edc4e51b` | `codex/maps` | preserve latest user asset deletions | 保存用户最新删除 |
| 08-20 | `3139bc34` | `codex/maps` | apply final manual sculpture calibration | 雕塑 27 人工几何正式落地 |
| 08-20 | `cef66165` | `codex/maps` | preserve final sculpture manual review | 保存雕塑 review |
| 08-20 | `daaf13f1` | `codex/maps` | rebuild sculpture assets with seam partition | R3 弯曲 seam 切割 |
| 08-20 | `224c5783` | `codex/maps` | recut xzsc sculpture assets | R2 雕塑重切 |
| 08-20 | `35e694fa` | `codex/maps` | import xzsc sculpture assets | 第一批雕塑导入 |
| 08-20 | `7bd8a185` | `codex/maps` | apply final manual cage calibration | 8 囚笼正式落地 |
| 08-20 | `e404008a` | `codex/maps` | preserve final manual asset calibration review | 861 全量 review 保存 |
| 08-20 | `2fe4a3d3` | `codex/maps` | apply manual asset calibration and add cage assets | 853 正式几何落地 + 囚笼 |
| 08-20 | `2acb4baf` | `codex/maps` | preserve completed manual asset calibration | 用户校准数据保存 |
| 08-18 | `b7188497` | `codex/integration` | Merge monsters | 怪物集成 |
| 08-18 | `252d034a` | `codex/monsters` | Merge integration | 怪物同步 |

---

## 22. 当前 Open Issues

### P0: 旧地图实例自动 refresh 导致素材移位

- **Status**: OPEN
- **Branch**: `codex/maps`
- **Severity**: P0 — BLOCKER
- **Mechanism**: 打开旧地图时，`MapEditorApp._open_document_path()` 调用 `_migrate_loaded_instances_to_class_profiles()`，进而调用 `MapEditorInstanceProfileService.refresh_from_asset()`。当素材 footprint / placement anchor 变化后，旧实例的 `tile` 和 `offset_px` 未相应调整，导致视觉脚点移位。
- **Evidence**: `scripts/map_editor/map_editor_app.gd`、`scripts/map_editor/map_editor_instance_profile_service.gd`
- **Next Action**: 在正式修复前，不要批量打开/保存旧地图。修复方案：保持旧实例 visual foot 不变的情况下迁移 geometry。

### P1: Maps Worktree Dirty

- **Status**: OPEN
- **Branch**: `codex/maps`
- **Severity**: P1
- **Detail**: 用户 maps worktree 有大量 dirty 文件（地图编辑、override、review state）。需要保护，不能 reset。

### P1: 雕塑 Apply SHA 不一致

- **Status**: RESOLVED
- **Detail**: 首次 apply 的 commit (48bae3e5) 丢失，已重新创建 (3139bc34) 并推送至 edc4e51b。

### P2: 怪物 Runtime Closure

- **Status**: RESOLVED
- **Detail**: 怪物分类和 runtime closure 已在之前任务中验证。

### P2: UI Drift

- **Status**: UNKNOWN
- **Branch**: `codex/ui-art`
- **Detail**: 历史 UI drift 问题，需要从当前分支重新验证。

---

## 23. 当前 Local-only / Dirty 状态

### 23.1 关键 Dirty 文件（maps worktree）

```
M assets/data/expansions/personal_expansion_001/map_asset_overrides.json
M assets/data/map_design/map_blank_templates.json
M map_editor_workspace/**/*.editor.json (多个地图)
M map_editor_workspace/**/*.editor.json.bak
M map_editor_workspace/**/ground/** (多个 ground 文件)
```

### 23.2 保护要求

- 这些文件是用户直接操作成果
- 禁止 reset/restore/stash/clean
- 远端 `codex/maps` 已完成所有正式素材数据，但用户本地 dirty 文件尚未提交

---

## 24. 文件 Authority Matrix

| 子系统 | 权威分支 | 主要文件 | 生成? | 用户可编辑? | 禁止触碰? |
|--------|---------|---------|------|-----------|----------|
| 地图素材 Catalog | `codex/maps` | `assets/data/assets/map_asset_catalog.json` | YES | NO | YES |
| 人工素材 Override | `codex/maps` | `assets/data/expansions/.../map_asset_overrides.json` | NO | YES（人工产出） | NO |
| 人工 Review State | `codex/maps` | `assets/data/expansions/.../map_asset_footprint_review_state.json` | NO | YES（人工产出） | NO |
| 怪物 Catalog | `codex/monsters` | `assets/data/assets/monster_catalog.json` | YES | NO | YES |
| 掉落数据 | `codex/monsters` | `assets/data/assets/drop_catalog.json` | YES | NO | YES |
| 技能数据 | `codex/professions-skills` | `assets/data/vanilla_176/skills.json` | NO | YES | NO |
| 装备属性 | `codex/equipment` | `assets/data/equipment_attribute_master.json` | NO | YES | NO |
| UI | `codex/ui-art` | `assets/ui/**` | NO | YES | NO |
| 地图 Workspace | `codex/maps` | `map_editor_workspace/**` | NO | YES（地图编辑） | 禁止自动修改 |
| 地图运行时 | `codex/integration` | `assets/maps/**` | YES | NO | YES |
| 游戏脚本 | `codex/integration` | `scripts/**` | NO | YES | 按子系统 |
| Golden APK | `main` | `outputs/hardcore/*.apk` | YES | NO | YES |

---

## 25. Sol 接手后的前 10 步

1. **`git fetch --all --tags --prune`** — 获取全部分支和标签
2. **阅读 `SOL_HANDOFF.md`** — 找到最新入口
3. **阅读 `docs/handoff/2026-08-20/00_MASTER_PROJECT_MANUAL.md`** — 当前文档
4. **检查 `handoff_manifest.json`** — 确认所有 branch SHA 和 worktree 状态
5. **`git worktree list`** — 确认当前 worktree 状态
6. **确认 dirty 用户数据** — maps worktree 的 dirty 文件，禁止 reset
7. **确认每个 permanent branch tip** — 与 manifest 一致
8. **不要先 merge** — 先评估 P0 issue
9. **优先处理 P0: 旧地图 refresh 移位问题** — 这是当前最大风险
10. **任何施工前运行 `tools/agent_bootstrap.ps1 -Compact`**

---

## 26. 禁止事项

- 不要 reset / restore / stash / clean 用户地图 workspace
- 不要把历史 WIP branch（deepseek/*, qwen/*, dsh/*）当 authority
- 不要重新编号 `monster_id`
- 不要重新做已人工校准的素材
- 不要修改 Golden APK
- 不要手改 generated file（`assets/data/assets/*.json` 中的 catalog）
- 不要在未解决旧地图 refresh bug 前批量打开旧地图
- 不要轻易恢复 2026-08-17 的旧状态
- 不要把 local-only commit 当 remote truth
- 不要 force push
- 不要修改 `map_editor_workspace/*` 除非明确的地图编辑任务

---

## 27. 常用命令速查

```powershell
# 获取最新
git fetch --all --tags --prune

# 查看 worktree
git worktree list

# 运行测试
powershell -ExecutionPolicy Bypass -File tools\run_godot_tests.ps1 -TestPaths 'tests/<test>.tscn'

# 启动人工校准工具
powershell -ExecutionPolicy Bypass -File tools\map_assets\run_manual_footprint_review.ps1

# Godot 只读审计
tools\godot-4.7\Godot_v4.7-stable_win64_console.exe --headless --path . --script <script.gd>

# 标记当前用户数据
# 保护: 不要 reset/restore/stash/clean
```

---

## 28. Appendix — Branch SHA / Worktree Snapshot

见 `handoff_manifest.json` 获取完整机器可读快照。

**关键 SHA：**

| 分支 | Remote SHA |
|------|-----------|
| `main` | `7d36c678e6ca4b3a65e1a0ad9a54ee1fa7c3deb4` |
| `codex/integration` | `b7188497b2e74cafc40475ea1e54ec5520e227ff` |
| `codex/maps` | `edc4e51b03ee572509e9645525447a40d3ca1c5b` |
| `codex/monsters` | `252d034ad27e7d1372b409b5615c37e987aa914a` |
| `codex/equipment` | `ba8d4ff372589e822072ce23c303098020f899b6` |
| `codex/professions-skills` | `162df988d9f7ee513ce6fcca3e67e55898dc8eb9` |
| `codex/ui-art` | `700e884dad8d432e14250b676c71eb65714f5cca` |

---

*本文档由 DeepSeek 于 2026-08-20 生成，供 ChatGPT Sol 接手项目使用。*
*所有数据以仓库实际状态为准，旧 handoff 文档仅作历史参考。*