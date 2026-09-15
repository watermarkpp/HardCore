# GPT 审查请求：火墙性能/镜头/错误提示热修（分支 codex/fix-aoe-firewall-perf-20260915）

- 请求时间：2026-09-15
- 基线：`f8dda719`（codex/integration 当时 tip，origin 已同步）
- 审查 HEAD：`e7c0c6bf`（4 个提交，见 §3）
- 审查方式：`git diff f8dda719..e7c0c6bf` + 本文档
- 状态：阶段 0-6 施工完成；用户实机首测**确认火墙卡顿缓解**；镜头方案经用户实测裁决后二次修正（§4.2）；**尚未合并 codex/integration**（等用户复测通过并明确授权）

---

## 1. 任务来源与范围

用户报告四问题：① 火墙 AOE 掉帧（蜈蚣洞/祖玛重于比奇，怪少即恢复）；② 怪物刷新后第二轮更卡（刷新节奏本身正确，不许改）；③ 取消镜头自动拉扯、固定视角高度；④ 装备需求错误提示消失 + 错误类提示仅中文。要求彻底根除、判断是否核心设计问题。

## 2. 根因链（最终裁定，含两模型交叉审查结论）

1. **P0-1 火墙叠加合同丢失（玩法+性能双 bug）**。项目权威 SOT（`assets/data/vanilla_176/skill_source_package_v1_0_1/mir2_176_skills_source_of_truth_v1.json` 与同名施工规格 md，`status: project_canonical`）原文：
   `"stacking_policy": "same_caster_same_tile_refreshes_duration; one target takes at most one tick per caster per tick"`，`"max_active_fields_per_caster": "config_required_default_8"`。
   但执行链：`wizard_skill_runtime.gd` 将 `stacking_policy` 写入 effect（`max_active_fields_per_caster` 此前未写）→ `skill_execution_plan_contract.gd` ground 描述符只透传 power/radius/duration/tick（**两字段被丢**）→ `game_root`/`FireWallFieldController` 无任何执行代码。净效果：同格重放也新建字段、无上限堆叠（时长 ≈9.7~13s+魔法/2，冷却 1.5s → 稳态 20+ 字段 ≈ 180+ 动画精灵）。
2. **P0-2 生命周期时钟错位**。系统菜单 `get_tree().paused = true`（`game_root.gd:1820-1822`）；`create_timer` 默认 `process_always=true` → 刷新定时器菜单期间照走（用户确认正确，保留）；火墙字段随树暂停 → 寿命冻结。第二轮 = 旧字段未过期 + 新怪全量 → 更卡。
3. **P1 渲染放大器**：9 格/字段各自独立 `_process` 推帧；镜头小地图动态拉近（边缘压力→1.16，像素 +19.8%）乘在半透明精灵上。
4. **P1 问题 4**：三个装备入口（槽点击/长按菜单/双击穿戴）在 UI 事务重构（`dd919c21`）时有意丢弃 `result.message`（注释"never its prose"/"no prose"）；权威层 `PlayerState.equip_inventory_index_result` 的中文消息完好。
5. **否证记录**：legacy `GroundSkillEffect` 组扫描路径曾被列为 P0 候选——实测当前生产不可达（火墙被 `game_root.gd:8141-8156` 显式拦截；通用伤害效果 `manager_owned_damage_ticks=true` 走 `PersistentGroundEffectManager`+空间索引；ground_dot 技能仅火墙一种）。降级为 P2 防回归项。claim key 已是 `caster:skill:target` 施法者粒度（`ground_effect.gd` claim 函数），SOT"每施法者每 tick 单 tick"**天然满足，无需改动**。40ms 火墙动画为原版 A 级还原（manifest `mapping_rule`：clEvent.pas ET_FIRE，`FIREBURNBASE=1630 + ((m_dwCurframe div 2) mod 6)`，20ms 计数 → 可见帧 40ms，confidence A）——**不修改**。

## 3. 施工明细（4 提交）

