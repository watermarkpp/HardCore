# 当前开放问题与优先级

> 生成日期: 2026-08-17

---

## P0: 怪物 Runtime Closure

| 字段 | 值 |
|------|-----|
| **STATUS** | 进行中 |
| **OWNER** | codex/monsters |
| **BRANCH** | codex/monsters |
| **BLOCKER** | `canonical_monster_catalog` 仍存在 `ART_MAPPING_MISSING`，但 Golden 已确认存在正式 art authority |
| **NEXT_ACTION** | 检查 authority wiring（`build_canonical_monster_catalog.py` 的 art source 路由逻辑），不是重新制作美术 |
| **DO_NOT_DO** | ❌ 不要重新制作美术，不要重新校 footAnchor，不要从 APK 回填数据 |

### 说明
Golden 阶段已完成 214 只怪物的全量校准（foot_anchor + ground_contacts + overhead_anchors + manual_alignment）。当前 `ART_MAPPING_MISSING` 的根因是 canonical catalog 构建脚本未能正确路由到已有的 art authority 源，而非美术资源真正缺失。修复方向是检查 `build_canonical_monster_catalog.py` 中的 art source 路由逻辑，确保 monster_id → appearance 映射正确连接。

---

## P1: 旧地图 monster identity migration

| 字段 | 值 |
|------|-----|
| **STATUS** | 部分完成 |
| **OWNER** | codex/maps |
| **BRANCH** | codex/maps |
| **BLOCKER** | 地图编辑器 `authoring_allowed` 与 `runtime_ready` 已分离 |
| **NEXT_ACTION** | 稳定 monster_id 不得重编号，继续迁移 |
| **DO_NOT_DO** | ❌ 不要重编号 monster_id |

### 说明
旧地图中引用的怪物需要通过稳定的 `monster_id` 与新 canonical catalog 对齐。地图编辑器的 authoring 权限与 runtime 就绪状态已经解耦，可以继续逐地图迁移。关键约束：monster_id 一旦分配禁止重编号。

---

## P2: UI 脚本 drift 处理

| 字段 | 值 |
|------|-----|
| **STATUS** | 已识别 |
| **OWNER** | codex/ui-art / codex/integration |
| **BRANCH** | codex/ui-art |
| **BLOCKER** | 17 个 UI 脚本当前 HEAD ≠ golden hotfix 最终版 |
| **NEXT_ACTION** | 逐项判断是否需要将 golden 版本恢复为当前版本 |
| **DO_NOT_DO** | ❌ 不要整体回滚 |

### 说明
Golden hotfix 之后，部分 UI 脚本在 codex/ui-art 分支上继续演进，导致与 golden 基线产生 drift。需要逐个文件判断：哪些 drift 是有意改进（保留当前版本），哪些是意外偏离（恢复 golden 版本）。禁止一刀切整体回滚。

---

## P3: 远端分支整理

| 字段 | 值 |
|------|-----|
| **STATUS** | 待执行 |
| **OWNER** | codex/integration |
| **BRANCH** | codex/integration |
| **BLOCKER** | 3 个 `dsh/*` 已完全合并可删除；3 个永久分支无远端 |
| **NEXT_ACTION** | push 永久分支，标记审计分支 |
| **DO_NOT_DO** | ❌ 不要 force push |

### 说明
远端存在 3 个已完全合并的 `dsh/*` 分支（`dsh/monster-runtime-closure`、`dsh/monster-classification-audit`、`dsh/monsters-drop-audit`），应清理删除。同时 5 个永久工作树分支中部分缺少远端对应，需要 push 以保持一致性。操作时禁止 force push，避免覆盖远端历史。
