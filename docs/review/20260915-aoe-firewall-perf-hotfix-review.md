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