### fa3022b3 — 火墙合同闭环 + wall-clock 寿命 + 共享动画时钟
- `scripts/fire_wall_field_controller.gd`：新增 `expires_at_ticks_msec`（`Time.get_ticks_msec()` 真实时间到期，暂停/后台不冻结，下一模拟帧释放）、`refresh_field()`（同格刷新：更新 power/duration/snapshot、重挂 wall-clock、刷新各 cell 寿命、`refresh_count+=1`；伤害 claim 节奏不动）、`fire_wall_anim_clock_ms()`（字段级共享动画时钟，`_physics_process` 推进）；诊断字典增 `expires_at_ticks_msec/refresh_count/anim_clock_ms`。
- `scripts/ground_skill_visual_cell.gd`：新增 `refresh_lifetime()`（刷新后 cell 生命周期与字段同步，防"cell 先死/后活"）。
- `scripts/ground_effect.gd`：新增 `set_shared_anim_clock_ms()` 转发至 `CasterSkillAnimationPlayer`。
- `scripts/caster_skill_animation_player.gd`：新增外部时钟模式 `set_shared_clock_ms()/ _apply_shared_clock_frame()`——帧号由共享时钟推导（幂等），`frame_time_ms` 原版节奏不变。
- `scripts/game_root.gd`：`FireWallFieldRegistry`（key=覆盖格集合的质心格 `Vector2i`；同格命中→`refresh_field` 后直接 return，不新建；新格→注册并 `_fire_wall_evict_excess_fire_wall_fields`（cap 解析 `config_required_default_8`→8，驱逐最旧→`cancel()`）；`_fire_wall_prune_invalid_registry_entries` 惰性清理；地图切换处 `_clear_fire_wall_field_registry()` 显式释放控制器）；cells 接线共享时钟；修正 9058 行过时"4 cells"注释为 3×3=9。
- `scripts/skills/skill_execution_plan_contract.gd`：ground 描述符补透传 `stacking_policy`/`max_active_fields_per_caster`/`max_ticks_per_target_per_caster`。
- `scripts/skills/runtimes/wizard_skill_runtime.gd`：effect 增写 `max_active_fields_per_caster`（mechanics 无值时为空串 → 运行时取 SOT 默认 8）。
- `tests/fire_wall_field_registry_test.gd/.tscn`（新增）：同格连放 10 次→1 controller/9 cells/refresh_count=1；异格 1+8 次→cap 8 且最旧被逐；wall-clock 到期→`expired`+释放。
- `tests/skill_plan_single_snapshot_build_test.gd`：**基线陈旧测试修正**——fixture 仍冻结 2×2（4 cells），与 2026-09-13 用户要求 5 的 3×3 geometry override 冲突；在未改动主树 f8dda719 复现同样失败后，按 SOT geometry（width/height_tiles 3, project_canonical）更新为 3×3/9 cells。

### 98afcf47 — 镜头 v1（后被 e7c0c6bf 部分推翻）+ 错误提示恢复
- `scripts/game_root.gd`：v1 实现 `zoom = max(1.06, minimum_uniform_zoom)` 每图一次性固定——**该实现的"小地图不露黑边优先"假设被用户实测推翻，见 §4.2**。
- `scripts/inventory_panel.gd`：新增 `_show_center_message()`（经 `get_parent()` 到 HUD `show_message`，与"目标被遮挡或已失效"同通道）；三个拒绝分支补 `hud.show_message(result.message, 2.0)`；详情面板行为不动。
- 错误 toast 仅中文：`"map_projection_unavailable:%d"`×2 → `"目标/当前地图投影暂不可用（%d）"`；`"技能栏配置失败：%s"`/`"技能释放失败：%s"` 去除英文错误码后缀。

### ed2a5f28 — 注释修正（无行为影响；APK 82 基于前一提交构建，不含本提交）

### e7c0c6bf — 镜头 v2（用户实测裁决）：全游戏统一视角高度
- `scripts/game_root.gd`：删除每图 `max(base, minimum_uniform_zoom)` 适配，改为**恒定 `ArtSpec.CAMERA_ZOOM`（1.06，即盟重安全区高度）**；`resolve_soft_follow` 仍调用但 `maximum_zoom=base`（recommended_zoom 恒等于 base，杜绝一切拉近）；位置软跟随/±14% 带限保留；视口超出边界时服务退化为带限跟随（`constrain_center` infeasible → 质心钳制 + tanh 软差，玩家始终可见），小地图按用户裁决**露边缘不拉近**。

## 4. 实测结果与裁决

1. **首测（APK 82，源 98afcf47）**：火墙卡顿缓解——用户确认。同轮发现新问题：地下城被强制近景（minimum_uniform_zoom > base），非战斗也持续掉帧。根因：v1 的"不露黑边优先"假设错误；近景放大像素覆盖（(zoom/1.06)²），GPU overdraw 恒定增高。
2. **用户裁决（2026-09-15）**：取消一切拉近；全游戏统一 = 盟重安全区高度；小地图宁可露边。→ e7c0c6bf 落地。
3. **行为变化点（均已向用户披露）**：同格重放=刷新时长（SOT 合同，非新设计）；火墙菜单/后台期间按真实时间老化；小地图显示地图边缘。

## 5. 测试矩阵与证据

| 套件/测试 | 结果 |
|---|---|
| fire_wall_controller_critical（12 场景） | 12/12 PASS |
| skill_execution_plan_critical | 10/10 PASS（含修正后的 snapshot 测试） |
| persistent_ground_effect_critical | 10/10 PASS |
| formal_map_projection_critical | 8/8 PASS（v1 与 v2 各跑一轮） |
| map_runtime_release_critical | 5/5 PASS（v1 与 v2 各跑一轮） |
| map_diamond_camera_constraint_test | PASS（两轮） |
| equipment 套件 | 21 过 / 4 失败——**基线预存**，已在未改动主树逐一复现（hud_authority_integration、inventory_equipment_ui"人物属性超长时没有右侧滑块"line142、equipment_durability_policy、equipment_precise_durability），不属本任务 |
| fire_wall_field_registry_test（新增） | PASS |
| 热补丁 APK（82，98afcf47） | ANDROID_ISOLATED_BUILD_PASS；com.personal.mafaoffline；versionCode 82；SHA256 3B2057F9101E9A853439662896644399AAA8CD7DED31720DC025842B0D5F57CA；签名/运行时资源/编译脚本探针全过 |

## 6. 已知债务与风险（如实记录）

