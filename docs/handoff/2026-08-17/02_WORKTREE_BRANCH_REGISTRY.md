# 02 — 工作树与分支清单

> 本文档列出 HardCore 仓库的全部 15 个工作树（6 个永久 + 9 个临时），
> 包含分支、HEAD、脏文件数、远端状态及用途说明。
>
> **注意**：dirty 数较大（580–618）的工作树，其脏文件主要是 Godot 重新导入产生的 `.png.import` 文件变更，并非实质性代码修改。

---

## 永久工作树（6 个）

### 1. HardCore — codex/integration
| 字段 | 值 |
|------|-----|
| **路径** | `HardCore`（主工作树） |
| **分支** | `codex/integration` |
| **HEAD** | `1e2927f7` |
| **Dirty Tracked** | 12 |
| **Untracked** | 271 |
| **远端** | 无 |
| **类型** | 永久 |
| **可移除** | 否 |
| **用途** | 集成主控：负责基线、跨系统接口、合并、冲突解决和完整验收；独占 `project.godot`、`AGENTS.md`、`scripts/game_root.gd`、`scripts/game_data.gd`、`scripts/region_content.gd`、存档格式、全局服务注册、跨系统测试入口 |

### 2. maps — codex/maps
| 字段 | 值 |
|------|-----|
| **路径** | `maps` |
| **分支** | `codex/maps` |
| **HEAD** | `668064fa` |
| **Dirty Tracked** | 98 |
| **Untracked** | 84 |
| **远端** | ✅ `origin/codex/maps` |
| **类型** | 永久 |
| **可移除** | 否 |
| **用途** | 地图系统：地图资源、环境目录/验证器、地图编辑器工具；负责 `assets/art/maps/`、`assets/maps/`、`map_editor_workspace/`、`scripts/map_*.gd`、`scripts/map_assets/`、`scripts/map_editor/` |

### 3. monsters — codex/monsters
| 字段 | 值 |
|------|-----|
| **路径** | `monsters` |
| **分支** | `codex/monsters` |
| **HEAD** | `4a7d1cd3` |
| **Dirty Tracked** | 1 |
| **Untracked** | 205 |
| **远端** | 无 |
| **类型** | 永久 |
| **可移除** | 否 |
| **用途** | 怪物系统：怪物/Boss 数据、外观、动画、AI、战斗行为；负责 `assets/art/monsters/`、`scripts/enemy.gd`、`scripts/monster_visual.gd` |

### 4. equipment — codex/equipment
| 字段 | 值 |
|------|-----|
| **路径** | `equipment` |
| **分支** | `codex/equipment` |
| **HEAD** | `5da60808` |
| **Dirty Tracked** | 581 |
| **Untracked** | 193 |
| **远端** | 无 |
| **类型** | 永久 |
| **可移除** | 否 |
| **用途** | 装备系统：物品/装备数据、外观、穿戴规则、耐久；负责 `assets/art/items/`、`scripts/equipment_rules.gd` |

### 5. professions-skills — codex/professions-skills
| 字段 | 值 |
|------|-----|
| **路径** | `professions-skills` |
| **分支** | `codex/professions-skills` |
| **HEAD** | `0e142450` |
| **Dirty Tracked** | 2 |
| **Untracked** | 198 |
| **远端** | 无 |
| **类型** | 永久 |
| **可移除** | 否 |
| **用途** | 职业与技能：职业成长、玩家技能、投射物、召唤物、职业公式、技能状态机/特效；负责 `scripts/profession_rules.gd`、`scripts/skill_projectile.gd`、`scripts/summon_actor.gd`、`scripts/warrior_combat_math.gd`、`assets/data/vanilla_176/skills.json`、`assets/data/vanilla_176/profession_growth.json` |

### 6. ui-art — codex/ui-art
| 字段 | 值 |
|------|-----|
| **路径** | `ui-art` |
| **分支** | `codex/ui-art` |
| **HEAD** | `ec02c08e` |
| **Dirty Tracked** | 616 |
| **Untracked** | 192 |
| **远端** | 无 |
| **类型** | 永久 |
| **可移除** | 否 |
| **用途** | UI 美术与面板：UI 素材、HUD、面板布局、角色预览；负责 `assets/ui/**`、`scripts/hud.gd`、`scripts/*_panel.gd`、`scripts/equipment_character_preview.gd` |

---

