# 永久工作树方案

## 目录与分支

| 用途 | 分支 | 永久工作树目录 |
| --- | --- | --- |
| 主整合 | `codex/integration` | `C:/Users/Administrator/Documents/HardCore` |
| UI 与 UI 美术 | `codex/ui-art` | `C:/Users/Administrator/Documents/HardCore-worktrees/ui-art` |
| 地图与环境 | `codex/maps` | `C:/Users/Administrator/Documents/HardCore-worktrees/maps` |
| 怪物与 Boss | `codex/monsters` | `C:/Users/Administrator/Documents/HardCore-worktrees/monsters` |
| 装备与物品 | `codex/equipment` | `C:/Users/Administrator/Documents/HardCore-worktrees/equipment` |
| 职业与技能 | `codex/professions-skills` | `C:/Users/Administrator/Documents/HardCore-worktrees/professions-skills` |

## 设计原则

- 专业工作树生产本领域内容，主整合区维护跨领域关系。
- UI 读取玩法数据但不改变玩法数据；地图提供刷新槽位但不定义怪物；怪物提供稳定 ID 但不定义装备；装备提供稳定 ID 但不决定怪物掉落。
- 职业与技能分支提供稳定技能/职业行为接口，但不负责技能和职业面板的视觉布局，也不直接改共享战斗运行时。
- 大型开发源素材和本地工具不复制进 Git，通过只读目录联接供各工作树使用。
- `.godot`、测试截图和导出产物由各工作树独立生成，避免缓存污染。

## 推荐施工顺序

1. 各专业工作树分别完成小而完整的垂直批次。
2. 专业分支提交并报告测试证据与跨系统需求。
3. 主整合区逐个合并：地图 → 怪物 → 装备 → 职业与技能 → UI。
4. 每次合并后运行专项测试和冒烟测试。
5. 全部接入后进行一次桌面与 Android 横屏视觉验收。

## 日常检查

```powershell
git worktree list
git status --short --branch
git branch --show-current
```

工作树不再使用时，先确认分支已提交，再从主整合区执行 `git worktree remove <路径>`。不要手动删除仍被 Git 登记的工作树目录。
