# 生成数据与权限策略

> 生成日期: 2026-08-17

---

## 数据权限分类

### 1. HAND-AUTHORED authority（手工权威）

以下文件由人工编写/校准，是数据的最终权威来源，**禁止由脚本覆盖**：

| 文件 | 说明 |
|------|------|
| `source_priority_policy.json` | 来源优先级总表 |
| `equipment_attribute_master.json` | 装备属性主表 |
| `bich_common_client_art_sources.json` | 22 只怪物手工校准 |
| `bich_undead_client_art_sources.json` | 11 只怪物手工校准 |
| `classic_boss_client_art_sources.json` | 6 条 Boss 手工校准 |
| `vanilla_176/monsters.json` | 原始 1.76 怪物数据 |
| `vanilla_176/skills.json` | 原始技能数据 |

### 2. GENERATED（生成物，禁止手改）

以下文件由脚本自动生成，**禁止手工修改**，需要更新时重新运行对应脚本：

| 生成文件 | 生成脚本 |
|---------|---------|
| `complete_monster_client_art_sources.json` | `tools/build_complete_monster_client_art.py` |
| `runtime/monster_animation_catalog.json` | `tools/build_monster_animation_catalog.py` |
| `runtime/monster_ground_contacts.json` | `tools/build_monster_ground_contacts.py` |
| `runtime/monster_ground_contact_calibrations.json` | `tools/build_monster_ground_contacts.py`（同上） |
| `runtime/monster_overhead_anchors.json` | `tools/build_monster_overhead_anchors.py` |
| `runtime/monster_ground_alignment_manual_v1.json` | `tools/import_monster_ground_alignment_drafts.py` |
| `runtime/canonical_monster_catalog.json` | `tools/build_canonical_monster_catalog.py` |

### 3. APK/PCK 权限

| 规则 | 说明 |
|------|------|
| **Verification authority ONLY** | APK/PCK 仅用于验证运行时行为是否与源码一致 |
| **NOT source authoring authority** | APK/PCK **不是**源码的数据来源 |
| **禁止从 APK 反哺源码** | 不得将 APK 中提取的数据写回源码或数据文件 |

### 4. monster_id 规则

| 规则 | 说明 |
|------|------|
| **稳定 ID，禁止重编号** | monster_id 一旦分配即为永久标识，任何情况下不得重新编号 |
| **name fallback 不得成为持久 identity** | 当名称仅作为 fallback 出现时，不得将其固化为怪物的正式身份标识 |

---

## 权限层级总结

```
HAND-AUTHORED (最高权威)
    ↓ 驱动
GENERATED (自动派生，禁止手改)
    ↓ 验证
APK/PCK (仅用于校验，禁止反哺)
```

- 手工权威 → 生成脚本 → 运行时数据 → APK 验证
- 任何反向流动（APK → 源码、生成物 → 手工权威）均严格禁止