## 临时工作树（9 个）

### 7. visual-lab-frozen-20260730
| 字段 | 值 |
|------|-----|
| **路径** | `visual-lab-frozen-20260730` |
| **分支** | detached `99afded9` |
| **HEAD** | `99afded9` |
| **Dirty Tracked** | 616 |
| **Untracked** | 188 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | 否（frozen provenance — 冻结溯源用途） |
| **用途** | 视觉实验室冻结快照，用于溯源和对比基线 |

### 8. monster-classification-audit
| 字段 | 值 |
|------|-----|
| **路径** | `monster-classification-audit` |
| **分支** | `dsh/monster-runtime-r2r3` |
| **HEAD** | `62fafc5a` |
| **Dirty Tracked** | 0 |
| **Untracked** | 227 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | 待确认 |
| **用途** | 怪物分类审计（R2R3 轮次） |

### 9. monsters-combat-gu-final-audit
| 字段 | 值 |
|------|-----|
| **路径** | `monsters-combat-gu-final-audit` |
| **分支** | `codex/monsters-combat-gu-final-audit` |
| **HEAD** | `2ae9f914` |
| **Dirty Tracked** | 618 |
| **Untracked** | 236 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | 待确认 |
| **用途** | 怪物战斗 GU 最终审计 |

### 10. equipment-bronze-repair
| 字段 | 值 |
|------|-----|
| **路径** | `equipment-bronze-repair` |
| **分支** | `codex/equipment-bronze-repair` |
| **HEAD** | `a6960207` |
| **Dirty Tracked** | 617 |
| **Untracked** | 167 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | 待确认 |
| **用途** | 装备 Bronze 级修复 |

### 11. equipment-god-magic-236
| 字段 | 值 |
|------|-----|
| **路径** | `equipment-god-magic-236` |
| **分支** | `codex/equipment-god-magic-236` |
| **HEAD** | `b39eb972` |
| **Dirty Tracked** | 15 |
| **Untracked** | 171 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | 待确认 |
| **用途** | 装备神级/魔法级 236 项修复 |

### 12. equipment-prayer-224-directions
| 字段 | 值 |
|------|-----|
| **路径** | `equipment-prayer-224-directions` |
| **分支** | `codex/equipment-prayer-224-directions` |
| **HEAD** | `17c6a45b` |
| **Dirty Tracked** | 1 |
| **Untracked** | 0 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | 待确认 |
| **用途** | 装备祈祷级 224 方向修复 |

### 13. ui-single-ring-system
| 字段 | 值 |
|------|-----|
| **路径** | `ui-single-ring-system` |
| **分支** | `codex/ui-single-ring-system` |
| **HEAD** | `fd12bf52` |
| **Dirty Tracked** | 1 |
| **Untracked** | 202 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | 待确认 |
| **用途** | UI 单环系统重构 |

### 14. HardCore-runtime-audit
| 字段 | 值 |
|------|-----|
| **路径** | `HardCore-runtime-audit` |
| **分支** | detached `066e84f6` |
| **HEAD** | `066e84f6` |
| **Dirty Tracked** | 0 |
| **Untracked** | 0 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | ✅ **SAFE TO REMOVE** |
| **用途** | 运行时审计（已完成，无残留修改） |

### 15. HardCore-dsh-monsters-drop-audit
| 字段 | 值 |
|------|-----|
| **路径** | `HardCore-dsh-monsters-drop-audit` |
| **分支** | `dsh/monsters-drop-audit` |
| **HEAD** | `8808ebe3` |
| **Dirty Tracked** | 0 |
| **Untracked** | 0 |
| **远端** | 无 |
| **类型** | 临时 |
| **可移除** | ✅ **SAFE TO REMOVE** |
| **用途** | 怪物掉落审计（已完成，无残留修改） |

---

## 汇总统计

| 类别 | 数量 |
|------|------|
| 永久工作树 | 6 |
| 临时工作树 | 9 |
| **合计** | **15** |
| 有远端追踪 | 1（maps） |
| 可安全移除 | 2（#14, #15） |
| Frozen 不可移除 | 1（#7） |

## 清理建议

可立即安全移除的工作树：
```
git worktree remove HardCore-runtime-audit
git worktree remove HardCore-dsh-monsters-drop-audit
```

其余临时工作树需先确认其审计/修复任务是否已合并至对应永久工作树后再清理。
