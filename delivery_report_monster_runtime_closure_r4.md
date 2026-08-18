# MONSTER RUNTIME CLOSURE R4 AUDIT — CORRECTED METHODOLOGY

**日期**: 2026-08-18
**分支**: `qwen/monster-runtime-closure-audit-r4-20260818`
**基线**: `a2e9cb243b58aa33b50cce870e754901fb247595`
**历史审计 commit**: `eacd70df`（保留为历史，判定方法被驳回）
**本 commit**: correction commit（方法学修正，不改任何业务源码）

> ⚠️ **驳回修正声明**：`eacd70df` 的 R4 审计使用了被驳回的浅层代理判定
> （`field != None => complete`、`resolution_status != unresolved => resolved`、
> `attack_interval_ms != None => complete`、用 blocker 数量/runtime_allowed 定义 Tier、
> classification blocker 遮住其他 blocker）。本报告用**源权威（source authority）逐字段、
> 逐 ID、独立多标签**的方法全部重算。所有数字与 `eacd70df` 不可比，且大部分被推翻。

---

## 0. 最终报告指标（必需清单）

```
AUDIT_BASE = a2e9cb243b58aa33b50cce870e754901fb247595

ACTIVE_IDENTITY_COUNT        = 214
RUNTIME_ALLOWED_COUNT        = 39
RUNTIME_BLOCKED_COUNT        = 175
UNRESOLVED_STATUS_COUNT      = 172
VERSION_DIFFERENCE_COUNT     = 3
VERSION_DIFFERENCE_IDS       = [41, 78, 225]

ART_FORMAL_COUNT             = 214

COMBAT_IDENTITY_MISSING      = 70
COMBAT_STATS_INCOMPLETE      = 70
AI_UNRESOLVED                = 70
TIMING_INCOMPLETE            = 70
DROP_MISSING                 = 9
DROP_AUTHORITY_BLOCKED       = 203
CLASSIFICATION_UNRESOLVED    = 160
CLASSIFICATION_OR_POLICY_BLOCKED = 4      # [41, 77, 78, 225]
SPECIAL_RUNTIME_SEMANTICS    = 69
APPEARANCE_TRANSLATION_MISSING = 55
ART_UNRESOLVED               = 0

FALSE_WITH_ZERO_REASON_COUNT = 0

CURRENT_GATE_OCCURRENCES     = 175        # runtime_allowed=false 的 ID 数
DEEP_CLOSURE_OCCURRENCES     = 213        # 至少携带 1 个独立 closure blocker 的 ID 数
PRIMARY_BLOCKER_COUNT        = 780        # 全部独立 blocker 标签的总出现次数(多标签)

TIER_A_COUNT = 11   IDS = [38, 39, 64, 65, 67, 68, 69, 71, 74, 137, 194]
TIER_B_COUNT = 8    IDS = [57, 77, 90, 107, 108, 121, 142, 192]
TIER_C_COUNT = 192
TIER_D_COUNT = 3    IDS = [41, 78, 225]

EXISTING_CLASSIFICATION_AUTHORITY_NOT_WIRED_COUNT = 0

NEXT_RECOMMENDED_BATCH = 0   (无纯 wiring-only Tier A 候选，见 §9 如实说明)
NEXT_RECOMMENDED_IDS   = []

ID_SET_COMPARISON = EQUAL_WITH_DOCUMENTED_AIRBORNE_EXCLUSION

BUSINESS_FILES_CHANGED = NO
READY_FOR_SOL_NEXT_BATCH_DECISION = YES
```

**恒等式校验（两条投影独立验证，均成立）**：
```
status-based: 214 == RUNTIME_ALLOWED(39) + UNRESOLVED_STATUS(172) + VERSION_DIFFERENCE(3)  ✅
gate-based:   214 == RUNTIME_ALLOWED(39) + RUNTIME_BLOCKED(175)                              ✅
```
> 注意：旧报告只验证了 `214 = allowed + blocked`。修正版同时验证 status-based 三分解，
> 其中 `UNRESOLVED_STATUS_COUNT=172`（entry.status==unresolved）≠ `RUNTIME_BLOCKED_COUNT=175`
> （runtime_allowed==false）。二者是不同投影，差值 3 = version_difference（status 单列）。

