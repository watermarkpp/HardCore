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
| `origin/main` | `066e84f6` | — | 0 | 主集成分支 | — | **KEEP** |
| `origin/codex/maps` | `668064fa` | NO | 49 | Maps 工作树 | codex/maps | **KEEP** |
| `origin/dsh/monster-runtime-r2r3` | `62fafc5a` | NO | 4 | Monster R2R3 | monster-classification-audit | **REVIEW** |
| `origin/dsh/monster-runtime-closure` | `066e84f6` | YES | 0 | 已合并 | — | **DELETE CANDIDATE** |
| `origin/dsh/monster-classification-audit` | `f2ab65cf` | YES | 0 | 已合并 | — | **DELETE CANDIDATE** |
| `origin/dsh/monsters-drop-audit` | `8808ebe3` | YES | 0 | 已合并 | — | **DELETE CANDIDATE** |

### 操作说明

- **KEEP**: 活跃分支，保留不动
- **REVIEW**: 未合并但有独有提交，需人工审查是否仍有价值
- **DELETE CANDIDATE**: 已完全合并入 main，可安全删除

---

## 本地永久分支（缺少远端对应）

| 分支 | 领先 main 提交数 | 需要的操作 |
|------|-----------------|-----------|
| `codex/integration` | 1 commit | Push 到 `origin/codex/integration` |
| `codex/monsters` | 0 (in main) | Push 以保持一致性 |
| `codex/equipment` | 11 commits | Push 到 `origin/codex/equipment` |
| `codex/professions-skills` | 0 (in main) | Push 以保持一致性 |
| `codex/ui-art` | 38 commits | Push 到 `origin/codex/ui-art` |

### 操作说明

所有永久工作树分支均应有远端对应，确保：
1. 跨机器协作时可直接 fetch/checkout
2. 本地意外丢失时可从远端恢复
3. CI/CD 或其他自动化可访问分支状态

**注意**: Push 时禁止 force push，避免覆盖远端已有历史。
