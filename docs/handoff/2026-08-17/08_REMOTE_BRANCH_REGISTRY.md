# 远端分支注册表

> 生成日期: 2026-08-17

---

## 远端信息

| 字段 | 值 |
|------|-----|
| **Remote** | `watermarkpp/HardCore` (origin) |
| **Default Branch** | main |

---

## 远端分支清单

| 分支 | Tip SHA | 已合并? | 独有提交数 | 用途 | 本地对应 | 操作建议 |
|------|---------|---------|-----------|------|---------|---------|
| `origin/main` | `7c471980` | — | 0 | 主集成分支（含 SOL_HANDOFF.md） | — | **KEEP** |
| `origin/codex/integration` | `6b91ba8b` | NO | 2 | 集成主控 | HardCore/ | **KEEP** |
| `origin/codex/maps` | `668064fa` | NO | 49 | Maps 工作树 | maps/ | **KEEP** |
| `origin/codex/monsters` | `4a7d1cd3` | NO | — | Monsters 工作树 | monsters/ | **KEEP** |
| `origin/codex/equipment` | `5da60808` | NO | 11 | Equipment 工作树 | equipment/ | **KEEP** |
| `origin/codex/professions-skills` | `0e142450` | NO | — | Professions-Skills 工作树 | professions-skills/ | **KEEP** |
| `origin/codex/ui-art` | `ec02c08e` | NO | 38 | UI-Art 工作树 | ui-art/ | **KEEP** |
| `origin/dsh/monster-runtime-r2r3` | `62fafc5a` | NO | 4 | Monster R2R3 | monster-classification-audit | **ARCHIVAL** |
| `origin/dsh/monster-runtime-closure` | `066e84f6` | YES | 0 | 已合并 | — | **DELETE CANDIDATE** |
| `origin/dsh/monster-classification-audit` | `f2ab65cf` | YES | 0 | 已合并 | — | **DELETE CANDIDATE** |
| `origin/dsh/monsters-drop-audit` | `8808ebe3` | YES | 0 | 已合并 | — | **DELETE CANDIDATE** |

### 操作说明

- **KEEP**: 活跃分支，保留不动
- **REVIEW**: 未合并但有独有提交，需人工审查是否仍有价值
- **DELETE CANDIDATE**: 已完全合并入 main，可安全删除

---

## 本地永久分支远端状态（2026-08-17 最终）

| 分支 | 远端已推送 | 远端 HEAD | 本地 HEAD | 本地 dirty |
|------|:---:|---------|---------|-----------|
| `codex/integration` | ✅ | `6b91ba8b` | `6b91ba8b` | 12 tracked + 271 untracked |
| `codex/maps` | ✅ | `668064fa` | `668064fa` | 98 tracked + 84 untracked |
| `codex/monsters` | ✅ | `4a7d1cd3` | `4a7d1cd3` | 1 tracked + 205 untracked |
| `codex/equipment` | ✅ | `5da60808` | `5da60808` | 581 tracked + 193 untracked |
| `codex/professions-skills` | ✅ | `0e142450` | `0e142450` | 2 tracked + 198 untracked |
| `codex/ui-art` | ✅ | `ec02c08e` | `ec02c08e` | 616 tracked + 192 untracked |

### Dirty 内容说明

所有永久 worktree 的 dirty 内容均为**未提交本地修改**，不影响远端分支完整性。

- **ui-art** (616 dirty): 全部为 `.png.import` 重导入噪声，零有意义 WIP
- **equipment** (581 dirty): 580 个 `.png.import` 噪声 + 1 个测试文件修改
- **maps** (98 dirty): 最多有意义 WIP（95 个），含活跃地图编辑、新素材、新脚本
- **integration** (12 dirty): 数据权威文件、测试、构建工具的本地修改
- **monsters** (1 dirty): 仅 `visual_acceptance_lab.gd`
- **professions-skills** (2 dirty): 2 个测试文件修改

**注意**: Push 时禁止 force push，避免覆盖远端已有历史。