---

## 1. Combat Stats —— 逐字段 value/source/tier/resolution

**修正**：禁止 `field != None => complete`。逐字段审 value + source evidence + source tier + resolution。
生成器对缺失 `exact_service_name` 的 ID 生成的 **zeroed placeholder 判为 UNRESOLVED**，
除非该字段被正式 auxiliary authority 覆盖。

判定规则（`combat_stats_field_resolution`，每 ID 7 字段）：
- `role==combat_auxiliary_override` → **resolved_auxiliary_1**（正式 auxiliary 权威覆盖）
- evidence 含 `exact_service_name row missing; unresolved` → **unresolved_zeroed_placeholder**
- `role==combat_stats_primary_service` 且 evidence 含 `.serviceRecord.` → **resolved_primary**

结果：
| 判定 | ID 数 | 说明 |
|------|:---:|------|
| COMBAT_STATS_COMPLETE（7 字段全 resolved） | 144 | 142 exact_service_name + 2 auxiliary_1（68/69） |
| COMBAT_STATS_INCOMPLETE（7 字段全 zeroed placeholder） | 70 | 55 unresolved_project_fallback + 15 base_name_fallback |

- 68/69（沃玛战将）：7 字段全部 `resolved_auxiliary_1`，源 `source.angelk727.mir2_server_databases`，
  tier=auxiliary_1 —— 正式 auxiliary authority 覆盖，判 **COMPLETE**。
- 70 个非 allowlist ID：7 字段全部 zeroed placeholder，判 **UNRESOLVED**（旧报告误判 COMBAT_STATS_INCOMPLETE=0）。
- 关键：判定**只看源权威，不看数值**。例如 ID 21（稻草人）defense=0、magic_defense=0 是真实
  service 值（`resolved_primary`），不因数值为 0 而判 UNRESOLVED；反之 70 个 placeholder 即使非 0 也判 UNRESOLVED。

`COMBAT_STATS_INCOMPLETE = 70`

---

## 2. AI —— allowlist fail-closed

**修正**：禁止 `resolution_status != "unresolved" => resolved`。建立明确 allowlist，其余全部 fail closed。

**AI_RESOLUTION_ALLOWLIST = { `exact_service_name`, `auxiliary_1_exact_row` }**
（`base_name_fallback`、`unresolved_project_fallback`、空值 一律 fail closed —— base_name_fallback
虽是真实 service 行，但属 name-derived 匹配，不是 exact-ID 权威，只能在 Tier B 作"需确认"证据。）

AI resolution_status 分布（214）：
| resolution_status | 数量 | allowlist? |
|------|:---:|:---:|
| exact_service_name | 142 | ✅ |
| auxiliary_1_exact_row | 2 | ✅ |
| base_name_fallback | 15 | ❌ fail-closed |
| unresolved_project_fallback | 55 | ❌ fail-closed |

`AI_UNRESOLVED = 70`（15 + 55；旧报告误判 AI_UNRESOLVED=0）

---

## 3. Timing —— source authority，不看数值大小

**修正**：禁止 `attack_interval_ms != None && move_interval_ms != None => complete`。
同时审 value + source + tier + resolution/confidence。由 unresolved service fallback 生成的
2500/1800 默认值**不算 authority**。**不以数值 >0 判定**（stationary/special 怪可合法为 0）。

Timing 权威完全跟随 AI resolution allowlist（同一 service 行派生）：
| timing source | tier | 数量 | authority_complete |
|------|------|:---:|:---:|
| primary_service_record（exact） | primary | 142 | ✅ |
| auxiliary_1_exact_row_override | auxiliary_1 | 2 | ✅ |
| base_name_fallback_service_record | primary_name_derived_fail_closed | 15 | ❌ |
| unresolved_project_fallback_default（2500/1800, confidence C） | project_fallback | 55 | ❌ |

`TIMING_INCOMPLETE = 70`（旧报告误判 TIMING_INCOMPLETE=0）

---

## 4. Blocker —— 全部独立计算，真多标签

**修正**：即使 `classification == unresolved`，也独立检查全部 blocker；禁止 classification blocker
遮住其他 blocker。每个 ID 携带完整的独立 blocker 标签集合（`deep_closure_blockers`）。

