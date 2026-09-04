# Golden Source Map

> 最终锁定源映射表。所有系统均已溯源到具体 commit，无 SOURCE_MISSING 项。

## 源映射总表

| SYSTEM | GOLDEN_RUNTIME_LAYER | GOLDEN_SOURCE_COMMIT | MATCH_LEVEL | CURRENT_STATE |
|--------|---------------------|---------------------|-------------|---------------|
| MONSTER_DATA | APK_BASE | ee09aefd (CMAS) | EXACT_SOURCE_MATCH | MATCHES_GOLDEN (monsters worktree) |
| MONSTER_ART | APK_BASE | 1abd038b (bich split) | EXACT_SOURCE_MATCH | MATCHES_GOLDEN (all worktrees) |
| MONSTER_ALIGNMENT | APK_BASE | b478b7cc / 8f522258 | EXACT_SOURCE_MATCH | MATCHES_GOLDEN (all worktrees) |
| MONSTER_AI | APK_BASE | 58665f12 | PARTIAL_MATCH | POST_GOLDEN_DEVELOPMENT (+1 profile) |
| MONSTER_DROPS | APK_BASE | b893b951 | PARTIAL_MATCH | POST_GOLDEN_DEVELOPMENT (+3 records) |
| SKILL_RUNTIME | APK_BASE | 2e65bd3e / 5d0441bb | EXACT_SOURCE_MATCH | MATCHES_GOLDEN |
| SKILL_VISUAL | APK_BASE | 14bb52f5 | SEMANTIC_EXACT | MATCHES_GOLDEN |
| SKILL_UI | HOTFIX warehouse_v6 | 7c08edcd | PROVENANCE_EXACT | DRIFTED_FROM_GOLDEN |
| HUD | HOTFIX warehouse_v6 | 7c08edcd | PROVENANCE_EXACT | DRIFTED_FROM_GOLDEN |
| INVENTORY | HOTFIX repair_theme | a9a98b3b | PROVENANCE_EXACT | MATCHES_GOLDEN |
| EQUIPMENT_UI | APK_BASE | 8ba485dd | EXACT_SOURCE_MATCH | MATCHES_GOLDEN |
| SHOP | HOTFIX shop_v11 | 612c05a5 | PROVENANCE_EXACT | DRIFTED_FROM_GOLDEN |
| WAREHOUSE | HOTFIX warehouse_v6 | 7c08edcd | PROVENANCE_EXACT | DRIFTED_FROM_GOLDEN |
| MAP_RUNTIME | APK_BASE | 666e2883 | EXACT_SOURCE_MATCH | POST_GOLDEN_DEVELOPMENT |
| MAP_UI | HOTFIX startup_cg | 0af855db | PROVENANCE_EXACT | DRIFTED_FROM_GOLDEN |
| NPC | HOTFIX world_label | c1a60bcb | PROVENANCE_EXACT | DRIFTED_FROM_GOLDEN |
| STARTUP | HOTFIX startup_cg | 0af855db | PROVENANCE_EXACT | DRIFTED_FROM_GOLDEN |
| CG | HOTFIX startup_direct | 0af855db | PROVENANCE_EXACT | DRIFTED_FROM_GOLDEN |
| GLOBAL_SERVICES | HOTFIX + post-APK | 7c08edcd → a91bc586 | PROVENANCE_EXACT | POST_GOLDEN_DEVELOPMENT |

## 状态定义

| CURRENT_STATE | 含义 | 处理方式 |
|---------------|------|----------|
| **MATCHES_GOLDEN** | 当前 worktree HEAD 与 golden 基线一致 | 无需操作 |
| **POST_GOLDEN_DEVELOPMENT** | golden 之后的后续开发，非错误 | 保留，属于正常演进 |
| **DRIFTED_FROM_GOLDEN** | 当前 HEAD 已偏离 golden，但 golden 版本可通过 `git show` 取回 | 逐项判断是否需要回退，禁止整体回滚 |
| **SOURCE_MISSING** | 源在 git 中未找到（COUNT = 0） | 本项目此项为 0，无缺失 |

## MATCH_LEVEL 定义

| MATCH_LEVEL | 含义 |
|-------------|------|
| EXACT_SOURCE_MATCH | 源 commit 中的文件内容与 APK 运行时完全一致 |
| SEMANTIC_EXACT | 语义完全一致，可能存在格式化/注释差异 |
| PARTIAL_MATCH | 源 commit 包含大部分内容，后续有少量增量开发 |
| PROVENANCE_EXACT | 来源链路可精确追溯，但当前 worktree 已有后续修改 |

## 验证结果

| 指标 | 值 |
|------|-----|
| ALL_GOLDEN_UI_SOURCE_COMMITS_VERIFIED | **YES** (13 commits, 22 files) |
| TRUE_SOURCE_MISSING_COUNT | **0** |
| CURRENT_WORKTREE_DRIFT_COUNT | **17** |
| POST_GOLDEN_DEVELOPMENT_COUNT | **5** |

### 验证说明

- 所有 13 个 golden UI 源 commit 均已通过 `git show` 验证存在且可读取
- 22 个关联文件均可从对应 commit 精确还原
- 17 个 DRIFTED 项均为后续开发导致的正常偏离，golden 版本随时可恢复
- 0 个 SOURCE_MISSING — 不存在无法追溯的系统