1. **数据链回填**：`skills.json` 现无 `mechanics.stacking_policy/max_active_fields_per_caster`；运行时以 SOT 默认值执行。回填须走 SOT→生成链，且需核对 tick 权威差异：SOT `timing.tick_interval_ms=1000` vs `profession_combat_rules.json` 火墙 `tick_interval_ms=3000`（本次以运行时现状为准，未改 tick）。
2. **legacy group-scan fail-closed（P2）**：6 个测试文件直接驱动裸 `GroundSkillEffect`，钉死前需先迁移到 manager 合同；生产不可达性当前由合同拦截+registry 保证。
3. **equipment 套件 4 个基线失败**：不在本任务范围，已单独记录。
4. **Android 恢复突发（刷新定时器同帧集中到期）**：保留"需实机插桩"定性；菜单时钟错位已由 wall-clock 解决主要矛盾，未改刷新调度。
5. 小地图露边为用户明示接受；若后续想减黑边，可评估 UI 解锁/edge skirt 强化，而非恢复拉近。

## 7. 请 GPT 重点审查的点

1. `refresh_field` 的 snapshot/claim 窗口替换是否引入跨字段同帧双伤（claim key 粒度已验证为施法者级，但请复核并发刷新与驱逐竞态）。
2. wall-clock 到期与 `_tick_timer`（仿真钟）并存是否产生"过期前最后一跳"语义偏差。
3. e7c0c6bf 后 `resolve_soft_follow` 以 base=maximum 调用，`constrain_center` infeasible→质心分支在小地图的跟随体验是否有更优退化策略。
4. registry 以覆盖格质心为 key 的"同格"判定是否与玩家感知的"同一格"一致（含边缘半格情形）。
5. 执行计划透传三字段后，是否有消费者对新增键做严格 schema 校验而拒绝计划（本轮 10/10 套件未见，请独立复核）。

## 8. 附加建议（供裁决，未施工）

- 验收引入 Gen1→Gen5 逐代稳定性矩阵（同场景连烧 5 轮，P50/P95/P99/max 帧不逐代恶化）。
- `RuntimeDiagnostics` 增 field/cell 计数、respawn pending/due、resume 后前 120 帧采样，为问题 ② 的恢复突发提供实测裁决。
- cap=8 从常量升级为可配置（SOT `config_required_default_8` 本意）。
- 修复 4 个基线预存失败（另一专项）。

---

# R1 增补（Combat Runtime R1 — 按 GPT 审计方案施工，2026-09-15）

## R0. 对 GPT 审计的采纳记录

全部接受并落地/排期：第 9 块策略不得擅自发明（已改）；registry key 源感知（已改）；"共享动画时钟"表述收敛（仅统一时间源，每格仍有 `_process`，中心调度器待 profiler 证据）；legacy 组扫描退出生产（已改）；直连 `take_damage` fallback 消灭（已改）。执行映射修正：GPT 规划的 PeriodicScheduler 角色由既有 `PersistentGroundEffectManager` 承担，不重复造轮子；特殊几何技能按 GPT"逐步搬掉"原则分批迁移。保护项（冻结，本轮未触碰）：Camera 1.06 裁决、火墙 40ms 原版节奏、刷新玩法、**用户 UI 解锁设定**（HUD/布局体系文件本轮零改动）。

## R1. 本轮提交（基线 f8dda719 → HEAD）

1. `153bf394` — 源感知 registry + 显式 fail-closed cap_policy。key=map|zone_generation|caster|family|中心格；上限按**单施法者**计数（原实现误计全局）；`cap_policy` 走执行合同透传（`reject_new` 默认=fail-closed，`evict_oldest` 仅显式数据）。测试扩展：默认第 9 块拒绝且最旧保留；显式 evict_oldest 驱逐；key 分离 caster/family/tile/generation。证据：registry 测试 PASS、fire_wall_controller_critical 12/12、skill_execution_plan_critical 10/10。
2. `58422737` — 关闭 legacy 组扫描与直连 take_damage。`GroundSkillEffect._physics_process` 候选改由共享 `RuntimeCombatSpatialIndex` 供给（索引内置 `+max_actor_bounds_gu` 保守扩展，exact 门 `runtime_target_is_inside` 与 claim 门逐字保留=目标集合不变）；无注入空间上下文 → fail-closed 跳过并计数；adapter-only 投递。生产现状佐证：generic 效果本就走 `PersistentGroundEffectManager`（`manager_owned_damage_ticks=true`），火墙走 controller——本提交关闭的是最后一条敞开的 legacy 路径。claim-parity 测试 `fire_wall_runtime_overlap_test` 已移植到索引合同（PASS）。回归：persistent 10/10、fire_wall 12/12、plan 10/10、map_runtime_release 5/5。
3. 静态门禁（本轮第 3 提交）— `tests/combat_authority_static_gate_test.gd`：源码级断言 ground_effect/controller 无组扫描、无 take_damage；cap_policy 与源感知 key 必须存在。PASS。

## R2. 交付清单对照（GPT 12 项）

