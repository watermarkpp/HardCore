# SOL HANDOFF — HardCore 项目接手指南

> **START HERE.** 这是 Sol 接手项目的第一入口。

> ## 2026-08-20 最新接手入口
>
> 本文件原主体是 2026-08-17 handoff。
> 当前项目已经继续施工。
>
> 最新 authoritative handoff：
>
> `docs/handoff/2026-08-20/00_MASTER_PROJECT_MANUAL.md`
>
> 当前机器状态：
>
> `docs/handoff/2026-08-20/handoff_manifest.json`
>
> **Sol 必须优先阅读 2026-08-20 文档。**
> 旧 2026-08-17 文档仅作历史证据。

---

## 1. 项目是什么

HardCore 是一个 Godot 4.7 的 ARPG 游戏项目。多 worktree 架构，6 个永久专业分支 + 1 个集成主控分支。

- **引擎**: Godot 4.7 stable
- **包名**: `com.personal.mafaoffline`（兼容旧存档）
- **品牌**: HardCore
- **远端**: `watermarkpp/HardCore` (GitHub)

## 2. 正式开发分支结构

| 分支 | Worktree 路径 | 职责 |
|------|--------------|------|
| `codex/integration` | `HardCore/` (主控) | 跨系统集成、merge、验收、全局服务 |
| `codex/maps` | `HardCore-worktrees/maps` | 地图、地图编辑器、环境素材 |
| `codex/monsters` | `HardCore-worktrees/monsters` | 怪物/Boss 数据、AI、动画、战斗 |
| `codex/equipment` | `HardCore-worktrees/equipment` | 装备数据、美术、穿戴规则 |
| `codex/professions-skills` | `HardCore-worktrees/professions-skills` | 职业成长、技能、投射物、召唤物 |
| `codex/ui-art` | `HardCore-worktrees/ui-art` | UI 面板、HUD、装备预览、UI 素材 |

详见 → [`docs/handoff/2026-08-17/02_WORKTREE_BRANCH_REGISTRY.md`](docs/handoff/2026-08-17/02_WORKTREE_BRANCH_REGISTRY.md)

## 3. Golden Runtime 是什么

**最新 APK + 配套热修补丁 = 已验收游戏内容的最高真值。**

| 字段 | 值 |
|------|-----|
| APK | `outputs/hardcore/HardCore-1.18.3-runtime-fix-9d6435bc-debug.apk` |
| SHA256 | `B74F58FC1E17A28D2A0FAE7E709085E410F4C48FF6141DD6C293596DDEF341CB` |
| Base Commit | `9d6435bc` (tag: `golden/apk-1.18.3-base-9d6435bc`) |
| Hotfix | 32 个 PCK（0 个含怪物数据） |
| 怪物 | 214 只全量校准 |

详见 → [`docs/handoff/2026-08-17/03_GOLDEN_RUNTIME_AUTHORITY.md`](docs/handoff/2026-08-17/03_GOLDEN_RUNTIME_AUTHORITY.md)

## 4. Golden Source Map 在哪里

每个子系统的最终源码来源已锁定：

- **怪物数据/美术/对齐**: MATCHES_GOLDEN (visual-lab-frozen / codex/monsters)
- **技能运行时**: MATCHES_GOLDEN (codex/professions-skills)
- **UI 脚本 (17 个)**: DRIFTED_FROM_GOLDEN (golden 版本可从 git 历史检索)
- **源码丢失数**: **0**

详见 → [`docs/handoff/2026-08-17/04_GOLDEN_SOURCE_MAP.md`](docs/handoff/2026-08-17/04_GOLDEN_SOURCE_MAP.md)

## 5. 当前最重要工作

| 优先级 | 问题 | Owner |
|--------|------|-------|
| P0 | 怪物 Runtime Closure — ART_MAPPING_MISSING 是 authority wiring 问题 | codex/monsters |
| P1 | 旧地图 monster identity migration | codex/maps |
| P2 | UI 脚本 drift 逐项处理 | codex/ui-art |

> **REMOTE CONSOLIDATION = COMPLETE** — 所有永久分支已推送，WIP snapshot 已备份。