| Blocker | 出现次数 |
|---------|:---:|
| COMBAT_IDENTITY_MISSING | 70 |
| COMBAT_STATS_INCOMPLETE | 70 |
| AI_UNRESOLVED | 70 |
| TIMING_INCOMPLETE | 70 |
| DROP_MISSING | 9 |
| DROP_AUTHORITY_BLOCKED | 203 |
| CLASSIFICATION_UNRESOLVED | 160 |
| CLASSIFICATION_OR_POLICY_BLOCKED | 4 |
| SPECIAL_RUNTIME_SEMANTICS | 69 |
| APPEARANCE_TRANSLATION_MISSING | 55 |
| ART_UNRESOLVED | 0 |
| **PRIMARY_BLOCKER_COUNT（总标签数）** | **780** |

- `CURRENT_GATE_OCCURRENCES = 175`（当前 gate 下 runtime_allowed=false）。
- `DEEP_CLOSURE_OCCURRENCES = 213`（只有 ID 194 恶魔弓箭手 0 个 deep blocker）。
- `FALSE_WITH_ZERO_REASON_COUNT = 0`（每个 runtime_allowed=false 都有明确 gate 原因）。
- 例：ID 143（石墓尸王）classification 已 resolved(boss)，但仍独立携带
  `COMBAT_IDENTITY_MISSING, COMBAT_STATS_INCOMPLETE, AI_UNRESOLVED, TIMING_INCOMPLETE,
  DROP_AUTHORITY_BLOCKED, SPECIAL_RUNTIME_SEMANTICS, APPEARANCE_TRANSLATION_MISSING` 七个 blocker
  —— classification 不再遮挡其它维度。

---

## 5. Drop Authority —— item_resolution_status，分离 MISSING / AUTHORITY_BLOCKED

**修正**：检查正式字段 `item_resolution_status`（含 `unresolved_token` 及其它 unresolved 状态），
不再只看 item/item_id/item_token/slot_status。**分别输出** DROP_MISSING 与 DROP_AUTHORITY_BLOCKED。

- `DROP_MISSING`：无 drop 行且无 confirmed exemption。
- `DROP_AUTHORITY_BLOCKED`：有 drop 行但 `item_resolution_status` 为 unresolved。
  → **有 drop rows 但 item authority unresolved 的怪：DROP_MISSING=NO, DROP_AUTHORITY_BLOCKED=YES。**

Drop profile 状态（214）：
| profile status | 数量 | 说明 |
|------|:---:|------|
| exact_slots（Excel 用户权威槽位） | 203 | 全部行 item_resolution_status=unresolved_token |
| no_drop_confirmed | 1 | ID 33 |
| no_monitems_file | 10 | 其中 ID 194 有正式 exemption |

结果：
- `DROP_AUTHORITY_BLOCKED = 203`（203 个 exact_slots 的 item token 全部 unresolved）。
- `DROP_MISSING = 9`：no_monitems_file 共 10 个，扣除 ID 194（non_hostile_guard_or_script_object 正式豁免）。
  旧报告 DROP_MISSING=10 未处理豁免，修正为 9。IDs = [49 掷斧骷髅9, 59 骷髅精灵9, 78 沃玛教主9,
  161 祖玛教主9, 183 爆裂蜘蛛, 184 爆裂蜘蛛0, 186 鹰卫, 187 虎卫, 241 飞火流星]。

**Item token 权威覆盖**（用于 Tier 判定，见 §7）：token 与仓库内 item authority 匹配
（equipment_attribute_master 175 件 + service_item_catalog 538 件 + 金币）：
- 241 个不同 drop token 中，217 个有 item authority，**24 个无任何 item authority**（1147 行），
  主要为各类神水/药水（HP强化水、强效金创药、攻击神水…）、材料（毒蜘蛛牙齿、蝎子的尾巴、食人树叶…）、
  篮翡翠项链/铂金项链、群体治愈术。
- 因此 203 个 exact_slots 中：87 个 token 全部有 item authority（wireable），116 个含无权威 token。

---

## 6. Special Runtime —— 逐 ID 真审