1. BASE/HEAD/commits：f8dda719 → （见 R1 + 本文档提交），共 7 提交。
2. 逐文件职责：见 §3 与 R1；`ground_effect.gd` 净语义=表现+自管 tick（索引候选/adapter 投递/fail-closed）；`game_root.gd` 增 registry/policy；contract/runtime 增 cap_policy 透传。
3. production target-query 权威：`RuntimeCombatSpatialIndex`（game_root `_target_spatial_query_*`、manager、controller、自管 tick 注入）。
4. production damage 权威：adapter/callback/manager 路由；ground_effect 直连 take_damage 已删。
5. persistent/DOT 权威：`PersistentGroundEffectManager`（唯一 generic DOT 调度器）+ controller（火墙）。
6. cap-policy 证据来源：SOT 仅 `config_required_default_8`，无第 9 块行为记录（已全文检索 cap/evict/第九/max_active）；故 reject_new=fail-closed 默认，evict_oldest 须显式数据。权威缺口如实记录。
7. 残余 `get_nodes_in_group("enemies")` 分类：game_root `_aoe_reference_*`（oracle 参照，`reference_audit_mode/_test_enabled` 双 flag 门，生产默认关）；game_root boss-surrounded 邻域机制查询（非投递，staged→R1-A 迁移 `query_neighbor_enemy_nodes_into`）；game_root 随机传送占位检查（GPT 允许类）；device_lab×2/hc_r6_frame_probe（诊断 harness）。
8. 残余 `.take_damage(` 分类：manager:285（generic DOT 唯一生产投递点，R1-C CombatHitRequest 改造对象）；skill_projectile:710、summon_actor:815（R1 后续）；enemy.gd×4（怪→人方向，独立管线）；combat_runtime_service:29（professions-skills 共享桥，staged）。
9. GameRoot ability-id 特例枚举与描述符迁移：**staged**（R1-A 主体，下轮先建 CombatTargetQueryService + oracle 再逐支迁移，禁止无 parity 证据删除）。
10. correctness oracle：**staged**（R1-A：穷举参照 vs 服务，随机化边界/半径/代际/cap/排序/LOS/零半径）。
11. 性能矩阵：headless 套件全绿；3 图×17/30/60 怪×Gen1→Gen5 实机矩阵 NOT_RUN（需设备）。
12. 未解决债务：equipment 套件 4 基线失败；complete_client_resource_catalog_test 需工作树生成 outputs 夹具；canonical_skill_production_entry/smoke_test/professions_combat_gu_contract 在 f8dda719 同签名失败（预存）；skills.json stacking 字段数据链回填；tick 权威差异（SOT 1000 vs combat_rules 3000）需回填时裁决。

## R3. 下轮排期（R1-A 优先）

R1-A 主体已落地（见 R4）；GameRoot 特殊几何技能逐支迁移（每支带 parity 证据）与静态门禁扩展（禁止新增 ability-id 战斗分支）为下一步。合并门禁不变：GPT 复审 + 用户实机 + 明确授权前，不合 `codex/integration`。

## R4. R1-A 落地（本节替代 R3 首条）

- `scripts/layers/runtime/combat_target_query_service.gd`（新增）：唯一生产目标查询权威。形状 `single/circle/sector/capsule/cross`（CHAIN 显式未实现→fail-closed 空结果）；两阶段查询：形状保守 AABB broadphase（索引侧再加全体注册者半径，superset 保证）→ 形状精确门（绝对 ground GU，`<=` 边界含闭）；输出沿用索引稳定序（stable_combat_order 升序）；未知/欠规范形状 fail-closed 空结果 + `last_rejection_reason()`；服务无状态变更、无投递、无组扫描。
- `scripts/runtime_combat_spatial_index.gd`：`_query_aabb_candidates` 结果**纯增补** `position_ground_gu`（复用其已计算的 live 位置；既有消费者忽略新键，无行为变化）。
- `tests/combat_target_query_service_oracle_test.gd`（新增）：独立参照实现（按形状合同手写、不调用服务）vs 服务，5 形状 × 160 随机查询（seed 固定）集合严格等价 + 稳定顺序断言 + 边界含闭/零半径用例 + 4 类 fail-closed（未知形状/负半径/非法方向/地图不可用）。首跑 PASS。
- 静态门禁扩展：服务源码禁 `get_nodes_in_group(` / `take_damage(`。PASS。
- 回归：persistent 10/10、fire_wall 12/12、plan 10/10（索引增补无回归）。

## R5. R1-A 收尾（d1d015ba）

- 火墙 controller broadphase 迁入 `CombatTargetQueryService`：新增 `SHAPE_AABB` 直通形状（包络即请求矩形；精确性仍由 controller 的 canonical snapshot 门决定，行为与原直连索引查询逐位一致）。
- 迁移过程缺陷被 parity harness 当场抓获并修复：服务 origin 有限性守卫误拒无 origin 的 aabb 形状（`legacy=1 manager=0`）；修复后 origin 检查仅适用于锚定形状。
- 证据：fire_wall_controller_critical 12/12（hit/claim parity、no_group_scan 全绿）、registry PASS、oracle PASS。
- 现状：所有生产目标查询均经 `RuntimeCombatSpatialIndex`（controller 走统一服务入口）；组扫描/直连 take_damage 由静态门禁锁定。
- 剩余 staged：GameRoot 特殊几何技能（半月/十字/野蛮/雷霆/冰暴）逐支迁移到描述符+形状策略（每支带 parity 证据，需独立施工轮）；实机 Gen1→Gen5 矩阵 NOT_RUN（待设备）。

---

