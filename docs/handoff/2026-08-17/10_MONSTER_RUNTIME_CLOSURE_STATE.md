# 怪物 Runtime Closure 状态

> 生成日期: 2026-08-17

---

## Golden 运行时怪物

| 指标 | 数值 |
|------|------|
| **全量校准数量** | 214 只 |
| **foot_anchor** | ✅ 完整 |
| **ground_contacts** | ✅ 完整 |
| **overhead_anchors** | ✅ 完整 |
| **manual_alignment** | ✅ 完整 |

### 投射策略分布

| 类型 | 数量 |
|------|------|
| grounded | 202 |
| flying | 9 |
| hover | 3 |

---

## Post-Golden canonical identity

| 指标 | 数值 |
|------|------|
| **canonical_monster_catalog.json 总条目** | 217 条 |
| **Golden 校准覆盖** | 214 条 |
| **后续添加** | 3 条 |

---

## 当前闭环状态

| 状态 | 说明 |
|------|------|
| **runtime-ready** | 大部分怪物已完成闭环 |
| **not-ready** | 需检查 `ART_MAPPING_MISSING` 的怪物 |

---

## ART_MAPPING_MISSING 解释

### 核心判断

当 Golden art/animation 已被证明存在时，`ART_MAPPING_MISSING` 优先解释为 **authority wiring 问题**，**不是美术缺失**。

### 检查方向

1. **`build_canonical_monster_catalog.py` 的 art source 路由逻辑**
   - 检查脚本是否正确读取了手工校准的 art source 文件
   - 检查路由条件是否遗漏了某些 monster_id 分支

2. **monster_id → appearance 映射是否正确连接**
   - 确认 canonical catalog 中的 monster_id 与 art source 中的 ID 完全匹配
   - 检查是否存在 ID 拼写错误或格式不一致

3. **不要建议重新做美术**
   - Golden 已确认 214 只怪物的美术资源完整存在
   - 问题在于构建脚本未能找到/连接这些资源，而非资源本身缺失

---

## 其他 blocker 分类

| 分类标签 | 含义 | 说明 |
|---------|------|------|
| `COMBAT_IDENTITY` | 战斗身份匹配 | 怪物的战斗身份（职业/类型标识）需要与运行时对齐 |
| `COMBAT_STATS` | 战斗数值 | 怪物的战斗属性（HP、攻击、防御等）需要确认/校准 |
| `AI` | 行为逻辑 | 怪物的 AI 行为模式需要实现或修复 |
| `SPECIAL_RUNTIME` | 特殊运行时 | 特殊怪物（如 Boss）需要专属运行时逻辑 |
| `DROP` | 掉落表 | 怪物掉落物品表需要配置或验证 |
| `TIMING` | 时序参数 | 动画时序、攻击间隔等时间相关参数需要校准 |

---

## 闭环优先级

```
ART_MAPPING_MISSING (P0 — authority wiring)
    ↓ 解决后
COMBAT_IDENTITY / COMBAT_STATS (战斗完整性)
    ↓
AI / SPECIAL_RUNTIME (行为完整性)
    ↓
DROP / TIMING (内容完整性)
```

首先解决 authority wiring 问题，使 canonical catalog 能正确路由到已有 art；然后逐步处理战斗、行为、内容层面的 blocker。
