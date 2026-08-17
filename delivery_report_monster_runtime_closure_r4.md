# MONSTER RUNTIME CLOSURE R4 AUDIT REPORT

**日期**: 2026-08-18  
**分支**: `qwen/monster-runtime-closure-audit-r4-20260818`  
**基线**: `a2e9cb24` (origin/codex/integration)

---

## 关键数字

```
AUDIT_BASE = a2e9cb243b58aa33b50cce870e754901fb247595

ACTIVE_IDENTITY_COUNT = 214
RUNTIME_ALLOWED_COUNT = 39
RUNTIME_BLOCKED_COUNT = 175
VERSION_DIFFERENCE_COUNT = 3

ART_FORMAL_COUNT = 214
ART_UNRESOLVED_COUNT = 0

COMBAT_IDENTITY_MISSING = 11
COMBAT_STATS_INCOMPLETE = 0
AI_UNRESOLVED = 0
SPECIAL_RUNTIME_SEMANTICS = 0
DROP_MISSING = 10
TIMING_INCOMPLETE = 0
CLASSIFICATION_OR_POLICY_BLOCKED = 160
APPEARANCE_TRANSLATION_MISSING = 0

FALSE_WITH_ZERO_REASON_COUNT = 0

TIER_A_COUNT = 29
TIER_B_COUNT = 10
TIER_C_COUNT = 175
TIER_D_COUNT = 0

NEXT_RECOMMENDED_BATCH = R4A (classification resolution batch)
NEXT_RECOMMENDED_IDS = 见下方

BUSINESS_FILES_CHANGED = NO
READY_FOR_SOL_NEXT_BATCH_DECISION = YES
```

---

## 核心发现

### 为什么只有 39 个 runtime_allowed？

`runtime_allowed` 的 gate 公式：
```
runtime_allowed = art_ok AND classification_ok AND drop_ok AND combat_identity_ok
```

| Gate | 通过数 | 阻塞数 | 说明 |
|------|:---:|:---:|------|
| ART | 214 | 0 | ✅ 全部 formal |
| CLASSIFICATION | 54 | **160** | ⚠️ **主要瓶颈** |
| DROP | 204 | 10 | 10 个缺少 monitems 文件 |
| COMBAT IDENTITY | 203 | 11 | 11 个 unresolved_project_fallback |

**结论**: 160 个怪物的 classification 为 "unresolved"，是 runtime_allowed 的唯一大规模阻塞点。

### 各维度完成度

| 维度 | 完成 | 总数 | 比例 |
|------|:---:|:---:|:---:|
| ART (formal profile) | 214 | 214 | 100% |
| COMBAT STATS | 214 | 214 | 100% |
| AI (behavior profile) | 214 | 214 | 100% |
| TIMING | 214 | 214 | 100% |
| DROP | 204 | 214 | 95.3% |
| CLASSIFICATION | 54 | 214 | 25.2% |

### Blocker 频率（occurrence，非互斥）

| Blocker | 出现次数 |
|---------|:---:|
| classification_unresolved | 160 |
| combat_identity_unresolved | 11 |
| drop_incomplete (no_monitems_file) | 10 |
| version_difference_forces_placement_false | 3 |
| wooma_matrix_policy_override | 1 |

### Classification 分布

| 分类 | 数量 |
|------|:---:|
| unresolved | 160 |
| ordinary | 17 |
| elite | 14 |
| boss | 13 |
| special | 6 |
| version_difference | 3 |
| non_hostile | 1 |

---

## Tier 分类

### Tier A (29) — runtime_allowed, 无 deep blocker
已有完整运行时资格。IDs: 21, 24, 28, 30, 34, 38, 39, 56, 64-71, 73-76, 89, 120, 124, 156-160, 180

### Tier B (10) — runtime_allowed, 有 deep blocker
运行时已通过但缺少 behavior profile mapping。IDs: 18, 19, 26, 135-137, 141, 188, 191, 194

### Tier C (175) — blocked, 主要因 classification unresolved
需要 classification 决议后才能通过。这是下一批施工的主要目标。

### Tier D (0) — 无

---

## 下一批推荐: Batch R4A

**目标**: 解决 classification_unresolved 中最高置信度的子集

**优先条件**:
- classification 数据已存在于其他 source（如 canonical_monster_classification_v1.json）
- 只需 wiring，不需要新数据
- 同 root cause 可批量解决

**建议首批 10-20 个 ID**: 从 Tier C 中选择 classification 已有证据但未接入的怪物。

具体 ID 需查看 `outputs/audit/monster_runtime_closure_r4_matrix.json` 中各怪物的 `classification_evidence` 字段确定。

---

## 审计完整性验证

```
214 = 39 (allowed) + 175 (blocked) ✅
ART_UNRESOLVED = 0 ✅
FALSE_WITH_ZERO_REASON = 0 ✅
Retired 14/16/17 不在 214 active 中 ✅
```

---

## 输出文件

| 文件 | 说明 |
|------|------|
| `outputs/audit/monster_runtime_closure_r4_matrix.json` | 逐 214-ID 完整矩阵 (344 KB) |
| `outputs/audit/monster_runtime_closure_r4_summary.json` | 机器可读统计摘要 |
| `outputs/audit/build_matrix.py` | 可重放的审计脚本 |
| `delivery_report_monster_runtime_closure_r4.md` | 本报告 |