**修正**：逐 ID 检查现有 boss_rule / behavior_profile / runtime special semantics。只有 source 明确
证明"不需要特殊 runtime"或"所需 special semantics 已正式实现/映射"，才判 SPECIAL_RUNTIME_COMPLETE=YES。
**禁止因脚本没检查就统计为 0**（旧报告 SPECIAL_RUNTIME_SEMANTICS=0 属漏检）。

检测到的 special semantics（area/ranged、summon、teleport、burrow、stationary、spawn/minion 等）：
| semantic | IDs |
|------|------|
| area_attack | 180, 195 |
| ranged_or_area_attack_range | 70, 71, 124, 150, 151, 152, 180, 195, 206, 207, 220, 221, 222, 223 |
| summon | 126, 182 |
| summoned_minion | 127, 170 |
| stationary | 30, 124, 126, 180, 182, 195 |
| dormant_wake | 153, 154, 155, 156, 157, 158, 159, 160 |
| on_hit_effect（poison/control） | 120, 121, 122, 123, 124, 128, 168, 169 |
| life_steal | 193, 222, 223 |
| large_client_boss | 56, 76, 89, 124, 160 |
| collision_exception（飞行/无碰撞） | 43, 44 |
| service_class_mapping | 126, 180, 182, 195 |
| special_classification | 30, 124, 126, 180, 182, 195 |

boss_rule 特殊技能裁决（boss_service_rules.json，含 original_gameofmir 源码证据）：
- 56/89：specialSkill.enabled=false（标准 TATMonster，源码未发现专属技能）→ 证明无需特殊技能。
- 76：specialSkill.enabled=false（狂暴/受困传送由 mechanics 状态机处理）。
- 160：specialSkill.enabled=false（普通魔法攻击 + 血量阶段触发召唤）。
- 124（触龙神）：specialSkill.enabled=true，完整 circle/area 参数（confidence A）→ 已正式映射。
- **teleport**：未发现独立 teleport special 语义（76 的传送已由状态机映射），不产生额外 blocker。

结果：`SPECIAL_RUNTIME_SEMANTICS = 69`（fail-closed：无 allowlist service/boss-rule 权威、又无
authored special 语义可证明"不需要特殊 runtime"的 ID）。其中 ID 195（千年树妖）虽
unresolved_project_fallback，但 behavior profile 以 confidence A 的 service_class_mapping 正式映射了
area_attack/stationary，special runtime 判 complete；这 69 个是真正无法证明的。

---

## 7. Tier —— 恢复原始权威定义

**修正**：禁止用 `runtime_allowed / blocker 数量` 定义 Tier。恢复权威定义：
- **Tier A**：现有正式 authority 已存在，只是 exact-ID wiring 没接上；**不需要用户决定**。
- **Tier B**：authority/source 存在，但映射或语义需要确认。
- **Tier C**：真正缺 authority，需要新资料或用户决定。
- **Tier D**：version_difference 或 intentional exclusion。**所有 version_difference 至少进 Tier D。**

Tier 由各 facet（combat / classification / policy_placement / drop / special_runtime /
appearance_translation）的权威状态取最坏值决定（MISSING→C，CONFIRM→B，WIREABLE/OK→A）。

| Tier | 数量 | IDs |
|------|:---:|------|
| A | 11 | 38, 39, 64, 65, 67, 68, 69, 71, 74, 137, 194（全部已 runtime_allowed，authority 完整） |
| B | 8 | 57, 77, 90, 107, 108, 121, 142, 192 |
| C | 192 | 真正缺 authority（classification 160 / combat 70 / drop item 权威缺口），需新资料或用户决定 |
| D | 3 | 41, 78, 225（version_difference） |

> 与旧报告对比：旧 Tier 用 runtime_allowed+blocker 数量定义（A=29/B=10/C=175/D=0），被驳回。
> 修正后 Tier D 首次正确收录 3 个 version_difference；Tier A 收敛到"authority 完整"的 11 个已接入 ID；
> **无任何 blocked ID 是纯 wiring-only 的 Tier A**（原因见 §9）。

---

## 8. Classification —— 逐 ID 审 evidence（160 个 unresolved）