# R6. R1-B 落地 — GameRoot 特殊几何技能 broadphase 迁入服务（2026-09-15 新会话续作）

## R6.0 五技能的代码裁定映射

评审 R5 的五名简称按生产代码落定为以下查询路径（每支的**canonical 精确门一字未动**）：

| 简称 | skill_id | 迁移前 broadphase | 迁移后服务请求 |
|---|---|---|---|
| 半月 | warrior.half_moon | `_half_moon_secondary_targets` → `_aoe_query_enemy_candidates_aabb`（plan 包络） | 服务 `SHAPE_AABB(bounds=plan.ground_aabb)`；精确门仍为 `WarriorMeleeGeometryScript.half_moon_footprint_relative_sector_gu`/target-aligned sector |
| 十字 | warrior.thrusting（刺杀轴线三探针槽位判定，GPT 审计语境的"十字"判定组） | `_thrust_secondary_targets` → 同上 | 同上；精确门仍为 thrust slot/axis 合同 |
| 野蛮 | warrior.wild_rush | `_wild_rush_has_dynamic_blocker` → `_target_spatial_query_segment_into`（segment 包络） | 服务 `SHAPE_AABB(segment AABB ± expansion)`；精确门仍为 forward/lateral 窗口 |
| 雷霆 | wizard.lightning（雷电术 targeted_sky_strike 专支） | `_apply_canonical_spell_damage` → `_aoe_query_enemy_candidates_aabb` | 同 aabb 收口；精确门仍为 `node == primary` + snapshot 足迹 |
| 冰暴 | wizard.ice_storm（及全部 cell-union 区域：hell_lightning/exploding_flame/repulsion_ring、径向 area_damage） | `_canonical_spell_geometry_targets` → 同上 | 同 aabb 收口；精确门仍为逐格 `declared_cells_intersect_actor_footprint`/snapshot |

实施说明：五支共享同一 broadphase 收口函数，故本轮按收口点一次性迁移（每支的 parity 断言见 R6.2），而非五笔等价 diff。服务真实形状库（single/circle/sector/capsule/cross）保留给"形状即精确门"的未来技能；本轮各技能的精确权威（近战几何/法术 snapshot 门）比服务通用形状更丰富，按 d1d015ba 既定范式以 `SHAPE_AABB` 包络直通 + 原精确门执行。

## R6.1 施工内容

1. `scripts/game_root.gd`：
   - `_target_query_service()`：game_root 持有的服务实例，map id 或 index 实例变化即重建（防陈旧绑定）。
   - `_service_candidates_envelope_into()`：服务包络查询 + **活体过滤复刻**——服务记录路径不过滤 `_dying/_death_pending/hp<=0`，旧 `query_enemy_nodes_*_into` 过滤；wrapper 复刻旧活体过滤保持候选集逐位一致；拒绝时 fail-closed 并记 `projection_rejection_reason`。
   - 四个收口函数（`_target_spatial_query_aabb_into/_target_spatial_query_segment_into/_aoe_query_enemy_candidates_aabb/_aoe_query_enemy_candidates_segment`）全部改走服务；非法包络/线段保持旧行为（空候选 + 无拒绝）；计数器语义保持（`aoe_spatial_queries/aoe_spatial_candidates`）。
   - 保留直连索引的两处 sanctioned 站点：`_enforce_bich_safe_zone`（安全区执法）与 `_hc_m30_landing_clear`（M30 落点探针）——非五技能、非投递路径。
2. `scripts/layers/runtime/combat_target_query_service.gd`：请求支持可选 `broadphase_epsilon_gu`（默认 `BROADPHASE_EPSILON_GU=0.05` 不变）。**parity 关键裁定**：game_root 包络直通传 `0.0`，使服务包络 = 旧索引包络（索引侧仍加 max_actor_bounds），候选集逐位一致——避免默认 0.05 epsilon 环使野蛮冲撞 blocker 的 lateral 窗口（+0.0001）在 0.1mm 级条带接受旧路径不返回的候选。
3. 静态门禁扩展（`tests/combat_authority_static_gate_test.gd`）：四个收口函数必须经 `_service_candidates_envelope_into` 且不得直连索引节点查询；两个 sanctioned 直连站点存在性；五组 ability-id 战斗枚举（`CANONICAL_WIZARD_GEOMETRY_SKILLS/CONTINUOUS_WIZARD_LINE_SKILLS/GROUND_EXACT_SKILL_IDS/TARGET_FOOTPRINT_SKILL_IDS/ATTACHED_STATE_SKILL_IDS`）内容冻结——新增 ability-id 战斗分支即 FAIL。

## R6.2 parity 证据

1. 新增 `tests/game_root_special_geometry_service_parity_test.gd/.tscn`：随机包络（96 rect + 48 segment，种子 20260915）下 服务(ε=0)+活体过滤 ≡ 旧索引节点查询（集合严格相等）；默认 ε 包络 ⊇ 旧包络；濒死/死亡待决/0 HP 注册演员两侧同拒；`update_actor` 移动与 `clear_map` 两侧同排空；坏 map fail-closed 带原因。PASS。
2. 中途问题归类（一次真实失败）：`game_root_r3x6_targeting_broadphase_test` 断言"召唤占位必须用敌方空间 broadphase"测量的是旧直连节点查询专用计数器 `index_enemy_node_aabb_query_count`；R1-B 后召唤占位经服务记录路径（行为不变、仍走共享索引），该计数器不再递增。生产正确、测量过时——按 TEST INTEGRITY 修测量为 `index_query_count`（服务记录路径递增的 broadphase 计数器），断言语义不变。修复后 PASS。
3. 功能回归（迁移后）：warrior_target_aligned（半月/刺杀目标对齐）、wizard_geometry、sky_strike（雷电）、melee_spatial_broadphase_parity、r3x6 全部 PASS。