详见 → [`docs/handoff/2026-08-17/06_OPEN_ISSUES_AND_PRIORITIES.md`](docs/handoff/2026-08-17/06_OPEN_ISSUES_AND_PRIORITIES.md)

## 6. 不可手工修改的数据

- **GENERATED 文件**（由 Python 脚本生成，禁止手改）→ 见 `09_GENERATED_DATA_AND_AUTHORITY_POLICY.md`
- **monster_id**: 稳定 ID，禁止重编号
- **APK/PCK**: 仅用于验证，禁止反哺源码
- **用户冻结对象**: 用户说"已修改好"的文件只读

## 7. Worktree 职责

见上方第 2 节。临时 worktree（audit/dsh/*/task-*）是历史证据，不升级为长期。

## 8. 如何运行测试

```powershell
# 怪物专项
tools\run_godot_tests.ps1

# 或手动
tools\godot-4.7\Godot_v4.7-stable_win64_console.exe --path . --headless -s tests\run_all_tests.gd
```

详见 → [`docs/handoff/2026-08-17/07_VALIDATION_AND_LAUNCH_COMMANDS.md`](docs/handoff/2026-08-17/07_VALIDATION_AND_LAUNCH_COMMANDS.md)

## 9. 如何启动地图编辑器

```
tools\godot-4.7\Godot_v4.7-stable_win64.exe --path "HardCore-worktrees\maps" "res://tools/map_editor/map_editor_app.tscn"
```

## 10. 如何启动 Visual Acceptance Lab

```
# 完整模式
tools\godot-4.7\Godot_v4.7-stable_win64.exe --path "HardCore-worktrees\monsters" "res://tools/visual_acceptance_lab/visual_acceptance_lab.tscn"

# 怪物 ground review 模式
tools\godot-4.7\Godot_v4.7-stable_win64.exe --path "HardCore-worktrees\monsters" "res://tools/visual_acceptance_lab/visual_acceptance_lab.tscn" --monster-ground-review
```

## 11. 未闭环问题

→ [`docs/handoff/2026-08-17/06_OPEN_ISSUES_AND_PRIORITIES.md`](docs/handoff/2026-08-17/06_OPEN_ISSUES_AND_PRIORITIES.md)

## 12. 修改任何东西以前应该读

1. **本文件** (SOL_HANDOFF.md)
2. [`AGENTS.md`](AGENTS.md) — 项目协作规则
3. [`docs/handoff/2026-08-17/00_START_HERE.md`](docs/handoff/2026-08-17/00_START_HERE.md) — 完整文档索引
4. [`docs/handoff/2026-08-17/09_GENERATED_DATA_AND_AUTHORITY_POLICY.md`](docs/handoff/2026-08-17/09_GENERATED_DATA_AND_AUTHORITY_POLICY.md) — 数据权限策略

---

## 远端状态

```
REMOTE CONSOLIDATION = COMPLETE

所有永久分支已推送到 origin:
  origin/main                          (含 SOL_HANDOFF.md)
  origin/codex/integration             (集成主控)
  origin/codex/maps                    (地图)
  origin/codex/monsters                (怪物)
  origin/codex/equipment               (装备)
  origin/codex/professions-skills      (职业技能)
  origin/codex/ui-art                  (UI/Art)

WIP Snapshot 分支 (备份，禁止 merge):
  origin/handoff/wip/maps-20260817
  origin/handoff/wip/integration-20260817
  origin/handoff/wip/professions-skills-20260817
  origin/handoff/wip/equipment-20260817
  origin/handoff/wip/monsters-20260817

Golden Tag:
  golden/apk-1.18.3-base-9d6435bc → 9d6435bc

当前各分支 tip SHA: see docs/handoff/2026-08-17/handoff_manifest.json
```

## 快速参考

```
Golden Tag:     golden/apk-1.18.3-base-9d6435bc
Godot:          tools/godot-4.7/Godot_v4.7-stable_win64.exe
Remote:         watermarkpp/HardCore (origin)
Main branch:    main (default), codex/integration (development)
Docs:           docs/handoff/2026-08-17/
Manifest:       docs/handoff/2026-08-17/handoff_manifest.json
```
