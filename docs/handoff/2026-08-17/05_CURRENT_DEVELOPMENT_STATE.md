# 当前开发状态总览

> **核心原则：DRIFTED ≠ BUG。** Golden 是已人工验收基线。Post-Golden 是后续开发。处理 drift 时必须逐项判断，禁止整体回滚。

---

## 1. MATCHES_GOLDEN 系统

以下系统的当前 worktree HEAD 与 golden 基线完全一致，无需任何操作。

### 怪物数据 (MONSTER_DATA)
- **源 commit:** `ee09aefd` (CMAS)
- **Worktree:** monsters
- **状态:** 214 条怪物记录完整匹配，包含动画目录、地面接触、头顶锚点等全部数据文件

### 怪物美术 (MONSTER_ART)
- **源 commit:** `1abd038b` (bich split)
- **Worktree:** all worktrees
- **状态:** 6 顶级目录、~113 怪物动画子目录，全部拥有完整 5 动作集 (idle/walk/attack/hit/death)

### 怪物对齐 (MONSTER_ALIGNMENT)
- **源 commit:** `b478b7cc` / `8f522258`
- **Worktree:** all worktrees
- **状态:** 214 条地面接触校准、212 + 2 airborne 手动对齐数据完整匹配

### 技能运行时 (SKILL_RUNTIME)
- **源 commit:** `2e65bd3e` / `5d0441bb`
- **状态:** 投射物、召唤物、职业公式运行时与 golden 一致

### 技能视觉 (SKILL_VISUAL)
- **源 commit:** `14bb52f5`
- **状态:** 技能特效语义完全一致

### 背包 (INVENTORY)
- **源 commit:** `a9a98b3b` (repair_theme hotfix)
- **状态:** 背包 UI 与 golden 一致

### 装备 UI (EQUIPMENT_UI)
- **源 commit:** `8ba485dd`
- **状态:** 装备界面与 golden 一致

---

## 2. POST_GOLDEN_DEVELOPMENT 系统

以下系统在 golden 基线之后有后续开发，属于正常演进，**不是错误**。

### 怪物 AI (MONSTER_AI) — +1 profile
- **源 commit:** `58665f12`
- **增量:** 新增 1 个 behavior profile
- **处理:** 保留新增内容，golden 基线行为不受影响

### 怪物掉落 (MONSTER_DROPS) — +3 records
- **源 commit:** `b893b951`
- **增量:** 新增 3 条掉落记录
- **处理:** 保留新增记录，不影响已有掉落表

### 地图运行时 (MAP_RUNTIME)
- **源 commit:** `666e2883`
- **增量:** 地图编辑器 canonical ID 等后续开发
- **处理:** 保留，属于地图子系统正常演进

### NPC 世界标签 (NPC world labels)
- **源 commit:** `c1a60bcb`
- **增量:** NPC 世界标签功能后续完善
- **处理:** 保留新增功能

### 全局服务 (GLOBAL_SERVICES)
- **源 commit:** `7c08edcd` → `a91bc586`
- **增量:** 全局服务注册在 golden 之后有演进
- **处理:** 保留，服务层正常迭代

### canonical_monster_catalog 217
- 怪物目录从 golden 的 214 条发展到 217 条
- 新增条目属于后续数据扩充，不影响已有 214 条的完整性

---

## 3. DRIFTED_FROM_GOLDEN 系统

以下系统的当前 HEAD 已偏离 golden 基线。**Golden 版本未丢失**，可通过 `git show <commit>:<file>` 精确还原。

### 涉及系统（共 17 个文件）

| 系统 | Golden Commit | 偏离原因 |
|------|--------------|----------|
| SKILL_UI | `7c08edcd` | 后续 UI 调整 |
| HUD | `7c08edcd` | 后续 HUD 布局修改 |
| SHOP | `612c05a5` | 商店界面后续迭代 |
| WAREHOUSE | `7c08edcd` | 仓库界面后续修改 |
| MAP_UI | `0af855db` | 地图 UI 后续调整 |
| STARTUP | `0af855db` | 启动流程后续修改 |
| CG | `0af855db` | CG 播放后续调整 |

### 恢复方法

所有 drifted 文件均可通过以下方式恢复 golden 版本：

```bash
# 查看 golden 版本的特定文件
git show <GOLDEN_SOURCE_COMMIT>:<file_path>

# 恢复到 golden 版本（仅在逐项确认后执行）
git checkout <GOLDEN_SOURCE_COMMIT> -- <file_path>
```

### 处理原则

- **禁止整体回滚** — 每个 drifted 文件必须逐项判断是否需要恢复
- 部分 drift 可能是有价值的改进，不应盲目回退
- 恢复前必须对比 golden 版本与当前版本的差异，确认恢复必要性
- UI 类 drift 通常涉及视觉调整，需结合 APK 实际运行效果判断

---

## 4. SOURCE_MISSING = 0

**所有系统的 golden 源均已找到并可验证。** 无缺失项。

- 13 个 golden UI 源 commit 全部存在
- 22 个关联文件全部可从 git 精确还原
- 不需要从 APK 反编译或外部源补充任何内容

---

## 总结

| 分类 | 数量 | 操作 |
|------|:---:|------|
| MATCHES_GOLDEN | 7 系统 | 无需操作 |
| POST_GOLDEN_DEVELOPMENT | 5 系统 | 保留，正常演进 |
| DRIFTED_FROM_GOLDEN | 17 文件 | 逐项判断，禁止整体回滚 |
| SOURCE_MISSING | 0 | 无缺失 |

**Golden 是安全网，不是牢笼。** 它确保任何时刻都能回到已验收状态，但不阻止有价值的后续开发。
