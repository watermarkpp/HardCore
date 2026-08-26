# Monster → 地图布怪正式交接说明

**用途**：供后续 Codex / DeepSeek 在地图编辑器 / Map Runtime 中安全布置怪物，绝不修改 Monster 底层。
**基线**：`codex/integration` @ `7409b5da`（Monster Final Closure merge `6173e946` 为 ancestor，其后无 Monster Production 修改）。

---

## 1. Monster 最终状态

```
MONSTER SYSTEM = 100% CLOSED
MONSTER SYSTEM = FROZEN
MONSTER SYSTEM = PRODUCTION-READY
```

正式范围：

```
canonical identity     = 156
runtime_allowed        = 153
intentionally excluded = 3（33 / 183 / 241 —— 不得恢复、不得算 missing、不得重新加入 runtime_allowed）
```

Closure 状态：

```
MFC-1 属性/移动/攻击时序   = CLOSED
MFC-2 动画/远程/特殊机制   = CLOSED
MFC-3 自然回血             = CLOSED
MFC-4 respawn 权威+持久化  = CLOSED
MFC-4F 正式策略迁移        = CLOSED
MFC-5 Final Zero-Gap Gate  = PASS（identity/attribute/movement/attack/animation/ranged/special/regen/respawn/drop/map-runtime blockers 全 0，legacy_paths=0，unknown_fallbacks=0，engine_log_errors=0）
```

---

## 2. MONSTER FREEZE RULE

除非出现**可稳定复现的新 Monster Production Bug**（且单独立项打开对应 Closure），否则地图制作任务**禁止修改**：

```
Enemy / GameData Monster / Canonical Monster Catalog / Monster Identity Contract
behavior profile / movement / attack timing / animation profile / visual mapping
ranged attack runtime / special mechanics / natural regen / respawn resolver
drop runtime / classification / alias-fallback 规则
```

禁止行为：

```
顺手重构 Enemy、统一字段、清理 Legacy、优化 Monster AI
修改移动速度 / 攻击速度 / Boss 技能 / 回血 / 刷新时间 / 掉落
新增 name fallback、根据中文名称猜 monster_id
```

---

## 3. 地图布怪允许修改的范围

只允许修改**地图侧**数据：

```
地图 monster spawn 数据 / spawn group / spawn region / spawn count
地图中的 monster_id 引用 / 对应 respawn_policy_id
Boss / Elite 的地图位置 / spawn coverage / spawn density
safe area avoidance / door landing avoidance / walkable placement
地图 Runtime / Editor 对应的地图内容数据
```

任务说"给这张地图布怪"→ 只改地图数据，绝不碰 Monster Production。

---

## 4. monster_id 使用规则

正式链：

```
Map Spawn → monster_id → Canonical Monster → GameData → Enemy
```

**必须**使用正式整数 `monster_id`；**禁止** display_name 作身份、中文名称查怪、去后缀 fallback、alias fallback、近似名称、自动创建新 monster_id。

用户给中文名时：名称 → 查正式 canonical `monster_id`（`GameData.canonical_monster_id`）→ 确认唯一匹配 → 再写地图。找不到唯一正式 ID → **STOP 并报告**，不得猜。

---

## 5. respawn_policy_id 使用规则

正式链（MFC-4F 后）：

```
runtime.semantics.monster_spawn → respawn_policy_id
→ MapEditorRuntimeBridge → content.spawns top-level
→ GameRoot → MonsterRespawnPolicy.resolve()
```

正式普通怪**不再依赖** `legacy_seconds_tier_migration`。Gate：`formal ordinary requiring authored policy = 0`。

地图布怪时**必须**显式填写合法 `respawn_policy_id`，不得按历史 `respawn_seconds` 数字自行推导分类。

---

## 6. 当前刷新策略（以 MonsterRespawnPolicy 代码为准）

普通怪三档 map spawn policy：

```
beginner_outdoor = 300s
normal_cave      = 480s
special_normal   = 900s
```

Elite / Boss 由 canonical classification 自动锁定（地图填写普通 policy 也不会降级）：

```
elite -> 1800s
boss  -> 3600s
```

`random_seconds` 已被退役为 0。`respawn_seconds` 兼容字段仍可读，但**不是权威**。

---

## 7. Boss / Elite 特殊规则

Boss / Elite 不得被地图普通策略降级。最终仍走：

```
MonsterRespawnPolicy.resolve(policy_id, classification, legacy)
```

Boss classification → canonical override（3600）；Elite classification → canonical override（1800）。地图作者填写 `beginner_outdoor` / `normal_cave` 不会改变 Boss/Elite 刷新时间（resolver 自动 override，已由 `monster_respawn_policy_test` 锁定）。

---

## 8. 旧正式地图 Editor / Runtime 特殊状态

以下 5 张正式 playable 地图存在：

```
CURRENT AUTHORING TRANSITION DEBT
editor.json (schema 4) monster_spawn = 0
而 runtime.json 存在正式 monster spawn（当前 approved 权威）
```