## R6.3 测试矩阵

| 套件/测试 | 结果 |
|---|---|
| game_root_special_geometry_service_parity_test（新增） | PASS |
| combat_authority_static_gate_test（扩展） | PASS |
| combat_target_query_service_oracle_test | PASS |
| fire_wall_controller_critical | 12/12 PASS |
| persistent_ground_effect_critical | 10/10 PASS |
| skill_execution_plan_critical | 10/10 PASS |
| wizard_line_geometry_critical（segment 路径） | 3/3 PASS |
| combat_projection_fail_closed_critical | 6/6 PASS |
| game_root_r3x6_targeting_broadphase_test | PASS（含测量修正） |
| game_root_warrior_target_aligned_integration_test | PASS |
| game_root_wizard_geometry_integration_test | PASS |
| sky_strike_visual_contract_test | PASS |
| player_melee_spatial_broadphase_parity_test | PASS |

## R6.4 剩余 staged（如实）

1. boss-surrounded 邻域组扫描（R2 第 7 项）仍 staged：组扫描在死亡窗口会计入已 `unregister` 的演员、并计入召唤物（不在敌方索引）；直接换 `query_neighbor_enemy_nodes_into` 需先裁决死亡窗口/召唤物的计数合同，本轮未动。
2. 实机 Gen1→Gen5 矩阵 NOT_RUN（待设备）。
3. 服务形状库（sector/capsule/circle/cross 作为精确门）尚未被任何生产技能消费——留待新技能描述符化时启用，本轮不发明消费者。

---

# R7. PERF-1 落地 — 热路径 allocation-conscious 收口（2026-09-15，GPT 终审采纳轮）

## R7.0 对 GPT 终审的采纳与修正

终审四项技术断言（`_query_aabb_candidates` 每查询分配、manager 绕过服务、manager:285 直连 take_damage、`_max_actor_bounds_gu` 只增不减）经实码逐行核实**全部属实**并采纳；"正确性 oracle ≠ 性能收尾证据"、"彻底根除 = BLOCKED"判定接受。一处文档修正：R4"唯一生产目标查询权威"表述过满（manager/ground_effect 自管 tick 当时仍直连索引），本轮起以精确表述替代。工程校准两点：manager 迁移直接落在零分配快路径上（不先迁 dict 版再迁一次）；R1-C damage 闭环排最后一轮（跨 professions-skills 共享桥，用户痛点优先）。

## R7.1 施工内容

1. `combat_target_query_service.gd`：新增 `query_envelope_into(bounds, output, stable_order=true, epsilon_gu=0.0)` 零分配快路径——原始参数（**无 request Dictionary**）、caller-owned 输出、委托索引 caller-owned 节点查询（query-stamp 去重 + 内联活体过滤 + 插入序）；拒绝语义镜像 `query()`（bool 返回 + `last_rejection_reason`：`spatial_index_unavailable/runtime_map_unavailable/bounds_invalid`），任何分支先清输出。**宇宙恒等式**：record 路径 = bounds+ε+max_bounds，快路径 = grow(ε) 后节点查询再加 max_bounds——ε 相同则逐位一致。dict `query()` 保留（oracle/锚定形状）。
2. `runtime_combat_spatial_index.gd`：`query_enemy_nodes_aabb_into` 增加 `stable_order := true` 可选参数（默认不变，段查询同款先例），透传 `_query_enemy_nodes_in_aabb`。
3. `game_root.gd`：四收口改经 `_service_envelope_into(bounds, output)`（ε=0）；request dict 构造与 record 解包消失；`_aoe_service_enemy_broadphase_current` 删除（节点查询内联同款过滤，复刻件不再需要）。
4. `persistent_ground_effect_manager.gd`：broadphase 迁入服务（自建服务实例，controller 同款模式；map id/index 变化重建），ε=EXPANSION_EPSILON_GU=0.05 保持原 record 宇宙；精确门 `runtime_target_is_inside`、claim、damage 路由逐字不动；manager:285 直连 take_damage 保留（R1-C 对象，未隐瞒）。
5. `fire_wall_field_controller.gd`：同轮迁快路径（ε=0.05 = d1d015ba 前直连值），canonical snapshot 精确门不动；至此**生产 broadphase 无任何 record 路径消费者**（`ground_effect` 自管 tick 为 R1-P0 门禁冻结的休眠合同——generic 效果全由 manager 拥有，火墙走 controller；留作 R1-C 一并处理）。
6. 静态门禁：manager 禁 `query_aabb_candidates(` 且必含 `query_envelope_into(`；controller 同；服务必须保留快路径；四收口断言名更新。

## R7.2 行为保持与语义漂移（如实）