**修正**：对 160 个 unresolved 逐个检查已有正式 source / historical evidence，输出
classification_evidence / classification_source / classification_source_tier / classification_resolution，
再真正划分，**不再笼统写 "classification unresolved = 160"**。

分类策略（canonical_monster_classification_v1.json）：`visibleName exact canonical name, unique only;
no base-name, suffix trim, or alias` —— 禁止 name join / 后缀裁剪 / 别名。

160 个 unresolved 的 evidence 划分：
| bucket | 数量 | 含义 |
|------|:---:|------|
| EXISTING_AUTHORITY_NOT_WIRED | **0** | 无任何"权威已存在、只差 wiring"的 ID |
| SOURCE_PRESENT_NEEDS_CONFIRMATION | 19 | 有 vanilla_176/bosses.json ID-keyed 参考证据，但 confidence C/待判定，需用户 exact-ID 确认 |
| TRUE_AUTHORITY_MISSING | 141 | 名称不在用户附件 nameRules、无 policy、无 ID-keyed 参考 → 真缺权威 |

`EXISTING_CLASSIFICATION_AUTHORITY_NOT_WIRED_COUNT = 0`
`CLASSIFICATION_UNRESOLVED = 160`；`CLASSIFICATION_OR_POLICY_BLOCKED = 4`（[41, 77, 78, 225]）。

19 个 SOURCE_PRESENT_NEEDS_CONFIRMATION（ID, 名, bosses.json bossClass, confidence, AI 状态）：
```
57 骷髅精灵1  Boss    C  exact_service_name
59 骷髅精灵9  Boss    C  exact_service_name
90 尸王1      Boss    C  exact_service_name
91 尸王2      Boss    C  exact_service_name
107 巨型多角虫 精英/准Boss B exact_service_name
108 巨型多角虫1 精英/准Boss C exact_service_name
121 邪恶钳虫1 精英/准Boss C exact_service_name
122 邪恶钳虫2 精英/准Boss C exact_service_name
123 邪恶钳虫9 精英/准Boss C exact_service_name
142 邪恶毒蛇1 精英/准Boss C exact_service_name
161 祖玛教主9 Boss    C  exact_service_name
164 血巨人    精英/准Boss B exact_service_name
165 血巨人0   精英/准Boss C exact_service_name
192 虹魔蝎卫0 精英/准Boss C base_name_fallback
209 黄泉教主0 Boss    C  unresolved_project_fallback
236 暗之双头金刚 重装Boss B unresolved_project_fallback
237 暗之黄泉教主 重装Boss B unresolved_project_fallback
238 暗之骷髅精灵 重装Boss B unresolved_project_fallback
240 暗之虹魔教主 重装Boss B unresolved_project_fallback
```

---

## 9. NEXT_RECOMMENDED_IDS —— 如实报告（0 个纯 Tier A）

**结论：`NEXT_RECOMMENDED_IDS = []`，`NEXT_RECOMMENDED_BATCH = 0`。**

逐 ID 核查后，**不存在任何一个 blocked monster 满足 Tier A（authority 已齐、只差 wiring、无需用户决定）**：
- 160 个 classification unresolved：分类策略禁止 name join / 后缀裁剪，用户附件仅对 56 个 exact-ID
  授权（51 个 active resolved + 部分 version_difference）。其余变体名（骷髅战士0、僵尸1、多钩猫0…）
  在用户权威中**没有 exact-ID 授权**，wiring 无法在"无需用户决定"的前提下进行 → 非 Tier A。
- 70 个无 service allowlist 行：combat identity/stats/AI/timing 无权威 → 需新资料 → 非 Tier A。
- drop：即便 token 全部有 item authority（87 个 wireable），这些 ID 仍被上面两条之一阻塞。

**因此如实报告 0 个**（规则允许"如找不到 10 个真正 Tier A，就如实少于 10 个"）。不使用
"从 Tier C 再选择 / 见 matrix / 后续确定"之类的回避表述。