| map_id | map_key | runtime monster_spawn |
|---|---|---|
| 4 | bich_province | 43 |
| 268 | wooma_forest | 20 |
| 313 | wooma_temple_1 | 15 |
| 314 | wooma_temple_2 | 15 |
| 315 | wooma_temple_3 | 13（+1 boss）|

**这些地图的怪物数据已批准权威在正式 runtime release 中，不得假定空 editor.json 可以无损重建它们。** 6 张结构地图（orc_tomb_1/2/3、bich_mine_1/2、corpse_king_hall）editor 与 runtime 均为 0，无此问题。

---

## 9. 危险工具警告（DANGER）

```
DANGER
tools/map_editor/rebuild_formal_map_releases.gd
```

该工具从 `editor.json` 全量重建 11 张正式 runtime。**在旧地图完成 Runtime → Editor monster_spawn 回填之前，禁止对该工具用于上述 5 张 TRANSITION_DEBT 地图的全量正式重建**，否则会用空 editor spawn 覆盖正式 runtime，生成零怪物 Runtime，破坏 registry/hash 与 playable 状态。

不删除、不修改工具；只遵守使用边界。`tools/map_editor/mfc4_rehash_formal_runtime.gd` 是 MFC-4F 的 runtime rehash + registry 同步工具（旧地图改 runtime 后保持 hash 一致时可用）。

---

## 10. 正式地图布怪流程

**新地图 / 已回填地图**（editor.json 为权威）：

```
1. 确认目标 map_id / map_key（map_editor_workspace/<map_key>/<map_key>.editor.json）
2. 读取用户怪物分布，逐个查唯一正式 monster_id（GameData.canonical_monster_id）
3. 确认 classification（canonical catalog）
4. 普通怪填合法 respawn_policy_id；Boss/Elite 不填（canonical 锁定）
5. 检查 safe_area / door landing / walkable：spawn 避开安全区与门点落脚区
6. editor 中设置 spawn region / group / count
7. 保存 document → MapEditorBuildRuntimeService.build_candidate（需 runtime_approved）
8. MapEditorBuildRuntimeService.publish_runtime_release → 提升正式 runtime + 更新 registry
9. 跑 Map Runtime Gate
10. 跑 Monster Final Regression
```

**旧 TRANSITION_DEBT 地图**：当前 authority 在 runtime.json。直接布怪需先单独完成 **Runtime → Editor Monster Spawn Backfill** 恢复 editor 权威，再走上述正式流程；回填前不得用空 editor 覆盖 runtime。若必须改 runtime，需同步重算 `build_sha256` 并更新 registry `approved_build_sha256`（registry 与 runtime hash 不一致会使 `is_formal_playable` 失败）。

---

## 11. 地图布怪后的强制测试

必须运行（当前仓库实测存在）：

```
tests/monster_final_zero_gap_gate_test.tscn            # Monster Final Gate（blockers 必须 = 0）
tests/monster_formal_respawn_policy_audit_test.tscn     # formal ordinary requiring authored policy = 0
tests/all_monster_loading_test.tscn
tests/monster_mfc1_attribute_timing_audit_test.tscn
tests/monster_mfc2_animation_special_audit_test.tscn
tests/map_runtime_release_registry_contract_test.tscn   # Map Runtime / Release Registry Gate
tests/release_registry_consumer_validation_test.tscn
```

已有正式 Monster suite（`tools/run_godot_tests.ps1 -Suite monster`）完整运行，要求无新增失败（`monster_world_integration_test` 为已确认 PREEXISTING_INFRA_TIMEOUT，不视为新增 blocker）。

---

## 12. 地图任务出现 Monster Gate FAIL 时

布怪导致 Monster Final Gate blocker > 0：**禁止直接修改 Monster System**。先判断归属：

```
地图数据错误（monster_id 写错 / policy 写错）
Bridge / build 输出错误
registry 错误
还是新发现的 Monster Production Bug
```

优先修**地图数据 / 发布数据**。只有证据证明 Monster Production Contract 本身存在新 Bug，才允许重新打开 Monster，且必须单独立项。

---

## 13. Editor 回填债务 ≠ Monster 未完成

`editor.json monster_spawn = 0` while `runtime.json` 有正式怪物，属 **Map Authoring / Runtime Backfill Debt**，不是 Monster System blocker。Monster 已正式 Closure。未来可单独执行 `Runtime → Editor Monster Spawn Backfill` 恢复理想链 `editor.json → Build Runtime → runtime.json` —— 该任务不属于 Monster Final Closure。

---

## 给地图制作代理的 10 条规则

1. Monster 已冻结，不改底层。
2. 只用正式 `monster_id`。
3. 禁止 name / alias fallback。
4. 只用正式 `respawn_policy_id`。
5. Boss / Elite 保持 canonical classification。
6. 不修改 Monster 属性 / AI / 攻击 / 动画 / 掉落 / 回血 / 刷新 resolver。
7. 避开 safe_area 和 door landing。
8. 旧正式地图不要用空 editor.json 覆盖 runtime。
9. 布怪后跑 Monster Final Gate + Map Runtime Gate。
10. Gate 失败优先修地图数据，不得为了过测试修改 Monster。