- 候选集：parity 测试三重断言（快路径 ≡ 直连节点查询；快路径 ≡ record∩活体过滤；默认 ε ⊇ ε=0，两路径各自成立）96 rect + 48 segment 全等。
- 顺序：PERF-1 全部调用点 stable（插入序 + instance_id 决胜）；ORDER_NONE 切换留给 PERF-2（probe 类）。
- fail-closed：manager/controller 对拒绝按"空候选集"处理（旧 record 查询对不可用 map 返回空、无拒绝）——净行为一致。
- 诊断漂移：`candidate_count/total_candidate_count` 现统计**活体**节点（旧 record 路径把濒死注册者也计入）——仅诊断口径变化，已注释。

## R7.3 测试证据（49 项全 PASS）

| 套件 | 结果 |
|---|---|
| combat_authority_static_gate_test（含 PERF-1 新断言） | PASS |
| game_root_special_geometry_service_parity_test（三重断言版） | PASS |
| combat_target_query_service_oracle_test | PASS |
| fire_wall_controller_critical | 12/12 |
| persistent_ground_effect_critical | 10/10 |
| skill_execution_plan_critical | 10/10 |
| r3x6 / warrior_target_aligned / wizard_geometry / sky_strike / melee_parity | 5/5 |
| wizard_line_geometry_critical | 3/3 |
| combat_projection_fail_closed_critical | 6/6 |

## R7.4 PERF-2 — max_bounds 收缩 + probe ORDER_NONE

1. **`_max_actor_bounds_gu` 惰性收缩**（终审 §14）：`unregister/_erase_entry/clear_map` 移除条目时，若其 bounds ≥ 当前 max 则置 `_max_actor_bounds_dirty`；五个查询入口（record aabb/segment、节点 aabb/segment、批量段）首行 `_maybe_refresh_max_actor_bounds()` 一次 O(在册) 重算。安全性：dirty 期间存量 max 偏大（保守方向），重算只缩不涨，superset 不变量（在册集上界）保持。新增 `runtime_combat_spatial_index_max_bounds_test`：5.0 大脚 actor 注销 → 查询前仍 5.0（惰性）→ 下次查询缩到 0.3 → 新 max 立即生效 → clear_map 缩到 0。
2. **probe ORDER_NONE**：调用点逐一分类后仅 4 个纯探测切无序——野蛮冲撞 blocker（布尔）、召唤占位、随机传送占位（均为距离存在性判定，被滤掉的桶边 actor 必然不过精确门：center 超出 bounds+max_bounds ⇒ 身体够不到窗口）；**锁定/目标搜索/伤害投递路径全部保持 STABLE**（`7660` 为 canonical 伤害路径；`5511` 野蛮目标搜索先见者胜对平局顺序敏感；攻击锁定虽带 instance_id 决胜仍保守保持 stable）。parity 测试新增性质断言：无序结果 ⊆ 稳定结果（96 随机 rect）。
3. 诊断 `max_actor_bounds_gu` 语义：反映当前存储值（惰性，不主动刷新）。
4. 证据：新增 max_bounds 测试 PASS；parity（含 unsorted ⊆ stable）PASS；门禁（索引 tripwire `_max_actor_bounds_dirty`）PASS；oracle PASS；r3x6 等 5 功能回归 5/5；fire_wall 12/12、persistent 10/10、plan 10/10、projection 6/6、wizard_line 3/3 —— 共 50 项全 PASS。

## R7.5 ANIM-EVIDENCE — 火墙动画节奏实测（取证完成，待用户裁决）

实测链（2026-09-15，全部读自当前 HEAD 65a0de59）：

1. **权威数据**（`assets/data/caster_skill_visuals.json` fire_wall 条目，生成器 `tools/build_caster_client_art.py` 产出）：`frame_time_ms: 40`、`frame_count: 6`（source_index 1630–1635 = FIREBURNBASE+0..5）、`playback: loop`。mapping_rule：原版 clEvent.pas `FIREBURNBASE=1630+((m_dwCurframe div 2) mod 6)`，m_dwCurframe 每 20ms 步进 → 可见帧 40ms → 6 帧 × 40ms = **240ms 循环**。
2. **运行时消费**（`ground_effect.gd` `_install_visual` → `caster_skill_animation_player.gd`）：播放器从 manifest 读 frame_time（40ms）与 frame_count（6）；`configure()` 置 `current_frame_index=0` 起步。
3. **相位语义**（`fire_wall_field_controller.gd`）：controller 持 `_anim_clock_ms`（`_physics_process` 累加 delta×1000，从 0 起步）→ 9 个 cell 经 `set_shared_anim_clock_ms` 共用同一现场时钟；`_apply_shared_clock_frame` 取 `fmod(clock,240)/40`。即：**每次施法现场独立计时、从帧 0 开始、全场 tile 同帧**——与原版每道火墙魔法各自 m_dwCurframe 从 0 步进、整墙同帧的语义一致。
4. **结论**：现行视觉节奏 = 原版 SOT 逐项一致（240ms 周期、40ms/帧、帧 0 起步、现场级相位、循环）。唯一量化差：帧切换点由物理 tick（≈16.7ms）量化，最大偏差一个物理 tick；原版客户端同样受 20ms 逻辑 tick 量化，幅度同级。
5. **伤害解耦**：伤害 tick（0.8s `tick_interval`）与 `_anim_clock_ms` 完全独立——任何视觉节奏改动不触碰伤害频率、claim 窗口与 SOT"每施法者每 tick 单 tick"合同。