### 最接近可施工的是 Tier B（8 个），但每个都差一次用户决定：
| ID | 名 | 已具备 | 缺的一次用户决定 |
|:---:|------|------|------|
| 57 | 骷髅精灵1 | combat allowlist + drop wireable | classification exact-ID 确认 |
| 90 | 尸王1 | combat allowlist + drop wireable | classification exact-ID 确认 |
| 107 | 巨型多角虫 | combat allowlist + drop wireable | classification exact-ID 确认 |
| 108 | 巨型多角虫1 | combat allowlist + drop wireable | classification exact-ID 确认 |
| 121 | 邪恶钳虫1 | combat allowlist + drop wireable | classification exact-ID 确认 |
| 142 | 邪恶毒蛇1 | combat allowlist + drop wireable | classification exact-ID 确认 |
| 192 | 虹魔蝎卫0 | drop wireable（combat base_name 需确认） | classification + combat 确认 |
| 77 | 沃玛教主1 | combat/classification/drop/special 全 OK | policy placement_allowed=false 需用户裁决 |

> **下一批的真正形态不是 wiring 批，而是"用户决定批"**：对上述 Tier B 做 exact-ID 分类/政策裁决后，
> 57/90/107/108/121/142（combat allowlist + drop wireable）即可转为可 wiring。真正缺权威的是
> 141 个 TRUE_AUTHORITY_MISSING 变体与 70 个无 service 行 ID，需要新资料。

---

## 10. 完整性检查与 Golden ID 集合

```
ACTIVE_ID_SET 大小 = 214
GOLDEN_VALIDATED_ID_SET 来源（5 个 golden 数据文件）:
  monster_animation_catalog.json               214  == active ✅
  monster_ground_contacts.json                 214  == active ✅
  monster_ground_contact_calibrations.json     214  == active ✅
  monster_overhead_anchors.json                214  == active ✅
  monster_ground_alignment_manual_v1.json      212  (+ 2 airborne)
ID_SET_COMPARISON = EQUAL_WITH_DOCUMENTED_AIRBORNE_EXCLUSION
```
manual alignment 为 212，是因为 2 个 airborne ID 按 golden 权威文档（03_GOLDEN_RUNTIME_AUTHORITY.md
"212 (+ 2 airborne)"）本就无地面对齐条目，属**文档化排除**，非身份不一致。

其它完整性：
```
FALSE_WITH_ZERO_REASON_COUNT = 0     ✅（无 runtime_allowed=false 却无原因）
retired 14/16/17 不在 214 active 中  ✅
status-based 三分解恒等式成立        ✅
gate-based 二分恒等式成立            ✅
```

---

## 11. 输出文件

| 文件 | 说明 |
|------|------|
| `outputs/audit/monster_runtime_closure_r4_matrix.json` | 逐 214-ID 完整矩阵：含 classification_evidence、combat_stats_field_resolution（逐字段 value/source/tier/resolution）、ai_evidence、timing_evidence、drop_item_resolution_summary、special_runtime_evidence、tier_facets、tier_reason、current_gate_blockers、deep_closure_blockers、runtime_blocked_reason |
| `outputs/audit/monster_runtime_closure_r4_summary.json` | 机器可读统计摘要（含全部必需指标、恒等式、ID 集合对比、Tier 名单、NEXT_RECOMMENDED、READY_FOR_SOL_NEXT_BATCH_DECISION） |
| `outputs/audit/build_matrix.py` | 可重放的 audit-only 审计脚本（只读数据源，不改业务源码） |
| `delivery_report_monster_runtime_closure_r4.md` | 本报告 |

---

## 12. 结论

- **39 个 runtime_allowed**；其中只有 11 个 authority 完整（Tier A，全部已接入），其余 28 个虽被 gate
  放行，但 drop item 权威仍有缺口（deep closure 未闭合）。
- **唯一真正"零 blocker"的是 ID 194（恶魔弓箭手）**。
- **主要瓶颈是 classification（160 unresolved）与 combat authority（70 无 service 行）**，两者都**不是
  wiring 能解决的**，而是需要用户 exact-ID 决定或新权威资料。
- 修正后没有任何"纯 wiring 即可接入"的 Tier A 候选；下一批应定位为**用户决定批**（先清 Tier B 的 8 个，
  再处理 19 个 SOURCE_PRESENT 参考与 141 个 TRUE_AUTHORITY_MISSING）。

**BUSINESS_FILES_CHANGED = NO**
**READY_FOR_SOL_NEXT_BATCH_DECISION = YES**