**待用户实机裁决的候选**（均只改 `frame_time_ms` 派生值，帧序列/索引/伤害不动）：

| 候选 | frame_time_ms | 周期 | 与原版关系 |
|---|---|---|---|
| ×1.0（现状） | 40 | 240ms | 原版 A 级还原 |
| ×1.25 | 50 | 300ms | 刻意放慢（火苗燃烧更舒缓） |
| ×1.5 | 60 | 360ms | 刻意放慢（更明显） |

实现注记（裁决后执行）：manifest 为生成物，规则是改生成器侧的显示节奏派生（如新增 per-skill `visual_frame_time_ms` 覆盖字段），保留 `frame_time_ms: 40` 作为 SOT 取证记录，不得手改生成 JSON。

## R7.6 R1-C — damage 闭环：最后一个直连伤害口关闭

1. **权威核实**：GPT 终审所称 "CombatHitRequest → CombatDamagePipeline" 在本仓的实体是 `scripts/layers/runtime/combat_runtime_service.gd`（autoload `CombatRuntime`；注入式消费先例：game_root:353 与 skill_projectile 各持自有实例，M30-CLEANUP-001 所有权合同）。manager `_apply_damage` 三级链：entry `damage_callback`（生产路径，game_root 注册时必带，绑 `_apply_canonical_ground_tick` → `apply_enemy_direct_spell_damage` 完整法术解析）→ effect `runtime_tick_adapter` → 兜底 `enemy.take_damage(...)`——兜底无任何生产或测试消费者（fixture 全部自带 callback），纯逃逸口。
2. **改动**：`PersistentGroundEffectManager._init` 增加可选 `combat_runtime` 注入；game_root 传入其自有 `_combat_runtime` 实例（RefCounted 不自建 Node，避免 M30 孤儿类泄漏）；兜底分支改走 `apply_enemy_physical_damage`（同数值、同 source 归因、服务侧 `can_receive_damage` 复检 + `take_damage_usec` 计时诊断），**无注入时 fail-closed**：拒绝交付并计 `damage_delivery_skip_count`。生产数值零变化（兜底在生产不可达；服务路径 `maxi(1,·)` 与既有 `damage > 0` 守卫等价）。
3. **门禁**：manager 必含 `apply_enemy_physical_damage(` 且**不得含 `take_damage(`**——直连伤害口从架构与门禁两层关闭。fire wall controller 与 GroundSkillEffect 的既有禁令保持。
4. **证据**：新增 `persistent_ground_effect_service_damage_delivery_test`（注入 → 经服务精确交付 7 点；未注入 → hp 不变 + skip 计数 1）；门禁/parity/oracle PASS；persistent 10/10、fire_wall 12/12、r3x6 等 5 功能回归 5/5、plan 10/10、projection 6/6、wizard_line 3/3 —— 共 50 项 PASS。

## R7.8 PERF-EVIDENCE — APK A/B 实测协议（已就绪，待设备执行）

**测量通道（已内建，无需新埋点）**：Device Lab mailbox 调试通道，`frame_sampling_snapshot` 全帧环形采样（capacity 环形缓冲，`frame_samples_dropped` 披露溢出）→ `frame_count`、`frame_ms_p50/p95/p99/max`（max 为 eb9ca528 新增字段，`monster_density_diagnostics_window_test` 已锁契约）+ `frames_over_16_67/33_33/50/100ms` 计数与比率。采样入口 `DeviceLabRuntime._process`（仅调试门放行，Release no-op）。

**A/B 双方**（同 versionCode，安装覆盖）：

| | 基线 | 实验组 |
|---|---|---|
| APK | `HardCore-20260915-aoe-fix-98afcf47-debug.apk` | `HardCore-20260915-aoe-fix-eb9ca528-debug.apk` |
| 源 | 98afcf47（R1 弧线之前，含用户报告卡顿的原始战斗实现） | eb9ca528（R1-P0/R1-A/R1-B + PERF-1/2 + R1-C + max 诊断，共 16 提交） |
| SHA256 | `3B2057F9…D5F57CA` | 构建完成后记录 |

**场景（每 APK 同脚本）**：
1. 蜈蚣洞：15 普怪 + 2 钳虫 + 固定节奏火墙（固定周期施放，覆盖多 field 叠加与 claim 窗口）。
2. 祖玛寺庙：高密度巡场 2–3 分钟。
3. Gen1→Gen5：生成矩阵冒烟（R6.4 遗留 NOT_RUN 项顺带补采）。

**流程**：进入场景 → 预热 ≥60s（排除加载期帧）→ 开采样 → 执行固定动作序列 → 停止后取快照 A（战斗窗口）→ 静置取快照 B（恢复后 120 帧窗口，验证 p99/max 回落）。

**裁决标准（GPT 终审方案）**：实验组 P95/P99/max 相对基线显著下降（重点 `frames_over_33_33ms`/`frames_over_50ms` 比率），且伤害节奏/命中/claim 行为无回归（本评审 R1–R7 各 parity 证据已在源层锁定行为不变）→ 解除"彻底根除掉帧 = BLOCKED"；数据不达标 → 如实记录并保持 BLOCKED。
